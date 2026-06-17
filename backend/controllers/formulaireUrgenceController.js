const mongoose = require('mongoose');

const Patient = require('../models/Patient');
const FormulaireUrgence = require('../models/FormulaireUrgence');
const { buildPatientInfoSnapshot } = require('../services/patientInfoSnapshot');

async function createFormulaireUrgence(req, res) {
  try {
    const { patientId, symptomes, alerteAcceptee } = req.body || {};

    if (!patientId || !Array.isArray(symptomes)) {
      return res.status(400).json({
        message: 'patientId et symptomes (tableau) requis.',
      });
    }

    if (!mongoose.Types.ObjectId.isValid(patientId)) {
      return res.status(400).json({ message: 'patientId invalide.' });
    }

    const patient = await Patient.findById(patientId);
    if (!patient) {
      return res.status(404).json({ message: 'Patient introuvable.' });
    }

    const doc = await FormulaireUrgence.create({
      patient: patientId,
      patientInfo: buildPatientInfoSnapshot(patient),
      symptomes: symptomes.map((s) => String(s)),
      alerteAcceptee: Boolean(alerteAcceptee),
    });

    return res.status(201).json({
      message: 'Formulaire enregistré.',
      id: doc._id.toString(),
    });
  } catch (err) {
    console.error('Erreur POST /formulaire-urgence', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

module.exports = {
  createFormulaireUrgence,
};
