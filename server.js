// server.js
const express = require('express');
const { Pool } = require('pg');
const app = express();
const PORT = process.env.PORT || 3000;

// Postgres connection
const pool = new Pool({ connectionString: process.env.DATABASE_URL });

// How long each key type lasts
const durations = {
  "30s": 30 * 1000,
  "24h": 24 * 60 * 60 * 1000,
  "7d": 7 * 24 * 60 * 60 * 1000,
  "30d": 30 * 24 * 60 * 60 * 1000
};

app.use(express.json());

// 1) Verify a key
app.post('/verify', async (req, res) => {
  const { key, deviceId } = req.body;
  if (!key || !deviceId) {
    return res.status(400).json({ status: 'error', message: 'Key and device ID required' });
  }
  const now = Date.now();
  const { rows } = await pool.query('SELECT * FROM keys WHERE key_text=$1', [key]);
  if (rows.length === 0) return res.json({ status: 'invalid' });

  const lic = rows[0];
  // first-time activation
  if (!lic.activated_at) {
    const expiresAt = now + (durations[lic.type] || 0);
    await pool.query(
      `UPDATE keys
         SET activated_at=$1, expires_at=$2, device_id=$3
       WHERE key_text=$4`,
      [now, expiresAt, deviceId, key]
    );
    return res.json({ status: 'valid', expiresAt });
  }
  // wrong device
  if (lic.device_id && lic.device_id !== deviceId) {
    return res.json({ status: 'invalid_device' });
  }
  // expired?
  if (now > lic.expires_at) {
    await pool.query('DELETE FROM keys WHERE key_text=$1', [key]);
    return res.json({ status: 'expired' });
  }
  // still good
  res.json({ status: 'valid', expiresAt: lic.expires_at });
});

// 2) Admin: add a new key
app.post('/admin/add-key', async (req, res) => {
  const { key, type } = req.body;
  if (!key || !type) {
    return res.status(400).json({ error: 'Key and type required' });
  }
  try {
    await pool.query(
      `INSERT INTO keys(key_text, type)
       VALUES($1,$2)
       ON CONFLICT DO NOTHING`,
      [key, type]
    );
    res.json({ status: 'added', key });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'DB error' });
  }
});

// 3) Admin: revoke (delete) a key
app.post('/admin/revoke-key', async (req, res) => {
  const { key } = req.body;
  if (!key) {
    return res.status(400).json({ error: 'Key required' });
  }
  try {
    await pool.query('DELETE FROM keys WHERE key_text=$1', [key]);
    res.json({ status: 'revoked', key });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'DB error' });
  }
});

// start listening
app.listen(PORT, () => {
  console.log(`✅ License server running on port ${PORT}`);
});
