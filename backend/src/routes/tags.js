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

/** POST /api/tags — 新建标签 */
router.post('/', async (req, res, next) => {
  try {
    const tag = await tagService.createTag(req.auth.userId, req.body?.name);
    return res.status(201).json({
      tag,
      message: '已创建',
    });
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
