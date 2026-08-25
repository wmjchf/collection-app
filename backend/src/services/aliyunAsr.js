const Client = require('@alicloud/nls-filetrans-2018-08-17');
const config = require('../config');

let cachedClient = null;

function speakerGapMs() {
  return config.aliyun.asrSpeakerGapMs;
}

function speakerOrphanMaxChars() {
  return config.aliyun.asrSpeakerOrphanMaxChars;
}

function isConfigured() {
  const a = config.aliyun;
  return !!(a.accessKeyId && a.accessKeySecret && a.nlsAppKey);
}

function getClient() {
  if (!isConfigured()) {
    throw Object.assign(new Error('语音转写服务未配置（需 ALIYUN_NLS_APP_KEY）'), {
      status: 503,
    });
  }
  if (cachedClient) return cachedClient;
  cachedClient = new Client({
    accessKeyId: config.aliyun.accessKeyId,
    secretAccessKey: config.aliyun.accessKeySecret,
    endpoint: config.aliyun.nlsEndpoint,
    apiVersion: '2018-08-17',
  });
  return cachedClient;
}

/**
 * 提交录音文件识别任务。
 * @param {string} fileLink 公网可访问的音频/视频 URL
 * @returns {Promise<{ taskId: string }>}
 */
async function submitFileTrans(fileLink) {
  const client = getClient();
  const task = JSON.stringify({
    appkey: config.aliyun.nlsAppKey,
    file_link: fileLink,
    version: '4.0',
    auto_split: true,
    enable_words: false,
    enable_sample_rate_adaptive: true,
  });
  const response = await client.submitTask({ Task: task }, { method: 'POST' });
  const statusText = response?.StatusText;
  if (statusText !== 'SUCCESS') {
    const err = new Error(
      `提交转写失败：${statusText || response?.StatusCode || '未知错误'}`,
    );
    err.status = 502;
    err.code = statusText || 'SUBMIT_FAILED';
    throw err;
  }
  const taskId = response?.TaskId;
  if (!taskId) {
    throw Object.assign(new Error('提交转写失败：未返回 TaskId'), {
      status: 502,
    });
  }
  return { taskId: String(taskId) };
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
  const client = getClient();
  const response = await client.getTaskResult({ TaskId: taskId });
  const statusText = String(response?.StatusText || '');

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

  if (statusText === 'SUCCESS') {
    const built = buildTranscriptFromResult(response?.Result);
    return {
      statusText,
      done: true,
      ok: true,
      text: built.text,
      cues: built.cues,
      errorMessage: null,
    };
  }

  if (statusText === 'SUCCESS_WITH_NO_VALID_FRAGMENT') {
    return {
      statusText,
      done: true,
      ok: true,
      text: '',
      cues: [],
      errorMessage: null,
    };
  }

  return {
    statusText,
    done: true,
    ok: false,
    text: null,
    cues: null,
    errorMessage: statusText || '转写失败',
  };
}

/** auto_split 分轨以 ChannelId 为准；部分 16k 结果带 SpeakerId / speaker_id */
function sentenceSpeakerId(sentence) {
  const channel = sentence?.ChannelId ?? sentence?.channel_id;
  if (channel != null && channel !== '') return `c:${channel}`;
  const id = sentence?.SpeakerId ?? sentence?.speaker_id;
  if (id == null || id === '') return null;
  return `s:${id}`;
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

/** NLS 文档写秒，实测部分结果更像毫秒；≤30 按秒，否则按毫秒 */
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
      return { text, cues: text ? [{ startMs: null, endMs: null, speaker: null, text }] : [] };
    }
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
  else if (piece.startMs != null) target.startMs = Math.min(target.startMs, piece.startMs);
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
        text: String(s?.Text || '').trim(),
        speakerId: sentenceSpeakerId(s),
        startMs: msOrNull(timing.beginTime),
        endMs: msOrNull(timing.endTime),
        silenceDuration: timing.silenceDuration,
        // gapBeforeSentence 仍读 beginTime/endTime
        beginTime: timing.beginTime,
        endTime: timing.endTime,
      };
    })
    .filter((s) => s.text);
  if (!items.length) return { text: '', cues: [] };

  items = smoothSpeakersByTiming(items);

  const speakerIds = new Set(
    items.map((s) => s.speakerId).filter((id) => id != null),
  );

  // 单人 / 无分轨：文稿连写；cues 按句保留时间点，避免整段只有 0:00
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
  groups = peelMisattributedPrefix(groups);
  groups = collapseFleetingSpeakerGroups(groups);
  groups = mergeConsecutiveSpeakerGroups(groups);
  groups = assignSpeakerLabels(groups);

  const cues = groups.map(toCue).filter((c) => c.text);
  const text = groups.map((g) => `说话人 ${g.label}：${g.text}`).join('\n\n');
  return { text, cues };
}

/** 去掉分轨误判导致的相邻重复 / 前缀重叠（同句被标成两个说话人） */
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

/**
 * NLS 常把误切短句与后续正文合在同一段（如「释放消费潜力。增强消费保障…」整段标成新说话人）。
 * 若新段以 ≤N 字的完整短句开头，将该短句剥回上一说话人。
 */
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
          // 剥走前缀后本段起点未知，保留原 startMs 作为近似
        }
      }
    }
    if (text) out.push({ speakerId: g.speakerId, text, startMs, endMs });
  }
  return out;
}

/**
 * 极短误切片段（整段仅一句）：如单独「释放消费潜力。」被标成新说话人。
 */
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

/** 按首次出现顺序映射为 说话人 1、2…，不直接用 API 原始 ChannelId */
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
};
