const {
  ChatOpenAI,
  ChatOpenAICompletions,
} = require('@langchain/openai');
const { isAIMessage } = require('@langchain/core/messages');
const config = require('../../../config');

/**
 * 百炼兼容：把 LangChain AIMessage.additional_kwargs.reasoning_content
 * 写回 Chat Completions 的 assistant.reasoning_content（多轮 tool 必需）。
 */
function patchMappedWithReasoning(mapped, lcMessages) {
  if (!Array.isArray(mapped) || !Array.isArray(lcMessages)) return mapped;
  const ais = lcMessages.filter((m) => isAIMessage(m));
  let i = 0;
  return mapped.map((p) => {
    if (!p || p.role !== 'assistant') return p;
    const src = ais[i++];
    const rc = src?.additional_kwargs?.reasoning_content;
    if (typeof rc === 'string' && rc) {
      return { ...p, reasoning_content: rc };
    }
    return p;
  });
}

/**
 * DashScope Completions：流式/非流式请求前注入 reasoning_content。
 */
class DashScopeCompletions extends ChatOpenAICompletions {
  constructor(fields) {
    super(fields);
    this._pendingLcMessages = null;
  }

  async *_streamResponseChunks(messages, options, runManager) {
    this._pendingLcMessages = messages;
    try {
      yield* super._streamResponseChunks(messages, options, runManager);
    } finally {
      this._pendingLcMessages = null;
    }
  }

  async _generate(messages, options, runManager) {
    this._pendingLcMessages = messages;
    try {
      return await super._generate(messages, options, runManager);
    } finally {
      this._pendingLcMessages = null;
    }
  }

  async completionWithRetry(request, requestOptions) {
    let next = request;
    if (request?.messages && this._pendingLcMessages) {
      next = {
        ...request,
        messages: patchMappedWithReasoning(
          request.messages,
          this._pendingLcMessages,
        ),
      };
    }
    return super.completionWithRetry(next, requestOptions);
  }
}

/**
 * 助手用 Chat：默认开百炼 think（enable_thinking）。
 * @param {{
 *   temperature?: number,
 *   enableThinking?: boolean,
 *   purpose?: 'agent'|'search',
 *   model?: string,
 * }} [opts]
 */
function createAgentChatModel(opts = {}) {
  const apiKey = config.aliyun.dashScopeApiKey;
  if (!apiKey) {
    throw Object.assign(new Error('AI 未配置：请设置 DASHSCOPE_API_KEY'), {
      status: 503,
    });
  }
  const baseURL = (config.aliyun.dashScopeBaseUrl || '').replace(/\/$/, '');
  const purpose = opts.purpose === 'search' ? 'search' : 'agent';
  const model =
    (opts.model && String(opts.model).trim()) ||
    (purpose === 'search'
      ? config.aliyun.aiModelAgentSearch
      : config.aliyun.aiModelAgent) ||
    config.aliyun.aiModel ||
    'qwen3.8-flash';
  const temperature =
    opts.temperature != null && Number.isFinite(Number(opts.temperature))
      ? Number(opts.temperature)
      : 0.3;
  const enableThinking = opts.enableThinking !== false;

  const fields = {
    model,
    apiKey,
    temperature,
    streaming: true,
    streamUsage: true,
    configuration: { baseURL },
    modelKwargs: enableThinking ? { enable_thinking: true } : {},
  };

  return new ChatOpenAI({
    ...fields,
    completions: new DashScopeCompletions(fields),
  });
}

/**
 * 本轮 ReAct 是否用 Agentic Search 模型（与深挖/打标等分开）。
 * @param {{ userText?: string, hasFocus?: boolean }} args
 */
function preferSearchChatModel({ userText, hasFocus } = {}) {
  const t = String(userText || '').trim();
  if (!t) return !hasFocus;

  // 打标 / 推荐标签 / 偏好：走 agent
  if (
    /帮我归类|整理归类|推荐标签|打标|改标签|加减标签|记住|偏好/.test(t)
  ) {
    return false;
  }
  // 文稿 / 成文：走 agent
  if (/生成文稿|转写|整理成一篇|整理成文章|根据图片整理/.test(t)) {
    return false;
  }

  if (hasFocus) {
    // 阅读页：找类似 / 搜库 → search；总结深挖等 → agent
    return /找类似|类似的|还有没有|库里|搜一?下|查找|关于.+的|存过|收藏里/.test(
      t,
    );
  }

  // 全局：盘点也可 search 模型；默认偏检索
  return true;
}

module.exports = {
  createAgentChatModel,
  preferSearchChatModel,
  DashScopeCompletions,
  patchMappedWithReasoning,
};
