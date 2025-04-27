// server.js
const express = require('express');
const { Pool } = require('pg');
const app = express();
const PORT = process.env.PORT || 3000;

// Initialize PostgreSQL pool from DATABASE_URL
const pool = new Pool({ connectionString: process.env.DATABASE_URL });

// Duration lookup table
const durations = {
  "30s": 30 * 1000,            // 🧪 Test key: 30 seconds
  "24h": 24 * 60 * 60 * 1000,  // ✅ Real 24 hours
  "7d": 7 * 24 * 60 * 60 * 1000,
  "30d": 30 * 24 * 60 * 60 * 1000
};

app.use(express.json());

// VERIFY LICENSE
app.post('/verify', async (req, res) => {
  const { key, deviceId } = req.body;
  if (!key || !deviceId) {
    return res.status(400).json({ status: 'error', message: 'Key or device ID missing' });
  }

  // 1) Look up the key
  const { rows } = await pool.query(
    'SELECT * FROM keys WHERE key_text = $1',
    [key]
  );
  if (rows.length === 0) {
    return res.json({ status: 'invalid' });
  }
  const lic = rows[0];
  const now = Date.now();

  // 2) First-time activation
  if (!lic.activated_at) {
    const expiresAt = now + (durations[lic.type] || 0);
    await pool.query(
      `UPDATE keys
         SET activated_at=$1, expires_at=$2, device_id=$3
       WHERE key_text=$4`,
      [now, expiresAt, deviceId, key]
    );
    console.log(`🔑 Activated key '${key}' for device '${deviceId}'`);
    return res.json({ status: 'valid', expiresAt });
  }

  // 3) Device mismatch
  if (lic.device_id && lic.device_id !== deviceId) {
    console.log(`❌ Device mismatch for key '${key}'`);
    return res.json({ status: 'invalid_device' });
  }

  // 4) Expiration check
  if (now > lic.expires_at) {
    console.log(`🗑️ Deleting expired key '${key}'`);
    await pool.query('DELETE FROM keys WHERE key_text=$1', [key]);
    return res.json({ status: 'expired' });
  }

  // 5) Still valid
  res.json({ status: 'valid', expiresAt: lic.expires_at });
});

// ADMIN: download & purge
app.get('/download-keys', async (req, res) => {
  const now = Date.now();
  // Remove expired entries
  await pool.query(
    'DELETE FROM keys WHERE expires_at IS NOT NULL AND expires_at < $1',
    [now]
  );
  // Return all remaining keys
  const { rows } = await pool.query(
    `SELECT
       key_text   AS key,
       type,
       activated_at   AS "activatedAt",
       expires_at     AS "expiresAt",
       device_id      AS "deviceId"
     FROM keys`
  );
  res.json(rows);
});

app.listen(PORT, () => {
  console.log(`✅ License server running with Postgres on port ${PORT}`);
});
