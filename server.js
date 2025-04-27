// ADMIN: add a new key
app.post('/admin/add-key', async (req, res) => {
  const { key, type } = req.body;
  if (!key || !type) {
    return res.status(400).json({ error: 'Key and type are required' });
  }
  try {
    await pool.query(
      `INSERT INTO keys(key_text, type)
       VALUES($1, $2)
       ON CONFLICT (key_text) DO NOTHING`,
      [key, type]
    );
    res.json({ status: 'added', key });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Database error' });
  }
});

// ADMIN: revoke (delete) a key
app.post('/admin/revoke-key', async (req, res) => {
  const { key } = req.body;
  if (!key) {
    return res.status(400).json({ error: 'Key is required' });
  }
  try {
    await pool.query(
      `DELETE FROM keys WHERE key_text = $1`,
      [key]
    );
    res.json({ status: 'revoked', key });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Database error' });
  }
});
