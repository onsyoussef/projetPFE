'use strict';

const https = require('https');

/**
 * Force HTTPS pour les livraisons Cloudinary (le proxy refuse http:).
 */
function normalizeCloudinaryDeliveryUrl(urlStr) {
  if (!urlStr || typeof urlStr !== 'string') return urlStr;
  const t = urlStr.trim();
  if (t.startsWith('http://res.cloudinary.com')) {
    return 'https://' + t.slice('http://'.length);
  }
  return t;
}

function isTrustedCloudinaryDeliveryUrl(urlStr) {
  if (!urlStr || typeof urlStr !== 'string') return false;
  const normalized = normalizeCloudinaryDeliveryUrl(urlStr);
  const cloud = process.env.CLOUDINARY_CLOUD_NAME;
  try {
    const u = new URL(normalized);
    if (u.hostname !== 'res.cloudinary.com') return false;
    const parts = u.pathname.split('/').filter(Boolean);
    if (parts.length < 3) return false;
    const first = parts[0];
    if (cloud && String(cloud).trim()) {
      return first.toLowerCase() === String(cloud).trim().toLowerCase();
    }
    return /^(image|video|raw)$/.test(parts[1]);
  } catch {
    return false;
  }
}

/**
 * URL signée vers l’endpoint API `…/raw/download` (private_download_url), pas le CDN.
 */
function isTrustedCloudinaryApiDownloadUrl(urlStr) {
  if (!urlStr || typeof urlStr !== 'string') return false;
  const cloud = String(process.env.CLOUDINARY_CLOUD_NAME || '').trim();
  if (!cloud) return false;
  try {
    const u = new URL(normalizeCloudinaryDeliveryUrl(urlStr));
    if (u.hostname !== 'api.cloudinary.com') return false;
    const prefix = `/v1_1/${encodeURIComponent(cloud)}/`;
    return u.pathname.startsWith(prefix) && u.pathname.includes('/download');
  } catch {
    return false;
  }
}

function isTrustedCloudinaryUpstreamUrl(urlStr) {
  return (
    isTrustedCloudinaryDeliveryUrl(urlStr) || isTrustedCloudinaryApiDownloadUrl(urlStr)
  );
}

/** Si la livraison `fl_inline` échoue (404), retenter sans ce flag. */
function stripFlInlineFromCloudinaryUrl(urlStr) {
  if (!urlStr || typeof urlStr !== 'string') return urlStr;
  return urlStr
    .replace('/raw/upload/fl_inline/', '/raw/upload/')
    .replace('/video/upload/fl_inline/', '/video/upload/');
}

/**
 * Relaie un fichier HTTPS (Cloudinary) vers le client avec Content-Disposition contrôlée.
 * @param {'inline'|'attachment'} [options.disposition='inline']
 * @param {boolean} [options.skipUpstreamTrustCheck=false] — après contrôle d’accès métier (ex. ordonnance en base).
 * @param {(result:{ok:boolean,statusCode?:number,reason?:string}) => void} [options.onFinished]
 */
function streamHttpsUrlToClient(
  targetUrl,
  res,
  { filename, mimetype, disposition = 'inline', skipUpstreamTrustCheck = false, onFinished } = {},
  depth = 0
) {
  const manualErrorHandling = typeof onFinished === 'function';
  const finish = (result) => {
    if (typeof onFinished === 'function') onFinished(result);
  };
  if (depth > 5) {
    if (!res.headersSent) res.status(502).json({ message: 'Trop de redirections.' });
    finish({ ok: false, statusCode: 502, reason: 'too_many_redirects' });
    return;
  }
  const normalizedTarget = normalizeCloudinaryDeliveryUrl(targetUrl);
  if (!skipUpstreamTrustCheck && !isTrustedCloudinaryUpstreamUrl(normalizedTarget)) {
    if (!res.headersSent) {
      res
        .status(400)
        .set('Content-Type', 'text/plain; charset=utf-8')
        .send('URL de fichier non autorisée (Cloudinary attendu).');
    }
    finish({ ok: false, statusCode: 400, reason: 'untrusted_upstream' });
    return;
  }
  let u;
  try {
    u = new URL(normalizedTarget);
  } catch {
    if (!res.headersSent) {
      res.status(400).set('Content-Type', 'text/plain; charset=utf-8').send('URL invalide.');
    }
    finish({ ok: false, statusCode: 400, reason: 'invalid_url' });
    return;
  }
  if (u.protocol !== 'https:') {
    if (!res.headersSent) {
      res.status(400).set('Content-Type', 'text/plain; charset=utf-8').send('HTTPS requis.');
    }
    finish({ ok: false, statusCode: 400, reason: 'https_required' });
    return;
  }
  const opts = {
    hostname: u.hostname,
    path: u.pathname + u.search,
    method: 'GET',
    headers: { 'User-Agent': 'TelemedecineBackend/1.0' },
  };
  const reqOut = https.request(opts, (upstream) => {
    if (upstream.statusCode >= 300 && upstream.statusCode < 400 && upstream.headers.location) {
      upstream.resume();
      const next = normalizeCloudinaryDeliveryUrl(new URL(upstream.headers.location, normalizedTarget).href);
      streamHttpsUrlToClient(
        next,
        res,
        { filename, mimetype, disposition, skipUpstreamTrustCheck, onFinished },
        depth + 1
      );
      return;
    }
    if (upstream.statusCode !== 200) {
      const cldErr = upstream.headers['x-cld-error'];
      console.error(
        '[STREAM][CLOUDINARY] upstream non-200',
        JSON.stringify({
          statusCode: upstream.statusCode,
          target: normalizedTarget.slice(0, 220),
          depth,
          xCldError: typeof cldErr === 'string' ? cldErr.slice(0, 300) : undefined,
        })
      );
      upstream.resume();
      const stripped = stripFlInlineFromCloudinaryUrl(normalizedTarget);
      if (
        depth === 0 &&
        stripped !== normalizedTarget &&
        (skipUpstreamTrustCheck || isTrustedCloudinaryUpstreamUrl(stripped))
      ) {
        streamHttpsUrlToClient(
          stripped,
          res,
          { filename, mimetype, disposition, skipUpstreamTrustCheck, onFinished },
          depth + 1
        );
        return;
      }
      if (!manualErrorHandling && !res.headersSent) {
        res.status(502).json({
          message: 'PDF Cloudinary inaccessible.',
          cloudinaryStatusCode: upstream.statusCode,
        });
      }
      finish({
        ok: false,
        statusCode: upstream.statusCode,
        reason: 'upstream_non_200',
      });
      return;
    }
    let ct = mimetype || upstream.headers['content-type'] || 'application/octet-stream';
    if (typeof ct === 'string' && ct.includes('application/octet-stream') && filename) {
      const guessed = guessContentTypeFromFilename(String(filename));
      if (guessed) ct = guessed;
    }
    res.setHeader('Content-Type', ct);
    const dispName = String(filename || 'fichier').replace(/[\r\n"]/g, '_');
    const safeDisp = disposition === 'attachment' ? 'attachment' : 'inline';
    res.setHeader('Content-Disposition', `${safeDisp}; filename*=UTF-8''${encodeURIComponent(dispName)}`);
    res.setHeader('Cache-Control', 'private, max-age=300');
    upstream.on('error', (err) => {
      console.error('[STREAM][CLOUDINARY] upstream stream error', err);
      finish({ ok: false, reason: 'upstream_stream_error' });
    });
    upstream.on('end', () => {
      finish({ ok: true, statusCode: 200 });
    });
    upstream.pipe(res);
  });
  reqOut.on('error', (err) => {
    console.error('streamHttpsUrlToClient', err);
    if (!manualErrorHandling && !res.headersSent) {
      res.status(502).json({ message: 'Erreur lecture fichier.' });
    }
    finish({ ok: false, statusCode: 502, reason: 'request_error' });
  });
  reqOut.end();
}

function guessContentTypeFromFilename(name) {
  const lower = String(name || '').toLowerCase();
  const ext = lower.includes('.') ? lower.slice(lower.lastIndexOf('.')) : '';
  const map = {
    '.pdf': 'application/pdf',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.gif': 'image/gif',
    '.webp': 'image/webp',
    '.txt': 'text/plain; charset=utf-8',
    '.doc': 'application/msword',
    '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    '.xls': 'application/vnd.ms-excel',
    '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  };
  return map[ext] || null;
}

module.exports = {
  streamHttpsUrlToClient,
  guessContentTypeFromFilename,
  isTrustedCloudinaryUpstreamUrl,
};
