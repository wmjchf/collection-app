const express = require('express');
const path = require('path');
const cors = require('cors');
const healthRouter = require('./routes/health');
const authRouter = require('./routes/auth');
const itemsRouter = require('./routes/items');
const foldersRouter = require('./routes/folders');
const tagsRouter = require('./routes/tags');
const systemFiltersRouter = require('./routes/systemFilters');
const homeRouter = require('./routes/home');

const app = express();
const publicDir = path.join(__dirname, '..', 'public');

app.use(cors());
// 客户端上报微信等整页 HTML 可能达数 MB
app.use(express.json({ limit: '8mb' }));

app.use(express.static(publicDir));

app.get('/', (_req, res) => {
  res.sendFile(path.join(publicDir, 'index.html'));
});

/** App Store / 外链用的隐私政策页 */
function sendPrivacy(_req, res) {
  res.sendFile(path.join(publicDir, 'privacy.html'));
}
app.get('/privacy', sendPrivacy);
app.get('/privacy-policy', sendPrivacy);
app.get('/privacy.html', sendPrivacy);

/** App Store Support URL */
function sendSupport(_req, res) {
  res.sendFile(path.join(publicDir, 'support.html'));
}
app.get('/support', sendSupport);
app.get('/support.html', sendSupport);

app.use('/api', healthRouter);
app.use('/api/auth', authRouter);
app.use('/api/items', itemsRouter);
app.use('/api/folders', foldersRouter);
app.use('/api/tags', tagsRouter);
app.use('/api/system-filters', systemFiltersRouter);
app.use('/api/home', homeRouter);

app.use((err, _req, res, _next) => {
  console.error(err);
  const status = err.status || 500;
  res.status(status).json({
    message: err.message || 'Internal Server Error',
  });
});

module.exports = app;
