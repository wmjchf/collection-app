const config = require('../../config');
const aliyunDashScope = require('../aliyunDashScope');
const { WIKI_LINT_SYSTEM } = require('./wikiSchemaPrompt');
const wikiStore = require('./wikiStore');

const pendingUsers = new Set();

function lintModelId() {
  return (
    config.aliyun.aiModelAgentSearch ||
    config.aliyun.aiModelTags ||
    config.aliyun.aiModelAgent ||
    'qwen3.8-flash'
  );
}

function scheduleWikiLint(userId) {
  const uid = Number(userId);
  if (!uid || pendingUsers.has(uid)) return;
  pendingUsers.add(uid);
  setImmediate(async () => {
    try {
      await runWikiLint(uid);
    } catch (err) {
      console.error(`[wikiLint] user=${uid} failed`, err);
    } finally {
      pendingUsers.delete(uid);
    }
  });
}

/**
 * 规则 + 偶发 LLM：孤儿实体、断链候选；只写 log。
 */
async function runWikiLint(userId) {
  const uid = Number(userId);
  if (!uid) return;

  const orphans = await wikiStore.listOrphanEntityPages(uid, 40);
  const pages = await wikiStore.listPages(uid, {
    kinds: ['source', 'entity', 'concept'],
    limit: 80,
    withBody: true,
  });

  const broken = [];
  for (const p of pages) {
    const body = String(p.body || '');
    const re = /\[\[([^\]|#]+)(?:\|[^\]]+)?\]\]/g;
    let m;
    while ((m = re.exec(body))) {
      const slug = wikiStore.normalizeSlug(m[1]);
      if (!slug || slug === wikiStore.INDEX_SLUG) continue;
      const hit = await wikiStore.getPage(uid, { slug });
      if (!hit) {
        broken.push({ from: p.slug, missing: slug });
      }
    }
  }

  let llmNote = '';
  if (aliyunDashScope.isConfigured() && pages.length >= 3) {
    try {
      const catalog = pages
        .slice(0, 40)
        .map((p) => `${p.kind}:${p.slug}|${p.title}`)
        .join('\n');
      const { json } = await aliyunDashScope.chatJson({
        model: lintModelId(),
        temperature: 0.1,
        messages: [
          { role: 'system', content: WIKI_LINT_SYSTEM },
          {
            role: 'user',
            content: `孤儿候选：${orphans.map((o) => o.slug).join(', ') || '无'}\n页列表：\n${catalog}`,
          },
        ],
      });
      llmNote = JSON.stringify(json || {}).slice(0, 600);
    } catch (err) {
      llmNote = `llm_fail:${err?.message || err}`;
    }
  }

  await wikiStore.appendLog(uid, 'lint', {
    detail: JSON.stringify({
      orphans: orphans.map((o) => o.slug).slice(0, 20),
      broken: broken.slice(0, 20),
      llm: llmNote || null,
    }).slice(0, 1000),
  });
}

module.exports = {
  scheduleWikiLint,
  runWikiLint,
};
