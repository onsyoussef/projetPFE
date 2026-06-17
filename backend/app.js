require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');
const http = require('http');
const dns = require('dns');
const mongoose = require('mongoose');
const { Server } = require('socket.io');
const registerSocketHandlers = require('./sockets/registerSocketHandlers');
const { setIo } = require('./services/realtimeGateway');
const { hydrateWaitingRoomsFromDb } = require('./services/waitingRoomService');
const { initPushNotifications } = require('./services/pushNotificationService');

process.on('unhandledRejection', (reason) => {
  console.error('[FATAL] Unhandled promise rejection:', reason);
});

process.on('uncaughtException', (err) => {
  console.error('[FATAL] Uncaught exception:', err);
  process.exit(1);
});

// Contourne les résolveurs DNS locaux qui refusent les requêtes SRV MongoDB Atlas.
dns.setServers(['8.8.8.8', '1.1.1.1']);

const JWT_SECRET = String(process.env.JWT_SECRET || '').trim();
if (!JWT_SECRET) {
  console.error('[FATAL] JWT_SECRET manquant. Définissez process.env.JWT_SECRET avant de démarrer.');
  process.exit(1);
}

const { assertCryptoEnv, warmEncryptionKey } = require('./services/cryptoService');
try {
  assertCryptoEnv();
  warmEncryptionKey();
} catch (err) {
  console.error('[FATAL] Configuration chiffrement invalide:', err.message);
  process.exit(1);
}

const app = express();
app.set('trust proxy', 1);
const server = http.createServer(app);
// Les signatures base64 d'ordonnance peuvent dépasser 100kb.
app.use(express.json({ limit: '5mb' }));

const allowLanOrigins =
  String(process.env.CORS_ALLOW_LAN || '').toLowerCase() === '1' ||
  String(process.env.CORS_ALLOW_LAN || '').toLowerCase() === 'true';

const allowedOrigins = String(
  process.env.ALLOWED_ORIGINS ||
    'http://localhost:3000,http://localhost:*,http://127.0.0.1:*,http://[::1]:*',
)
  .split(',')
  .map((v) => v.trim().replace(/^["']|["']$/g, ''))
  .filter(Boolean);

function isPrivateLanHostname(hostname) {
  if (!hostname || hostname.includes(':')) return false;
  if (/^192\.168\.\d{1,3}\.\d{1,3}$/.test(hostname)) return true;
  if (/^10\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(hostname)) return true;
  const m = /^172\.(\d{1,3})\./.exec(hostname);
  if (m) {
    const n = Number(m[1]);
    return n >= 16 && n <= 31;
  }
  return false;
}

function isAllowedOrigin(origin) {
  const o = typeof origin === 'string' ? origin.trim() : '';
  if (!o) return true;
  try {
    const u = new URL(o);
    if (!/^https?:$/i.test(u.protocol)) return false;
    const host =
      u.hostname.startsWith('[') && u.hostname.endsWith(']')
        ? u.hostname.slice(1, -1)
        : u.hostname;
    if (host === 'localhost' || host === '127.0.0.1' || host === '::1') {
      return true;
    }
    if (allowLanOrigins && isPrivateLanHostname(host)) return true;
  } catch (_) {
    /* ignore */
  }
  if (/^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/i.test(o)) {
    return true;
  }
  for (const allowed of allowedOrigins) {
    if (allowed === o) return true;
    if (allowed.endsWith('*')) {
      const prefix = allowed.slice(0, -1);
      if (o.startsWith(prefix)) return true;
    }
  }
  return false;
}

function applyCorsHeaders(req, res) {
  const origin = req.headers.origin;
  if (origin && isAllowedOrigin(origin)) {
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Access-Control-Allow-Credentials', 'true');
  }
}

const corsOptions = {
  origin(origin, callback) {
    if (isAllowedOrigin(origin)) return callback(null, true);
    return callback(null, false);
  },
  credentials: true,
  optionsSuccessStatus: 204,
  methods: ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With'],
  maxAge: 86400,
};

// Répond aux préflight sans passer par le chemin d'erreur de `cors` (évite 500 sans en-têtes).
app.use((req, res, next) => {
  if (req.method !== 'OPTIONS') return next();
  const origin =
    typeof req.headers.origin === 'string' ? req.headers.origin.trim() : '';
  if (!origin || !isAllowedOrigin(origin)) return next();
  const reqHdr = req.headers['access-control-request-headers'];
  res.setHeader('Access-Control-Allow-Origin', origin);
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader(
    'Access-Control-Allow-Methods',
    'GET,HEAD,POST,PUT,PATCH,DELETE,OPTIONS',
  );
  res.setHeader(
    'Access-Control-Allow-Headers',
    typeof reqHdr === 'string' && reqHdr.length > 0
      ? reqHdr
      : 'Content-Type, Authorization, X-Requested-With',
  );
  res.setHeader('Access-Control-Max-Age', '86400');
  return res.status(204).end();
});

app.use(cors(corsOptions));

/** Santé pour Render / load balancers (ne pas protéger par auth). */
app.get('/health', (req, res) => {
  const dbState = mongoose.connection.readyState;
  const dbOk = dbState === 1;
  res.status(200).json({
    ok: true,
    mongodb: dbOk ? 'connected' : dbState === 2 ? 'connecting' : 'disconnected',
    uptime: process.uptime(),
  });
});

const uploadsDir = path.join(__dirname, 'uploads');
app.use('/uploads', express.static(uploadsDir));

const io = new Server(server, {
  cors: {
    origin(origin, callback) {
      if (isAllowedOrigin(origin)) return callback(null, true);
      return callback(null, false);
    },
    methods: ['GET', 'POST'],
    credentials: true,
  },
});
setIo(io);
registerSocketHandlers(io);
initPushNotifications();

mongoose
  .connect(process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/telemedecine')
  .then(async () => {
    console.log('MongoDB connecté ');
    await hydrateWaitingRoomsFromDb();
  })
  .catch((err) => {
    console.error('Erreur MongoDB ', err);
    process.exit(1);
  });

app.use('/', require('./routes/adminRoutes'));
app.use('/', require('./routes/authRoutes'));
app.use('/', require('./routes/patientRoutes'));
app.use('/', require('./routes/doctorRoutes'));
app.use('/', require('./routes/conversationMessageRoutes'));
app.use('/', require('./routes/prescriptionRoutes'));
app.use('/', require('./routes/teleconsultationRoutes'));
app.use('/', require('./routes/rendezvousRoutes'));
app.use('/', require('./routes/patientDossierRoutes'));
app.use('/', require('./routes/formulaireUrgenceRoutes'));
app.use('/', require('./routes/hl7Routes'));
app.use('/', require('./routes/webrtcRoutes'));
app.use('/', require('./routes/pushRoutes'));
app.use('/', require('./routes/callSignalRoutes'));
app.use('/', require('./routes/bloodPressureRoutes'));

app.use((err, req, res, next) => {
  console.error('Erreur middleware non gérée:', err);
  if (res.headersSent) return next(err);
  applyCorsHeaders(req, res);
  return res.status(500).json({ message: 'Erreur serveur inattendue.' });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`Serveur démarré sur http://0.0.0.0:${PORT}`);
});
