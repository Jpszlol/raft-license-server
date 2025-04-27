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
    const { key } = req.body;

    if (!key) {
        return res.status(400).json({ status: 'error', message: 'Key missing' });
    }

    const license = keys.find(k => k.key === key);

    if (!license) {
        return res.json({ status: 'invalid' });
    }

    const now = Date.now();

    // First time use → activate it
    if (!license.activatedAt) {
        license.activatedAt = now;
        license.expiresAt = now + (durations[license.type] || 0);
        saveKeys();
        return res.json({ status: 'valid', expiresAt: license.expiresAt });
    }

    // Already activated → check if expired
    if (now > license.expiresAt) {
        return res.json({ status: 'expired' });
    }

    res.json({ status: 'valid', expiresAt: license.expiresAt });
});

app.listen(PORT, () => {
    console.log(`License server running on port ${PORT}`);
});