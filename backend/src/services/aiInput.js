const crypto = require('crypto');
const transcriptSegments = require('./transcriptSegments');

const CONTENT_LIMIT = 8000;
const TRANSCRIPT_LIMIT = 6000;

function stripMarkdown(text) {
  return String(text || '')
    .replace(/!v?\[[^\]]*\]\([^)]+\)/g, ' ')
    .replace(/!\[[^\]]*\]\([^)]+\)/g, ' ')
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    .replace(/[#>*`_~-]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function collectTranscriptText(row) {
  const segments = transcriptSegments.parseSegments(row.transcript_segments);
  const parts = [];
  for (const seg of Object.values(segments)) {
    const t = (seg?.text || '').trim();
    if (t) parts.push(t);
  }
  return parts.join('\n\n');
}

function hasAiInput(row) {
  const title = (row.title || '').trim();
  const content = stripMarkdown(row.content || '');
  const summary = (row.summary || '').trim();
  const transcript = collectTranscriptText(row);
  return Boolean(title || content || summary || transcript);
}

function buildInputText(row) {
  const parts = [];
  const title = (row.title || '').trim();
  const summary = (row.summary || '').trim();
  const platform = (row.platform || '').trim();
  if (title) parts.push(`标题：${title}`);
  if (platform) parts.push(`来源：${platform}`);
  if (summary) parts.push(`摘要：${summary}`);
  const content = stripMarkdown(row.content || '').slice(0, CONTENT_LIMIT);
  if (content) parts.push(`正文：${content}`);
  const transcript = collectTranscriptText(row).slice(0, TRANSCRIPT_LIMIT);
  if (transcript) parts.push(`文稿：${transcript}`);
  return parts.join('\n\n');
}

function computeContentHash(row) {
  return crypto
    .createHash('sha256')
    .update(buildInputText(row))
    .digest('hex')
    .slice(0, 24);
}

/**
 * 百炼隐式缓存：稳定正文放前，任务/重新生成放后（Context Cache 文档建议）。
 */
function buildAiUserMessage(inputText, taskTail) {
  const body = String(inputText || '').trim();
  const tail = String(taskTail || '').trim();
  if (!body) return tail;
  if (!tail) return body;
  return `${body}\n\n${tail}`;
}

function messageContentLen(content) {
  if (typeof content === 'string') return content.length;
  if (!Array.isArray(content)) return 0;
  return content.reduce((n, part) => {
    if (typeof part === 'string') return n + part.length;
    if (part && typeof part === 'object') {
      return n + String(part.text || part.content || '').length;
    }
    return n;
  }, 0);
}

/**
 * 百炼显式 Context Cache：正文放入带 cache_control 的 system 块（跨功能相同），
 * 任务说明放 user（总结/标签/脑图各异）。5 分钟内同一篇文章后续功能可命中。
 * @see https://help.aliyun.com/zh/model-studio/context-cache
 */
function buildExplicitCacheMessages(inputText, taskContent) {
  const body = String(inputText || '').trim();
  const task = String(taskContent || '').trim();
  if (!body) {
    return task ? [{ role: 'user', content: task }] : [];
  }
  const messages = [
    {
      role: 'system',
      content: [
        {
          type: 'text',
          text: body,
          cache_control: { type: 'ephemeral' },
        },
      ],
    },
  ];
  if (task) {
    messages.push({ role: 'user', content: task });
  }
  return messages;
}

/** @param {string} inputText @param {Array<string | null | undefined>} taskParts */
function buildAiTaskMessages(inputText, taskParts) {
  const taskContent = (Array.isArray(taskParts) ? taskParts : [taskParts])
    .map((p) => String(p || '').trim())
    .filter(Boolean)
    .join('\n\n');
  return buildExplicitCacheMessages(inputText, taskContent);
}

module.exports = {
  CONTENT_LIMIT,
  TRANSCRIPT_LIMIT,
  stripMarkdown,
  collectTranscriptText,
  hasAiInput,
  buildInputText,
  computeContentHash,
  buildAiUserMessage,
  messageContentLen,
  buildExplicitCacheMessages,
  buildAiTaskMessages,
};
