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
 * Accept: text/event-stream → SSE（phase / token / done / error）
 */
router.post('/conversations/:id/messages', async (req, res, next) => {
  const id = Number(req.params.id);
  const wantStream = String(req.headers.accept || '').includes(
    'text/event-stream',
  );

  if (!wantStream) {
    try {
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
  }

  res.status(200);
  res.setHeader('Content-Type', 'text/event-stream; charset=utf-8');
  res.setHeader('Cache-Control', 'no-cache, no-transform');
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('X-Accel-Buffering', 'no');
  if (typeof res.flushHeaders === 'function') res.flushHeaders();

  const send = (event, data) => {
    if (res.writableEnded) return;
    res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
  };

  try {
    await orchestrator.runUserTurn({
      userId: req.auth.userId,
      conversationId: id,
      content: req.body?.content,
      clientMessageId: req.body?.clientMessageId,
      stream: true,
      onEvent: (ev) => {
        if (!ev || !ev.type) return;
        if (ev.type === 'done') {
          send('done', {
            userMessage: ev.userMessage,
            assistantMessage: ev.assistantMessage,
            usage: ev.usage,
          });
          return;
        }
        if (ev.type === 'token') {
          send('token', { text: ev.text || '' });
          return;
        }
        if (ev.type === 'phase') {
          send('phase', { phase: ev.phase });
          return;
        }
        if (ev.type === 'user') {
          send('user', { message: ev.message });
        }
      },
    });
    if (!res.writableEnded) res.end();
  } catch (err) {
    send('error', {
      message: err?.message || '助手出错了',
      status: err?.status || 500,
      code: err?.code,
    });
    if (!res.writableEnded) res.end();
  }
});

module.exports = router;
