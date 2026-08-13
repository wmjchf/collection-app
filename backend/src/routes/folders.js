const express = require('express');
const { requireAuth } = require('../middleware/auth');
const folderService = require('../services/folderService');

const router = express.Router();

router.use(requireAuth);

/** GET /api/folders — 未分类 + 用户自建，含条目数 */
router.get('/', async (req, res, next) => {
  try {
    const folders = await folderService.listFolders(req.auth.userId);
    return res.json({ folders });
  } catch (err) {
    return next(err);
  }
});

/** POST /api/folders — 新建收藏夹 */
router.post('/', async (req, res, next) => {
  try {
    const folder = await folderService.createFolder(
      req.auth.userId,
      req.body?.name,
    );
    return res.status(201).json({
      folder,
      message: '已创建',
    });
  } catch (err) {
    return next(err);
  }
});

/** GET /api/folders/:id/items — 夹内条目 */
router.get('/:id/items', async (req, res, next) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isFinite(id) || id <= 0) {
      return res.status(400).json({ message: '无效的收藏夹 ID' });
    }
    const result = await folderService.listFolderItems(req.auth.userId, id, {
      limit: Number(req.query.limit ?? 50),
      offset: Number(req.query.offset ?? 0),
    });
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

/** DELETE /api/folders/:id — 删除自建夹，条目移回未分类 */
router.delete('/:id', async (req, res, next) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isFinite(id) || id <= 0) {
      return res.status(400).json({ message: '无效的收藏夹 ID' });
    }
    const result = await folderService.deleteFolder(req.auth.userId, id);
    return res.json({
      ...result,
      message: '已删除，夹内条目已移回未分类',
    });
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
