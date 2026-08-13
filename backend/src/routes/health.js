const { Router } = require('express');
const { ping } = require('../db');

const router = Router();

router.get('/health', async (_req, res) => {
  try {
    await ping();
    res.json({ ok: true, db: 'up' });
  } catch (err) {
    res.status(503).json({
      ok: false,
      db: 'down',
      message: err.message,
    });
  }
});

module.exports = router;
