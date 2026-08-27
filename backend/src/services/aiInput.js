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

module.exports = {
  CONTENT_LIMIT,
  TRANSCRIPT_LIMIT,
  stripMarkdown,
  collectTranscriptText,
  hasAiInput,
  buildInputText,
  computeContentHash,
};
