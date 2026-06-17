#!/usr/bin/env node
/**
 * Génère ENCRYPTION_KEY (64 hex) et HMAC_KEY pour backend/.env
 * Usage : node scripts/generate-crypto-keys.js
 */
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const encryptionKey = crypto.randomBytes(32).toString('hex');
const hmacKey = crypto.randomBytes(48).toString('base64url');

console.log('Copiez ces lignes dans backend/.env ET dans Render (Environment) :\n');
console.log(`ENCRYPTION_KEY=${encryptionKey}`);
console.log(`HMAC_KEY=${hmacKey}`);
console.log('\nImportant :');
console.log('- Gardez ces valeurs secrètes et identiques partout (local + Render).');
console.log('- Si vous changez ENCRYPTION_KEY, les données déjà chiffrées en base ne seront plus lisibles.');
console.log('- Après changement de HMAC_KEY, les connexions par email existantes ne fonctionneront plus (emailHash).');

const envPath = path.join(__dirname, '..', '.env');
if (fs.existsSync(envPath)) {
  let content = fs.readFileSync(envPath, 'utf8');
  const encRe = /^ENCRYPTION_KEY=.*$/m;
  const hmacRe = /^HMAC_KEY=.*$/m;
  if (encRe.test(content) && hmacRe.test(content)) {
    content = content
      .replace(encRe, `ENCRYPTION_KEY=${encryptionKey}`)
      .replace(hmacRe, `HMAC_KEY=${hmacKey}`);
    fs.writeFileSync(envPath, content, 'utf8');
    console.log('\n[OK] backend/.env mis à jour automatiquement.');
  } else {
    console.log('\n[INFO] backend/.env trouvé mais ENCRYPTION_KEY/HMAC_KEY introuvables : copie manuelle requise.');
  }
} else {
  console.log('\n[INFO] backend/.env absent : copie manuelle requise.');
}
