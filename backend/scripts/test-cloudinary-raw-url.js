'use strict';

/**
 * Test rapide des URL signées PDF (raw).
 * Usage :
 *   node scripts/test-cloudinary-raw-url.js "telemedecine/ordonnances/.../fichier.pdf"
 * Ou : TEST_CLOUDINARY_PUBLIC_ID=... node scripts/test-cloudinary-raw-url.js
 */

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const https = require('https');
const {
  isConfigured,
  resolveRawAssetForSigning,
  buildSignedRawUrl,
} = require('../config/cloudinaryConfig');

function fetchStatus(url) {
  return new Promise((resolve, reject) => {
    https
      .get(
        url,
        {
          headers: { 'User-Agent': 'TelemedecineCloudinaryUrlTest/1.0' },
        },
        (res) => {
          res.resume();
          resolve({
            status: res.statusCode,
            xCldError: res.headers['x-cld-error'],
          });
        }
      )
      .on('error', reject);
  });
}

async function main() {
  const publicId =
    process.argv[2] || String(process.env.TEST_CLOUDINARY_PUBLIC_ID || '').trim();
  if (!publicId) {
    console.error(
      'Usage: node scripts/test-cloudinary-raw-url.js <public_id>\nOu définir TEST_CLOUDINARY_PUBLIC_ID.'
    );
    process.exit(1);
  }
  if (!isConfigured) {
    console.error('Cloudinary non configuré (CLOUDINARY_CLOUD_NAME / API_KEY / API_SECRET).');
    process.exit(1);
  }

  const meta = await resolveRawAssetForSigning(publicId, '');
  const pid = meta?.publicId || publicId;
  const ver =
    meta && meta.version > 0 ? String(meta.version) : '';

  console.log('public_id utilisé:', pid);
  if (ver) console.log('version:', ver);

  for (const mode of ['cdn', 'api_download']) {
    const url = buildSignedRawUrl(pid, 600, {
      deliveryMode: mode,
      ...(ver ? { version: ver } : {}),
    });
    if (!url) {
      console.log(`\n[${mode}] URL vide.`);
      continue;
    }
    console.log(`\n--- Mode: ${mode} ---`);
    console.log('URL (tronquée):', url.slice(0, 140) + (url.length > 140 ? '…' : ''));
    try {
      const { status, xCldError } = await fetchStatus(url);
      console.log('GET status:', status);
      if (xCldError) console.log('X-Cld-Error:', String(xCldError).slice(0, 400));
      if (status === 200) console.log('OK — le fichier est accessible avec cette URL.');
    } catch (e) {
      console.error('Erreur réseau:', e.message);
    }
  }

  console.log(
    '\nAstuce : en cas de 401 sur `cdn`, définir CLOUDINARY_RAW_DELIVERY_MODE=api_download dans .env.'
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
