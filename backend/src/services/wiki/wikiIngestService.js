const { pool } = require('../../db');
const config = require('../../config');
const aliyunDashScope = require('../aliyunDashScope');
const {
  hasAiInput,
  buildInputText,
  computeContentHash,
} = require('../aiInput');
const { peekGalleryVisual } = require('../agent/tools/peekGalleryVisual');
const { isGalleryItem } = require('../agent/tools/draftFromGallery');
const { WIKI_INGEST_SYSTEM } = require('./wikiSchemaPrompt');
const wikiStore = require('./wikiStore');

const INPUT_MAX = 8000;
const BODY_MAX = 1200;

function ingestModelId() {
  return (
    config.aliyun.aiModelAgentSearch ||
    config.aliyun.aiModelTags ||
    config.aliyun.aiModelAgent ||
    'qwen3.8-flash'
  );
}

/**
 * 解析成功 / 转写成功 / 改正文后：入队 Wiki ingest（免费、不计额度）。
 */
function schedule(itemId) {
  const { enqueueWikiIngest } = require('./wikiIngestQueue');
  enqueueWikiIngest(itemId);
}

function sourceSlugForItem(itemId) {
  return `src-${Number(itemId)}`;
}

/**
 * @param {number} itemId
 */
async function runWikiIngestJob(itemId) {
  const id = Number(itemId);
  if (!id) return;

  if (!aliyunDashScope.isConfigured()) {
    console.warn(`[wikiIngest] skip item=${id}: DashScope 未配置`);
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

  const userId = Number(row.user_id);
  const contentHash = computeContentHash(row);
  const existing = await wikiStore.getSourcePageByItem(userId, id);
  if (
    existing &&
    String(existing.content_hash || '').trim() === contentHash
  ) {
    return;
  }

  let input = buildInputText(row);
  if (input.length > INPUT_MAX) {
    input = `${input.slice(0, INPUT_MAX)}…`;
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
        `[wikiIngest] gallery VL fail item=${id}:`,
        err?.message || err,
      );
    }
  }

  let parsed = null;
  try {
    const { json } = await aliyunDashScope.chatJson({
      model: ingestModelId(),
      temperature: 0.2,
      messages: [
        { role: 'system', content: WIKI_INGEST_SYSTEM },
        { role: 'user', content: input },
      ],
    });
    parsed = json;
  } catch (err) {
    console.warn(`[wikiIngest] LLM fail item=${id}:`, err?.message || err);
    return;
  }

  const sourceIn = parsed?.source || parsed || {};
  const title = String(
    sourceIn.title || row.title || row.url || `条目 ${id}`,
  )
    .trim()
    .slice(0, 255);
  let body = String(sourceIn.body || sourceIn.digest || '')
    .trim()
    .slice(0, BODY_MAX);
  if (!body) return;
  const summary = String(sourceIn.summary || body.slice(0, 40))
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 400);

  const sourcePage = await wikiStore.upsertPage(userId, {
    kind: 'source',
    slug: sourceSlugForItem(id),
    title,
    body,
    summary,
    itemId: id,
    contentHash,
  });
  if (!sourcePage?.id) return;

  const entitiesRaw = Array.isArray(parsed?.entities)
    ? parsed.entities
    : Array.isArray(parsed?.entityMentions)
      ? parsed.entityMentions
      : [];
  const entities = entitiesRaw.slice(0, wikiStore.MAX_ENTITY_TOUCH);
  let linked = 0;

  for (const ent of entities) {
    const name = String(ent?.name || '').trim();
    if (!name) continue;
    const kind =
      String(ent?.kind || '').toLowerCase() === 'concept'
        ? 'concept'
        : 'entity';
    const slug = wikiStore.normalizeSlug(ent?.slug || name);
    const aliases = Array.isArray(ent?.aliases)
      ? ent.aliases.map((a) => String(a).trim()).filter(Boolean)
      : [];
    const existingEnt = await wikiStore.getPage(userId, { kind, slug });
    let entPage = existingEnt;
    if (!entPage) {
      const entBodyParts = [
        `# ${name}`,
        aliases.length ? `别名：${aliases.join('、')}` : '',
        `（由收藏编译；主题相关时可读本页再回源页）`,
      ].filter(Boolean);
      entPage = await wikiStore.upsertPage(userId, {
        kind,
        slug,
        title: name.slice(0, 255),
        body: entBodyParts.join('\n\n'),
        summary: name.slice(0, 40),
      });
    } else if (existingEnt.title !== name) {
      await wikiStore.upsertPage(userId, {
        kind,
        slug,
        title: name.slice(0, 255),
        body: existingEnt.body,
        summary: name.slice(0, 40),
      });
      entPage = await wikiStore.getPage(userId, { kind, slug });
    }
    if (!entPage?.id) continue;
    entPage = await wikiStore.appendSeenIn(
      userId,
      entPage.id,
      title,
      sourcePage.slug,
    );
    await wikiStore.upsertLink(
      userId,
      sourcePage.id,
      entPage.id,
      'mentions',
    );
    await wikiStore.upsertLink(userId, entPage.id, sourcePage.id, 'about');
    linked += 1;
    try {
      const wikiEmbeddingService = require('./wikiEmbeddingService');
      wikiEmbeddingService.scheduleIndexPage(userId, entPage.id);
    } catch (_) {
      /* optional */
    }
  }

  await wikiStore.refreshIndexPage(userId);
  await wikiStore.appendLog(userId, 'ingest', {
    itemId: id,
    detail: `source=${sourcePage.slug}; entities=${linked}; hash=${contentHash}`,
  });

  // 每 N 次 ingest 触发轻量 lint（异步、不阻塞）
  if (id % 7 === 0) {
    try {
      const { scheduleWikiLint } = require('./wikiLintService');
      scheduleWikiLint(userId);
    } catch (_) {
      /* optional */
    }
  }
}

/**
 * 存量批 ingest：status=success 且尚无 source 页（或强制）。
 * CLI 会串行 await 跑完（不再入队后立刻退出）。
 * @param {{ userId?: number, limit?: number, force?: boolean }} opts
 */
async function backfillMissing({ userId, limit = 50, force = false } = {}) {
  const lim = Math.min(Math.max(Number(limit) || 50, 1), 500);
  let sql = `
    SELECT i.id
    FROM items i
    LEFT JOIN wiki_pages w
      ON w.item_id = i.id AND w.kind = 'source' AND w.user_id = i.user_id
    WHERE i.deleted_at IS NULL
      AND i.status = 'success'
  `;
  const params = {};
  if (userId) {
    sql += ` AND i.user_id = :userId`;
    params.userId = Number(userId);
  }
  if (!force) {
    sql += ` AND w.id IS NULL`;
  }
  sql += ` ORDER BY i.id DESC LIMIT ${lim}`;

  const [rows] = await pool.execute(sql, params);
  let ok = 0;
  let failed = 0;
  const total = rows.length;
  for (let i = 0; i < total; i += 1) {
    const id = Number(rows[i].id);
    const n = i + 1;
    try {
      await runWikiIngestJob(id);
      ok += 1;
      console.log(`[wiki-backfill] ${n}/${total} item=${id} ok`);
    } catch (err) {
      failed += 1;
      console.error(
        `[wiki-backfill] ${n}/${total} item=${id} fail:`,
        err?.message || err,
      );
    }
  }
  return { queued: total, ok, failed };
}

module.exports = {
  schedule,
  runWikiIngestJob,
  backfillMissing,
};
