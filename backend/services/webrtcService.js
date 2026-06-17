const crypto = require('crypto');
const https = require('https');

const METERED_MAX_CACHE_MS = 60 * 60 * 1000;
const METERED_DEFAULT_TURN_URLS = [
  'turn:global.relay.metered.ca:80',
  'turn:global.relay.metered.ca:443?transport=tcp',
  'turns:global.relay.metered.ca:443?transport=tcp',
];
const meteredCache = {
  expiresAtMs: 0,
  servers: [],
};

async function buildIceServersForUser(userId = '') {
  const metered = await fetchMeteredIceServers();
  if (metered.length) {
    console.log(`[WEBRTC] ICE from Metered for user=${userId || 'unknown'} count=${metered.length}`);
    console.log('[WEBRTC] ICE servers:', JSON.stringify(metered));
    return metered;
  }

  const stunUrls = csvList(
    process.env.STUN_URLS,
    ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302']
  );
  const turnUrls = csvList(process.env.TURN_URLS, []);
  const servers = [];
  if (stunUrls.length) servers.push({ urls: stunUrls });
  if (!turnUrls.length) return servers;

  const turnSecret = String(process.env.TURN_SECRET || '').trim();
  const staticUser = String(process.env.TURN_USERNAME || '').trim();
  const staticPass = String(process.env.TURN_PASSWORD || '').trim();
  const ttlSeconds = Math.max(parseInt(process.env.TURN_TTL_SECONDS || '3600', 10) || 3600, 60);

  if (turnSecret) {
    const exp = Math.floor(Date.now() / 1000) + ttlSeconds;
    const uname = `${exp}:${userId || 'telemed-user'}`;
    const credential = crypto.createHmac('sha1', turnSecret).update(uname).digest('base64');
    servers.push({
      urls: turnUrls,
      username: uname,
      credential,
    });
    return servers;
  }

  if (staticUser && staticPass) {
    servers.push({
      urls: turnUrls,
      username: staticUser,
      credential: staticPass,
    });
  }
  console.log(`[WEBRTC] ICE fallback config for user=${userId || 'unknown'} count=${servers.length}`);
  console.log('[WEBRTC] ICE servers:', JSON.stringify(servers));
  return servers;
}

async function fetchMeteredIceServers() {
  const now = Date.now();
  if (meteredCache.servers.length && meteredCache.expiresAtMs > now) {
    return meteredCache.servers;
  }

  const appName = String(process.env.METERED_APP_NAME || '').trim();
  const apiKey = String(process.env.METERED_API_KEY || '').trim();
  if (!appName || !apiKey) return [];

  const host = `${appName}.metered.live`;
  const path = `/api/v1/turn/credentials?apiKey=${encodeURIComponent(apiKey)}`;
  try {
    const payload = await httpsGetJson({ host, path, method: 'GET' });
    if (!Array.isArray(payload)) return [];
    const normalized = payload
      .map((row) => normalizeIceServer(row))
      .filter(Boolean);
    const servers = withMeteredRecommendedTurnUrls(normalized);
    if (!servers.length) return [];

    const ttlMs = Math.min(
      Math.max(parseInt(process.env.METERED_CACHE_TTL_MS || `${METERED_MAX_CACHE_MS}`, 10) || METERED_MAX_CACHE_MS, 60 * 1000),
      METERED_MAX_CACHE_MS
    );
    meteredCache.servers = servers;
    meteredCache.expiresAtMs = now + ttlMs;
    return servers;
  } catch (err) {
    console.error('[WEBRTC] Metered credentials error:', err?.message || err);
    return [];
  }
}

function withMeteredRecommendedTurnUrls(servers) {
  if (!Array.isArray(servers) || !servers.length) return [];
  const firstCredentialed = servers.find(
    (s) => Array.isArray(s?.urls) && s.urls.length && s.username && s.credential
  );
  if (!firstCredentialed) return servers;

  const turnUrls = uniqueUrls([
    ...METERED_DEFAULT_TURN_URLS,
    ...(Array.isArray(firstCredentialed.urls) ? firstCredentialed.urls : []),
  ]);
  const stitched = [
    ...servers.map((s) => ({
      ...s,
      urls: uniqueUrls(Array.isArray(s.urls) ? s.urls : []),
    })),
    {
      urls: turnUrls,
      username: firstCredentialed.username,
      credential: firstCredentialed.credential,
    },
  ];
  return dedupeIceServers(stitched);
}

function normalizeIceServer(row) {
  if (!row || typeof row !== 'object') return null;
  const urls = row.urls;
  const out = {};
  if (Array.isArray(urls)) {
    out.urls = urls.map((x) => String(x || '').trim()).filter(Boolean);
  } else if (typeof urls === 'string') {
    const one = urls.trim();
    if (one) out.urls = [one];
  }
  if (!out.urls || !out.urls.length) return null;
  const username = String(row.username || '').trim();
  const credential = String(row.credential || '').trim();
  if (username && credential) {
    out.username = username;
    out.credential = credential;
  }
  return out;
}

function httpsGetJson(options) {
  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', (chunk) => {
        body += chunk;
      });
      res.on('end', () => {
        const code = Number(res.statusCode || 0);
        if (code < 200 || code >= 300) {
          return reject(new Error(`HTTP ${code}: ${body.slice(0, 200)}`));
        }
        try {
          const parsed = JSON.parse(body);
          return resolve(parsed);
        } catch (err) {
          return reject(new Error('Invalid JSON from Metered'));
        }
      });
    });
    req.on('error', reject);
    req.setTimeout(8000, () => {
      req.destroy(new Error('Metered timeout'));
    });
    req.end();
  });
}

function csvList(raw, fallback = []) {
  const src = String(raw || '').trim();
  if (!src) return fallback;
  return src
    .split(',')
    .map((x) => x.trim())
    .filter(Boolean);
}

function uniqueUrls(urls) {
  const out = [];
  const seen = new Set();
  for (const raw of urls || []) {
    const value = String(raw || '').trim();
    if (!value || seen.has(value)) continue;
    seen.add(value);
    out.push(value);
  }
  return out;
}

function dedupeIceServers(servers) {
  const out = [];
  const seen = new Set();
  for (const row of servers || []) {
    if (!row || typeof row !== 'object') continue;
    const urls = uniqueUrls(Array.isArray(row.urls) ? row.urls : []);
    if (!urls.length) continue;
    const username = String(row.username || '').trim();
    const credential = String(row.credential || '').trim();
    const key = `${urls.join('|')}::${username}::${credential}`;
    if (seen.has(key)) continue;
    seen.add(key);
    const item = { urls };
    if (username && credential) {
      item.username = username;
      item.credential = credential;
    }
    out.push(item);
  }
  return out;
}

module.exports = {
  buildIceServersForUser,
  csvList
};
