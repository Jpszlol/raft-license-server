const express = require('express');
const fs = require('fs');
const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());

// Load keys
let keys = JSON.parse(fs.readFileSync('keys.json'));

// Duration lookup table
const durations = {
  "24h": 24 * 60 * 60 * 1000,
  "7d": 7 * 24 * 60 * 60 * 1000,
  "30d": 30 * 24 * 60 * 60 * 1000
};

// Save updated keys back to file
function saveKeys() {
  fs.writeFileSync('keys.json', JSON.stringify(keys, null, 2));
}

// Verify license
app.post('/verify', (req, res) => {
  const { key, deviceId } = req.body;

  // must have both
  if (!key || !deviceId) {
    return res.status(400).json({ status: 'error', message: 'Key or device ID missing' });
  }

  const license = keys.find(k => k.key === key);
  if (!license) {
    return res.json({ status: 'invalid' });
  }

  const now = Date.now();

  // First-time activation: bind to this device
  if (!license.activatedAt) {
    license.activatedAt = now;
    license.expiresAt  = now + (durations[license.type] || 0);
    license.deviceId  = deviceId;
    saveKeys();
    return res.json({ status: 'valid', expiresAt: license.expiresAt });
  }

  // Reject if different device
  if (license.deviceId && license.deviceId !== deviceId) {
    return res.json({ status: 'invalid_device' });
  }

  // Check expiration
  if (now > license.expiresAt) {
    return res.json({ status: 'expired' });
  }

  // All good
  res.json({ status: 'valid', expiresAt: license.expiresAt });
});

app.listen(PORT, () => {
  console.log(`License server running on port ${PORT}`);
});
