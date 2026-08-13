const authService = require('../services/authService');

function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const [, token] = header.split(' ');
  if (!token) {
    return res.status(401).json({ message: '未登录' });
  }
  try {
    const payload = authService.verifyAccessToken(token);
    req.auth = { userId: payload.sub, phone: payload.phone };
    return next();
  } catch (_err) {
    return res.status(401).json({ message: '登录已失效' });
  }
}

module.exports = { requireAuth };
