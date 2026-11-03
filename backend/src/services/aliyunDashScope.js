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
async function chatJson({ messages, model, temperature }) {
  const apiKey = config.aliyun.dashScopeApiKey;
  if (!apiKey) {
    throw Object.assign(new Error('AI 未配置：请设置 DASHSCOPE_API_KEY'), {
      status: 503,
    });
  }

  const baseUrl = (config.aliyun.dashScopeBaseUrl || '').replace(/\/$/, '');
  const modelId = model || config.aliyun.aiModel || 'qwen3.8-max';

  const payload = {
    model: modelId,
    messages,
    response_format: { type: 'json_object' },
    enable_thinking: false,
  };
  if (temperature != null && Number.isFinite(Number(temperature))) {
    payload.temperature = Number(temperature);
  }

  const res = await fetch(`${baseUrl}/chat/completions`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
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

/**
 * 流式纯文本补全（OpenAI 兼容 SSE）。
 * yield: { delta?: string, usage?: object }
 */
async function* chatTextStream({ messages, model, temperature }) {
  const apiKey = config.aliyun.dashScopeApiKey;
  if (!apiKey) {
    throw Object.assign(new Error('AI 未配置：请设置 DASHSCOPE_API_KEY'), {
      status: 503,
    });
  }

  const baseUrl = (config.aliyun.dashScopeBaseUrl || '').replace(/\/$/, '');
  const modelId = model || config.aliyun.aiModel || 'qwen3.8-max';

  const payload = {
    model: modelId,
    messages,
    stream: true,
    enable_thinking: false,
    stream_options: { include_usage: true },
  };
  if (temperature != null && Number.isFinite(Number(temperature))) {
    payload.temperature = Number(temperature);
  }

  const res = await fetch(`${baseUrl}/chat/completions`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
      Accept: 'text/event-stream',
    },
    body: JSON.stringify(payload),
  });

  if (!res.ok) {
    const errText = await res.text();
    let msg = `AI 请求失败 (${res.status})`;
    try {
      const body = JSON.parse(errText);
      msg = body?.error?.message || body?.message || msg;
    } catch {
      if (errText) msg = errText.slice(0, 200);
    }
    throw Object.assign(new Error(msg), { status: 502 });
  }

  if (!res.body) {
    throw Object.assign(new Error('AI 未返回流'), { status: 502 });
  }

  const reader = res.body.getReader();
  const decoder = new TextDecoder('utf-8');
  let buffer = '';
  let usage = null;

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const parts = buffer.split('\n');
    buffer = parts.pop() || '';
    for (const rawLine of parts) {
      const line = rawLine.trim();
      if (!line || line.startsWith(':')) continue;
      if (!line.startsWith('data:')) continue;
      const data = line.slice(5).trim();
      if (data === '[DONE]') continue;
      let json;
      try {
        json = JSON.parse(data);
      } catch {
        continue;
      }
      const delta = json?.choices?.[0]?.delta?.content;
      if (typeof delta === 'string' && delta) {
        yield { delta };
      }
      if (json?.usage) {
        usage = json.usage;
      }
    }
  }

  if (usage) {
    const promptTokens = Number(usage.prompt_tokens) || 0;
    const completionTokens = Number(usage.completion_tokens) || 0;
    let totalTokens = Number(usage.total_tokens) || 0;
    if (totalTokens <= 0) totalTokens = promptTokens + completionTokens;
    yield {
      usage: {
        promptTokens,
        completionTokens,
        totalTokens,
        cachedTokens: parseCachedTokens(usage),
        cacheCreationTokens: parseCacheCreationTokens(usage),
        model: modelId,
      },
    };
  }
}

module.exports = {
  isConfigured,
  chatJson,
  chatTextStream,
};
