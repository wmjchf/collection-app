const { pool } = require('../db');
const { normalizeUrl, detectPlatform, placeholderTitle, resolveParseUrl, normalizeBilibiliCanonical } = require('../utils/url');
const { fetchQuickMeta, parseFullContent } = require('./parser');
const {
  getAdapter,
  prefersClientFetch,
  listClientFetchPlatformIds,
} = require('./parser/adapters/registry');
const transcriptSegments = require('./transcriptSegments');
const aiMeta = require('./aiMeta');

/** 服务端抓取被拦时，等待客户端上报 HTML */
const NEED_CLIENT_FETCH = 'NEED_CLIENT_FETCH';

function mapItem(row) {
  if (!row) return null;
  let imageUrls = [];
  if (row.image_urls != null) {
    try {
      const parsed =
        typeof row.image_urls === 'string'
          ? JSON.parse(row.image_urls)
          : row.image_urls;
      if (Array.isArray(parsed)) {
        imageUrls = parsed.map((u) => String(u)).filter(Boolean);
      }
    } catch {
      imageUrls = [];
    }
  }
  return {
    id: row.id,
    userId: row.user_id,
    url: row.url,
    canonicalUrl: row.platform === 'bilibili'
        ? normalizeBilibiliCanonical(row.canonical_url) ||
          normalizeBilibiliCanonical(row.url) ||
          row.canonical_url
        : row.canonical_url,
    title: row.title,
    content: row.content,
    summary: row.summary,
    coverImageUrl: row.cover_image_url,
    imageUrls,
    videoUrl: row.video_url || null,
    transcriptSegments: transcriptSegments.mapSegmentsForApi(
      transcriptSegments.parseSegments(row.transcript_segments),
    ),
    platform: row.platform,
    status: row.status,
    errorMessage: row.error_message,
    note: row.note,
    contentEditedAt: row.content_edited_at || null,
    folderId: row.folder_id,
    isStarred: !!row.is_starred,
    isUnread: !!row.is_unread,
    isArchived: !!row.is_archived,
    lastReadAt: row.last_read_at,
    deletedAt: row.deleted_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    annotationCount:
      row.annotation_count != null ? Number(row.annotation_count) : undefined,
    aiMeta: aiMeta.mapAiMetaForApi(row.ai_meta),
  };
}

async function getUncategorizedFolderId() {
  const [rows] = await pool.execute(
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

async function findByCanonical(userId, canonicalUrl) {
  const [rows] = await pool.execute(
    `SELECT * FROM items
     WHERE user_id = :userId
       AND canonical_url = :canonicalUrl
       AND deleted_at IS NULL
     LIMIT 1`,
    { userId, canonicalUrl },
  );
  return rows[0] || null;
}

/**
 * @param {{ includeDeleted?: boolean }} [opts]
 */
async function getByIdForUser(userId, itemId, opts = {}) {
  const includeDeleted = !!opts.includeDeleted;
  const [rows] = await pool.execute(
    `SELECT * FROM items
     WHERE id = :itemId AND user_id = :userId
       ${includeDeleted ? '' : 'AND deleted_at IS NULL'}
     LIMIT 1`,
    { itemId, userId },
  );
  return mapItem(rows[0] || null);
}

/**
 * 创建条目：同步快速元信息 → 写库 → 触发异步正文解析
 */
async function createItem(userId, rawUrl) {
  const url = String(rawUrl || '').trim();
  let canonicalUrl = normalizeUrl(url);
  let meta = null;

  if (detectPlatform(canonicalUrl) === 'bilibili') {
    try {
      meta = await fetchQuickMeta(canonicalUrl);
      const fixed = normalizeBilibiliCanonical(meta.finalUrl);
      if (fixed) canonicalUrl = fixed;
    } catch (err) {
      meta = {
        platform: 'bilibili',
        finalUrl: canonicalUrl,
        title: placeholderTitle(canonicalUrl),
        summary: null,
        coverImageUrl: null,
        blocked: false,
        html: null,
        fetchError: err.message,
      };
    }
  }

  const existing = await findByCanonical(userId, canonicalUrl);
  if (existing) {
    return { item: mapItem(existing), existed: true };
  }

  if (!meta) {
    try {
      meta = await fetchQuickMeta(canonicalUrl);
    } catch (err) {
      // 快速阶段失败仍入库，标题用域名占位，交给异步重试正文
      meta = {
        platform: detectPlatform(canonicalUrl),
        finalUrl: canonicalUrl,
        title: placeholderTitle(canonicalUrl),
        summary: null,
        coverImageUrl: null,
        blocked: false,
        html: null,
        fetchError: err.message,
      };
    }
  }

  const folderId = await getUncategorizedFolderId();
  const title = meta.title || placeholderTitle(canonicalUrl);

  const [result] = await pool.execute(
    `INSERT INTO items (
       user_id, url, canonical_url, title, summary, cover_image_url,
       platform, status, folder_id, is_unread
     ) VALUES (
       :userId, :url, :canonicalUrl, :title, :summary, :coverImageUrl,
       :platform, 'pending', :folderId, 1
     )`,
    {
      userId,
      url,
      canonicalUrl,
      title,
      summary: meta.summary || null,
      coverImageUrl: meta.coverImageUrl || null,
      platform: meta.platform || 'web',
      folderId,
    },
  );

  const itemId = result.insertId;

  // 异步正文解析；把阶段 1 HTML / 专项结果暂存，供 runContentParse 复用
  const { enqueueParse } = require('./parseQueue');
  if (meta.html) {
    _htmlCache.set(itemId, { html: meta.html, at: Date.now() });
  }
  if (meta.adapterParsed) {
    _parsedCache.set(itemId, { parsed: meta.adapterParsed, at: Date.now() });
  }
  enqueueParse(itemId);

  const item = await getByIdForUser(userId, itemId);
  return { item, existed: false };
}

/** itemId -> { html, at }，5 分钟过期 */
const _htmlCache = new Map();
/** itemId -> { parsed, at }，专项 API 结果缓存 */
const _parsedCache = new Map();

function takeCachedHtml(itemId) {
  const entry = _htmlCache.get(itemId);
  _htmlCache.delete(itemId);
  if (!entry) return null;
  if (Date.now() - entry.at > 5 * 60 * 1000) return null;
  return entry.html;
}

function takeCachedParsed(itemId) {
  const entry = _parsedCache.get(itemId);
  _parsedCache.delete(itemId);
  if (!entry) return null;
  if (Date.now() - entry.at > 5 * 60 * 1000) return null;
  return entry.parsed;
}

async function runContentParse(itemId) {
  const [rows] = await pool.execute(
    'SELECT * FROM items WHERE id = :itemId AND deleted_at IS NULL LIMIT 1',
    { itemId },
  );
  const row = rows[0];
  if (!row) return;

  // 适配器声明 fetchMode=client（如微信）：云端不抓正文，等本机回传 HTML
  if (prefersClientFetch(row.platform)) {
    await pool.execute(
      `UPDATE items SET status = 'pending', error_message = :errorMessage
       WHERE id = :itemId`,
      { itemId, errorMessage: NEED_CLIENT_FETCH },
    );
    return;
  }

  const cachedHtml = takeCachedHtml(itemId);
  const adapterParsed = takeCachedParsed(itemId);

  try {
    const parsed = await parseFullContent(
      resolveParseUrl(row.canonical_url, row.url),
      {
      platform: row.platform,
      existingSummary: row.summary,
      html: cachedHtml,
      adapterParsed,
    });

    if (parsed.ok) {
      const imageUrls = Array.isArray(parsed.imageUrls)
        ? parsed.imageUrls.filter(Boolean).slice(0, 30)
        : [];
      const bilibiliCanonical =
        row.platform === 'bilibili'
          ? normalizeBilibiliCanonical(parsed.pageUrl)
          : null;
      const preserveUserContent = !!row.content_edited_at;
      await pool.execute(
        `UPDATE items SET
           title = COALESCE(:title, title),
           summary = :summary,
           cover_image_url = COALESCE(:coverImageUrl, cover_image_url),
           image_urls = CAST(:imageUrls AS JSON),
           video_url = :videoUrl,
           content = :content,
           canonical_url = COALESCE(:canonicalUrl, canonical_url),
           status = 'success',
           error_message = NULL
         WHERE id = :itemId`,
        {
          itemId,
          title: parsed.title || null,
          summary: parsed.summary || null,
          coverImageUrl: parsed.coverImageUrl || null,
          imageUrls: JSON.stringify(imageUrls),
          videoUrl: parsed.videoUrl || null,
          content: preserveUserContent ? row.content : parsed.content,
          canonicalUrl: bilibiliCanonical,
        },
      );
      return;
    }

    if (parsed.blocked) {
      await pool.execute(
        `UPDATE items SET
           title = COALESCE(:title, title),
           summary = COALESCE(:summary, summary),
           cover_image_url = COALESCE(:coverImageUrl, cover_image_url),
           status = 'pending',
           error_message = :errorMessage
         WHERE id = :itemId`,
        {
          itemId,
          title: parsed.title || null,
          summary: parsed.summary || null,
          coverImageUrl: parsed.coverImageUrl || null,
          errorMessage: NEED_CLIENT_FETCH,
        },
      );
      return;
    }

    // 云上常拿到壳页/空正文（如掘金 Please wait）：改由客户端抓取
    if (
      parsed.errorMessage === '未能提取到可读正文' ||
      (!parsed.content &&
        !(parsed.imageUrls && parsed.imageUrls.length) &&
        !parsed.videoUrl)
    ) {
      await pool.execute(
        `UPDATE items SET
           title = COALESCE(:title, title),
           summary = COALESCE(:summary, summary),
           cover_image_url = COALESCE(:coverImageUrl, cover_image_url),
           status = 'pending',
           error_message = :errorMessage
         WHERE id = :itemId`,
        {
          itemId,
          title: parsed.title || null,
          summary: parsed.summary || null,
          coverImageUrl: parsed.coverImageUrl || null,
          errorMessage: NEED_CLIENT_FETCH,
        },
      );
      return;
    }

    await pool.execute(
      `UPDATE items SET
         title = COALESCE(:title, title),
         summary = COALESCE(:summary, summary),
         cover_image_url = COALESCE(:coverImageUrl, cover_image_url),
         status = 'failed',
         error_message = :errorMessage
       WHERE id = :itemId`,
      {
        itemId,
        title: parsed.title || null,
        summary: parsed.summary || null,
        coverImageUrl: parsed.coverImageUrl || null,
        errorMessage: parsed.errorMessage || '解析失败',
      },
    );
  } catch (err) {
    await pool.execute(
      `UPDATE items SET status = 'failed', error_message = :errorMessage
       WHERE id = :itemId`,
      {
        itemId,
        errorMessage: (err.message || '解析失败').slice(0, 500),
      },
    );
  }
}

/** 客户端上报 HTML，服务端只负责抽取正文（不再向源站请求） */
async function parseWithClientHtml(userId, itemId, html) {
  const item = await getByIdForUser(userId, itemId);
  if (!item) {
    throw Object.assign(new Error('条目不存在'), { status: 404 });
  }
  const raw = typeof html === 'string' ? html : '';
  if (raw.trim().length < 80) {
    throw Object.assign(new Error('页面内容过短'), { status: 400 });
  }
  if (raw.length > 8 * 1024 * 1024) {
    throw Object.assign(new Error('页面内容过大'), { status: 400 });
  }

  const parsed = await parseFullContent(
    resolveParseUrl(item.canonicalUrl, item.url),
    {
    platform: item.platform,
    existingSummary: item.summary,
    html: raw,
    preferProvidedHtml: true,
  });

  if (parsed.ok) {
    const imageUrls = Array.isArray(parsed.imageUrls)
      ? parsed.imageUrls.filter(Boolean).slice(0, 30)
      : [];
    await pool.execute(
      `UPDATE items SET
         title = COALESCE(:title, title),
         summary = :summary,
         cover_image_url = COALESCE(:coverImageUrl, cover_image_url),
         image_urls = CAST(:imageUrls AS JSON),
         video_url = :videoUrl,
         content = :content,
         status = 'success',
         error_message = NULL
       WHERE id = :itemId AND user_id = :userId`,
      {
        itemId,
        userId,
        title: parsed.title || null,
        summary: parsed.summary || null,
        coverImageUrl: parsed.coverImageUrl || null,
        imageUrls: JSON.stringify(imageUrls),
        videoUrl: parsed.videoUrl || null,
        content: parsed.content,
      },
    );
    return getByIdForUser(userId, itemId);
  }

  await pool.execute(
    `UPDATE items SET
       title = COALESCE(:title, title),
       summary = COALESCE(:summary, summary),
       cover_image_url = COALESCE(:coverImageUrl, cover_image_url),
       status = 'failed',
       error_message = :errorMessage
     WHERE id = :itemId AND user_id = :userId`,
    {
      itemId,
      userId,
      title: parsed.title || null,
      summary: parsed.summary || null,
      coverImageUrl: parsed.coverImageUrl || null,
      errorMessage: parsed.errorMessage || '解析失败',
    },
  );
  return getByIdForUser(userId, itemId);
}

async function reparseItem(userId, itemId, { forceOverwrite = false } = {}) {
  const [rows] = await pool.execute(
    `SELECT content_edited_at FROM items
     WHERE id = :itemId AND user_id = :userId AND deleted_at IS NULL
     LIMIT 1`,
    { itemId, userId },
  );
  const row = rows[0];
  if (!row) {
    throw Object.assign(new Error('条目不存在'), { status: 404 });
  }
  if (row.content_edited_at && !forceOverwrite) {
    throw Object.assign(
      new Error('正文已手工修改，重新解析将覆盖您的编辑'),
      { status: 409, code: 'CONTENT_USER_EDITED' },
    );
  }

  await pool.execute(
    `UPDATE items
     SET status = 'pending',
         error_message = NULL,
         content_edited_at = NULL
     WHERE id = :itemId AND user_id = :userId`,
    { itemId, userId },
  );

  const { enqueueParse } = require('./parseQueue');
  enqueueParse(itemId);

  return getByIdForUser(userId, itemId);
}

/**
 * 刷新易过期的 CDN 播放直链（B站顶栏、头条正文内嵌等）。
 * 会重跑该平台专项抓取，更新 video_url 与正文里的播放地址。
 */
async function refreshItemVideo(userId, itemId) {
  const item = await getByIdForUser(userId, itemId);
  if (!item) {
    throw Object.assign(new Error('条目不存在'), { status: 404 });
  }

  const adapter = getAdapter(item.platform);
  const target = resolveParseUrl(item.canonicalUrl, item.url);
  let parsed;
  if (typeof adapter.fetchParsed === 'function') {
    parsed = await adapter.fetchParsed(target);
  } else {
    parsed = await parseFullContent(target, { platform: item.platform });
  }
  const hasInlineVideo =
    typeof parsed.content === 'string' && /(?:^|\n)\s*!v\[/m.test(parsed.content);
  if (!parsed?.ok || (!parsed.videoUrl && !hasInlineVideo)) {
    throw Object.assign(
      new Error(parsed?.errorMessage || '未能获取到新的视频链接'),
      { status: 502 },
    );
  }

  const [rows] = await pool.execute(
    `SELECT content_edited_at FROM items
     WHERE id = :itemId AND user_id = :userId AND deleted_at IS NULL
     LIMIT 1`,
    { itemId, userId },
  );
  const preserveUserContent = !!rows[0]?.content_edited_at;

  await pool.execute(
    `UPDATE items
     SET video_url = :videoUrl,
         content = COALESCE(:content, content),
         cover_image_url = COALESCE(:coverImageUrl, cover_image_url),
         canonical_url = COALESCE(:canonicalUrl, canonical_url),
         updated_at = CURRENT_TIMESTAMP
     WHERE id = :itemId AND user_id = :userId`,
    {
      itemId,
      userId,
      videoUrl: parsed.videoUrl || null,
      content: preserveUserContent ? null : parsed.content || null,
      coverImageUrl: parsed.coverImageUrl || null,
      canonicalUrl:
        item.platform === 'bilibili'
          ? normalizeBilibiliCanonical(parsed.pageUrl)
          : null,
    },
  );

  return getByIdForUser(userId, itemId);
}

async function getParseStatus(userId, itemId) {
  const [rows] = await pool.execute(
    `SELECT id, status, title, updated_at, error_message, url, canonical_url, platform
     FROM items
     WHERE id = :itemId AND user_id = :userId AND deleted_at IS NULL
     LIMIT 1`,
    { itemId, userId },
  );
  const row = rows[0];
  if (!row) {
    throw Object.assign(new Error('条目不存在'), { status: 404 });
  }
  const needsClientFetch =
    row.error_message === NEED_CLIENT_FETCH ||
    (row.status === 'pending' && prefersClientFetch(row.platform));
  return {
    id: row.id,
    status: row.status,
    title: row.title,
    updatedAt: row.updated_at,
    errorMessage:
      row.error_message === NEED_CLIENT_FETCH ? null : row.error_message,
    needsClientFetch,
    url: row.canonical_url || row.url,
    platform: row.platform,
  };
}

/** 待客户端抓取的 pending 条目（快捷指令后台入库后补齐） */
async function listNeedsClientFetch(userId, { limit = 20 } = {}) {
  const safeLimit = Math.min(Math.max(Number(limit) || 20, 1), 50);
  const clientPlatforms = listClientFetchPlatformIds();
  const platformClause =
    clientPlatforms.length > 0
      ? `OR platform IN (${clientPlatforms.map(() => '?').join(', ')})`
      : '';
  const [rows] = await pool.query(
    `SELECT id, title, url, canonical_url, platform, status, error_message, updated_at
     FROM items
     WHERE user_id = ?
       AND deleted_at IS NULL
       AND status = 'pending'
       AND (
         error_message = ?
         ${platformClause}
       )
     ORDER BY updated_at ASC
     LIMIT ${safeLimit}`,
    [userId, NEED_CLIENT_FETCH, ...clientPlatforms],
  );
  return rows.map((row) => ({
    id: row.id,
    title: row.title,
    url: row.canonical_url || row.url,
    platform: row.platform,
    status: row.status,
    updatedAt: row.updated_at,
  }));
}

const systemFilterService = require('./systemFilterService');

async function listBySystemFilter(userId, code, options = {}) {
  const result = await systemFilterService.listItemsBySystemFilter(
    userId,
    code,
    options,
  );
  return {
    ...result,
    items: result.items.map(mapItem),
  };
}

/** 进入阅读：标为已读并更新最近阅读时间 */
async function markAsRead(userId, itemId) {
  const existing = await getByIdForUser(userId, itemId);
  if (!existing) {
    throw Object.assign(new Error('条目不存在'), { status: 404 });
  }
  await pool.execute(
    `UPDATE items
     SET is_unread = 0, last_read_at = CURRENT_TIMESTAMP(3)
     WHERE id = :itemId AND user_id = :userId AND deleted_at IS NULL`,
    { itemId, userId },
  );
  return getByIdForUser(userId, itemId);
}

/** 切换星标 */
async function setStarred(userId, itemId, starred) {
  const existing = await getByIdForUser(userId, itemId);
  if (!existing) {
    throw Object.assign(new Error('条目不存在'), { status: 404 });
  }
  await pool.execute(
    `UPDATE items
     SET is_starred = :starred
     WHERE id = :itemId AND user_id = :userId AND deleted_at IS NULL`,
    { itemId, userId, starred: starred ? 1 : 0 },
  );
  return getByIdForUser(userId, itemId);
}

/** 更新备注 */
async function updateNote(userId, itemId, note) {
  const existing = await getByIdForUser(userId, itemId);
  if (!existing) {
    throw Object.assign(new Error('条目不存在'), { status: 404 });
  }
  const value = note == null ? null : String(note).trim().slice(0, 5000);
  await pool.execute(
    `UPDATE items SET note = :note
     WHERE id = :itemId AND user_id = :userId AND deleted_at IS NULL`,
    { itemId, userId, note: value || null },
  );
  return getByIdForUser(userId, itemId);
}

const CONTENT_MAX_LEN = 512000;

/** 用户手工更新正文（Markdown 原文）；保留已有 AI 标签/思维导图（微调场景） */
async function updateContent(userId, itemId, content) {
  const existing = await getByIdForUser(userId, itemId);
  if (!existing) {
    throw Object.assign(new Error('条目不存在'), { status: 404 });
  }
  const value =
    content == null ? null : String(content).slice(0, CONTENT_MAX_LEN);
  await pool.execute(
    `UPDATE items
     SET content = :content,
         content_edited_at = CURRENT_TIMESTAMP(3),
         updated_at = CURRENT_TIMESTAMP(3)
     WHERE id = :itemId AND user_id = :userId AND deleted_at IS NULL`,
    { itemId, userId, content: value },
  );
  return getByIdForUser(userId, itemId);
}

/** 移动到收藏夹 */
async function moveToFolder(userId, itemId, folderId) {
  const existing = await getByIdForUser(userId, itemId);
  if (!existing) {
    throw Object.assign(new Error('条目不存在'), { status: 404 });
  }
  const [folders] = await pool.execute(
    `SELECT id FROM categories
     WHERE id = :folderId AND section = 'folder'
       AND (user_id = :userId OR (user_id = 0 AND is_system = 1))
     LIMIT 1`,
    { folderId, userId },
  );
  if (!folders[0]) {
    throw Object.assign(new Error('收藏夹不存在'), { status: 404 });
  }
  await pool.execute(
    `UPDATE items SET folder_id = :folderId
     WHERE id = :itemId AND user_id = :userId AND deleted_at IS NULL`,
    { itemId, userId, folderId },
  );
  return getByIdForUser(userId, itemId);
}

/** 软删除 → 回收站 */
async function softDelete(userId, itemId) {
  const existing = await getByIdForUser(userId, itemId);
  if (!existing) {
    throw Object.assign(new Error('条目不存在'), { status: 404 });
  }
  await pool.execute(
    `UPDATE items SET deleted_at = CURRENT_TIMESTAMP(3)
     WHERE id = :itemId AND user_id = :userId AND deleted_at IS NULL`,
    { itemId, userId },
  );
  return { id: itemId, deleted: true };
}

/** 从回收站恢复 */
async function restoreFromTrash(userId, itemId) {
  const existing = await getByIdForUser(userId, itemId, {
    includeDeleted: true,
  });
  if (!existing || !existing.deletedAt) {
    throw Object.assign(new Error('回收站中不存在该条目'), { status: 404 });
  }

  if (existing.canonicalUrl) {
    const [dup] = await pool.execute(
      `SELECT id FROM items
       WHERE user_id = :userId
         AND canonical_url = :canonicalUrl
         AND deleted_at IS NULL
         AND id <> :itemId
       LIMIT 1`,
      {
        userId,
        canonicalUrl: existing.canonicalUrl,
        itemId,
      },
    );
    if (dup[0]) {
      throw Object.assign(
        new Error('已有相同链接的收藏，无法恢复'),
        { status: 409 },
      );
    }
  }

  await pool.execute(
    `UPDATE items SET deleted_at = NULL
     WHERE id = :itemId AND user_id = :userId AND deleted_at IS NOT NULL`,
    { itemId, userId },
  );
  return getByIdForUser(userId, itemId);
}

/** 彻底删除（详情页 / 回收站均可） */
async function purgeFromTrash(userId, itemId) {
  const existing = await getByIdForUser(userId, itemId, {
    includeDeleted: true,
  });
  if (!existing) {
    throw Object.assign(new Error('条目不存在'), { status: 404 });
  }
  await pool.execute(
    `DELETE FROM items
     WHERE id = :itemId AND user_id = :userId`,
    { itemId, userId },
  );
  return { id: itemId, purged: true };
}

/** 清空回收站 */
async function emptyTrash(userId) {
  const [result] = await pool.execute(
    `DELETE FROM items
     WHERE user_id = :userId AND deleted_at IS NOT NULL`,
    { userId },
  );
  return { emptied: true, deletedCount: Number(result.affectedRows || 0) };
}

/** 条目当前标签（不含系统「无标签」） */
async function listItemTags(userId, itemId) {
  const existing = await getByIdForUser(userId, itemId);
  if (!existing) {
    throw Object.assign(new Error('条目不存在'), { status: 404 });
  }
  const [rows] = await pool.execute(
    `SELECT c.id, c.name, c.code, c.is_system, c.sort_order, c.created_at, c.updated_at
     FROM item_tags it
     INNER JOIN categories c ON c.id = it.category_id
     INNER JOIN items i ON i.id = it.item_id
     WHERE it.item_id = :itemId
       AND i.user_id = :userId
       AND c.section = 'tag'
       AND c.is_system = 0
     ORDER BY c.sort_order ASC, c.id ASC`,
    { itemId, userId },
  );
  return rows.map((row) => ({
    id: row.id,
    name: row.name,
    code: row.code,
    isSystem: !!row.is_system,
    sortOrder: row.sort_order,
    itemCount: 0,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  }));
}

/** 覆盖设置条目标签（仅用户自建标签 id） */
async function setItemTags(userId, itemId, tagIds) {
  const existing = await getByIdForUser(userId, itemId);
  if (!existing) {
    throw Object.assign(new Error('条目不存在'), { status: 404 });
  }
  const ids = [...new Set((tagIds || []).map((n) => Number(n)).filter((n) => n > 0))];

  if (ids.length) {
    for (const tagId of ids) {
      const [owned] = await pool.execute(
        `SELECT id FROM categories
         WHERE id = :tagId AND section = 'tag'
           AND user_id = :userId AND is_system = 0
         LIMIT 1`,
        { tagId, userId },
      );
      if (!owned[0]) {
        throw Object.assign(new Error('包含无效标签'), { status: 400 });
      }
    }
  }

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    await conn.execute(`DELETE FROM item_tags WHERE item_id = :itemId`, { itemId });
    for (const tagId of ids) {
      await conn.execute(
        `INSERT INTO item_tags (item_id, category_id) VALUES (:itemId, :tagId)`,
        { itemId, tagId },
      );
    }
    await conn.commit();
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }

  return listItemTags(userId, itemId);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function listTranscriptTargetsForUser(userId, itemId) {
  const [rows] = await pool.execute(
    `SELECT * FROM items
     WHERE id = :itemId AND user_id = :userId AND deleted_at IS NULL
     LIMIT 1`,
    { itemId, userId },
  );
  const row = rows[0];
  if (!row) {
    throw Object.assign(new Error('条目不存在'), { status: 404 });
  }
  return {
    id: row.id,
    targets: transcriptSegments.listTranscriptTargets(row),
  };
}

/**
 * 用户触发：按 segmentKey 提交阿里云录音文件识别。
 * 已有任一段 pending 时拒绝（409）。
 */
async function beginTranscriptSegment(
  userId,
  itemId,
  segmentKey,
  { force = false, mediaUrl: clientMediaUrl } = {},
) {
  const aliyunAsr = require('./aliyunAsr');
  const { enqueueTranscript } = require('./transcriptQueue');

  if (!aliyunAsr.isConfigured()) {
    throw Object.assign(
      new Error('语音转写未配置：请设置 ALIYUN_NLS_APP_KEY'),
      { status: 503 },
    );
  }

  const key = String(segmentKey || '').trim();
  if (!key) {
    throw Object.assign(new Error('缺少 segmentKey'), { status: 400 });
  }

  const [rows] = await pool.execute(
    `SELECT * FROM items
     WHERE id = :itemId AND user_id = :userId AND deleted_at IS NULL
     LIMIT 1`,
    { itemId, userId },
  );
  const row = rows[0];
  if (!row) {
    throw Object.assign(new Error('条目不存在'), { status: 404 });
  }

  const targets = transcriptSegments.listTranscriptTargets(row);
  const target = targets.find((t) => t.segmentKey === key);
  if (!target) {
    throw Object.assign(new Error('无效的转写对象'), { status: 400 });
  }

  let segments = transcriptSegments.parseSegments(row.transcript_segments);
  if (transcriptSegments.hasPendingSegment(segments)) {
    throw Object.assign(new Error('请等当前转写完成'), { status: 409 });
  }

  const cur = transcriptSegments.normalizeSegment(segments[key]);
  if (cur.status === 'success' && cur.text && !force) {
    return mapItem(row);
  }

  const mediaUrl = transcriptSegments.resolveMediaUrlForSegment(
    row,
    key,
    clientMediaUrl,
  );
  if (!mediaUrl) {
    throw Object.assign(
      new Error('该段没有可转写的音视频直链，请先刷新视频'),
      { status: 400 },
    );
  }

  segments = transcriptSegments.setSegment(segments, key, {
    status: 'pending',
    text: null,
    cues: [],
    error: null,
    taskId: null,
    mediaUrl,
    transcribedAt: null,
    phase: 'queued',
    phaseLabel: '排队等待中',
  });

  await pool.execute(
    `UPDATE items
     SET transcript_segments = :segments,
         updated_at = CURRENT_TIMESTAMP(3)
     WHERE id = :itemId AND user_id = :userId`,
    { itemId, userId, segments: JSON.stringify(segments) },
  );

  enqueueTranscript(itemId);
  return getByIdForUser(userId, itemId);
}

async function requestTranscript(
  userId,
  itemId,
  { segmentKey, force = false, mediaUrl: clientMediaUrl } = {},
) {
  return beginTranscriptSegment(userId, itemId, segmentKey, {
    force,
    mediaUrl: clientMediaUrl,
  });
}

async function getTranscriptStatus(userId, itemId) {
  const [rows] = await pool.execute(
    `SELECT id, transcript_segments, updated_at
     FROM items
     WHERE id = :itemId AND user_id = :userId AND deleted_at IS NULL
     LIMIT 1`,
    { itemId, userId },
  );
  const row = rows[0];
  if (!row) {
    throw Object.assign(new Error('条目不存在'), { status: 404 });
  }
  const segments = transcriptSegments.parseSegments(row.transcript_segments);
  const pendingSegmentKey = transcriptSegments.findPendingSegmentKey(segments);
  return {
    id: row.id,
    segments: transcriptSegments.mapSegmentsForApi(segments),
    pendingSegmentKey,
    hasPending: pendingSegmentKey != null,
    updatedAt: row.updated_at,
  };
}

async function saveTranscriptSegments(itemId, segments) {
  await pool.execute(
    `UPDATE items
     SET transcript_segments = :segments, updated_at = CURRENT_TIMESTAMP(3)
     WHERE id = :itemId`,
    { itemId, segments: JSON.stringify(segments) },
  );
}

/**
 * 队列执行：对 pending 段提交 FileTrans → 轮询 → 写回该段。
 * 日志含分阶段耗时：download / upload / submit / poll / total。
 * pending 期间写入 phase / phaseLabel 供 App 轮询展示。
 */
async function runTranscriptJob(itemId) {
  const aliyunAsr = require('./aliyunAsr');
  const transcriptMediaOss = require('./transcriptMediaOss');
  const jobT0 = Date.now();
  const [rows] = await pool.execute(
    `SELECT * FROM items WHERE id = :itemId AND deleted_at IS NULL LIMIT 1`,
    { itemId },
  );
  const row = rows[0];
  if (!row) return;

  let segments = transcriptSegments.parseSegments(row.transcript_segments);
  const segmentKey = transcriptSegments.findPendingSegmentKey(segments);
  if (!segmentKey) return;

  const seg = transcriptSegments.normalizeSegment(segments[segmentKey]);
  const mediaUrl = seg.mediaUrl;
  if (!mediaUrl) {
    segments = transcriptSegments.setSegment(segments, segmentKey, {
      status: 'failed',
      error: '没有可转写的音视频直链',
      phase: null,
      phaseLabel: null,
    });
    await saveTranscriptSegments(itemId, segments);
    return;
  }

  let taskId = seg.taskId;
  let ossKeyToDelete = null;
  let viaOss = false;
  let downloadMs = 0;
  let uploadMs = 0;
  let submitMs = 0;
  let pollMs = 0;
  let pollAttempts = 0;
  let lastStatus = '';

  const persistPhase = async (phase, phaseLabel) => {
    segments = transcriptSegments.setSegment(segments, segmentKey, {
      phase,
      phaseLabel,
    });
    await saveTranscriptSegments(itemId, segments);
  };

  console.log(
    `[runTranscriptJob] start item=${itemId} segment=${segmentKey} ` +
      `platform=${row.platform} viaOssHint=${transcriptMediaOss.needsOssProxy(mediaUrl)} ` +
      `mediaHost=${safeMediaHost(mediaUrl)}`,
  );

  try {
    if (!taskId) {
      const pageUrl = row.canonical_url || row.url;
      const resolveT0 = Date.now();
      const resolved = await transcriptMediaOss.resolveAsrFileLink({
        mediaUrl,
        pageUrl,
        itemId,
        segmentKey,
        onPhase: persistPhase,
      });
      viaOss = !!resolved.viaOss;
      downloadMs = resolved.downloadMs || 0;
      uploadMs = resolved.uploadMs || 0;
      ossKeyToDelete = resolved.ossKey;
      console.log(
        `[runTranscriptJob] file_link ready item=${itemId} viaOss=${viaOss} ` +
          `resolveMs=${Date.now() - resolveT0} ` +
          `downloadMs=${downloadMs} uploadMs=${uploadMs} ` +
          `durationSec=${resolved.durationSec == null ? 'unknown' : Number(resolved.durationSec).toFixed(1)}`,
      );

      await persistPhase('submitting', '提交识别中');
      const submitT0 = Date.now();
      const submitted = await aliyunAsr.submitFileTrans(resolved.fileLink);
      submitMs = Date.now() - submitT0;
      taskId = submitted.taskId;
      console.log(
        `[runTranscriptJob] submitted item=${itemId} taskId=${taskId} submitMs=${submitMs}`,
      );
      segments = transcriptSegments.setSegment(segments, segmentKey, {
        taskId,
        phase: 'queueing',
        phaseLabel: '识别排队中',
      });
      await saveTranscriptSegments(itemId, segments);
    } else {
      await persistPhase('recognizing', '识别中');
    }

    const maxAttempts = 180;
    const intervalMs = 10000;
    const pollT0 = Date.now();
    let lastPhase = '';
    for (let i = 0; i < maxAttempts; i += 1) {
      pollAttempts = i + 1;
      const result = await aliyunAsr.getFileTransResult(taskId);
      lastStatus = result.statusText || '';
      if (!result.done) {
        const phase =
          lastStatus === 'QUEUEING' ? 'queueing' : 'recognizing';
        const phaseLabel =
          lastStatus === 'QUEUEING' ? '识别排队中' : '识别中';
        if (phase !== lastPhase) {
          lastPhase = phase;
          await persistPhase(phase, phaseLabel);
        }
        if (i === 0 || i % 6 === 5) {
          console.log(
            `[runTranscriptJob] polling item=${itemId} attempt=${pollAttempts} ` +
              `status=${lastStatus} elapsedMs=${Date.now() - pollT0}`,
          );
        }
        await sleep(intervalMs);
        continue;
      }
      pollMs = Date.now() - pollT0;
      if (!result.ok) {
        console.warn(
          `[runTranscriptJob] failed item=${itemId} status=${lastStatus} ` +
            `pollMs=${pollMs} attempts=${pollAttempts} totalMs=${Date.now() - jobT0}`,
        );
        segments = transcriptSegments.setSegment(segments, segmentKey, {
          status: 'failed',
          error: String(result.errorMessage || '转写失败').slice(0, 500),
          taskId: null,
          mediaUrl: null,
          phase: null,
          phaseLabel: null,
        });
        await saveTranscriptSegments(itemId, segments);
        return;
      }
      console.log(
        `[runTranscriptJob] ok item=${itemId} segment=${segmentKey} viaOss=${viaOss} ` +
          `downloadMs=${downloadMs} uploadMs=${uploadMs} submitMs=${submitMs} ` +
          `pollMs=${pollMs} attempts=${pollAttempts} lastStatus=${lastStatus} ` +
          `totalMs=${Date.now() - jobT0} textLen=${(result.text || '').length} ` +
          `cues=${Array.isArray(result.cues) ? result.cues.length : 0}`,
      );
      segments = transcriptSegments.setSegment(segments, segmentKey, {
        status: 'success',
        text: result.text || '',
        cues: Array.isArray(result.cues) ? result.cues : [],
        error: null,
        taskId: null,
        mediaUrl: null,
        transcribedAt: new Date().toISOString(),
        phase: null,
        phaseLabel: null,
      });
      await saveTranscriptSegments(itemId, segments);
      return;
    }

    pollMs = Date.now() - pollT0;
    console.warn(
      `[runTranscriptJob] timeout item=${itemId} pollMs=${pollMs} attempts=${pollAttempts} ` +
        `lastStatus=${lastStatus} totalMs=${Date.now() - jobT0}`,
    );
    segments = transcriptSegments.setSegment(segments, segmentKey, {
      status: 'failed',
      error: '转写超时，请稍后重试',
      taskId: null,
      mediaUrl: null,
      phase: null,
      phaseLabel: null,
    });
    await saveTranscriptSegments(itemId, segments);
  } catch (err) {
    console.error(
      `[runTranscriptJob] error item=${itemId} segment=${segmentKey} ` +
        `totalMs=${Date.now() - jobT0}`,
      err,
    );
    segments = transcriptSegments.setSegment(segments, segmentKey, {
      status: 'failed',
      error: String(err.message || '转写异常').slice(0, 500),
      taskId: null,
      mediaUrl: null,
      phase: null,
      phaseLabel: null,
    });
    await saveTranscriptSegments(itemId, segments);
  } finally {
    if (ossKeyToDelete) {
      transcriptMediaOss.deleteOssObject(ossKeyToDelete).catch((err) => {
        console.warn(`[runTranscriptJob] OSS cleanup ${ossKeyToDelete}`, err.message);
      });
    }
    try {
      const aiMindmapService = require('./aiMindmapService');
      await aiMindmapService.onTranscriptSettledForMindmap(itemId);
    } catch (err) {
      console.error(
        `[runTranscriptJob] mindmap resume failed item=${itemId}`,
        err.message,
      );
    }
    try {
      const aiSuggestService = require('./aiSuggestService');
      await aiSuggestService.onTranscriptSettledForAiSuggest(itemId);
    } catch (err) {
      console.error(
        `[runTranscriptJob] ai-suggest resume failed item=${itemId}`,
        err.message,
      );
    }
  }
}

function safeMediaHost(mediaUrl) {
  try {
    return new URL(String(mediaUrl)).host;
  } catch {
    return 'invalid';
  }
}

const HIT_LABELS = {
  title: '标题',
  content: '正文',
  summary: '摘要',
  note: '备注',
  transcript: '文稿',
  url: '链接',
  platform: '来源',
  tag: '标签',
  annotation: '标注',
};

const PLATFORM_ALIASES = {
  微信: 'weixin',
  视频号: 'channels',
  channels: 'channels',
  小红书: 'xiaohongshu',
  抖音: 'douyin',
  微博: 'weibo',
  B站: 'bilibili',
  bilibili: 'bilibili',
  即刻: 'jike',
  jike: 'jike',
  知乎: 'zhihu',
  头条: 'toutiao',
  今日头条: 'toutiao',
  toutiao: 'toutiao',
  人民日报: 'people',
  people: 'people',
  腾讯新闻: 'qqnews',
  qqnews: 'qqnews',
  新浪: 'sina',
  新浪新闻: 'sina',
  sina: 'sina',
  澎湃: 'thepaper',
  澎湃新闻: 'thepaper',
  thepaper: 'thepaper',
  南方周末: 'infzm',
  infzm: 'infzm',
  新华社: 'xinhuaxmt',
  xinhuaxmt: 'xinhuaxmt',
  小宇宙: 'xiaoyuzhou',
  xiaoyuzhou: 'xiaoyuzhou',
  网页: 'web',
  zaker: 'zaker',
  扎克: 'zaker',
};

function escapeLike(text) {
  return String(text).replace(/\\/g, '\\\\').replace(/%/g, '\\%').replace(/_/g, '\\_');
}

function buildMatchedFields(row, query, platformAlias) {
  const q = query.toLowerCase();
  const hits = [];
  const includes = (value) =>
    value != null && String(value).toLowerCase().includes(q);

  if (includes(row.title)) hits.push('title');
  if (includes(row.content)) hits.push('content');
  if (includes(row.summary)) hits.push('summary');
  if (includes(row.note)) hits.push('note');
  const transcriptBlob = transcriptSegments.allTranscriptText(
    transcriptSegments.parseSegments(row.transcript_segments),
  );
  if (includes(transcriptBlob)) hits.push('transcript');
  if (includes(row.url) || includes(row.canonical_url)) hits.push('url');
  if (
    includes(row.platform) ||
    (platformAlias && row.platform === platformAlias)
  ) {
    hits.push('platform');
  }
  if (Number(row.hit_tag) === 1) hits.push('tag');
  if (Number(row.hit_annotation) === 1) hits.push('annotation');

  return [...new Set(hits)];
}

/**
 * 全局搜索（未删除条目）
 * 匹配：标题 / 正文 / 摘要 / 备注 / 文稿 / 链接 / 来源 / 标签名 / 标注原文与短注
 */
async function searchItems(userId, rawQuery, { limit = 50, offset = 0 } = {}) {
  const query = String(rawQuery || '').trim();
  if (!query) {
    return { query: '', total: 0, items: [] };
  }
  if (query.length > 100) {
    throw Object.assign(new Error('关键词过长'), { status: 400 });
  }

  const safeLimit = Math.min(Math.max(Number(limit) || 50, 1), 100);
  const safeOffset = Math.max(Number(offset) || 0, 0);
  const like = `%${escapeLike(query)}%`;
  const platformAlias = PLATFORM_ALIASES[query] || PLATFORM_ALIASES[query.toLowerCase()] || null;

  const params = { userId, like };
  let platformClause = '';
  if (platformAlias) {
    platformClause = ' OR i.platform = :platformAlias';
    params.platformAlias = platformAlias;
  }

  const matchClause = `
    (
      i.title LIKE :like
      OR i.summary LIKE :like
      OR i.content LIKE :like
      OR i.note LIKE :like
      OR CAST(i.transcript_segments AS CHAR) LIKE :like
      OR i.url LIKE :like
      OR i.canonical_url LIKE :like
      OR i.platform LIKE :like
      ${platformClause}
      OR EXISTS (
        SELECT 1 FROM item_tags it
        INNER JOIN categories c ON c.id = it.category_id
        WHERE it.item_id = i.id
          AND c.section = 'tag'
          AND c.name LIKE :like
      )
      OR EXISTS (
        SELECT 1 FROM annotations a
        WHERE a.item_id = i.id
          AND (a.selected_text LIKE :like OR a.note LIKE :like)
      )
    )
  `;

  const [countRows] = await pool.execute(
    `SELECT COUNT(*) AS cnt
     FROM items i
     WHERE i.user_id = :userId
       AND i.deleted_at IS NULL
       AND ${matchClause}`,
    params,
  );
  const total = Number(countRows[0]?.cnt || 0);

  const [rows] = await pool.execute(
    `SELECT i.*,
       EXISTS (
         SELECT 1 FROM item_tags it
         INNER JOIN categories c ON c.id = it.category_id
         WHERE it.item_id = i.id
           AND c.section = 'tag'
           AND c.name LIKE :like
       ) AS hit_tag,
       EXISTS (
         SELECT 1 FROM annotations a
         WHERE a.item_id = i.id
           AND (a.selected_text LIKE :like OR a.note LIKE :like)
       ) AS hit_annotation
     FROM items i
     WHERE i.user_id = :userId
       AND i.deleted_at IS NULL
       AND ${matchClause}
     ORDER BY i.created_at DESC, i.id DESC
     LIMIT ${safeLimit} OFFSET ${safeOffset}`,
    params,
  );

  const items = rows.map((row) => {
    const matchedFields = buildMatchedFields(row, query, platformAlias);
    return {
      ...mapItem(row),
      matchedFields,
      matchedLabels: matchedFields.map((f) => HIT_LABELS[f] || f),
    };
  });

  return {
    query,
    total,
    items,
    limit: safeLimit,
    offset: safeOffset,
  };
}

module.exports = {
  createItem,
  getByIdForUser,
  getParseStatus,
  listNeedsClientFetch,
  reparseItem,
  refreshItemVideo,
  runContentParse,
  parseWithClientHtml,
  mapItem,
  listBySystemFilter,
  markAsRead,
  setStarred,
  updateNote,
  updateContent,
  softDelete,
  restoreFromTrash,
  purgeFromTrash,
  emptyTrash,
  listItemTags,
  setItemTags,
  searchItems,
  listTranscriptTargetsForUser,
  beginTranscriptSegment,
  requestTranscript,
  getTranscriptStatus,
  runTranscriptJob,
  requestAiSuggest: require('./aiSuggestService').requestAiSuggest,
  getAiSuggestStatus: require('./aiSuggestService').getAiSuggestStatus,
  applyAiSuggest: require('./aiSuggestService').applyAiSuggest,
  dismissAiSuggest: require('./aiSuggestService').dismissAiSuggest,
  runAiSuggestJob: require('./aiSuggestService').runAiSuggestJob,
  requestMindmap: require('./aiMindmapService').requestMindmap,
  getMindmapStatus: require('./aiMindmapService').getMindmapStatus,
  runMindmapJob: require('./aiMindmapService').runMindmapJob,
};
