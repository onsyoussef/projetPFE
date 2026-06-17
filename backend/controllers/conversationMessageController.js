const mongoose = require('mongoose');

const Conversation = require('../models/Conversation');
const Message = require('../models/Message');
const Doctor = require('../models/Doctor');
const RendezVous = require('../models/RendezVous');

const { persistAutoHl7ForConversation } = require('../services/hl7Service');
const {
  notifyDoctorInboxNewMessage,
  notifyPatientInboxNewMessage,
  notifyPatientCallMissedPush,
} = require('../services/utilsService');
const { emitToConversation, emitToUserId } = require('../services/realtimeGateway');
const { streamHttpsUrlToClient } = require('../services/streamHttpsFile');
const { decrypt } = require('../services/cryptoService');

async function doctorMinuteOccupied(doctorId, scheduledAtIso, opts = {}) {
  const excludeMessageId = opts.excludeMessageId ? String(opts.excludeMessageId) : null;
  const excludeRdvId = opts.excludeRdvId ? String(opts.excludeRdvId) : null;
  const chosenMs = new Date(scheduledAtIso).getTime();
  if (Number.isNaN(chosenMs)) return null;
  const chosenMinute = Math.floor(chosenMs / 60000);

  const convos = await Conversation.find({ doctor: doctorId }).select('_id').lean();
  const convIds = convos.map((c) => c._id);
  const existingMsgs = await Message.find({
    conversation: { $in: convIds },
    type: 'teleconsult_scheduled',
  }).lean();
  for (const m of existingMsgs) {
    if (excludeMessageId && String(m._id) === excludeMessageId) continue;
    const iso = m.payload && m.payload.scheduledAt;
    if (!iso) continue;
    const t = new Date(iso).getTime();
    if (Number.isNaN(t)) continue;
    if (Math.floor(t / 60000) !== chosenMinute) continue;
    return {
      kind: 'message',
    };
  }

  const rvs = await RendezVous.find({
    medecinId: doctorId,
    statut: { $ne: 'annule' },
  }).lean();
  for (const r of rvs) {
    if (excludeRdvId && String(r._id) === excludeRdvId) continue;
    const t = new Date(r.startAt).getTime();
    if (Number.isNaN(t)) continue;
    if (Math.floor(t / 60000) !== chosenMinute) continue;
    return {
      kind: 'rendezvous',
    };
  }
  return null;
}

async function doctorTeleconsultSlotConflict(conversationId, scheduledAtIso, excludeMessageId) {
  const conv = await Conversation.findById(conversationId).lean();
  if (!conv) return 'notfound';
  const hit = await doctorMinuteOccupied(conv.doctor, scheduledAtIso, {
    excludeMessageId,
  });
  return hit ? 'conflict' : 'ok';
}

async function createConversation(req, res) {
  try {
    const { patientId, doctorId } = req.body;
    if (!patientId || !doctorId) {
      return res.status(400).json({ message: 'patientId et doctorId requis.' });
    }

    let conv = await Conversation.findOne({ patient: patientId, doctor: doctorId });
    if (!conv) {
      conv = await Conversation.create({ patient: patientId, doctor: doctorId });
      await Message.create({
        conversation: conv._id,
        fromType: 'system',
        type: 'question_physique',
        content: 'Avez‑vous déjà eu une consultation physique avec ce médecin ?',
      });
    }
    return res.json({ conversationId: conv._id.toString() });
  } catch (err) {
    console.error('Erreur /conversations', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getMessages(req, res) {
  try {
    const { conversationId } = req.query;
    if (!conversationId) {
      return res.status(400).json({ message: 'conversationId requis.' });
    }

    const msgs = await Message.find({ conversation: conversationId }).sort({ createdAt: 1 }).lean();
    const conv = await Conversation.findById(conversationId).select('sessionStatus').lean();
    const sessionStatus = conv && conv.sessionStatus === 'cloture' ? 'cloture' : 'open';
    return res.json({ messages: msgs, sessionStatus });
  } catch (err) {
    console.error('Erreur /messages', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getMessagesAfter(req, res) {
  try {
    const { conversationId, afterId } = req.query;
    if (!conversationId) {
      return res.status(400).json({ message: 'conversationId requis.' });
    }
    const query = { conversation: conversationId };
    if (afterId) {
      if (!mongoose.Types.ObjectId.isValid(afterId)) {
        return res.status(400).json({ message: 'afterId invalide.' });
      }
      query._id = { $gt: afterId };
    }
    const msgs = await Message.find(query).sort({ _id: 1 }).limit(100).lean();
    const conv = await Conversation.findById(conversationId).select('sessionStatus').lean();
    const sessionStatus = conv && conv.sessionStatus === 'cloture' ? 'cloture' : 'open';
    return res.json({ messages: msgs, sessionStatus });
  } catch (err) {
    console.error('Erreur /messages/after', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getMessageFile(req, res) {
  try {
    const { messageId } = req.params;
    const { conversationId, download } = req.query;
    if (!conversationId || !mongoose.Types.ObjectId.isValid(messageId)) {
      return res.status(400).json({ message: 'Paramètres invalides.' });
    }
    if (!mongoose.Types.ObjectId.isValid(String(conversationId))) {
      return res.status(400).json({ message: 'conversationId invalide.' });
    }
    const msg = await Message.findOne({
      _id: messageId,
      conversation: conversationId,
      type: { $in: ['attachment', 'file'] },
    }).lean();
    if (!msg) {
      return res.status(404).json({ message: 'Pièce jointe introuvable.' });
    }
    const rawPath = msg.payload && msg.payload.path;
    if (!rawPath || typeof rawPath !== 'string' || !rawPath.startsWith('http')) {
      return res.status(404).json({ message: 'Fichier introuvable.' });
    }
    streamHttpsUrlToClient(rawPath, res, {
      filename: msg.content || (msg.payload && msg.payload.filename) || 'fichier',
      mimetype: msg.payload && msg.payload.mimetype,
      disposition: download === '1' ? 'attachment' : 'inline',
    });
  } catch (err) {
    console.error('GET /messages/:messageId/file', err);
    if (!res.headersSent) res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function postMessage(req, res) {
  try {
    const { conversationId, fromType, from, type, content, payload } = req.body;
    if (!conversationId || !fromType) {
      return res.status(400).json({ message: 'conversationId et fromType requis.' });
    }

    const convForSession = await Conversation.findById(conversationId).select('sessionStatus').lean();
    if (!convForSession) {
      return res.status(404).json({ message: 'Conversation introuvable.' });
    }
    if (convForSession.sessionStatus === 'cloture' && fromType !== 'system') {
      return res.status(403).json({
        message: "Cette session est clôturée. Impossible d'envoyer un message.",
      });
    }

    const msgType = type || 'text';
    if (msgType === 'teleconsult_scheduled' && fromType === 'doctor' && payload && payload.scheduledAt) {
      const st = await doctorTeleconsultSlotConflict(conversationId, payload.scheduledAt, null);
      if (st === 'notfound') {
        return res.status(404).json({ message: 'Conversation introuvable.' });
      }
      if (st === 'conflict') {
        return res.status(409).json({
          message:
            'Un créneau existe déjà à cette heure pour vous (tous patients). Choisissez une autre heure.',
        });
      }
    }

    const msg = await Message.create({
      conversation: conversationId,
      fromType,
      from,
      type: type || 'text',
      content: content || '',
      payload: payload || {},
    });

    emitToConversation(conversationId, 'chat:new_activity', {
      conversationId: String(conversationId),
      messageId: String(msg._id),
      fromType,
      type: msgType,
    });

    await notifyDoctorInboxNewMessage(conversationId, fromType, msgType, msg._id);
    await notifyPatientInboxNewMessage(conversationId, fromType, msgType, msg._id);

    if (msgType === 'call_event' && fromType === 'system' && payload) {
      try {
        await notifyPatientCallMissedPush(conversationId, String(msg._id), payload);
      } catch (e) {
        console.error('[PUSH] notifyPatientCallMissedPush', e);
      }
    }

    if (msgType === 'teleconsult_scheduled' && payload && payload.scheduledAt) {
      emitToConversation(conversationId, 'consultation:scheduled', {
        conversationId,
        messageId: String(msg._id),
        scheduledAt: payload.scheduledAt,
      });
    }

    if (msgType === 'call_event' && payload && payload.kind === 'call_log') {
      emitToConversation(conversationId, 'chat:call_summary', {
        conversationId,
        messageId: String(msg._id),
        mediaType: payload.mediaType === 'video' ? 'video' : 'audio',
        outcome: payload.outcome || 'ended',
        durationSeconds: parseInt(String(payload.durationSeconds || 0), 10) || 0,
      });
    }

    await persistAutoHl7ForConversation({
      conversationId,
      source: 'auto-message',
      fromType,
      content: content || '',
      payload: payload || {},
    });

    if (type === 'chat_closed' && fromType === 'doctor') {
      await Message.create({
        conversation: conversationId,
        fromType: 'system',
        type: 'form_teleconsult_prompt',
        content: 'Le chat a été clôturé. Vous pouvez remplir à nouveau le formulaire.',
        payload: {},
      });
    }

    return res.status(201).json({ message: msg });
  } catch (err) {
    console.error('Erreur /messages POST', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function markMessagesRead(req, res) {
  try {
    const conversationId = String(req.body.conversationId || '').trim();
    const readerFromType = String(req.body.readerFromType || '').trim();
    if (!conversationId || !mongoose.Types.ObjectId.isValid(conversationId)) {
      return res.status(400).json({ message: 'conversationId invalide.' });
    }
    if (readerFromType !== 'patient' && readerFromType !== 'doctor') {
      return res.status(400).json({ message: 'readerFromType doit être patient ou doctor.' });
    }
    const now = new Date();
    const filter =
      readerFromType === 'doctor'
        ? {
            conversation: conversationId,
            fromType: 'patient',
            type: { $in: ['text', 'attachment', 'file'] },
            readAt: null,
          }
        : {
            conversation: conversationId,
            fromType: 'doctor',
            readAt: null,
          };
    const result = await Message.updateMany(filter, { $set: { readAt: now } });
    emitToConversation(conversationId, 'chat:messages_read', {
      conversationId,
      readerFromType,
      readAt: now.toISOString(),
    });
    return res.json({ ok: true, modifiedCount: result.modifiedCount || 0 });
  } catch (err) {
    console.error('Erreur POST /messages/mark-read', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function closeConversation(req, res) {
  try {
    const { conversationId } = req.params;
    const doctorId = String(req.body.doctorId || '').trim();
    if (!mongoose.Types.ObjectId.isValid(conversationId) || !mongoose.Types.ObjectId.isValid(doctorId)) {
      return res.status(400).json({ message: 'Identifiants invalides.' });
    }
    const conv = await Conversation.findById(conversationId);
    if (!conv) {
      return res.status(404).json({ message: 'Conversation introuvable.' });
    }
    if (String(conv.doctor) !== doctorId) {
      return res.status(403).json({ message: 'Accès refusé.' });
    }
    if (conv.sessionStatus === 'cloture') {
      return res.json({ ok: true, sessionStatus: 'cloture', idempotent: true });
    }
    conv.sessionStatus = 'cloture';
    await conv.save();

    const sysMsg = await Message.create({
      conversation: conversationId,
      fromType: 'system',
      type: 'chat_closed',
      content: '🔒 La session a été clôturée par le médecin.',
      payload: {},
    });

    const doctor = await Doctor.findById(doctorId).select('fullName').lean();
    const doctorName = decrypt(doctor?.fullName) || 'Médecin';
    const patientId = String(conv.patient);
    const convStr = String(conversationId);

    emitToConversation(convStr, 'chat:new_activity', {
      conversationId: convStr,
      messageId: String(sysMsg._id),
    });
    emitToConversation(convStr, 'chat:session_closed', { conversationId: convStr });
    emitToUserId(patientId, 'patient:chat_session_closed', {
      title: 'Session terminée 🔒',
      body: `Dr. ${doctorName} a clôturé la session de chat.`,
      conversationId: convStr,
      doctorId,
      doctorName,
      openChat: true,
    });

    return res.json({
      ok: true,
      sessionStatus: 'cloture',
      message: sysMsg,
    });
  } catch (err) {
    console.error('Erreur PUT /api/conversations/:conversationId/cloturer', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function reopenConversation(req, res) {
  try {
    const { conversationId } = req.params;
    const doctorId = String(req.body.doctorId || '').trim();
    if (!mongoose.Types.ObjectId.isValid(conversationId) || !mongoose.Types.ObjectId.isValid(doctorId)) {
      return res.status(400).json({ message: 'Identifiants invalides.' });
    }
    const conv = await Conversation.findById(conversationId);
    if (!conv) {
      return res.status(404).json({ message: 'Conversation introuvable.' });
    }
    if (String(conv.doctor) !== doctorId) {
      return res.status(403).json({ message: 'Accès refusé.' });
    }
    if (conv.sessionStatus !== 'cloture') {
      return res.json({ ok: true, sessionStatus: 'open', idempotent: true });
    }
    conv.sessionStatus = 'open';
    await conv.save();

    const sysMsg = await Message.create({
      conversation: conversationId,
      fromType: 'system',
      type: 'chat_reopened',
      content: '🔓 La session a été réouverte par le médecin.',
      payload: {},
    });

    const doctor = await Doctor.findById(doctorId).select('fullName photoPath').lean();
    const doctorName = decrypt(doctor?.fullName) || 'Médecin';
    const patientId = String(conv.patient);
    const convStr = String(conversationId);

    emitToConversation(convStr, 'chat:new_activity', {
      conversationId: convStr,
      messageId: String(sysMsg._id),
    });
    emitToConversation(convStr, 'chat:session_reopened', { conversationId: convStr });
    emitToUserId(patientId, 'patient:chat_session_reopened', {
      title: 'Session réouverte 🔓',
      body: `Dr. ${doctorName} a réouvert la session de chat. Vous pouvez de nouveau envoyer des messages.`,
      conversationId: convStr,
      doctorId,
      doctorName,
      doctorPhotoPath: doctor?.photoPath || null,
      openChat: true,
    });

    return res.json({
      ok: true,
      sessionStatus: 'open',
      message: sysMsg,
    });
  } catch (err) {
    console.error('Erreur PUT /api/conversations/:conversationId/rouvrir', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function patchMessage(req, res) {
  try {
    const { messageId } = req.params;
    const { conversationId, fromType, content, payload } = req.body;
    if (!conversationId || fromType !== 'doctor') {
      return res.status(400).json({ message: 'conversationId et fromType doctor requis.' });
    }
    if (!mongoose.Types.ObjectId.isValid(messageId)) {
      return res.status(400).json({ message: 'messageId invalide.' });
    }

    const existing = await Message.findOne({
      _id: messageId,
      conversation: conversationId,
    }).lean();
    if (!existing) {
      return res.status(404).json({ message: 'Message introuvable.' });
    }
    if (existing.type !== 'teleconsult_scheduled' || existing.fromType !== 'doctor') {
      return res.status(403).json({ message: 'Ce message ne peut pas être modifié.' });
    }

    const newPayload = { ...(existing.payload || {}), ...(payload || {}) };
    const newContent = content != null ? String(content) : existing.content;
    const scheduledAt = newPayload.scheduledAt;
    if (scheduledAt && typeof scheduledAt === 'string') {
      const st = await doctorTeleconsultSlotConflict(conversationId, scheduledAt, messageId);
      if (st === 'notfound') {
        return res.status(404).json({ message: 'Conversation introuvable.' });
      }
      if (st === 'conflict') {
        return res.status(409).json({
          message:
            'Un créneau existe déjà à cette heure pour vous (tous patients). Choisissez une autre heure.',
        });
      }
    }

    const updated = await Message.findByIdAndUpdate(
      messageId,
      { $set: { content: newContent, payload: newPayload } },
      { returnDocument: 'after' },
    ).lean();

    emitToConversation(conversationId, 'consultation:updated', {
      conversationId,
      messageId: String(messageId),
      scheduledAt: (updated.payload && updated.payload.scheduledAt) || null,
    });

    return res.json({ message: updated });
  } catch (err) {
    console.error('Erreur PATCH /messages/:messageId', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function deleteMessage(req, res) {
  try {
    const { messageId } = req.params;
    const { conversationId, fromType } = req.query;
    if (!conversationId || fromType !== 'doctor') {
      return res.status(400).json({ message: 'conversationId et fromType=doctor requis (query).' });
    }
    if (!mongoose.Types.ObjectId.isValid(messageId)) {
      return res.status(400).json({ message: 'messageId invalide.' });
    }

    const result = await Message.deleteOne({
      _id: messageId,
      conversation: conversationId,
      type: 'teleconsult_scheduled',
      fromType: 'doctor',
    });
    if (result.deletedCount === 0) {
      return res.status(404).json({ message: 'Créneau introuvable ou déjà supprimé.' });
    }

    emitToConversation(conversationId, 'consultation:cancelled', {
      conversationId,
      messageId: String(messageId),
    });
    return res.status(204).send();
  } catch (err) {
    console.error('Erreur DELETE /messages/:messageId', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

module.exports = {
  createConversation,
  getMessages,
  getMessagesAfter,
  getMessageFile,
  postMessage,
  markMessagesRead,
  closeConversation,
  reopenConversation,
  patchMessage,
  deleteMessage,
};
