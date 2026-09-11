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

/** POST /api/tags — 新建标签；可选 body.parentId */
router.post('/', async (req, res, next) => {
  try {
    const tag = await tagService.createTag(req.auth.userId, req.body?.name, {
      parentId: req.body?.parentId,
    });
    return res.status(201).json({
      tag,
      message: '已创建',
    });
  } catch (err) {
    return next(err);
  }
});

/** PUT /api/tags/reorder — 批量更新分组与排序（须提交全部自建标签） */
router.put('/reorder', async (req, res, next) => {
  try {
    const tags = await tagService.reorderTags(
      req.auth.userId,
      req.body?.items,
    );
    return res.json({ tags, message: '已更新' });
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

/** PATCH /api/tags/:id — 重命名自建标签 */
router.patch('/:id', async (req, res, next) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isFinite(id) || id <= 0) {
      return res.status(400).json({ message: '无效的标签 ID' });
    }
    const tag = await tagService.renameTag(
      req.auth.userId,
      id,
      req.body?.name,
    );
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
