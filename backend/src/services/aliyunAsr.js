const Client = require('@alicloud/nls-filetrans-2018-08-17');
const config = require('../config');

let cachedClient = null;

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
      errorMessage: null,
    };
  }

  if (statusText === 'SUCCESS') {
    return {
      statusText,
      done: true,
      ok: true,
      text: flattenResult(response?.Result),
      errorMessage: null,
    };
  }

  if (statusText === 'SUCCESS_WITH_NO_VALID_FRAGMENT') {
    return {
      statusText,
      done: true,
      ok: true,
      text: '',
      errorMessage: null,
    };
  }

  return {
    statusText,
    done: true,
    ok: false,
    text: null,
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

function flattenResult(result) {
  if (!result) return '';
  let parsed = result;
  if (typeof result === 'string') {
    try {
      parsed = JSON.parse(result);
    } catch {
      return result.trim();
    }
  }
  const sentences = parsed?.Sentences;
  if (Array.isArray(sentences) && sentences.length) {
    return formatSentencesWithSpeakers(sentences);
  }
  if (typeof parsed?.Text === 'string') return parsed.Text.trim();
  return '';
}

/** 合并同说话人连续句；多人时段首「说话人 N：」，单人或无分轨信息时纯连写 */
function formatSentencesWithSpeakers(sentences) {
  const items = sentences
    .map((s) => ({
      text: String(s?.Text || '').trim(),
      speakerId: sentenceSpeakerId(s),
    }))
    .filter((s) => s.text);
  if (!items.length) return '';

  const speakerIds = new Set(
    items.map((s) => s.speakerId).filter((id) => id != null),
  );
  if (speakerIds.size <= 1) {
    return items.map((s) => s.text).join('');
  }

  let groups = [];
  for (const item of items) {
    const last = groups[groups.length - 1];
    if (last && last.speakerId === item.speakerId) {
      last.text += item.text;
    } else {
      groups.push({ speakerId: item.speakerId, text: item.text });
    }
  }

  groups = dedupeAdjacentSpeakerGroups(groups);
  groups = mergeConsecutiveSpeakerGroups(groups);
  groups = assignSpeakerLabels(groups);

  return groups
    .map((g) => `说话人 ${g.label}：${g.text}`)
    .join('\n\n');
}

/** 去掉分轨误判导致的相邻重复 / 前缀重叠（同句被标成两个说话人） */
function dedupeAdjacentSpeakerGroups(groups) {
  const out = [];
  for (const g of groups) {
    const text = g.text.trim();
    if (!text) continue;
    const prev = out[out.length - 1];
    if (!prev) {
      out.push({ speakerId: g.speakerId, text });
      continue;
    }
    if (text === prev.text.trim()) continue;
    if (
      prev.speakerId !== g.speakerId &&
      text.startsWith(prev.text.trim())
    ) {
      const suffix = text.slice(prev.text.trim().length).trim();
      if (suffix) out.push({ speakerId: g.speakerId, text: suffix });
      continue;
    }
    out.push({ speakerId: g.speakerId, text });
  }
  return out;
}

function mergeConsecutiveSpeakerGroups(groups) {
  const out = [];
  for (const g of groups) {
    const last = out[out.length - 1];
    if (last && last.speakerId === g.speakerId) {
      last.text += g.text;
    } else {
      out.push({ speakerId: g.speakerId, text: g.text });
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
};
