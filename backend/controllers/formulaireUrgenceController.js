const mongoose = require('mongoose');

const Patient = require('../models/Patient');
const FormulaireUrgence = require('../models/FormulaireUrgence');
const { buildPatientInfoSnapshot } = require('../services/patientInfoSnapshot');

const AUCUN_SYMPTOME_LABEL = 'aucun de ces symptômes';

function normalizeSymptomes(symptomes) {
  if (!Array.isArray(symptomes)) return [];
  return symptomes.map((s) => String(s).trim()).filter(Boolean);
}

function hasGraveSymptomes(symptomes) {
  const cleaned = normalizeSymptomes(symptomes);
  if (cleaned.length === 0) return false;
  return cleaned.some(
    (label) => label.toLowerCase() !== AUCUN_SYMPTOME_LABEL,
  );
}

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

    if (!Boolean(alerteAcceptee)) {
      return res.status(400).json({
        message: 'Seuls les formulaires avec symptômes graves acceptés sont enregistrés.',
      });
    }

    if (!hasGraveSymptomes(symptomes)) {
      return res.status(400).json({
        message: 'Au moins un symptôme grave est requis pour enregistrer le formulaire.',
      });
    }

    const patient = await Patient.findById(patientId);
    if (!patient) {
      return res.status(404).json({ message: 'Patient introuvable.' });
    }

    const graveSymptomes = normalizeSymptomes(symptomes).filter(
      (label) => label.toLowerCase() !== AUCUN_SYMPTOME_LABEL,
    );

    const doc = await FormulaireUrgence.create({
      patient: patientId,
      patientInfo: buildPatientInfoSnapshot(patient),
      symptomes: graveSymptomes,
      alerteAcceptee: true,
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
