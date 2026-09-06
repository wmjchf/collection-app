const config = require('../config');
const { messageContentLen } = require('./aiInput');

function isConfigured() {
  return Boolean(config.aliyun.dashScopeApiKey);
}

function messageTextLen(content) {
  return messageContentLen(content);
}

function parseCacheCreationTokens(usage) {
  const u = usage || {};
  const details = u.prompt_tokens_details || u.promptTokensDetails || {};
  return (
    Number(details.cache_creation_input_tokens ?? details.cacheCreationInputTokens) ||
    0
  );
}

function parseCachedTokens(usage) {
  const u = usage || {};
  const details = u.prompt_tokens_details || u.promptTokensDetails || {};
  const fromDetails =
    Number(details.cached_tokens ?? details.cachedTokens) || 0;
  if (fromDetails > 0) return fromDetails;
  return Number(u.cached_tokens ?? u.cachedTokens) || 0;
}

/**
 * 调用百炼 OpenAI 兼容接口（qwen3.8-max 等）
 * @returns {Promise<{ json: object, usage: { promptTokens, completionTokens, totalTokens, cachedTokens, model } }>}
 */
async function chatJson({ messages, model }) {
  const apiKey = config.aliyun.dashScopeApiKey;
  if (!apiKey) {
    throw Object.assign(new Error('AI 未配置：请设置 DASHSCOPE_API_KEY'), {
      status: 503,
    });
  }

  const baseUrl = (config.aliyun.dashScopeBaseUrl || '').replace(/\/$/, '');
  const modelId = model || config.aliyun.aiModel || 'qwen3.8-max';

  const res = await fetch(`${baseUrl}/chat/completions`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: modelId,
      messages,
      response_format: { type: 'json_object' },
      enable_thinking: false,
    }),
  });

  const text = await res.text();
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    throw Object.assign(
      new Error(`AI 响应解析失败：${text.slice(0, 200)}`),
      { status: 502 },
    );
  }

  if (!res.ok) {
    const msg =
      body?.error?.message ||
      body?.message ||
      `AI 请求失败 (${res.status})`;
    throw Object.assign(new Error(msg), { status: 502 });
  }

  const content = body?.choices?.[0]?.message?.content;
  if (!content || typeof content !== 'string') {
    throw Object.assign(new Error('AI 返回为空'), { status: 502 });
  }

  let json;
  try {
    json = JSON.parse(content);
  } catch {
    throw Object.assign(new Error('AI 未返回合法 JSON'), { status: 502 });
  }

  const u = body?.usage || {};
  const promptTokens = Number(u.prompt_tokens) || 0;
  const completionTokens = Number(u.completion_tokens) || 0;
  const cachedTokens = parseCachedTokens(u);
  const cacheCreationTokens = parseCacheCreationTokens(u);
  let totalTokens = Number(u.total_tokens) || 0;
  if (totalTokens <= 0) {
    totalTokens = promptTokens + completionTokens;
  }
  if (totalTokens <= 0) {
    const chars =
      messages.reduce((n, m) => n + messageTextLen(m?.content), 0) +
      content.length;
    totalTokens = Math.max(1, Math.ceil(chars / 2));
  }

  if (cachedTokens > 0) {
    console.log(
      `[chatJson] context_cache hit model=${modelId} cached=${cachedTokens} prompt=${promptTokens}`,
    );
  } else if (cacheCreationTokens > 0) {
    console.log(
      `[chatJson] context_cache create model=${modelId} created=${cacheCreationTokens} prompt=${promptTokens}`,
    );
  }

  return {
    json,
    usage: {
      promptTokens,
      completionTokens,
      totalTokens,
      cachedTokens,
      cacheCreationTokens,
      model: modelId,
    },
  };
}

module.exports = {
  isConfigured,
  chatJson,
};
