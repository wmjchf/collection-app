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
 * @param {{ temperature?: number, enableThinking?: boolean }} [opts]
 */
function createAgentChatModel(opts = {}) {
  const apiKey = config.aliyun.dashScopeApiKey;
  if (!apiKey) {
    throw Object.assign(new Error('AI 未配置：请设置 DASHSCOPE_API_KEY'), {
      status: 503,
    });
  }
  const baseURL = (config.aliyun.dashScopeBaseUrl || '').replace(/\/$/, '');
  const model =
    config.aliyun.aiModelAgent || config.aliyun.aiModel || 'qwen3.8-flash';
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

module.exports = {
  createAgentChatModel,
  DashScopeCompletions,
  patchMappedWithReasoning,
};
