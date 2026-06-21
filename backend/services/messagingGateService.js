const Message = require('../models/Message');

const GATED_MESSAGE_TYPES = new Set(['text', 'attachment', 'file', 'prescription']);

function getPayloadEvent(payload) {
  if (!payload || typeof payload !== 'object') return null;
  const ev = payload.event;
  return ev != null ? String(ev) : null;
}

function isTeleconsultAnchor(type) {
  return type === 'request_teleconsult' || type === 'form_teleconsult';
}

/**
 * Échange libre autorisé uniquement après que le médecin a choisi « Répondre par message »
 * (message système payload.event = reply_by_message) postérieur au dernier jalon téléconsultation.
 */
async function isFreeMessagingUnlocked(conversationId) {
  const messages = await Message.find({ conversation: conversationId })
    .sort({ createdAt: 1 })
    .select('fromType type payload')
    .lean();

  let lastTeleIndex = -1;
  for (let i = 0; i < messages.length; i++) {
    const m = messages[i];
    if (m.fromType === 'system' && isTeleconsultAnchor(m.type)) {
      lastTeleIndex = i;
    }
  }
  if (lastTeleIndex === -1) return false;

  for (let j = lastTeleIndex + 1; j < messages.length; j++) {
    const m = messages[j];
    if (m.type === 'system' && getPayloadEvent(m.payload) === 'reply_by_message') {
      return true;
    }
  }
  return false;
}

async function assertFreeMessagingAllowed(conversationId, msgType) {
  const type = String(msgType || 'text');
  if (!GATED_MESSAGE_TYPES.has(type)) return;

  const unlocked = await isFreeMessagingUnlocked(conversationId);
  if (!unlocked) {
    const err = new Error(
      'Échange de messages non autorisé. Le médecin doit choisir « Répondre par message » depuis le formulaire de téléconsultation.',
    );
    err.statusCode = 403;
    throw err;
  }
}

module.exports = {
  isFreeMessagingUnlocked,
  assertFreeMessagingAllowed,
};
