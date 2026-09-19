const cheerio = require('cheerio');
const { pool } = require('../db');
const helpImageOss = require('./helpImageOss');

const HTML_MAX = 20000;
const TITLE_MAX = 40;
const IMAGE_MAX = Math.floor(2.5 * 1024 * 1024);
const LOCAL_IMAGE_URL = /^\/help\/[a-zA-Z0-9._-]+\.(png|jpe?g|webp)$/;
const COLOR_VALUE = /^(#[0-9a-fA-F]{3,8}|rgb\(\s*\d{1,3}\s*,\s*\d{1,3}\s*,\s*\d{1,3}\s*\)|rgba\(\s*\d{1,3}\s*,\s*\d{1,3}\s*,\s*\d{1,3}\s*,\s*(?:0|1|0?\.\d+)\s*\))$/;

const FONT_SIZES = new Set(['12px', '14px', '16px', '18px', '20px', '24px', '28px']);

function safeInlineStyle(style) {
  const kept = [];
  for (const chunk of String(style || '').split(';')) {
    const idx = chunk.indexOf(':');
    if (idx < 0) continue;
    const key = chunk.slice(0, idx).trim().toLowerCase();
    const value = chunk.slice(idx + 1).trim();
    if (key === 'color' && COLOR_VALUE.test(value)) kept.push(`color: ${value}`);
    else if (key === 'font-size' && FONT_SIZES.has(value.toLowerCase())) {
      kept.push(`font-size: ${value.toLowerCase()}`);
    }
  }
  return kept.join('; ');
}
const ALLOWED = new Set([
  'p', 'br', 'strong', 'b', 'em', 'i', 'u', 's', 'span',
  'h2', 'h3', 'ul', 'ol', 'li', 'img', 'a', 'blockquote',
]);
const DROP = new Set(['script', 'style', 'iframe', 'object', 'embed', 'link', 'meta', 'svg']);

/** 允许 App 展示、后台编辑的帮助页。缺行时用这里的默认正文补上。 */
const PAGES = {
  ai_auto_tags: {
    title: 'AI自动标签分类方法',
    body: 'Pro 用户在内容解析成功后，如果这篇还没有标签，AI 会根据正文自动打上标签。\n\n标签完成后，会显示在内容上。已经有标签的内容不会重复自动打标。',
  },
};

function httpError(message, status) {
  const err = new Error(message);
  err.status = status;
  return err;
}

function assertKey(key) {
  if (!PAGES[key]) throw httpError('帮助页不存在', 404);
}

function cleanText(value, max) {
  return String(value || '')
    .replace(/\r\n/g, '\n')
    .trim()
    .slice(0, max);
}

function escapeHtml(text) {
  return String(text)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function looksLikeHtml(text) {
  return /<\/?[a-z][^>]*>/i.test(text);
}

function plainToHtml(text) {
  return String(text || '')
    .trim()
    .split(/\n{2,}/)
    .map((part) => part.trim())
    .filter(Boolean)
    .map((part) => `<p>${escapeHtml(part).replace(/\n/g, '<br>')}</p>`)
    .join('');
}

function parseStoredBlocks(raw) {
  if (Array.isArray(raw)) return raw;
  if (typeof raw !== 'string' || !raw.trim()) return null;
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : null;
  } catch (_) {
    return null;
  }
}

function blocksToHtml(blocks) {
  return blocks.map((item) => {
    if (!item || typeof item !== 'object') return '';
    const bits = [];
    const title = cleanText(item.title, TITLE_MAX);
    const text = cleanText(item.text, 2000);
    const imageUrl = String(item.imageUrl || '').trim();
    if (title) bits.push(`<h2>${escapeHtml(title)}</h2>`);
    if (LOCAL_IMAGE_URL.test(imageUrl)) bits.push(`<p><img src="${imageUrl}"></p>`);
    if (text) bits.push(`<p>${escapeHtml(text).replace(/\n/g, '<br>')}</p>`);
    return bits.join('');
  }).join('');
}

function sanitizeHtml(input) {
  const raw = String(input || '').trim();
  if (!raw) return '';
  const $ = cheerio.load(`<div id="help-root">${raw}</div>`);
  const root = $('#help-root');
  root.find([...DROP].join(',')).remove();

  for (let guard = 0; guard < 30; guard += 1) {
    const bad = root.find('*').filter((_, el) => {
      const tag = String(el.name || '').toLowerCase();
      return tag && !ALLOWED.has(tag);
    }).first();
    if (!bad.length) break;
    const tag = String(bad.get(0).name || '').toLowerCase();
    if (tag === 'h1') bad.replaceWith(`<h2>${bad.html() || ''}</h2>`);
    else bad.replaceWith(bad.html() || '');
  }

  root.find('*').each((_, el) => {
    const tag = String(el.name || '').toLowerCase();
    const $el = $(el);
    const attrs = { ...(el.attribs || {}) };
    for (const name of Object.keys(attrs)) $el.removeAttr(name);
    const inlineStyle = safeInlineStyle(attrs.style);
    if (inlineStyle) $el.attr('style', inlineStyle);
    if (tag === 'img') {
      const src = String(attrs.src || '').trim();
      const canonical = helpImageOss.canonicalSrc(src);
      if (canonical) $el.attr('src', canonical);
      else if (LOCAL_IMAGE_URL.test(src)) $el.attr('src', src);
      else $el.remove();
    } else if (tag === 'a') {
      const href = String(attrs.href || '').trim();
      if (!/^https?:\/\//i.test(href)) $el.replaceWith($el.html() || '');
      else $el.attr('href', href);
    }
  });

  return (root.html() || '')
    .replace(/<p>(\s|<br\s*\/?>)*<\/p>/gi, '')
    .trim();
}

function htmlFromRow(row) {
  const body = row.body == null ? '' : String(row.body);
  if (looksLikeHtml(body)) return sanitizeHtml(body);
  const blocks = parseStoredBlocks(row.blocks);
  if (blocks && blocks.length) return sanitizeHtml(blocksToHtml(blocks));
  return sanitizeHtml(plainToHtml(body));
}

function mapRow(row) {
  return {
    key: row.page_key,
    title: row.title,
    html: helpImageOss.signHtml(htmlFromRow(row)),
    updatedAt: row.updated_at,
  };
}

async function getPage(key) {
  assertKey(key);
  const [rows] = await pool.execute(
    `SELECT page_key, title, body, blocks, updated_at
     FROM help_pages
     WHERE page_key = :key
     LIMIT 1`,
    { key },
  );
  if (rows.length) return mapRow(rows[0]);

  const spec = PAGES[key];
  await pool.execute(
    `INSERT INTO help_pages (page_key, title, body)
     VALUES (:key, :title, :body)`,
    { key, title: spec.title, body: spec.body },
  );
  return {
    key,
    title: spec.title,
    html: sanitizeHtml(plainToHtml(spec.body)),
    updatedAt: new Date().toISOString(),
  };
}

async function updatePage(key, payload) {
  assertKey(key);
  const fallback = PAGES[key].title;
  const title = cleanText(payload?.title, TITLE_MAX) || fallback;
  const html = sanitizeHtml(payload?.html);
  if (html.length > HTML_MAX) {
    throw httpError(`正文不能超过 ${HTML_MAX} 字`, 400);
  }
  await getPage(key);
  await pool.execute(
    `UPDATE help_pages
     SET title = :title, body = :body, blocks = NULL
     WHERE page_key = :key`,
    { key, title, body: html },
  );
  return getPage(key);
}

async function saveImage(key, dataUrl) {
  assertKey(key);
  const matched = /^data:image\/(png|jpeg|jpg|webp);base64,([A-Za-z0-9+/=\s]+)$/.exec(
    String(dataUrl || ''),
  );
  if (!matched) throw httpError('只支持 PNG、JPG、WebP', 400);
  const ext = matched[1] === 'png' ? 'png' : matched[1] === 'webp' ? 'webp' : 'jpg';
  const buf = Buffer.from(matched[2].replace(/\s/g, ''), 'base64');
  if (!buf.length || buf.length > IMAGE_MAX) {
    throw httpError('图片不能超过 2.5MB', 400);
  }
  const mime = ext === 'png' ? 'image/png' : ext === 'webp' ? 'image/webp' : 'image/jpeg';
  return helpImageOss.upload({
    pageKey: key,
    ext,
    buffer: buf,
    contentType: mime,
  });
}

module.exports = {
  PAGES,
  getPage,
  updatePage,
  saveImage,
};
