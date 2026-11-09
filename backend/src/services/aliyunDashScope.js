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

function parseEmbeddingUsage(raw) {
  if (!raw || typeof raw !== 'object') {
    return { promptTokens: 0, totalTokens: 0, textTokens: 0, imageTokens: 0 };
  }
  const promptTokens = Math.round(
    Number(raw.prompt_tokens ?? raw.input_tokens ?? 0) || 0,
  );
  const imageTokens = Math.round(Number(raw.image_tokens ?? 0) || 0);
  const totalTokens = Math.round(
    Number(raw.total_tokens ?? promptTokens + imageTokens) || 0,
  );
  const textTokens = Math.max(0, totalTokens - imageTokens) || promptTokens;
  return { promptTokens, totalTokens, textTokens, imageTokens };
}

/**
 * 文本向量（百炼 OpenAI 兼容 /embeddings）
 * @param {string[]} texts
 * @returns {Promise<{ vectors: number[][], model: string, dims: number, usage: object }>}
 */
async function embedTexts(texts) {
  const apiKey = config.aliyun.dashScopeApiKey;
  if (!apiKey) {
    throw Object.assign(new Error('AI 未配置：请设置 DASHSCOPE_API_KEY'), {
      status: 503,
    });
  }
  const list = (Array.isArray(texts) ? texts : [])
    .map((t) => String(t || '').trim())
    .filter(Boolean);
  if (!list.length) {
    return {
      vectors: [],
      model: '',
      dims: 0,
      usage: { promptTokens: 0, totalTokens: 0, textTokens: 0, imageTokens: 0 },
    };
  }

  const baseUrl = (config.aliyun.dashScopeBaseUrl || '').replace(/\/$/, '');
  const modelId = config.aliyun.embeddingModel || 'qwen3.7-text-embedding';
  const dims = Number(config.aliyun.embeddingDims) || 1024;

  const payload = {
    model: modelId,
    input: list,
    dimensions: dims,
    encoding_format: 'float',
  };

  const res = await fetch(`${baseUrl}/embeddings`, {
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
      new Error(`Embedding 响应解析失败：${text.slice(0, 200)}`),
      { status: 502 },
    );
  }
  if (!res.ok) {
    const msg =
      body?.error?.message ||
      body?.message ||
      `Embedding 请求失败 (${res.status})`;
    throw Object.assign(new Error(msg), { status: 502 });
  }

  const data = Array.isArray(body?.data) ? body.data : [];
  const sorted = [...data].sort(
    (a, b) => Number(a?.index || 0) - Number(b?.index || 0),
  );
  const vectors = sorted.map((row) => {
    const emb = row?.embedding;
    if (!Array.isArray(emb) || !emb.length) {
      throw Object.assign(new Error('Embedding 返回为空向量'), { status: 502 });
    }
    return emb.map((n) => Number(n) || 0);
  });
  if (vectors.length !== list.length) {
    throw Object.assign(
      new Error(`Embedding 条数不匹配：${vectors.length}/${list.length}`),
      { status: 502 },
    );
  }
  return {
    vectors,
    model: modelId,
    dims: vectors[0]?.length || dims,
    usage: parseEmbeddingUsage(body?.usage),
  };
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

/**
 * 多模态向量（文 / 图同一语义空间）。原生 API，非 OpenAI 兼容。
 * @param {Array<{ text?: string, image?: string }>} contents
 * @returns {Promise<{ vectors: number[][], model: string, dims: number, usage: object }>}
 */
async function embedMultimodal(contents) {
  const apiKey = config.aliyun.dashScopeApiKey;
  if (!apiKey) {
    throw Object.assign(new Error('AI 未配置：请设置 DASHSCOPE_API_KEY'), {
      status: 503,
    });
  }
  const list = (Array.isArray(contents) ? contents : [])
    .map((c) => {
      if (!c || typeof c !== 'object') return null;
      if (c.image) return { image: String(c.image).trim() };
      if (c.text) return { text: String(c.text).trim() };
      return null;
    })
    .filter((c) => c && (c.image || c.text));
  if (!list.length) {
    return {
      vectors: [],
      model: '',
      dims: 0,
      usage: { promptTokens: 0, totalTokens: 0, textTokens: 0, imageTokens: 0 },
    };
  }

  const modelId =
    config.aliyun.multimodalEmbeddingModel || 'qwen3-vl-embedding';
  const dimsWanted = Number(config.aliyun.multimodalEmbeddingDims) || 1024;
  const root = getDashScopeApiRoot();
  const url = `${root}/api/v1/services/embeddings/multimodal-embedding/multimodal-embedding`;

  // multimodal-embedding-v1：单次最多 1 张图；qwen3-vl-embedding 等可多图独立向量
  const oneImagePerBatch = /^multimodal-embedding-v1$/i.test(modelId);
  const maxImagesPerBatch = oneImagePerBatch ? 1 : 10;
  const batches = [];
  let textBuf = [];
  let imageBuf = [];
  const flushTexts = () => {
    if (!textBuf.length) return;
    batches.push([...textBuf]);
    textBuf = [];
  };
  const flushImages = () => {
    if (!imageBuf.length) return;
    batches.push([...imageBuf]);
    imageBuf = [];
  };
  for (const item of list) {
    if (item.image) {
      flushTexts();
      imageBuf.push(item);
      if (imageBuf.length >= maxImagesPerBatch) flushImages();
    } else {
      flushImages();
      textBuf.push(item);
      if (textBuf.length >= 16) flushTexts();
    }
  }
  flushImages();
  flushTexts();

  const supportsDimension = !/^multimodal-embedding-v1$/i.test(modelId);
  const vectors = [];
  const usageAcc = {
    promptTokens: 0,
    totalTokens: 0,
    textTokens: 0,
    imageTokens: 0,
  };
  for (const batch of batches) {
    const payload = {
      model: modelId,
      input: { contents: batch },
    };
    if (supportsDimension && dimsWanted > 0) {
      payload.parameters = { dimension: dimsWanted };
    }
    const res = await fetch(url, {
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
        new Error(`多模态 Embedding 响应解析失败：${text.slice(0, 200)}`),
        { status: 502 },
      );
    }
    if (!res.ok) {
      const msg =
        body?.message ||
        body?.code ||
        body?.error?.message ||
        `多模态 Embedding 失败 (${res.status})`;
      throw Object.assign(new Error(String(msg)), { status: 502 });
    }
    const usage = parseEmbeddingUsage(body?.usage || body?.output?.usage);
    usageAcc.promptTokens += usage.promptTokens;
    usageAcc.totalTokens += usage.totalTokens;
    usageAcc.textTokens += usage.textTokens;
    usageAcc.imageTokens += usage.imageTokens;
    const embeddings =
      body?.output?.embeddings ||
      body?.embeddings ||
      body?.data ||
      [];
    const arr = Array.isArray(embeddings) ? embeddings : [];
    const sorted = [...arr].sort(
      (a, b) => Number(a?.index ?? 0) - Number(b?.index ?? 0),
    );
    for (const row of sorted) {
      const emb = row?.embedding;
      if (!Array.isArray(emb) || !emb.length) {
        throw Object.assign(new Error('多模态 Embedding 返回空向量'), {
          status: 502,
        });
      }
      vectors.push(emb.map((n) => Number(n) || 0));
    }
  }

  if (vectors.length !== list.length) {
    throw Object.assign(
      new Error(
        `多模态 Embedding 条数不匹配：${vectors.length}/${list.length}`,
      ),
      { status: 502 },
    );
  }

  return {
    vectors,
    model: modelId,
    dims: vectors[0]?.length || dimsWanted || 1024,
    usage: usageAcc,
  };
}

/** 查询文本 → 多模态空间向量（用于文搜图） */
async function embedMultimodalText(text) {
  const t = String(text || '').trim().slice(0, 500);
  if (!t) return { vectors: [], model: '', dims: 0 };
  return embedMultimodal([{ text: t }]);
}

/** 单张图片 URL → 向量 */
async function embedMultimodalImage(imageUrl) {
  const url = String(imageUrl || '').trim();
  if (!/^https?:\/\//i.test(url)) {
    return { vectors: [], model: '', dims: 0 };
  }
  return embedMultimodal([{ image: url }]);
}

module.exports = {
  isConfigured,
  chatJson,
  chatTextStream,
  embedTexts,
  embedMultimodal,
  embedMultimodalText,
  embedMultimodalImage,
  getDashScopeApiRoot,
};
