const { pool } = require('../db');
const config = require('../config');
const aliyunDashScope = require('./aliyunDashScope');
const {
  hasAiInput,
  buildInputText,
  computeContentHash,
} = require('./aiInput');
const { peekGalleryVisual } = require('./agent/tools/peekGalleryVisual');
const { isGalleryItem } = require('./agent/tools/draftFromGallery');

const DIGEST_INPUT_MAX = 8000;
const DIGEST_OUT_MAX = 400;

const DIGEST_SYSTEM = `你在为「收藏库检索」写检索卡，供助手判断篇目是否相关，用户看不到。
根据输入用中文写 80～180 字：这篇大概讲什么、主题与关键实体/场景即可。
若有「画面要点」，须融入检索卡（体裁/画面在讲什么），不要单独复述成看图报告。
不要解读、不要条目列表、不要「这篇文章/本文/作者认为」等套话，不要编造输入没有的信息。
只输出 JSON：{"digest":"..."}`;

function digestModelId() {
  return (
    config.aliyun.aiModelAgentSearch ||
    config.aliyun.aiModelTags ||
    config.aliyun.aiModelAgent ||
    'qwen3.8-flash'
  );
}

/**
 * 解析成功 / 转写成功 / 改正文后：入队生成检索卡（免费、不计额度）。
 * 图集会先 VL 前 1～2 张，把画面要点写进卡。
 */
function scheduleAfterContentChange(itemId) {
  const { enqueueAgentDigest } = require('./agentDigestQueue');
  enqueueAgentDigest(itemId);
}

async function runAgentDigestJob(itemId) {
  const id = Number(itemId);
  if (!id) return;

  if (!aliyunDashScope.isConfigured()) {
    console.warn(`[agentDigest] skip item=${id}: DashScope 未配置`);
    return;
  }

  const [rows] = await pool.execute(
    `SELECT * FROM items WHERE id = :itemId AND deleted_at IS NULL LIMIT 1`,
    { itemId: id },
  );
  const row = rows[0];
  if (!row) return;
  if (String(row.status || '') !== 'success') return;
  if (!hasAiInput(row)) return;

  const contentHash = computeContentHash(row);
  const existing = String(row.agent_digest || '').trim();
  const existingHash = String(row.agent_digest_hash || '').trim();
  if (existing && existingHash && existingHash === contentHash) {
    return;
  }

  let input = buildInputText(row);
  if (input.length > DIGEST_INPUT_MAX) {
    input = `${input.slice(0, DIGEST_INPUT_MAX)}…`;
  }

  if (isGalleryItem(row)) {
    try {
      const visual = await peekGalleryVisual(row);
      if (visual?.notes) {
        input +=
          `\n\n画面要点（已看前 ${visual.imagesUsed}/${visual.imagesTotal} 张）：\n` +
          visual.notes;
      }
    } catch (err) {
      console.warn(
        `[agentDigest] gallery VL fail item=${id}:`,
        err?.message || err,
      );
    }
  }

  let digest = '';
  try {
    const { json } = await aliyunDashScope.chatJson({
      model: digestModelId(),
      temperature: 0.2,
      messages: [
        { role: 'system', content: DIGEST_SYSTEM },
        { role: 'user', content: input },
      ],
    });
    digest = String(json?.digest || json?.text || '')
      .replace(/\s+/g, ' ')
      .trim()
      .slice(0, DIGEST_OUT_MAX);
  } catch (err) {
    console.warn(
      `[agentDigest] LLM fail item=${id}:`,
      err?.message || err,
    );
    return;
  }

  if (!digest) return;

  await pool.execute(
    `UPDATE items
     SET agent_digest = :digest,
         agent_digest_hash = :hash
     WHERE id = :itemId AND deleted_at IS NULL`,
    { itemId: id, digest, hash: contentHash },
  );
}

module.exports = {
  scheduleAfterContentChange,
  runAgentDigestJob,
};
