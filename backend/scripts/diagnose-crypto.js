#!/usr/bin/env node
/**
 * Diagnostic chiffrement — stats uniquement, aucune donnée déchiffrée affichée.
 * Usage : node scripts/diagnose-crypto.js
 */
require('dotenv').config();
const mongoose = require('mongoose');
const { decrypt, isEncryptedPayload } = require('../services/cryptoService');

const SENSITIVE_FIELDS = [
  'fullName',
  'email',
  'phone',
  'specialty',
  'governorate',
  'address',
  'addressExact',
  'country',
  'knownAllergies',
];

function classify(value) {
  if (value == null || String(value).trim() === '') return 'empty';
  if (!isEncryptedPayload(value)) return 'plaintext';
  const out = decrypt(value);
  if (out && out !== '') return 'decrypted_ok';
  return 'decrypt_failed';
}

async function scanCollection(db, name) {
  const stats = { empty: 0, plaintext: 0, decrypted_ok: 0, decrypt_failed: 0 };
  const docs = await db.collection(name).find({}).limit(200).toArray();
  for (const doc of docs) {
    for (const field of SENSITIVE_FIELDS) {
      if (!(field in doc)) continue;
      stats[classify(doc[field])] += 1;
    }
  }
  return { name, docCount: docs.length, stats };
}

(async () => {
  const enc = String(process.env.ENCRYPTION_KEY || '').trim();
  console.log('ENCRYPTION_KEY:', enc ? `${enc.slice(0, 8)}…${enc.slice(-4)} (${enc.length} chars)` : 'MISSING');
  console.log('HMAC_KEY:', process.env.HMAC_KEY ? 'set' : 'MISSING');

  await mongoose.connect(process.env.MONGODB_URI);
  const db = mongoose.connection.db;

  for (const coll of ['doctors', 'patients']) {
    const { name, docCount, stats } = await scanCollection(db, coll);
    console.log(`\n[${name}] docs sampled: ${docCount}`);
    console.log(JSON.stringify(stats, null, 2));
  }

  await mongoose.disconnect();
  process.exit(0);
})().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
