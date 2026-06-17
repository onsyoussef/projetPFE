const admin = require('firebase-admin');
const mongoose = require('mongoose');
const PushDevice = require('../models/PushDevice');

let _enabled = false;

function initPushNotifications() {
  const requiredFirebaseEnv = [
    'FIREBASE_PROJECT_ID',
    'FIREBASE_CLIENT_EMAIL',
    'FIREBASE_PRIVATE_KEY',
  ];
  const missingFirebaseEnv = requiredFirebaseEnv.filter(
    (key) => !String(process.env[key] || '').trim()
  );

  if (missingFirebaseEnv.length > 0) {
    console.warn(
      `[PUSH] Firebase non configuré: variables manquantes (${missingFirebaseEnv.join(', ')}). Notifications natives désactivées.`
    );
    _enabled = false;
    return;
  }

  try {
    const projectId = String(process.env.FIREBASE_PROJECT_ID || '').trim();
    const clientEmail = String(process.env.FIREBASE_CLIENT_EMAIL || '').trim();
    const privateKey = String(process.env.FIREBASE_PRIVATE_KEY || '')
      .trim()
      .replace(/\\n/g, '\n');
    if (admin.apps.length === 0) {
      admin.initializeApp({
        credential: admin.credential.cert({
          projectId,
          clientEmail,
          privateKey,
        }),
      });
    }
    _enabled = true;
    console.log('[PUSH] Firebase Admin initialisé.');
  } catch (err) {
    _enabled = false;
    console.error('[PUSH] Échec init Firebase Admin:', err);
  }
}

function isPushEnabled() {
  return _enabled;
}

async function registerPushDevice({ userId, role, token, platform, appName, voipToken }) {
  if (!userId || !mongoose.Types.ObjectId.isValid(String(userId))) return;
  const tok = String(token || '').trim();
  if (!tok) return;
  const vTok = String(voipToken || '').trim();
  const update = {
    userId,
    role,
    token: tok,
    platform: String(platform || 'unknown'),
    appName: String(appName || ''),
    active: true,
    lastSeenAt: new Date(),
  };
  if (vTok) update.voipToken = vTok;
  await PushDevice.findOneAndUpdate(
    { token: tok },
    update,
    { upsert: true, returnDocument: 'after', setDefaultsOnInsert: true }
  );
}

async function unregisterPushDevice({ token }) {
  const tok = String(token || '').trim();
  if (!tok) return;
  await PushDevice.findOneAndUpdate(
    { token: tok },
    { active: false, lastSeenAt: new Date() }
  );
}

/**
 * Envoie une notification FCM aux appareils enregistrés pour l’utilisateur.
 * Sans Firebase configuré au démarrage (`initPushNotifications`), cette fonction ne fait rien
 * (pas d’exception) — le temps réel (Socket.IO) et les messages en base restent la source de vérité.
 */
async function sendPushToUser({ userId, role, title, body, data, appName }) {
  if (!_enabled) {
    console.warn('[PUSH] envoi ignoré : Firebase Admin non initialisé (vérifiez FIREBASE_* dans .env).');
    return;
  }
  if (!userId || !mongoose.Types.ObjectId.isValid(String(userId))) {
    console.warn('[PUSH] envoi ignoré : userId invalide.', userId);
    return;
  }
  const docs = await PushDevice.find({
    userId,
    role,
    appName,
    active: true,
  })
    .select('token')
    .lean();
  const tokens = docs.map((d) => String(d.token || '')).filter(Boolean);
  if (tokens.length === 0) {
    console.warn(
      `[PUSH] aucun appareil enregistré pour userId=${userId} role=${role} appName=${appName} (le patient doit ouvrir l’app mobile et se connecter).`
    );
    return;
  }

  const payload = {
    notification: {
      title: String(title || 'Télémedecine'),
      body: String(body || ''),
    },
    data: Object.fromEntries(
      Object.entries(data || {}).map(([k, v]) => [String(k), String(v ?? '')])
    ),
    android: { priority: 'high' },
  };

  const res = await admin.messaging().sendEachForMulticast({
    tokens,
    ...payload,
  });

  let ok = 0;
  const invalidTokens = [];
  for (let i = 0; i < res.responses.length; i += 1) {
    const r = res.responses[i];
    if (r.success) {
      ok += 1;
    } else {
      const code = r.error && r.error.code ? String(r.error.code) : '';
      const msg = r.error && r.error.message ? String(r.error.message) : '';
      console.warn(`[PUSH] échec token[${i}] code=${code} msg=${msg}`);
      if (
        code.includes('registration-token-not-registered') ||
        code.includes('invalid-registration-token')
      ) {
        invalidTokens.push(tokens[i]);
      }
    }
  }
  console.log(`[PUSH] envoyé ${ok}/${tokens.length} — ${title}`);
  if (invalidTokens.length > 0) {
    await PushDevice.updateMany(
      { token: { $in: invalidTokens } },
      { active: false, lastSeenAt: new Date() }
    );
  }
}

/**
 * Message FCM **data-only** (pas de clé `notification`) : l’app Flutter affiche la notification
 * locale avec actions (Répondre / Refuser). Toutes les valeurs de `data` doivent être des chaînes.
 */
async function sendDataOnlyToUser({ userId, role, appName, data }) {
  if (!_enabled) {
    console.warn('[PUSH] data-only ignoré : Firebase Admin non initialisé.');
    return;
  }
  if (!userId || !mongoose.Types.ObjectId.isValid(String(userId))) return;
  const docs = await PushDevice.find({
    userId,
    role,
    appName,
    active: true,
  })
    .select('token')
    .lean();
  const tokens = docs.map((d) => String(d.token || '')).filter(Boolean);
  if (tokens.length === 0) {
    console.warn(`[PUSH] data-only : aucun token userId=${userId}`);
    return;
  }
  const dataPayload = Object.fromEntries(
    Object.entries(data || {}).map(([k, v]) => [String(k), String(v ?? '')])
  );
  const res = await admin.messaging().sendEachForMulticast({
    tokens,
    data: dataPayload,
    android: { priority: 'high' },
    apns: {
      headers: { 'apns-priority': '10' },
      payload: { aps: { 'content-available': 1 } },
    },
  });
  let ok = 0;
  for (const r of res.responses) {
    if (r.success) ok += 1;
  }
  console.log(`[PUSH] data-only ${ok}/${tokens.length} type=${dataPayload.type || ''}`);
}

/**
 * Appel entrant « WhatsApp-like » : **data-only** (pas de clé `notification` FCM),
 * priorité haute Android + réveil iOS (content-available).
 * Les tokens sont séparés par plateforme pour appliquer la bonne config APNs.
 */
async function sendIncomingCallToUser({ userId, role, appName, data }) {
  if (!_enabled) {
    console.warn('[PUSH] incoming_call ignoré : Firebase Admin non initialisé.');
    return;
  }
  if (!userId || !mongoose.Types.ObjectId.isValid(String(userId))) return;
  const docs = await PushDevice.find({
    userId,
    role,
    appName,
    active: true,
  })
    .select('token platform voipToken')
    .lean();
  if (docs.length === 0) {
    console.warn(`[PUSH] incoming_call : aucun appareil userId=${userId}`);
    return;
  }
  const dataPayload = Object.fromEntries(
    Object.entries(data || {}).map(([k, v]) => [String(k), String(v ?? '')])
  );
  const androidDocs = docs.filter((d) => String(d.platform || '').toLowerCase() === 'android');
  const iosDocs = docs.filter((d) => String(d.platform || '').toLowerCase() === 'ios');
  const otherDocs = docs.filter((d) => {
    const p = String(d.platform || '').toLowerCase();
    return p !== 'android' && p !== 'ios';
  });

  const sendBatch = async (tokens, opts) => {
    if (!tokens.length) return;
    const res = await admin.messaging().sendEachForMulticast({
      tokens,
      data: dataPayload,
      ...opts,
    });
    let ok = 0;
    for (const r of res.responses) {
      if (r.success) ok += 1;
    }
    console.log(`[PUSH] incoming_call batch ${ok}/${tokens.length}`);
  };

  await sendBatch(androidDocs.map((d) => String(d.token || '')).filter(Boolean), {
    android: { priority: 'high' },
  });

  await sendBatch(iosDocs.map((d) => String(d.token || '')).filter(Boolean), {
    android: { priority: 'high' },
    apns: {
      headers: {
        'apns-priority': '10',
      },
      payload: {
        aps: {
          'content-available': 1,
        },
      },
    },
  });

  if (otherDocs.length > 0) {
    await sendBatch(otherDocs.map((d) => String(d.token || '')).filter(Boolean), {
      android: { priority: 'high' },
      apns: {
        headers: { 'apns-priority': '10' },
        payload: { aps: { 'content-available': 1 } },
      },
    });
  }

  await trySendVoipIncomingPush(
    docs.filter((d) => String(d.voipToken || '').trim()),
    dataPayload
  );
}

/**
 * APNs **VoIP** (PushKit) — hors FCM. À brancher avec une clef .p8 ou cert .p12
 * (`APNS_VOIP_KEY_ID`, `APNS_VOIP_TEAM_ID`, `APNS_VOIP_PRIVATE_KEY`, `APNS_VOIP_TOPIC=bundle.voip`).
 */
async function trySendVoipIncomingPush(docsWithVoip, dataPayload) {
  const topic = String(process.env.APNS_VOIP_TOPIC || '').trim();
  if (!topic || !docsWithVoip.length) return;
  const hasKey =
    String(process.env.APNS_VOIP_KEY_ID || '').trim() &&
    String(process.env.APNS_VOIP_TEAM_ID || '').trim() &&
    String(process.env.APNS_VOIP_PRIVATE_KEY || '').trim();
  if (!hasKey) {
    console.warn(
      '[PUSH] VoIP : tokens PushKit enregistrés mais APNS_VOIP_* non configurés — uniquement FCM data sur iOS.'
    );
    return;
  }
  console.warn(
    '[PUSH] VoIP APNs : implémentez l’envoi HTTP/2 (topic voip) ou ajoutez le package `apn` — payload prêt:',
    dataPayload
  );
}

module.exports = {
  initPushNotifications,
  isPushEnabled,
  registerPushDevice,
  unregisterPushDevice,
  sendPushToUser,
  sendDataOnlyToUser,
  sendIncomingCallToUser,
};
