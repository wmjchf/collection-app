const express = require('express');
const cors = require('cors');
const healthRouter = require('./routes/health');
const authRouter = require('./routes/auth');
const itemsRouter = require('./routes/items');
const foldersRouter = require('./routes/folders');
const tagsRouter = require('./routes/tags');
const systemFiltersRouter = require('./routes/systemFilters');
const homeRouter = require('./routes/home');

const app = express();

app.use(cors());
app.use(express.json());

app.get('/', (_req, res) => {
  res.json({ name: 'collection-backend', version: '1.0.0' });
});

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
