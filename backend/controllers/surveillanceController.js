const mongoose = require('mongoose');

const Patient = require('../models/Patient');
const SurveillanceActive = require('../models/SurveillanceActive');

async function activerSurveillance(req, res) {
  try {
    const { patientId, horodatageAlerte, symptomesCritiques } = req.body || {};
    if (!patientId || !horodatageAlerte || !Array.isArray(symptomesCritiques)) {
      return res.status(400).json({
        message: 'patientId, horodatageAlerte et symptomesCritiques sont requis.',
      });
    }
    if (!mongoose.Types.ObjectId.isValid(patientId)) {
      return res.status(400).json({ message: 'patientId invalide.' });
    }
    const dateAlerte = new Date(horodatageAlerte);
    if (Number.isNaN(dateAlerte.getTime())) {
      return res.status(400).json({ message: 'horodatageAlerte invalide (ISO 8601 UTC attendu).' });
    }
    const patient = await Patient.findById(patientId).lean();
    if (!patient) {
      return res.status(404).json({ message: 'Patient introuvable.' });
    }
    const doc = await SurveillanceActive.create({
      patient: patientId,
      horodatageAlerte: dateAlerte,
      symptomesCritiques: symptomesCritiques.map((s) => String(s)),
      etat: 'SURVEILLANCE_ACTIVE',
    });
    return res.status(201).json({
      message: 'SURVEILLANCE_ACTIVE activé.',
      id: String(doc._id),
      etat: doc.etat,
      horodatageAlerte: doc.horodatageAlerte.toISOString(),
    });
  } catch (err) {
    console.error('Erreur POST /api/surveillance/activer', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

module.exports = {
  activerSurveillance,
};
