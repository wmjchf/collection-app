const config = require('../config');

function speakerGapMs() {
  return config.aliyun.asrSpeakerGapMs;
}

function speakerOrphanMaxChars() {
  return config.aliyun.asrSpeakerOrphanMaxChars;
}

function getDashScopeApiRoot() {
  const raw = (
    config.aliyun.dashScopeApiRoot ||
    config.aliyun.dashScopeBaseUrl ||
    'https://dashscope.aliyuncs.com/compatible-mode/v1'
  ).replace(/\/$/, '');
  if (raw.includes('/compatible-mode/v1')) {
    return raw.replace(/\/compatible-mode\/v1$/, '');
  }
  if (raw.endsWith('/v1')) return raw.slice(0, -3);
  return raw || 'https://dashscope.aliyuncs.com';
}

function isConfigured() {
  return Boolean(config.aliyun.dashScopeApiKey);
}

function requireApiKey() {
  if (!isConfigured()) {
    throw Object.assign(
      new Error('语音转写未配置：请设置 DASHSCOPE_API_KEY'),
      { status: 503 },
    );
  }
  return config.aliyun.dashScopeApiKey;
}

function mapTaskStatus(taskStatus) {
  const s = String(taskStatus || '').toUpperCase();
  if (s === 'PENDING') return 'QUEUEING';
  if (s === 'RUNNING') return 'RUNNING';
  if (s === 'SUCCEEDED') return 'SUCCESS';
  if (s === 'FAILED') return 'FAILED';
  return s || 'UNKNOWN';
}

async function parseJsonResponse(res) {
  const text = await res.text();
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    throw Object.assign(
      new Error(`转写响应解析失败：${text.slice(0, 200)}`),
      { status: 502 },
    );
  }
  if (!res.ok) {
    const msg =
      body?.message ||
      body?.error?.message ||
      body?.code ||
      `转写请求失败 (${res.status})`;
    throw Object.assign(new Error(msg), { status: 502 });
  }
  return body;
}

/**
 * 提交百炼 Fun-ASR 录音文件识别（异步）。
 * @param {string} fileLink 公网可访问的音频/视频 URL
 * @returns {Promise<{ taskId: string }>}
 */
async function submitFileTrans(fileLink) {
  const apiKey = requireApiKey();
  const root = getDashScopeApiRoot();
  const model = config.aliyun.asrModel || 'fun-asr';

  const res = await fetch(`${root}/api/v1/services/audio/asr/transcription`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
      'X-DashScope-Async': 'enable',
    },
    body: JSON.stringify({
      model,
      input: {
        file_urls: [String(fileLink || '').trim()],
      },
      parameters: {
        diarization_enabled: true,
      },
    }),
  });

  const body = await parseJsonResponse(res);
  const taskId = body?.output?.task_id;
  if (!taskId) {
    throw Object.assign(new Error('提交转写失败：未返回 task_id'), {
      status: 502,
    });
  }
  return { taskId: String(taskId) };
}

async function fetchTranscriptionJson(url) {
  const res = await fetch(url);
  if (!res.ok) {
    throw Object.assign(
      new Error(`拉取转写结果失败 (${res.status})`),
      { status: 502 },
    );
  }
  return res.json();
}

function normalizeFunAsrPayload(parsed) {
  if (!parsed || typeof parsed !== 'object') return null;
  const transcripts = parsed.transcripts;
  if (!Array.isArray(transcripts) || !transcripts.length) return null;

  const sentences = [];
  for (const tr of transcripts) {
    const channelId = tr.channel_id;
    const sents = tr.sentences;
    if (Array.isArray(sents) && sents.length) {
      for (const s of sents) {
        const text = String(s?.text || '').trim();
        if (!text) continue;
        sentences.push({
          Text: text,
          BeginTime: s.begin_time ?? s.BeginTime,
          EndTime: s.end_time ?? s.EndTime,
          ChannelId: channelId,
          SpeakerId: s.speaker_id ?? s.SpeakerId,
        });
      }
    } else {
      const text = String(tr.text || tr.transcript || '').trim();
      if (text) {
        sentences.push({
          Text: text,
          ChannelId: channelId,
        });
      }
    }
  }
  return sentences.length ? { Sentences: sentences } : null;
}

/**
 * 查询转写任务。
 * @returns {Promise<{
 *   statusText: string,
 *   done: boolean,
 *   ok: boolean,
 *   text: string|null,
 *   cues: Array<{startMs:number|null,endMs:number|null,speaker:number|null,text:string}>|null,
 *   errorMessage: string|null,
 * }>}
 */
async function getFileTransResult(taskId) {
  requireApiKey();
  const root = getDashScopeApiRoot();
  const res = await fetch(`${root}/api/v1/tasks/${encodeURIComponent(taskId)}`, {
    headers: {
      Authorization: `Bearer ${requireApiKey()}`,
    },
  });
  const body = await parseJsonResponse(res);
  const output = body?.output || {};
  const statusText = mapTaskStatus(output.task_status);

  if (statusText === 'RUNNING' || statusText === 'QUEUEING') {
    return {
      statusText,
      done: false,
      ok: false,
      text: null,
      cues: null,
      errorMessage: null,
    };
  }

  if (statusText === 'FAILED') {
    const first = Array.isArray(output.results) ? output.results[0] : null;
    return {
      statusText,
      done: true,
      ok: false,
      text: null,
      cues: null,
      errorMessage:
        first?.message || first?.code || output.message || '转写失败',
    };
  }

  if (statusText !== 'SUCCESS') {
    return {
      statusText,
      done: true,
      ok: false,
      text: null,
      cues: null,
      errorMessage: statusText || '转写失败',
    };
  }

  const results = Array.isArray(output.results) ? output.results : [];
  const first = results[0];
  if (!first) {
    return {
      statusText: 'SUCCESS_WITH_NO_VALID_FRAGMENT',
      done: true,
      ok: true,
      text: '',
      cues: [],
      errorMessage: null,
    };
  }

  if (String(first.subtask_status || '').toUpperCase() === 'FAILED') {
    return {
      statusText: 'FAILED',
      done: true,
      ok: false,
      text: null,
      cues: null,
      errorMessage: first.message || first.code || '转写失败',
    };
  }

  const transcriptionUrl = first.transcription_url;
  if (!transcriptionUrl) {
    return {
      statusText: 'SUCCESS_WITH_NO_VALID_FRAGMENT',
      done: true,
      ok: true,
      text: '',
      cues: [],
      errorMessage: null,
    };
  }

  const transcription = await fetchTranscriptionJson(transcriptionUrl);
  const built = buildTranscriptFromResult(transcription);
  if (!built.text && (!built.cues || !built.cues.length)) {
    return {
      statusText: 'SUCCESS_WITH_NO_VALID_FRAGMENT',
      done: true,
      ok: true,
      text: '',
      cues: [],
      errorMessage: null,
    };
  }

  return {
    statusText: 'SUCCESS',
    done: true,
    ok: true,
    text: built.text,
    cues: built.cues,
    errorMessage: null,
  };
}

/** 说话人分离优先 speaker_id；多音轨时用 channel_id */
function sentenceSpeakerId(sentence) {
  const speaker = sentence?.SpeakerId ?? sentence?.speaker_id;
  if (speaker != null && speaker !== '') return `s:${speaker}`;
  const channel = sentence?.ChannelId ?? sentence?.channel_id;
  if (channel != null && channel !== '') return `c:${channel}`;
  return null;
}

function sentenceTiming(sentence) {
  const begin = sentence?.BeginTime ?? sentence?.begin_time;
  const end = sentence?.EndTime ?? sentence?.end_time;
  const silence = sentence?.SilenceDuration ?? sentence?.silence_duration;
  return {
    beginTime: begin == null ? null : Number(begin),
    endTime: end == null ? null : Number(end),
    silenceDuration: silence == null ? null : Number(silence),
  };
}

/** 文档写秒，实测部分结果更像毫秒；≤30 按秒，否则按毫秒 */
function silenceDurationToMs(silence) {
  if (silence == null || !Number.isFinite(silence)) return null;
  if (silence <= 30) return Math.max(0, silence * 1000);
  return Math.max(0, silence);
}

function gapBeforeSentence(prev, curr) {
  if (
    prev.endTime != null &&
    curr.beginTime != null &&
    Number.isFinite(prev.endTime) &&
    Number.isFinite(curr.beginTime)
  ) {
    return Math.max(0, curr.beginTime - prev.endTime);
  }
  const silenceMs = silenceDurationToMs(curr.silenceDuration);
  if (silenceMs != null) return silenceMs;
  return null;
}

/** 句间几乎无停顿却被标成新说话人 → 并回上一轨（仅极短句；长句靠 peelMisattributedPrefix） */
function smoothSpeakersByTiming(items) {
  if (items.length <= 1) return items;
  const gapMs = speakerGapMs();
  const maxChars = speakerOrphanMaxChars();
  const out = [{ ...items[0] }];
  for (let i = 1; i < items.length; i += 1) {
    const prev = out[out.length - 1];
    const curr = { ...items[i] };
    const gap = gapBeforeSentence(prev, curr);
    if (
      gap != null &&
      gap <= gapMs &&
      curr.speakerId != null &&
      prev.speakerId != null &&
      curr.speakerId !== prev.speakerId &&
      curr.text.length <= maxChars
    ) {
      curr.speakerId = prev.speakerId;
    }
    out.push(curr);
  }
  return out;
}

function buildTranscriptFromResult(result) {
  if (!result) return { text: '', cues: [] };
  let parsed = result;
  if (typeof result === 'string') {
    try {
      parsed = JSON.parse(result);
    } catch {
      const text = result.trim();
      return {
        text,
        cues: text ? [{ startMs: null, endMs: null, speaker: null, text }] : [],
      };
    }
  }

  const funAsr = normalizeFunAsrPayload(parsed);
  if (funAsr?.Sentences?.length) {
    return formatSentencesWithSpeakers(funAsr.Sentences);
  }

  const sentences = parsed?.Sentences;
  if (Array.isArray(sentences) && sentences.length) {
    return formatSentencesWithSpeakers(sentences);
  }
  if (typeof parsed?.Text === 'string') {
    const text = parsed.Text.trim();
    return {
      text,
      cues: text ? [{ startMs: null, endMs: null, speaker: null, text }] : [],
    };
  }
  return { text: '', cues: [] };
}

/** @deprecated 兼容旧调用；请用 buildTranscriptFromResult */
function flattenResult(result) {
  return buildTranscriptFromResult(result).text;
}

function msOrNull(v) {
  if (v == null || !Number.isFinite(v)) return null;
  return Math.max(0, Math.round(v));
}

function mergeGroupTiming(target, piece) {
  if (target.startMs == null) target.startMs = piece.startMs ?? null;
  else if (piece.startMs != null) {
    target.startMs = Math.min(target.startMs, piece.startMs);
  }
  if (piece.endMs != null) {
    target.endMs =
      target.endMs == null ? piece.endMs : Math.max(target.endMs, piece.endMs);
  }
}

function toCue(g) {
  return {
    startMs: msOrNull(g.startMs),
    endMs: msOrNull(g.endMs),
    speaker: g.label == null ? null : Number(g.label),
    text: String(g.text || '').trim(),
  };
}

/**
 * 合并同说话人连续句；多人时段首「说话人 N：」，单人或无分轨信息时纯连写。
 * @returns {{ text: string, cues: Array<{startMs:number|null,endMs:number|null,speaker:number|null,text:string}> }}
 */
function formatSentencesWithSpeakers(sentences) {
  let items = sentences
    .map((s) => {
      const timing = sentenceTiming(s);
      return {
        text: String(s?.Text || s?.text || '').trim(),
        speakerId: sentenceSpeakerId(s),
        startMs: msOrNull(timing.beginTime),
        endMs: msOrNull(timing.endTime),
        silenceDuration: timing.silenceDuration,
        beginTime: timing.beginTime,
        endTime: timing.endTime,
      };
    })
    .filter((s) => s.text);
  if (!items.length) return { text: '', cues: [] };

  const diarizationIds = items.some((s) =>
    String(s.speakerId || '').startsWith('s:'),
  );
  if (!diarizationIds) {
    items = smoothSpeakersByTiming(items);
  }

  const speakerIds = new Set(
    items.map((s) => s.speakerId).filter((id) => id != null),
  );

  if (speakerIds.size <= 1) {
    const text = items.map((s) => s.text).join('');
    const cues = items.map((s) => ({
      startMs: s.startMs,
      endMs: s.endMs,
      speaker: null,
      text: s.text,
    }));
    return { text, cues };
  }

  let groups = [];
  for (const item of items) {
    const last = groups[groups.length - 1];
    if (last && last.speakerId === item.speakerId) {
      last.text += item.text;
      mergeGroupTiming(last, item);
    } else {
      groups.push({
        speakerId: item.speakerId,
        text: item.text,
        startMs: item.startMs,
        endMs: item.endMs,
      });
    }
  }

  groups = dedupeAdjacentSpeakerGroups(groups);
  if (!diarizationIds) {
    groups = peelMisattributedPrefix(groups);
    groups = collapseFleetingSpeakerGroups(groups);
  }
  groups = mergeConsecutiveSpeakerGroups(groups);
  groups = assignSpeakerLabels(groups);

  const cues = groups.map(toCue).filter((c) => c.text);
  const text = groups.map((g) => `说话人 ${g.label}：${g.text}`).join('\n\n');
  return { text, cues };
}

function dedupeAdjacentSpeakerGroups(groups) {
  const out = [];
  for (const g of groups) {
    const text = g.text.trim();
    if (!text) continue;
    const prev = out[out.length - 1];
    if (!prev) {
      out.push({ ...g, text });
      continue;
    }
    if (text === prev.text.trim()) continue;
    if (
      prev.speakerId !== g.speakerId &&
      text.startsWith(prev.text.trim())
    ) {
      const suffix = text.slice(prev.text.trim().length).trim();
      if (suffix) {
        out.push({
          speakerId: g.speakerId,
          text: suffix,
          startMs: g.startMs,
          endMs: g.endMs,
        });
      }
      continue;
    }
    out.push({ ...g, text });
  }
  return out;
}

function peelMisattributedPrefix(groups) {
  const maxChars = speakerOrphanMaxChars();
  const out = [];
  for (const g of groups) {
    let text = g.text.trim();
    if (!text) continue;
    const prev = out[out.length - 1];
    let startMs = g.startMs;
    let endMs = g.endMs;
    if (prev && prev.speakerId !== g.speakerId) {
      const m = text.match(/^(.{1,80}?。)([\s\S]+)$/);
      if (m) {
        const prefix = m[1].trim();
        const rest = m[2].trim();
        if (prefix.length <= maxChars && rest) {
          prev.text += prefix;
          mergeGroupTiming(prev, { startMs, endMs });
          text = rest;
        }
      }
    }
    if (text) out.push({ speakerId: g.speakerId, text, startMs, endMs });
  }
  return out;
}

function collapseFleetingSpeakerGroups(groups) {
  const maxChars = speakerOrphanMaxChars();
  const out = [];
  for (const g of groups) {
    const text = g.text.trim();
    if (!text) continue;
    const prev = out[out.length - 1];
    if (
      prev &&
      prev.speakerId !== g.speakerId &&
      text.length <= maxChars
    ) {
      prev.text += text;
      mergeGroupTiming(prev, g);
      continue;
    }
    out.push({ ...g, text });
  }
  return out;
}

function mergeConsecutiveSpeakerGroups(groups) {
  const out = [];
  for (const g of groups) {
    const last = out[out.length - 1];
    if (last && last.speakerId === g.speakerId) {
      last.text += g.text;
      mergeGroupTiming(last, g);
    } else {
      out.push({
        speakerId: g.speakerId,
        text: g.text,
        startMs: g.startMs,
        endMs: g.endMs,
      });
    }
  }
  return out;
}

function assignSpeakerLabels(groups) {
  const order = new Map();
  let next = 1;
  return groups.map((g) => {
    if (!order.has(g.speakerId)) order.set(g.speakerId, next++);
    return { ...g, label: order.get(g.speakerId) };
  });
}

module.exports = {
  isConfigured,
  submitFileTrans,
  getFileTransResult,
  buildTranscriptFromResult,
  flattenResult,
  formatSentencesWithSpeakers,
  smoothSpeakersByTiming,
  peelMisattributedPrefix,
  collapseFleetingSpeakerGroups,
  gapBeforeSentence,
  silenceDurationToMs,
  normalizeFunAsrPayload,
};
