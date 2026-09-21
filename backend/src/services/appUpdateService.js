const { pool } = require('../db');

const KEY = 'app_update';

const EMPTY = {
  latestVersion: '',
  releaseNotes: '',
  iosStoreUrl: '',
  androidStoreUrl: '',
};

function normalize(raw) {
  const src = raw && typeof raw === 'object' ? raw : {};
  return {
    latestVersion: String(src.latestVersion || '').trim(),
    releaseNotes: String(src.releaseNotes || '').trim(),
    iosStoreUrl: String(src.iosStoreUrl || '').trim(),
    androidStoreUrl: String(src.androidStoreUrl || '').trim(),
  };
}

function parseStored(value) {
  if (value == null) return { ...EMPTY };
  if (typeof value === 'object') return normalize(value);
  if (typeof value === 'string') {
    try {
      return normalize(JSON.parse(value));
    } catch (_) {
      return { ...EMPTY };
    }
  }
  return { ...EMPTY };
}

async function getConfig() {
  const [rows] = await pool.execute(
    `SELECT setting_value, updated_at
     FROM app_settings
     WHERE setting_key = :key
     LIMIT 1`,
    { key: KEY },
  );
  if (!rows[0]) {
    return { ...EMPTY, updatedAt: null };
  }
  const cfg = parseStored(rows[0].setting_value);
  return {
    ...cfg,
    updatedAt: rows[0].updated_at
      ? new Date(rows[0].updated_at).toISOString()
      : null,
  };
}

async function updateConfig(payload) {
  const next = normalize(payload);
  await pool.execute(
    `INSERT INTO app_settings (setting_key, setting_value)
     VALUES (:key, CAST(:value AS JSON))
     ON DUPLICATE KEY UPDATE setting_value = CAST(:value AS JSON)`,
    { key: KEY, value: JSON.stringify(next) },
  );
  return getConfig();
}

module.exports = {
  getConfig,
  updateConfig,
  normalize,
};
