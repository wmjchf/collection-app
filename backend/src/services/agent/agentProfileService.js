const { pool } = require('../../db');
const config = require('../../config');
const aliyunDashScope = require('../aliyunDashScope');

/** 允许的 namespace；新能力挂载时在此追加 */
const NAMESPACES = new Set(['organize', 'tagging', 'general']);

const MAX_RULES_PER_NS = 5;
const MAX_RULE_TEXT = 120;
const MAX_TOTAL_CHARS = 600;

const COMPACT_SYSTEM = {
  organize:
    '你是归类偏好提炼器。把用户关于标签归类的具体说法，提炼成跨领域仍成立的抽象原则。' +
    '输出必须是纯原则：禁止任何实际例子，包括标签名、品牌/媒体名、产品型号、具体架名、垂类场景，以及「如××」「例如××」式举例。' +
    '只保留结构习惯：不同维度不混架、同维度可同架、标签过少先未归类、架名宜短稳定勿叠词改名等。' +
    '只输出 JSON：{"rules":["原则1","原则2"]}；最多 5 条；每条不超过 80 字；无原则则 rules 为空数组。',
  tagging:
    '你是打标偏好提炼器。把用户关于打标签的具体说法，提炼成跨领域仍成立的抽象原则。' +
    '输出禁止任何实际例子（标签名、篇名、品牌、「如××」）。只保留习惯原则：优先复用、粒度、命名长短等。' +
    '只输出 JSON：{"rules":["原则1"]}；最多 5 条；每条不超过 80 字。',
  general:
    '你是助手偏好提炼器。把用户关于助手行为的具体说法，提炼成可复用的抽象原则。' +
    '输出禁止任何实际例子与一次性任务细节。' +
    '只输出 JSON：{"rules":["原则1"]}；最多 5 条；每条不超过 80 字。',
};

function emptyProfile() {
  return { organize: [], tagging: [], general: [], updatedAt: null };
}

function parseProfile(raw) {
  const base = emptyProfile();
  if (raw == null) return base;
  let obj = raw;
  if (typeof raw === 'string') {
    try {
      obj = JSON.parse(raw);
    } catch {
      return base;
    }
  }
  if (!obj || typeof obj !== 'object') return base;
  for (const ns of NAMESPACES) {
    const list = Array.isArray(obj[ns]) ? obj[ns] : [];
    base[ns] = list
      .map((r) => ({
        text: String(r?.text || '')
          .trim()
          .slice(0, MAX_RULE_TEXT),
        source: String(r?.source || 'user_said').slice(0, 32),
        updatedAt: r?.updatedAt ? String(r.updatedAt) : null,
      }))
      .filter((r) => r.text);
  }
  base.updatedAt = obj.updatedAt ? String(obj.updatedAt) : null;
  return base;
}

function totalChars(profile) {
  let n = 0;
  for (const ns of NAMESPACES) {
    for (const r of profile[ns] || []) {
      n += String(r.text || '').length;
    }
  }
  return n;
}

function trimToBudget(profile) {
  while (totalChars(profile) > MAX_TOTAL_CHARS) {
    let oldestNs = null;
    let oldestIdx = -1;
    let oldestAt = null;
    for (const ns of NAMESPACES) {
      const list = profile[ns] || [];
      for (let i = 0; i < list.length; i += 1) {
        const at = list[i].updatedAt || '';
        if (oldestAt == null || at < oldestAt) {
          oldestAt = at;
          oldestNs = ns;
          oldestIdx = i;
        }
      }
    }
    if (oldestNs == null || oldestIdx < 0) break;
    profile[oldestNs].splice(oldestIdx, 1);
  }
  return profile;
}

function normalizeRuleList(rawRules, source, now) {
  const out = [];
  const seen = new Set();
  for (const item of Array.isArray(rawRules) ? rawRules : []) {
    const text = String(item || '')
      .trim()
      .slice(0, MAX_RULE_TEXT);
    if (!text) continue;
    const key = text.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({
      text,
      source: String(source || 'compacted').slice(0, 32),
      updatedAt: now,
    });
    if (out.length >= MAX_RULES_PER_NS) break;
  }
  return out;
}

/**
 * 将该 namespace 规则压成抽象原则（失败则原样保留）。
 */
async function compactNamespace(profile, namespace, source = 'compacted') {
  const ns = String(namespace || '')
    .trim()
    .toLowerCase();
  if (!NAMESPACES.has(ns)) return profile;
  const list = profile[ns] || [];
  if (!list.length) return profile;

  const system = COMPACT_SYSTEM[ns] || COMPACT_SYSTEM.general;
  const bullets = list.map((r) => `- ${r.text}`).join('\n');
  try {
    const { json } = await aliyunDashScope.chatJson({
      model: config.aliyun.aiModelTags || 'qwen3.8-flash',
      temperature: 0.1,
      messages: [
        { role: 'system', content: system },
        {
          role: 'user',
          content:
            `请提炼下列用户说法（namespace=${ns}）：\n${bullets}\n\n` +
            '记住：只要抽象原则，不要例子。',
        },
      ],
    });
    const now = new Date().toISOString();
    const next = normalizeRuleList(json?.rules, source, now);
    if (next.length) {
      profile[ns] = next;
      profile.updatedAt = now;
    }
  } catch (err) {
    console.warn(
      '[agentProfile] compact fail:',
      ns,
      err?.message || err,
    );
  }
  return trimToBudget(profile);
}

async function saveProfile(userId, profile) {
  await pool.execute(
    `UPDATE users SET agent_profile = CAST(:profile AS JSON) WHERE id = :userId`,
    { userId: Number(userId), profile: JSON.stringify(profile) },
  );
}

/**
 * @param {number} userId
 * @returns {Promise<ReturnType<typeof emptyProfile>>}
 */
async function getProfile(userId) {
  const uid = Number(userId);
  if (!Number.isFinite(uid) || uid <= 0) return emptyProfile();
  const [rows] = await pool.execute(
    `SELECT agent_profile FROM users WHERE id = :userId LIMIT 1`,
    { userId: uid },
  );
  return parseProfile(rows[0]?.agent_profile);
}

/**
 * 追加后立刻压成抽象原则再落库。
 * @param {number} userId
 * @param {string} namespace
 * @param {string} text
 * @param {string} [source]
 */
async function upsertRule(userId, namespace, text, source = 'user_said') {
  const uid = Number(userId);
  const ns = String(namespace || '')
    .trim()
    .toLowerCase();
  const body = String(text || '')
    .trim()
    .slice(0, MAX_RULE_TEXT);
  if (!Number.isFinite(uid) || uid <= 0) {
    return { ok: false, error: 'invalid_user' };
  }
  if (!NAMESPACES.has(ns)) {
    return { ok: false, error: 'invalid_namespace' };
  }
  if (!body) {
    return { ok: false, error: 'empty_text' };
  }

  const profile = await getProfile(uid);
  const list = profile[ns] || [];
  const key = body.toLowerCase();
  const now = new Date().toISOString();
  const idx = list.findIndex((r) => String(r.text).toLowerCase() === key);
  if (idx >= 0) {
    list[idx] = {
      text: body,
      source: String(source).slice(0, 32),
      updatedAt: now,
    };
  } else {
    list.push({
      text: body,
      source: String(source).slice(0, 32),
      updatedAt: now,
    });
    while (list.length > MAX_RULES_PER_NS) {
      list.shift();
    }
  }
  profile[ns] = list;
  profile.updatedAt = now;

  await compactNamespace(profile, ns, 'compacted');
  trimToBudget(profile);
  await saveProfile(uid, profile);

  return {
    ok: true,
    profile,
    namespace: ns,
    text: formatNamespace(profile, ns) || body,
  };
}

/**
 * 把已有档案各 namespace 再压一遍（迁移/修补用）。
 */
async function compactProfile(userId) {
  const uid = Number(userId);
  if (!Number.isFinite(uid) || uid <= 0) {
    return { ok: false, error: 'invalid_user' };
  }
  const profile = await getProfile(uid);
  for (const ns of NAMESPACES) {
    if ((profile[ns] || []).length) {
      await compactNamespace(profile, ns, 'compacted');
    }
  }
  trimToBudget(profile);
  await saveProfile(uid, profile);
  return { ok: true, profile };
}

/**
 * 某一 namespace 拼成多行文本（供 hint / system）。
 */
function formatNamespace(profile, namespace) {
  const list = Array.isArray(profile?.[namespace]) ? profile[namespace] : [];
  return list
    .map((r) => String(r.text || '').trim())
    .filter(Boolean)
    .join('\n');
}

/**
 * 注入 system 的整块文案；空则返回 ''。
 */
function formatProfileForPrompt(profile) {
  const p = profile && typeof profile === 'object' ? profile : emptyProfile();
  const lines = [];
  for (const ns of ['organize', 'tagging', 'general']) {
    const body = formatNamespace(p, ns);
    if (!body) continue;
    const label =
      ns === 'organize' ? '归类' : ns === 'tagging' ? '打标' : '一般';
    for (const line of body.split('\n')) {
      const t = line.trim();
      if (t) lines.push(`- ${label}：${t}`);
    }
  }
  if (!lines.length) return '';
  return (
    '【用户已知方向（短档案；原则级；与会话无关；相关能力必须遵守）】\n' +
    lines.join('\n')
  );
}

module.exports = {
  NAMESPACES,
  MAX_RULES_PER_NS,
  MAX_RULE_TEXT,
  MAX_TOTAL_CHARS,
  getProfile,
  upsertRule,
  compactProfile,
  compactNamespace,
  formatNamespace,
  formatProfileForPrompt,
  emptyProfile,
  parseProfile,
};
