const config = require('../config');

function isConfigured() {
  return Boolean(config.aliyun.dashScopeApiKey);
}

/**
 * 调用百炼 OpenAI 兼容接口（qwen3.8-max 等）
 * @returns {Promise<{ json: object, usage: { promptTokens: number, completionTokens: number, totalTokens: number } }>}
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
  let totalTokens = Number(u.total_tokens) || 0;
  if (totalTokens <= 0) {
    totalTokens = promptTokens + completionTokens;
  }
  // 接口偶发不带 usage：按内容长度粗估，避免漏记
  if (totalTokens <= 0) {
    const chars = messages.reduce(
      (n, m) => n + String(m?.content || '').length,
      0,
    ) + content.length;
    totalTokens = Math.max(1, Math.ceil(chars / 2));
  }

  return {
    json,
    usage: {
      promptTokens,
      completionTokens,
      totalTokens,
      model: modelId,
    },
  };
}

module.exports = {
  isConfigured,
  chatJson,
};
