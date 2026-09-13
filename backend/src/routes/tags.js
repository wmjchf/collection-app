const express = require('express');
const { requireAuth } = require('../middleware/auth');
const tagService = require('../services/tagService');

const router = express.Router();

router.use(requireAuth);

/** GET /api/tags — 用户自建标签，含条目数 */
router.get('/', async (req, res, next) => {
  try {
    const tags = await tagService.listTags(req.auth.userId);
    return res.json({ tags });
  } catch (err) {
    return next(err);
  }
});

/** POST /api/tags — 新建标签；可选 moduleId 归入模块 */
router.post('/', async (req, res, next) => {
  try {
    const tag = await tagService.createTag(req.auth.userId, req.body?.name, {
      moduleId: req.body?.moduleId,
    });
    return res.status(201).json({
      tag,
      message: '已创建',
    });
  } catch (err) {
    return next(err);
  }
});

/** GET /api/tags/search?q= — 搜标签 + 挂有匹配标签的条目（须在 /:id 之前） */
router.get('/search', async (req, res, next) => {
  try {
    const result = await tagService.searchTagsAndItems(
      req.auth.userId,
      req.query.q,
      {
        limit: req.query.limit,
        offset: req.query.offset,
        filterTagIds: req.query.filterTagIds,
      },
    );
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

/** GET /api/tags/:id/items — 标签下条目 */
router.get('/:id/items', async (req, res, next) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isFinite(id) || id <= 0) {
      return res.status(400).json({ message: '无效的标签 ID' });
    }
    const result = await tagService.listTagItems(req.auth.userId, id, {
      limit: Number(req.query.limit ?? 50),
      offset: Number(req.query.offset ?? 0),
    });
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

/** PATCH /api/tags/:id — 重命名，或放置（换模块 / 组内排序） */
router.patch('/:id', async (req, res, next) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isFinite(id) || id <= 0) {
      return res.status(400).json({ message: '无效的标签 ID' });
    }
    const body = req.body || {};
    const hasName = body.name !== undefined;
    const hasPlace = Object.prototype.hasOwnProperty.call(body, 'moduleId');
    if (!hasName && !hasPlace) {
      return res.status(400).json({ message: '请提供 name 或 moduleId' });
    }

    let tag = null;
    if (hasPlace) {
      tag = await tagService.placeTag(req.auth.userId, id, {
        moduleId: body.moduleId,
        beforeTagId: body.beforeTagId,
      });
    }
    if (hasName) {
      tag = await tagService.renameTag(req.auth.userId, id, body.name);
    }
    return res.json({
      tag,
      message: '已更新',
    });
  } catch (err) {
    return next(err);
  }
});

/** DELETE /api/tags/:id — 删除自建标签（仅解除关联） */
router.delete('/:id', async (req, res, next) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isFinite(id) || id <= 0) {
      return res.status(400).json({ message: '无效的标签 ID' });
    }
    const result = await tagService.deleteTag(req.auth.userId, id);
    return res.json({
      ...result,
      message: '已删除标签，条目仍保留',
    });
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
