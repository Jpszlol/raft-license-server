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

  if (!key || !deviceId) {
    return res.status(400).json({ status: 'error', message: 'Key or device ID missing' });
  }

  const licenseIndex = keys.findIndex(k => k.key === key);
  if (licenseIndex === -1) {
    return res.json({ status: 'invalid' });
  }

  const license = keys[licenseIndex];
  const now = Date.now();

  // First-time activation: bind to this device
  if (!license.activatedAt) {
    license.activatedAt = now;
    license.expiresAt = now + (durations[license.type] || 0);
    license.deviceId = deviceId;
    saveKeys();
    console.log(`🔑 Activated key '${key}' for device '${deviceId}'`);
    return res.json({ status: 'valid', expiresAt: license.expiresAt });
  }

  // Reject if different device
  if (license.deviceId && license.deviceId !== deviceId) {
    console.log(`❌ Device mismatch for key '${key}'. Expected '${license.deviceId}', got '${deviceId}'`);
    return res.json({ status: 'invalid_device' });
  }

  // Check expiration
  if (now > license.expiresAt) {
    console.log(`🗑️ Deleting expired key '${key}'`);
    keys.splice(licenseIndex, 1);   // Delete the expired key
    saveKeys();                     // Save updated list
    return res.json({ status: 'expired' });
  }

  // All good
  res.json({ status: 'valid', expiresAt: license.expiresAt });
});

// ✅ DOWNLOAD CURRENT KEYS (admin tool)
app.get('/download-keys', (req, res) => {
  res.json(keys);
});

app.listen(PORT, () => {
  console.log(`✅ License server running on port ${PORT}`);
});
