#!/usr/bin/env node
// manage-keys.js — add/remove keys directly in Postgres

const { Pool } = require('pg');
const [,, cmd, key, type] = process.argv;

if (!process.env.DATABASE_URL) {
  console.error('❌  Please set DATABASE_URL in your environment.');
  process.exit(1);
}

const pool = new Pool({ connectionString: process.env.DATABASE_URL });

async function main() {
  if (cmd === 'add') {
    if (!key || !type) {
      console.error('Usage: manage-keys.js add <KEY> <TYPE>');
      process.exit(1);
    }
    await pool.query(
      `INSERT INTO keys (key_text, type) VALUES ($1,$2) ON CONFLICT DO NOTHING`,
      [key, type]
    );
    console.log(`✅ Added key: ${key} (type=${type})`);
  }
  else if (cmd === 'remove') {
    if (!key) {
      console.error('Usage: manage-keys.js remove <KEY>');
      process.exit(1);
    }
    await pool.query(`DELETE FROM keys WHERE key_text=$1`, [key]);
    console.log(`🗑️  Removed key: ${key}`);
  }
  else {
    console.error('Commands: add, remove');
    process.exit(1);
  }
  await pool.end();
}

main().catch(err => {
  console.error('DB error:', err);
  process.exit(1);
});
