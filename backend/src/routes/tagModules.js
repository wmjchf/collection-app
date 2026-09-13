const express = require('express');
const { requireAuth } = require('../middleware/auth');
const tagModuleService = require('../services/tagModuleService');
const aiOrganizeService = require('../services/aiOrganizeService');

const router = express.Router();

router.use(requireAuth);

/** GET /api/tag-modules — 模块（含标签）+ 未归类 */
router.get('/', async (req, res, next) => {
  try {
    const result = await tagModuleService.listModules(req.auth.userId);
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

/** POST /api/tag-modules/ai-organize — AI 归类建议（同步，不落库） */
router.post('/ai-organize', async (req, res, next) => {
  try {
    const result = await aiOrganizeService.suggestOrganize(req.auth.userId, {
      hint: req.body?.hint,
    });
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

/** POST /api/tag-modules/ai-organize/apply — 应用归类方案 */
router.post('/ai-organize/apply', async (req, res, next) => {
  try {
    const result = await aiOrganizeService.applyOrganize(
      req.auth.userId,
      req.body || {},
    );
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

/** POST /api/tag-modules — 新建模块（仅标题） */
router.post('/', async (req, res, next) => {
  try {
    const module = await tagModuleService.createModule(
      req.auth.userId,
      req.body?.name,
    );
    return res.status(201).json({
      module,
      message: '已创建',
    });
  } catch (err) {
    return next(err);
  }
});

/** DELETE /api/tag-modules/:id — 删除模块（标签回未归类） */
router.delete('/:id', async (req, res, next) => {
  try {
    await tagModuleService.deleteModule(req.auth.userId, req.params.id);
    return res.json({ message: '已删除模块' });
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
