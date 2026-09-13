const express = require('express');
const { requireAuth } = require('../middleware/auth');
const tagModuleService = require('../services/tagModuleService');

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

module.exports = router;
