const crypto = require('crypto');

const PLACEHOLDER_ENCRYPTION_KEYS = new Set([
  '',
  'replace-with-64-hex-characters',
  'changeme',
  'change-me',
]);

const PLACEHOLDER_HMAC_KEYS = new Set([
  '',
  'replace-with-strong-hmac-secret',
  'changeme',
  'change-me',
]);

function assertCryptoEnv() {
  const encRaw = String(process.env.ENCRYPTION_KEY || '').trim();
  const hmacRaw = String(process.env.HMAC_KEY || '').trim();

  if (PLACEHOLDER_ENCRYPTION_KEYS.has(encRaw.toLowerCase())) {
    throw new Error(
      'ENCRYPTION_KEY est encore un placeholder. Générez une clé hex de 64 caractères (32 bytes), par ex. : node scripts/generate-crypto-keys.js',
    );
  }
  if (!/^[0-9a-fA-F]{64}$/.test(encRaw)) {
    throw new Error(
      'ENCRYPTION_KEY invalide : exactement 64 caractères hexadécimaux requis (32 bytes).',
    );
  }
  if (PLACEHOLDER_HMAC_KEYS.has(hmacRaw.toLowerCase())) {
    throw new Error(
      'HMAC_KEY est encore un placeholder. Générez un secret fort, par ex. : node scripts/generate-crypto-keys.js',
    );
  }
  if (hmacRaw.length < 32) {
    throw new Error('HMAC_KEY trop courte : utilisez au moins 32 caractères.');
  }
}

let _cachedEncryptionKey = null;
let _decryptFailCount = 0;
let _decryptFailSummaryLogged = false;

function logDecryptFailure(msg) {
  _decryptFailCount += 1;
  if (process.env.DEBUG_CRYPTO === '1') {
    console.warn('[CRYPTO] Échec déchiffrement:', msg);
    return;
  }
  if (!_decryptFailSummaryLogged) {
    _decryptFailSummaryLogged = true;
    console.warn(
      '[CRYPTO] Échec déchiffrement — la clé ENCRYPTION_KEY ne correspond probablement pas aux données en base, ou le champ est corrompu.',
      msg,
      '(Les prochains échecs sont masqués ; définissez DEBUG_CRYPTO=1 pour tout voir.)',
    );
  }
}

function getEncryptionKey() {
  if (_cachedEncryptionKey) return _cachedEncryptionKey;
  const raw = String(process.env.ENCRYPTION_KEY || '').trim().toLowerCase();
  if (!/^[0-9a-f]{64}$/.test(raw)) {
    throw new Error('ENCRYPTION_KEY invalide: clé hex de 32 bytes requise.');
  }
  const key = Buffer.from(raw, 'hex');
  if (key.length !== 32) {
    throw new Error('ENCRYPTION_KEY invalide: clé hex de 32 bytes requise.');
  }
  _cachedEncryptionKey = key;
  return key;
}

/** À appeler au démarrage après assertCryptoEnv pour figer la clé en mémoire. */
function warmEncryptionKey() {
  getEncryptionKey();
}

/** Vérifie que la clé courante chiffre/déchiffre correctement. */
function verifyEncryptionRoundTrip() {
  const sample = encrypt('__headsapp_crypto_probe__');
  const out = decrypt(sample);
  if (out !== '__headsapp_crypto_probe__') {
    throw new Error('Round-trip chiffrement échoué avec ENCRYPTION_KEY actuelle.');
  }
}

function getHmacKey() {
  const raw = String(process.env.HMAC_KEY || '').trim();
  if (!raw) {
    throw new Error('HMAC_KEY manquante.');
  }
  return raw;
}

/** Détecte un payload AES-256-GCM sérialisé `iv:authTag:cipher` (hex). */
function isEncryptedPayload(value) {
  if (value == null) return false;
  const raw = String(value).trim();
  if (!raw) return false;
  const parts = raw.split(':');
  if (parts.length !== 3) return false;
  const hex = /^[0-9a-fA-F]+$/;
  const [ivHex, authTagHex, encryptedHex] = parts;
  if (!hex.test(ivHex) || !hex.test(authTagHex) || !hex.test(encryptedHex)) {
    return false;
  }
  // AES-256-GCM : IV 12 octets, authTag 16 octets.
  if (ivHex.length !== 24 || authTagHex.length !== 32) return false;
  if (encryptedHex.length < 2 || encryptedHex.length % 2 !== 0) return false;
  return true;
}

function encrypt(text) {
  if (text == null) return null;
  const plain = String(text);
  if (isEncryptedPayload(plain)) return plain;
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', getEncryptionKey(), iv);
  const encrypted = Buffer.concat([cipher.update(plain, 'utf8'), cipher.final()]);
  const authTag = cipher.getAuthTag();
  return `${iv.toString('hex')}:${authTag.toString('hex')}:${encrypted.toString('hex')}`;
}

function decrypt(payload) {
  if (payload == null) return '';
  const raw = String(payload);
  if (!isEncryptedPayload(raw)) {
    return raw;
  }
  const [ivHex, authTagHex, encryptedHex] = raw.split(':');
  try {
    const iv = Buffer.from(ivHex, 'hex');
    const authTag = Buffer.from(authTagHex, 'hex');
    const encrypted = Buffer.from(encryptedHex, 'hex');
    const decipher = crypto.createDecipheriv('aes-256-gcm', getEncryptionKey(), iv);
    decipher.setAuthTag(authTag);
    const decrypted = Buffer.concat([decipher.update(encrypted), decipher.final()]);
    return decrypted.toString('utf8');
  } catch (err) {
    const msg = String(err?.message || err);
    if (msg.includes('ENCRYPTION_KEY')) {
      console.warn('[CRYPTO] Configuration chiffrement:', msg);
    } else {
      logDecryptFailure(msg);
    }
    return '';
  }
}

/** Déchiffre un champ texte pour l'API : jamais `null` en sortie. */
function decryptField(payload, fallback = '') {
  const value = decrypt(payload);
  if (value == null || value === '') return fallback;
  return value;
}

function hashEmail(email) {
  const normalized = String(email || '').trim().toLowerCase();
  return crypto.createHmac('sha256', getHmacKey()).update(normalized).digest('hex');
}

function decryptPatient(p) {
  if (!p) return null;
  return {
    id: p._id,
    fullName: decryptField(p.fullName),
    email: decryptField(p.email),
    country: decryptField(p.country),
    addressExact: decryptField(p.addressExact),
    phone: decryptField(p.phone),
    knownAllergies: p.knownAllergies ? decryptField(p.knownAllergies) : null,
    createdAt: p.createdAt,
    updatedAt: p.updatedAt,
    role: p.role,
  };
}

function decryptDoctor(d) {
  if (!d) return null;
  return {
    id: d._id,
    fullName: decryptField(d.fullName),
    specialty: decryptField(d.specialty),
    governorate: decryptField(d.governorate),
    address: decryptField(d.address),
    email: decryptField(d.email),
    phone: decryptField(d.phone),
    orderNumber: d.orderNumber || null,
    country: decryptField(d.country),
    verificationStatus: d.verificationStatus || 'pending',
    createdAt: d.createdAt,
    updatedAt: d.updatedAt,
    role: d.role,
  };
}

module.exports = {
  encrypt,
  decrypt,
  decryptField,
  isEncryptedPayload,
  assertCryptoEnv,
  warmEncryptionKey,
  verifyEncryptionRoundTrip,
  hashEmail,
  decryptPatient,
  decryptDoctor,
};
