const express = require('express');
const cors = require('cors');
const healthRouter = require('./routes/health');
const authRouter = require('./routes/auth');

const app = express();

app.use(cors());
app.use(express.json());

app.get('/', (_req, res) => {
  res.json({ name: 'collection-backend', version: '1.0.0' });
});

app.use('/api', healthRouter);
app.use('/api/auth', authRouter);

app.use((err, _req, res, _next) => {
  console.error(err);
  const status = err.status || 500;
  res.status(status).json({
    message: err.message || 'Internal Server Error',
  });
});

module.exports = app;
