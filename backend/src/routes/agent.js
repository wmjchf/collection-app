const express = require('express');
const { requireAuth } = require('../middleware/auth');
const conversationService = require('../services/agent/agentConversationService');
const orchestrator = require('../services/agent/agentOrchestrator');

const router = express.Router();
router.use(requireAuth);

/** POST /api/agent/conversations */
router.post('/conversations', async (req, res, next) => {
  try {
    const conv = await conversationService.createConversation(req.auth.userId, {
      title: req.body?.title,
    });
    return res.status(201).json(conv);
  } catch (err) {
    return next(err);
  }
});

/** GET /api/agent/conversations */
router.get('/conversations', async (req, res, next) => {
  try {
    const result = await conversationService.listConversations(req.auth.userId, {
      limit: req.query.limit,
      cursor: req.query.cursor,
    });
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

/** GET /api/agent/conversations/:id */
router.get('/conversations/:id', async (req, res, next) => {
  try {
    const id = Number(req.params.id);
    const result = await conversationService.listMessages(req.auth.userId, id);
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

/** DELETE /api/agent/conversations/:id — 归档 */
router.delete('/conversations/:id', async (req, res, next) => {
  try {
    const id = Number(req.params.id);
    const result = await conversationService.archiveConversation(
      req.auth.userId,
      id,
    );
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

/**
 * POST /api/agent/conversations/:id/messages
 * body: { content, clientMessageId? }
 */
router.post('/conversations/:id/messages', async (req, res, next) => {
  try {
    const id = Number(req.params.id);
    const result = await orchestrator.runUserTurn({
      userId: req.auth.userId,
      conversationId: id,
      content: req.body?.content,
      clientMessageId: req.body?.clientMessageId,
    });
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
