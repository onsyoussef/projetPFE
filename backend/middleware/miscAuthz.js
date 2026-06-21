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

async function requireFormulaireUrgenceRead(req, res, next) {
  try {
    const patientId = String(req.query.patientId || '').trim();
    if (!mongoose.Types.ObjectId.isValid(patientId)) {
      return res.status(400).json({ message: 'patientId invalide.' });
    }
    if (!req.auth) return res.status(401).json({ message: 'Authentification requise.' });
    if (req.auth.role === 'patient' && String(req.auth.sub) === patientId) return next();
    return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
  } catch (e) {
    console.error('requireFormulaireUrgenceRead', e);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

function requireFormulaireUrgenceWrite(req, res, next) {
  const patientId = String(req.body.patientId || '').trim();
  if (!mongoose.Types.ObjectId.isValid(patientId)) {
    return res.status(400).json({ message: 'patientId invalide.' });
  }
  if (!req.auth || req.auth.role !== 'patient' || String(req.auth.sub) !== patientId) {
    return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
  }
  next();
}

function requireHl7Auth(req, res, next) {
  const shared = process.env.HL7_SHARED_SECRET;
  if (!shared) return next();
  const got = req.headers['x-hl7-key'];
  if (!got || String(got) !== String(shared)) {
    return res.status(401).json({ message: 'Unauthorized HL7 access.' });
  }
  return next();
}

module.exports = {
  requireFormulaireUrgenceRead,
  requireFormulaireUrgenceWrite,
  requireHl7Auth
};
