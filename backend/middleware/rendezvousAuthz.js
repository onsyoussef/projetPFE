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

async function requireRdvPostDoctor(req, res, next) {
  const medecinId = String(req.body.medecinId || '').trim();
  if (!req.auth || req.auth.role !== 'doctor' || String(req.auth.sub) !== medecinId) {
    return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
  }
  if (!(await assertDoctorVerifiedForRequest(req, res))) return;
  next();
}

function requireRdvPatientGet(req, res, next) {
  const pid = String(req.query.patientId || '').trim();
  if (!req.auth || req.auth.role !== 'patient' || String(req.auth.sub) !== pid) {
    return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
  }
  next();
}

async function requireRdvDoctorGetQuery(req, res, next) {
  const mid = String(req.query.medecinId || '').trim();
  if (!req.auth || req.auth.role !== 'doctor' || String(req.auth.sub) !== mid) {
    return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
  }
  if (!(await assertDoctorVerifiedForRequest(req, res))) return;
  next();
}

async function requireRdvMutateDoctor(req, res, next) {
  const medecinId = String(req.body.medecinId || req.query.medecinId || '').trim();
  if (!req.auth || req.auth.role !== 'doctor' || String(req.auth.sub) !== medecinId) {
    return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
  }
  if (!(await assertDoctorVerifiedForRequest(req, res))) return;
  next();
}

module.exports = {
  requireRdvPostDoctor,
  requireRdvPatientGet,
  requireRdvDoctorGetQuery,
  requireRdvMutateDoctor,
};
