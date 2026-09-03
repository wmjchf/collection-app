const express = require('express');
const { requireAuth } = require('../middleware/auth');
const itemService = require('../services/itemService');

const router = express.Router();

router.use(requireAuth);

/** POST /api/items — 保存链接（同步快速元信息 + 异步正文解析） */
router.post('/', async (req, res, next) => {
  try {
    const url = req.body?.url;
    if (!url || !String(url).trim()) {
      return res.status(400).json({ message: '请输入链接' });
    }
    const { item, existed } = await itemService.createItem(req.auth.userId, url);
    return res.status(existed ? 200 : 201).json({
      item,
      existed,
      message: existed ? '该链接已收藏' : '已保存',
    });
  } catch (err) {
    return next(err);
  }
});

/**
 * GET /api/items?filter=unread|all|today|starred|parsed|annotated|recent_read|archived|trash
 * Query: tzOffsetMinutes, limit, offset
 */
router.get('/', async (req, res, next) => {
  try {
    const filter = String(req.query.filter || '').trim();
    if (!filter) {
      return res.status(400).json({
        message:
          '请指定 filter（unread/all/today/starred/parsed/annotated/recent_read/archived/trash）',
      });
    }
    const result = await itemService.listBySystemFilter(req.auth.userId, filter, {
      tzOffsetMinutes: Number(req.query.tzOffsetMinutes ?? 480),
      limit: Number(req.query.limit ?? 50),
      offset: Number(req.query.offset ?? 0),
    });
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

/**
 * GET /api/items/search?q=
 * Query: limit, offset
 */
router.get('/search', async (req, res, next) => {
  try {
    const q = String(req.query.q || '').trim();
    const result = await itemService.searchItems(req.auth.userId, q, {
      limit: Number(req.query.limit ?? 50),
      offset: Number(req.query.offset ?? 0),
    });
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

/** GET /api/items/needs-client-fetch — 待本机抓取补齐的条目 */
router.get('/needs-client-fetch', async (req, res, next) => {
  try {
    const items = await itemService.listNeedsClientFetch(req.auth.userId, {
      limit: Number(req.query.limit) || 20,
    });
    return res.json({ items });
  } catch (err) {
    return next(err);
  }
});

/** GET /api/items/:id — 详情（含最近删除中的条目） */
router.get('/:id', async (req, res, next) => {
  try {
    const item = await itemService.getByIdForUser(
      req.auth.userId,
      Number(req.params.id),
      { includeDeleted: true },
    );
    if (!item) {
      return res.status(404).json({ message: '条目不存在' });
    }
    return res.json({ item });
  } catch (err) {
    return next(err);
  }
});

/** GET /api/items/:id/parse-status — 轻量轮询 */
router.get('/:id/parse-status', async (req, res, next) => {
  try {
    const status = await itemService.getParseStatus(
      req.auth.userId,
      Number(req.params.id),
    );
    return res.json(status);
  } catch (err) {
    return next(err);
  }
});

/** POST /api/items/:id/reparse — 重试正文解析；body 可选 { forceOverwrite: true } */
router.post('/:id/reparse', async (req, res, next) => {
  try {
    const item = await itemService.reparseItem(
      req.auth.userId,
      Number(req.params.id),
      { forceOverwrite: req.body?.forceOverwrite === true },
    );
    return res.json({ item, message: '已开始重新解析' });
  } catch (err) {
    return next(err);
  }
});

/** POST /api/items/:id/refresh-video — 刷新 CDN 播放直链（B站等） */
router.post('/:id/refresh-video', async (req, res, next) => {
  try {
    const item = await itemService.refreshItemVideo(
      req.auth.userId,
      Number(req.params.id),
    );
    return res.json({ item, message: '视频链接已刷新' });
  } catch (err) {
    return next(err);
  }
});

/** GET /api/items/:id/transcript-targets — 可转写媒体列表及各段状态 */
router.get('/:id/transcript-targets', async (req, res, next) => {
  try {
    const data = await itemService.listTranscriptTargetsForUser(
      req.auth.userId,
      Number(req.params.id),
    );
    return res.json(data);
  } catch (err) {
    return next(err);
  }
});

/** POST /api/items/:id/transcript — 按 segmentKey 提交阿里云录音识别 */
router.post('/:id/transcript', async (req, res, next) => {
  try {
    const item = await itemService.requestTranscript(
      req.auth.userId,
      Number(req.params.id),
      {
        segmentKey: req.body?.segmentKey,
        force: !!req.body?.force,
        mediaUrl: req.body?.mediaUrl,
      },
    );
    return res.json({
      item,
      message: '已开始转写，请稍后查看',
    });
  } catch (err) {
    return next(err);
  }
});

/** GET /api/items/:id/ai-suggest-status — AI 标签建议轮询 */
router.get('/:id/ai-suggest-status', async (req, res, next) => {
  try {
    const status = await itemService.getAiSuggestStatus(
      req.auth.userId,
      Number(req.params.id),
    );
    return res.json(status);
  } catch (err) {
    return next(err);
  }
});

/** POST /api/items/:id/ai-suggest — 手动触发 AI 标签建议 */
router.post('/:id/ai-suggest', async (req, res, next) => {
  try {
    const item = await itemService.requestAiSuggest(
      req.auth.userId,
      Number(req.params.id),
      {
        force: !!req.body?.force,
        direction: req.body?.direction ?? req.body?.hint ?? null,
      },
    );
    return res.json({ item, message: '正在生成标签建议…' });
  } catch (err) {
    return next(err);
  }
});

/** POST /api/items/:id/ai-suggest/apply — 采纳所选标签（合并已有） */
router.post('/:id/ai-suggest/apply', async (req, res, next) => {
  try {
    const names = req.body?.names || req.body?.selected || [];
    const item = await itemService.applyAiSuggest(
      req.auth.userId,
      Number(req.params.id),
      { names: Array.isArray(names) ? names : [] },
    );
    return res.json({ item, message: '已采纳标签' });
  } catch (err) {
    return next(err);
  }
});

/** POST /api/items/:id/ai-suggest/dismiss — 忽略建议 */
router.post('/:id/ai-suggest/dismiss', async (req, res, next) => {
  try {
    const item = await itemService.dismissAiSuggest(
      req.auth.userId,
      Number(req.params.id),
    );
    return res.json({ item, message: '已忽略' });
  } catch (err) {
    return next(err);
  }
});

/** GET /api/items/:id/mindmap-status — 思维导图轮询 */
router.get('/:id/mindmap-status', async (req, res, next) => {
  try {
    const status = await itemService.getMindmapStatus(
      req.auth.userId,
      Number(req.params.id),
    );
    return res.json(status);
  } catch (err) {
    return next(err);
  }
});

/** POST /api/items/:id/mindmap — 手动触发思维导图 */
router.post('/:id/mindmap', async (req, res, next) => {
  try {
    const item = await itemService.requestMindmap(
      req.auth.userId,
      Number(req.params.id),
      {
        force: !!req.body?.force,
        direction: req.body?.direction ?? req.body?.hint ?? null,
      },
    );
    return res.json({ item, message: '正在生成思维导图…' });
  } catch (err) {
    return next(err);
  }
});

/** GET /api/items/:id/summary-status — AI 总结轮询 */
router.get('/:id/summary-status', async (req, res, next) => {
  try {
    const status = await itemService.getSummaryStatus(
      req.auth.userId,
      Number(req.params.id),
    );
    return res.json(status);
  } catch (err) {
    return next(err);
  }
});

/** POST /api/items/:id/summary — 手动触发 AI 总结 */
router.post('/:id/summary', async (req, res, next) => {
  try {
    const item = await itemService.requestSummary(
      req.auth.userId,
      Number(req.params.id),
      {
        force: !!req.body?.force,
        direction: req.body?.direction ?? req.body?.hint ?? null,
      },
    );
    return res.json({ item, message: '正在生成 AI 总结…' });
  } catch (err) {
    return next(err);
  }
});

/** GET /api/items/:id/transcript-status — 转写状态轮询 */
router.get('/:id/transcript-status', async (req, res, next) => {
  try {
    const status = await itemService.getTranscriptStatus(
      req.auth.userId,
      Number(req.params.id),
    );
    return res.json(status);
  } catch (err) {
    return next(err);
  }
});

/** POST /api/items/:id/parse-with-html — 客户端抓取 HTML 后交由服务端抽取 */
router.post('/:id/parse-with-html', async (req, res, next) => {
  try {
    const html = req.body?.html;
    const item = await itemService.parseWithClientHtml(
      req.auth.userId,
      Number(req.params.id),
      html,
    );
    return res.json({
      item,
      message: item.status === 'success' ? '解析完成' : '解析失败',
    });
  } catch (err) {
    return next(err);
  }
});

/** POST /api/items/:id/read — 进入阅读：已读 + last_read_at */
router.post('/:id/read', async (req, res, next) => {
  try {
    const item = await itemService.markAsRead(
      req.auth.userId,
      Number(req.params.id),
    );
    return res.json({ item });
  } catch (err) {
    return next(err);
  }
});

/** POST /api/items/:id/star — body { starred: boolean } */
router.post('/:id/star', async (req, res, next) => {
  try {
    const starred = !!req.body?.starred;
    const item = await itemService.setStarred(
      req.auth.userId,
      Number(req.params.id),
      starred,
    );
    return res.json({ item });
  } catch (err) {
    return next(err);
  }
});

/** PATCH /api/items/:id — body { note? } 或 { content? } */
router.patch('/:id', async (req, res, next) => {
  try {
    const itemId = Number(req.params.id);
    const userId = req.auth.userId;
    const body = req.body || {};
    const hasNote = Object.prototype.hasOwnProperty.call(body, 'note');
    const hasContent = Object.prototype.hasOwnProperty.call(body, 'content');
    if (!hasNote && !hasContent) {
      return res.status(400).json({ message: '请提供 note 或 content' });
    }
    if (hasNote && hasContent) {
      return res.status(400).json({ message: '请分别更新 note 或 content' });
    }
    let item;
    if (hasNote) {
      item = await itemService.updateNote(userId, itemId, body.note);
    } else {
      item = await itemService.updateContent(userId, itemId, body.content);
    }
    return res.json({ item });
  } catch (err) {
    return next(err);
  }
});

/** DELETE /api/items/trash — 清空回收站 */
router.delete('/trash', async (req, res, next) => {
  try {
    const result = await itemService.emptyTrash(req.auth.userId);
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

/** POST /api/items/:id/restore — 从回收站恢复 */
router.post('/:id/restore', async (req, res, next) => {
  try {
    const item = await itemService.restoreFromTrash(
      req.auth.userId,
      Number(req.params.id),
    );
    return res.json({ item });
  } catch (err) {
    return next(err);
  }
});

/** DELETE /api/items/:id/permanent — 彻底删除（不可恢复） */
router.delete('/:id/permanent', async (req, res, next) => {
  try {
    const result = await itemService.purgeFromTrash(
      req.auth.userId,
      Number(req.params.id),
    );
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

/** DELETE /api/items/:id — 软删除 */
router.delete('/:id', async (req, res, next) => {
  try {
    const result = await itemService.softDelete(
      req.auth.userId,
      Number(req.params.id),
    );
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

/** GET /api/items/:id/tags */
router.get('/:id/tags', async (req, res, next) => {
  try {
    const tags = await itemService.listItemTags(
      req.auth.userId,
      Number(req.params.id),
    );
    return res.json({ tags });
  } catch (err) {
    return next(err);
  }
});

/** PUT /api/items/:id/tags — body { tagIds: number[] } */
router.put('/:id/tags', async (req, res, next) => {
  try {
    const tags = await itemService.setItemTags(
      req.auth.userId,
      Number(req.params.id),
      req.body?.tagIds || [],
    );
    return res.json({ tags });
  } catch (err) {
    return next(err);
  }
});

const annotationService = require('../services/annotationService');

/** GET /api/items/:id/annotations */
router.get('/:id/annotations', async (req, res, next) => {
  try {
    const annotations = await annotationService.listByItem(
      req.auth.userId,
      Number(req.params.id),
    );
    return res.json({ annotations });
  } catch (err) {
    return next(err);
  }
});

/** POST /api/items/:id/annotations */
router.post('/:id/annotations', async (req, res, next) => {
  try {
    const annotation = await annotationService.create(
      req.auth.userId,
      Number(req.params.id),
      req.body || {},
    );
    return res.status(201).json({ annotation });
  } catch (err) {
    return next(err);
  }
});

/** PATCH /api/items/:id/annotations/:annotationId */
router.patch('/:id/annotations/:annotationId', async (req, res, next) => {
  try {
    const annotation = await annotationService.update(
      req.auth.userId,
      Number(req.params.id),
      Number(req.params.annotationId),
      req.body || {},
    );
    return res.json({ annotation });
  } catch (err) {
    return next(err);
  }
});

/** DELETE /api/items/:id/annotations/:annotationId */
router.delete('/:id/annotations/:annotationId', async (req, res, next) => {
  try {
    const result = await annotationService.remove(
      req.auth.userId,
      Number(req.params.id),
      Number(req.params.annotationId),
    );
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
