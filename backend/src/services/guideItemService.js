const fs = require('fs');
const path = require('path');
const { pool } = require('../db');
const { normalizeUrl } = require('../utils/url');
const { extractMeta } = require('./parser/extractMeta');

const GUIDE_URL = 'https://conflux.wobufang.com/guide';
const GUIDE_TITLE = '使用指引与技巧';
const GUIDE_SUMMARY =
  '三种收藏方式、整理与搜索技巧、阅读标注、AI 与转写、订阅档位说明。';
const GUIDE_PLATFORM = 'guide';

let _snapshotCache = null;

function guideHtmlPath() {
  return path.join(__dirname, '../../public/guide.html');
}

function guideCanonicalUrl() {
  return normalizeUrl(GUIDE_URL);
}

function decodeHtmlEntities(text) {
  return String(text)
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
}

function stripTags(html) {
  return decodeHtmlEntities(
    String(html)
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<\/p>/gi, '\n')
      .replace(/<\/li>/gi, '\n')
      .replace(/<[^>]+>/g, '')
      .replace(/\n{3,}/g, '\n\n')
      .trim(),
  );
}

/** 从 public/guide.html 提取正文并转为阅读页 Markdown（HTML 为唯一内容源） */
function guideHtmlToMarkdown(html) {
  const mainMatch = String(html).match(/<main[^>]*>([\s\S]*?)<\/main>/i);
  let body = mainMatch ? mainMatch[1] : html;

  body = body
    .replace(/<img[^>]*class=["'][^"']*\bcover\b[^"']*["'][^>]*>/gi, '')
    .replace(/<a class="back"[\s\S]*?<\/a>/gi, '')
    .replace(/<h1[\s\S]*?<\/h1>/i, '')
    .replace(/<p class="meta"[\s\S]*?<\/p>/i, '')
    .replace(/<div class="footer-links"[\s\S]*$/i, '');

  const chunks = [];
  const re =
    /<h2[^>]*>([\s\S]*?)<\/h2>|<h3[^>]*>([\s\S]*?)<\/h3>|<p class="tip"[^>]*>([\s\S]*?)<\/p>|<p class="lead"[^>]*>([\s\S]*?)<\/p>|<div class="plan-block"[^>]*>([\s\S]*?)<\/div>|<p[^>]*>([\s\S]*?)<\/p>|<ul[^>]*>([\s\S]*?)<\/ul>|<ol[^>]*>([\s\S]*?)<\/ol>/gi;

  let m;
  while ((m = re.exec(body)) !== null) {
    if (m[1]) chunks.push(`\n## ${stripTags(m[1])}\n`);
    else if (m[2]) chunks.push(`\n### ${stripTags(m[2])}\n`);
    else if (m[3]) chunks.push(`\n**${stripTags(m[3]).replace(/^技巧：\s*/, '技巧：')}**\n`);
    else if (m[4]) chunks.push(`\n${stripTags(m[4])}\n`);
    else if (m[5]) {
      const block = m[5];
      const title = block.match(/<strong>([\s\S]*?)<\/strong>/i);
      if (title) chunks.push(`\n**${stripTags(title[1])}**`);
      const items = block.match(/<li[^>]*>([\s\S]*?)<\/li>/gi) || [];
      for (const li of items) {
        const inner = li.replace(/<\/?li[^>]*>/gi, '');
        chunks.push(`- ${stripTags(inner)}`);
      }
      chunks.push('');
    } else if (m[6]) chunks.push(`\n${stripTags(m[6])}\n`);
    else if (m[7] || m[8]) {
      const list = m[7] || m[8];
      const items = list.match(/<li[^>]*>([\s\S]*?)<\/li>/gi) || [];
      for (const li of items) {
        const inner = li.replace(/<\/?li[^>]*>/gi, '');
        chunks.push(`- ${stripTags(inner)}`);
      }
      chunks.push('');
    }
  }

  return chunks.join('\n').replace(/\n{3,}/g, '\n\n').trim();
}

/** 从 guide.html 读取标题 / 摘要 / 封面 / 正文（封面走通用 og:image 解析） */
function loadGuideSnapshot() {
  if (_snapshotCache) return _snapshotCache;
  const html = fs.readFileSync(guideHtmlPath(), 'utf8');
  const meta = extractMeta(html, { platform: 'web', baseUrl: GUIDE_URL });
  _snapshotCache = {
    title: GUIDE_TITLE,
    summary: meta.summary || GUIDE_SUMMARY,
    coverImageUrl: meta.coverImageUrl || null,
    content: guideHtmlToMarkdown(html),
  };
  return _snapshotCache;
}

function clearGuideContentCache() {
  _snapshotCache = null;
}

async function getUncategorizedFolderId(conn) {
  const runner = conn || pool;
  const [rows] = await runner.execute(
    `SELECT id FROM categories
     WHERE user_id = 0 AND section = 'folder' AND code = 'uncategorized'
     LIMIT 1`,
  );
  if (!rows[0]) {
    throw Object.assign(new Error('系统未分类不存在，请先执行数据库迁移'), {
      status: 500,
    });
  }
  return rows[0].id;
}

function isGuideItem(rowOrItem) {
  if (!rowOrItem) return false;
  const platform = rowOrItem.platform;
  if (platform === GUIDE_PLATFORM) return true;
  const canonical =
    rowOrItem.canonical_url || rowOrItem.canonicalUrl || '';
  try {
    return normalizeUrl(String(canonical)) === guideCanonicalUrl();
  } catch {
    return false;
  }
}

/**
 * 为指定用户确保存在「使用指引」条目（不占解析队列、不计 quota）。
 * @returns {Promise<{ id: number, created: boolean }|null>}
 */
async function ensureForUser(userId) {
  const uid = Number(userId);
  if (!uid) return null;

  const canonicalUrl = guideCanonicalUrl();
  const [existingRows] = await pool.execute(
    `SELECT id FROM items
     WHERE user_id = :userId
       AND canonical_url = :canonicalUrl
       AND deleted_at IS NULL
     LIMIT 1`,
    { userId: uid, canonicalUrl },
  );
  if (existingRows[0]) {
    await syncGuideItemFields(existingRows[0].id);
    return { id: existingRows[0].id, created: false };
  }

  const folderId = await getUncategorizedFolderId();
  clearGuideContentCache();
  const snap = loadGuideSnapshot();

  const [result] = await pool.execute(
    `INSERT INTO items (
       user_id, url, canonical_url, title, content, summary, cover_image_url,
       platform, status, folder_id, is_unread
     ) VALUES (
       :userId, :url, :canonicalUrl, :title, :content, :summary, :coverImageUrl,
       :platform, 'success', :folderId, 1
     )`,
    {
      userId: uid,
      url: GUIDE_URL,
      canonicalUrl,
      title: snap.title,
      content: snap.content,
      summary: snap.summary,
      coverImageUrl: snap.coverImageUrl,
      platform: GUIDE_PLATFORM,
      folderId,
    },
  );

  return { id: result.insertId, created: true };
}

/** 按 guide.html 刷新标题、摘要、正文、封面 */
async function syncGuideItemFields(itemId) {
  clearGuideContentCache();
  const snap = loadGuideSnapshot();
  await pool.execute(
    `UPDATE items
     SET title = :title,
         summary = :summary,
         content = :content,
         cover_image_url = :coverImageUrl,
         platform = :platform,
         status = 'success',
         updated_at = CURRENT_TIMESTAMP(3)
     WHERE id = :itemId AND deleted_at IS NULL`,
    {
      itemId,
      title: snap.title,
      summary: snap.summary,
      content: snap.content,
      coverImageUrl: snap.coverImageUrl,
      platform: GUIDE_PLATFORM,
    },
  );
}

/** 按 guide.html 刷新已种子的全部字段 */
async function syncContentFromHtml() {
  clearGuideContentCache();
  const snap = loadGuideSnapshot();
  const canonicalUrl = guideCanonicalUrl();
  const [result] = await pool.execute(
    `UPDATE items
     SET content = :content,
         cover_image_url = :coverImageUrl,
         platform = :platform,
         title = :title,
         summary = :summary,
         updated_at = CURRENT_TIMESTAMP(3)
     WHERE canonical_url = :canonicalUrl AND deleted_at IS NULL`,
    {
      content: snap.content,
      coverImageUrl: snap.coverImageUrl,
      platform: GUIDE_PLATFORM,
      title: snap.title,
      summary: snap.summary,
      canonicalUrl,
    },
  );
  return result.affectedRows || 0;
}

/** 为全部存量用户补种指引条目（迁移 / 脚本用） */
async function ensureAllUsers() {
  const [users] = await pool.execute('SELECT id FROM users ORDER BY id ASC');
  let created = 0;
  let skipped = 0;
  for (const row of users) {
    const result = await ensureForUser(row.id);
    if (result?.created) created += 1;
    else skipped += 1;
  }
  const synced = await syncContentFromHtml();
  return { total: users.length, created, skipped, synced };
}

module.exports = {
  GUIDE_URL,
  GUIDE_TITLE,
  GUIDE_PLATFORM,
  guideCanonicalUrl,
  guideHtmlToMarkdown,
  loadGuideSnapshot,
  clearGuideContentCache,
  isGuideItem,
  ensureForUser,
  syncGuideItemFields,
  syncContentFromHtml,
  ensureAllUsers,
};
