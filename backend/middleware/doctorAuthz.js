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

async function requireDoctorParam(req, res, next) {
  const did = String(req.params.doctorId || '').trim();
  if (!req.auth || req.auth.role !== 'doctor') {
    return res.status(403).json({ message: 'Accès réservé aux médecins.' });
  }
  if (String(req.auth.sub) !== did) {
    return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
  }
  if (!(await assertDoctorVerifiedForRequest(req, res))) return;
  next();
}

async function requireDoctorQuery(req, res, next) {
  const did = String(req.query.doctorId || '').trim();
  if (!req.auth || req.auth.role !== 'doctor') {
    return res.status(403).json({ message: 'Accès réservé aux médecins.' });
  }
  if (String(req.auth.sub) !== did) {
    return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
  }
  if (!(await assertDoctorVerifiedForRequest(req, res))) return;
  next();
}

async function requireDoctorRole(req, res, next) {
  if (!req.auth || req.auth.role !== 'doctor') {
    return res.status(403).json({ message: 'Accès réservé aux médecins.' });
  }
  if (!(await assertDoctorVerifiedForRequest(req, res))) return;
  next();
}

async function requireDoctorBodyMatches(req, res, next) {
  const doctorId = String(req.body.doctorId || '').trim();
  if (!req.auth || req.auth.role !== 'doctor' || String(req.auth.sub) !== doctorId) {
    return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
  }
  if (!(await assertDoctorVerifiedForRequest(req, res))) return;
  next();
}

async function requireDoctorPublicRead(req, res, next) {
  const did = String(req.params.doctorId || '').trim();
  if (!req.auth) return res.status(401).json({ message: 'Authentification requise.' });
  if (req.auth.role === 'patient') return next();
  if (req.auth.role === 'doctor' && String(req.auth.sub) === did) {
    if (!(await assertDoctorVerifiedForRequest(req, res))) return;
    return next();
  }
  return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
}

module.exports = {
  requireDoctorParam,
  requireDoctorQuery,
  requireDoctorRole,
  requireDoctorBodyMatches,
  requireDoctorPublicRead,
};
