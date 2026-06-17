const mongoose = require('mongoose');
const Conversation = require('../models/Conversation');
const Message = require('../models/Message');
const Doctor = require('../models/Doctor');
const Patient = require('../models/Patient');
const FormulaireUrgence = require('../models/FormulaireUrgence');
const TeleconsultationForm = require('../models/TeleconsultationForm');
const TeleconsultationRequest = require('../models/TeleconsultationRequest');
const RendezVous = require('../models/RendezVous');
const { assertDoctorVerifiedForRequest } = require('../services/doctorVerificationService');

async function requireConversationAccess(req, res, next) {
  try {
    let conversationId =
      req.query.conversationId ||
      (req.body && req.body.conversationId) ||
      (req.params && req.params.conversationId);
    const messageId = req.params && req.params.messageId;
    if (!conversationId && messageId && mongoose.Types.ObjectId.isValid(String(messageId))) {
      const msg = await Message.findById(messageId).select('conversation').lean();
      if (msg && msg.conversation) conversationId = String(msg.conversation);
    }
    if (!conversationId || !mongoose.Types.ObjectId.isValid(String(conversationId))) {
      return res.status(400).json({ message: 'conversationId requis ou invalide.' });
    }
    const conv = await Conversation.findById(conversationId).select('patient doctor').lean();
    if (!conv) return res.status(404).json({ message: 'Conversation introuvable.' });
    const uid = req.auth && req.auth.sub;
    const role = req.auth && req.auth.role;
    if (role === 'patient' && String(conv.patient) !== String(uid)) {
      return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
    }
    if (role === 'doctor') {
      if (String(conv.doctor) !== String(uid)) {
        return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
      }
      if (!(await assertDoctorVerifiedForRequest(req, res))) return;
    }
    if (role !== 'patient' && role !== 'doctor') {
      return res.status(403).json({ message: 'Accès non autorisé.' });
    }
    req.conversationIdResolved = String(conversationId);
    next();
  } catch (e) {
    console.error('requireConversationAccess', e);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function requireConversationCreate(req, res, next) {
  const { patientId, doctorId } = req.body || {};
  const role = req.auth && req.auth.role;
  const sub = String(req.auth && req.auth.sub);
  if (role === 'patient' && patientId && String(patientId) === sub) return next();
  if (role === 'doctor' && doctorId && String(doctorId) === sub) {
    if (!(await assertDoctorVerifiedForRequest(req, res))) return;
    return next();
  }
  return res.status(403).json({ message: 'Accès non autorisé.' });
}

async function requireConversationParamParticipant(req, res, next) {
  try {
    const conversationId = String(req.params.conversationId || '').trim();
    if (!mongoose.Types.ObjectId.isValid(conversationId)) {
      return res.status(400).json({ message: 'conversationId invalide.' });
    }
    const conv = await Conversation.findById(conversationId).select('patient doctor').lean();
    if (!conv) return res.status(404).json({ message: 'Conversation introuvable.' });
    const uid = req.auth && req.auth.sub;
    const role = req.auth && req.auth.role;
    if (role === 'patient' && String(conv.patient) === String(uid)) return next();
    if (role === 'doctor' && String(conv.doctor) === String(uid)) {
      if (!(await assertDoctorVerifiedForRequest(req, res))) return;
      return next();
    }
    return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
  } catch (e) {
    console.error('requireConversationParamParticipant', e);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

module.exports = {
  requireConversationAccess,
  requireConversationCreate,
  requireConversationParamParticipant
};
