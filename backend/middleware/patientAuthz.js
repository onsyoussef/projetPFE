const mongoose = require('mongoose');
const Conversation = require('../models/Conversation');
const Message = require('../models/Message');
const Doctor = require('../models/Doctor');
const Patient = require('../models/Patient');
const FormulaireUrgence = require('../models/FormulaireUrgence');
const TeleconsultationForm = require('../models/TeleconsultationForm');
const TeleconsultationRequest = require('../models/TeleconsultationRequest');
const RendezVous = require('../models/RendezVous');
function requirePatientParam(req, res, next) {
  const pid = String(req.params.patientId || '').trim();
  if (!req.auth || req.auth.role !== 'patient') {
    return res.status(403).json({ message: 'Accès réservé aux patients.' });
  }
  if (String(req.auth.sub) !== pid) {
    return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
  }
  next();
}

function requirePatientQuery(req, res, next) {
  const pid = String(req.query.patientId || '').trim();
  if (!req.auth || req.auth.role !== 'patient') {
    return res.status(403).json({ message: 'Accès réservé aux patients.' });
  }
  if (String(req.auth.sub) !== pid) {
    return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
  }
  next();
}

function requirePatientBodyPatientId(req, res, next) {
  const body = (req && typeof req.body === 'object' && req.body) ? req.body : {};
  const patientId = String(body.patientId || '').trim();
  if (!mongoose.Types.ObjectId.isValid(patientId)) {
    return res.status(400).json({ message: 'patientId invalide.' });
  }
  if (!req.auth || req.auth.role !== 'patient' || String(req.auth.sub) !== patientId) {
    return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
  }
  next();
}

async function requirePatientConversationBody(req, res, next) {
  try {
    const body = (req && typeof req.body === 'object' && req.body) ? req.body : {};
    const conversationId = String(body.conversationId || '').trim();
    if (!mongoose.Types.ObjectId.isValid(conversationId)) {
      return res.status(400).json({ message: 'conversationId requis ou invalide.' });
    }
    if (!req.auth || req.auth.role !== 'patient') {
      return res.status(403).json({ message: 'Accès réservé aux patients.' });
    }
    const conv = await Conversation.findById(conversationId).select('patient').lean();
    if (!conv) return res.status(404).json({ message: 'Conversation introuvable.' });
    if (String(conv.patient) !== String(req.auth.sub)) {
      return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
    }
    next();
  } catch (e) {
    console.error('requirePatientConversationBody', e);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

module.exports = {
  requirePatientParam,
  requirePatientQuery,
  requirePatientBodyPatientId,
  requirePatientConversationBody
};
