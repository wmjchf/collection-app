const express = require('express');
const { requireAuth } = require('../middleware/auth');
const conversationService = require('../services/agent/agentConversationService');
const orchestrator = require('../services/agent/agentOrchestrator');
const agentPresetService = require('../services/agent/agentPresetService');

const router = express.Router();
router.use(requireAuth);

/** POST /api/agent/conversations */
router.post('/conversations', async (req, res, next) => {
  try {
    const conv = await conversationService.createConversation(req.auth.userId, {
      title: req.body?.title,
      focusItemId: req.body?.focusItemId,
    });
    return res.status(201).json(conv);
  } catch (err) {
    return next(err);
  }
});

/**
 * POST /api/agent/conversations/ensure
 * body: { focusItemId?: number } — 无则全局会话；有则该篇专属会话
 */
router.post('/conversations/ensure', async (req, res, next) => {
  try {
    const conv = await conversationService.ensureConversation(req.auth.userId, {
      focusItemId: req.body?.focusItemId,
      title: req.body?.title,
    });
    return res.json(conv);
  } catch (err) {
    return next(err);
  }
});

/** GET /api/agent/conversations */
router.get('/conversations', async (req, res, next) => {
  try {
    const globalOnly =
      req.query.global === '1' ||
      req.query.global === 'true' ||
      req.query.scope === 'global';
    const result = await conversationService.listConversations(req.auth.userId, {
      limit: req.query.limit,
      cursor: req.query.cursor,
      focusItemId: req.query.focusItemId,
      globalOnly,
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
 * body: { content, clientMessageId?, focusItemId? }
 * Accept: text/event-stream → SSE（thinking / phase / token / done / error）
 */
router.post('/conversations/:id/messages', async (req, res, next) => {
  const id = Number(req.params.id);
  const wantStream = String(req.headers.accept || '').includes(
    'text/event-stream',
  );
  const focusItemId =
    req.body?.focusItemId != null ? Number(req.body.focusItemId) : null;

  if (!wantStream) {
    try {
      const result = await orchestrator.runUserTurn({
        userId: req.auth.userId,
        conversationId: id,
        content: req.body?.content,
        clientMessageId: req.body?.clientMessageId,
        focusItemId,
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
      focusItemId,
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
        if (ev.type === 'thinking') {
          send('thinking', {
            delta: ev.delta || '',
            ...(ev.text ? { text: ev.text } : {}),
          });
          return;
        }
        if (ev.type === 'phase') {
          send('phase', {
            phase: ev.phase,
            ...(ev.detail ? { detail: ev.detail } : {}),
            ...(Array.isArray(ev.trail) && ev.trail.length
              ? { trail: ev.trail }
              : {}),
          });
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

/**
 * POST /api/agent/conversations/:id/presets
 * body: { focusItemId?, lastAssistantContent?, hasPendingAction? }
 * 动态口语预设；不计用户 AI 额度（仍需太子+）
 */
router.post('/conversations/:id/presets', async (req, res, next) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isFinite(id) || id <= 0) {
      return res.status(400).json({ message: '无效的会话' });
    }
    const focusItemId =
      req.body?.focusItemId != null ? Number(req.body.focusItemId) : null;
    const result = await agentPresetService.suggestPresets({
      userId: req.auth.userId,
      conversationId: id,
      focusItemId,
      lastAssistantContent: req.body?.lastAssistantContent,
      hasPendingAction: Boolean(req.body?.hasPendingAction),
    });
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

/**
 * POST /api/agent/actions/confirm
 * MVP 未接入改标/归类确认
 */
router.post('/actions/confirm', async (_req, res) => {
  return res.status(410).json({
    message: '当前助手版本暂不支持确认条操作',
    code: 'agent_action_unavailable',
  });
});

/**
 * POST /api/agent/actions/settle-transcript
 * body: { conversationId, messageId, status, content? }
 * App 在确认后本地提交 ASR / 轮询结束后写回 pendingAction，避免重进页重复弹确认。
 */
router.post('/actions/settle-transcript', async (req, res, next) => {
  try {
    const userId = req.auth.userId;
    const conversationId = Number(req.body?.conversationId);
    const messageId = Number(req.body?.messageId);
    const status = String(req.body?.status || '').trim();
    const content =
      req.body?.content != null ? String(req.body.content) : null;

    if (
      !Number.isFinite(conversationId) ||
      conversationId <= 0 ||
      !Number.isFinite(messageId) ||
      messageId <= 0
    ) {
      return res.status(400).json({ message: '参数无效' });
    }

    const allowed = new Set([
      'pending',
      'running',
      'success',
      'failed',
      'cancelled',
    ]);
    if (!allowed.has(status)) {
      return res.status(400).json({ message: 'status 无效' });
    }

    const msg = await conversationService.getMessageForUser(
      userId,
      conversationId,
      messageId,
    );
    if (!msg) {
      return res.status(404).json({ message: '消息不存在' });
    }

    const pa = msg.pendingAction;
    if (!pa || pa.type !== 'start_transcript') {
      return res.json({ ok: true, alreadySettled: true });
    }

    await conversationService.patchMessageToolPayload(messageId, {
      pendingAction: { ...pa, status },
    });
    if (content != null) {
      await conversationService.updateMessageContent(messageId, content);
    }

    return res.json({ ok: true });
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
