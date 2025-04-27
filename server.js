// server.js

const express = require('express');
const Airtable = require('airtable');
const app = express();
const PORT = process.env.PORT || 3000;

// — Configure Airtable —
const AIRTABLE_PAT = 'YOUR_AIRTABLE_PAT_HERE';
const BASE_ID      = 'app3OoIsiIPxQp3fR';   // your Base ID
const TABLE_NAME   = 'Keys';

Airtable.configure({ apiKey: AIRTABLE_PAT });
const base = Airtable.base(BASE_ID);

app.use(express.json());

// Durations in milliseconds
const durations = {
  "24h": 24 * 60 * 60 * 1000,
  "7d":  7  * 24 * 60 * 60 * 1000,
  "30d": 30 * 24 * 60 * 60 * 1000
};

// Helper to find one record by key
async function findRecordByKey(key) {
  const records = await base(TABLE_NAME)
    .select({ filterByFormula: `{Key}='${key}'`, maxRecords: 1 })
    .firstPage();
  return records[0] || null;
}

// ─── Verify endpoint ─────────────────────────────────────────
app.post('/verify', async (req, res) => {
  const { key, deviceId } = req.body;
  if (!key || !deviceId) {
    return res.status(400).json({ status: 'error', message: 'Key or deviceId missing' });
  }

  try {
    const record = await findRecordByKey(key);
    if (!record) {
      return res.json({ status: 'invalid' });
    }

    const f = record.fields;
    const now = Date.now();

    // First activation: bind key to this device
    if (!f['Device ID']) {
      const expiresAt = now + (durations[f.Type] || 0);
      await base(TABLE_NAME).update(record.id, {
        'Device ID':    deviceId,
        'Activated At': now,
        'Expires At':   expiresAt,
        'Active':       true
      });
      return res.json({ status: 'valid', expiresAt });
    }

    // Reject if device mismatch
    if (f['Device ID'] !== deviceId) {
      return res.json({ status: 'invalid' });
    }

    // Expiration check
    if (now > f['Expires At']) {
      return res.json({ status: 'expired' });
    }

    // Still good
    return res.json({ status: 'valid', expiresAt: f['Expires At'] });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ status: 'error', message: 'Server error' });
  }
});

// ─── Issue a new key ─────────────────────────────────────────
app.post('/keys', async (req, res) => {
  const { key, type } = req.body;
  if (!key || !type || !durations[type]) {
    return res.status(400).json({ status: 'error', message: 'Key or type missing/invalid' });
  }
  try {
    if (await findRecordByKey(key)) {
      return res.status(409).json({ status: 'error', message: 'Key already exists' });
    }
    const created = await base(TABLE_NAME).create({
      'Key':          key,
      'Type':         type,
      'Device ID':    null,
      'Activated At': null,
      'Expires At':   null,
      'Active':       false
    });
    return res.status(201).json({ status: 'ok', added: created.fields });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ status: 'error', message: 'Server error' });
  }
});

// ─── Revoke (delete) a key ──────────────────────────────────
app.delete('/keys/:key', async (req, res) => {
  const { key } = req.params;
  try {
    const record = await findRecordByKey(key);
    if (!record) {
      return res.status(404).json({ status: 'error', message: 'Key not found' });
    }
    await base(TABLE_NAME).destroy(record.id);
    return res.json({ status: 'ok', removed: key });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ status: 'error', message: 'Server error' });
  }
});

app.listen(PORT, () => {
  console.log(`License server running on port ${PORT}`);
});
