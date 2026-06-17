const mongoose = require('mongoose');

// 🔹 Modèle formulaire d'urgence (un enregistrement par soumission)
const formulaireUrgenceSchema = new mongoose.Schema(
  {
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'Patient', required: true },
    /** Instantané du profil patient au moment de la soumission (fiche d'urgence). */
    patientInfo: {
      fullName: { type: String, default: '' },
      birthDate: { type: Date },
      ageYears: { type: Number },
      sex: { type: String },
      bloodGroup: { type: String, default: '' },
      weightKg: { type: Number },
      heightCm: { type: Number },
    },
    symptomes: { type: [String], required: true },
    alerteAcceptee: { type: Boolean, default: false },
    /** Consultation vue par médecin (marquage « Consulté » côté app médecin). */
    doctorViews: [
      {
        doctor: { type: mongoose.Schema.Types.ObjectId, ref: 'Doctor', required: true },
        consultedAt: { type: Date, default: Date.now },
      },
    ],
  },
  { timestamps: true }
);
formulaireUrgenceSchema.index({ patient: 1, createdAt: -1 });
const FormulaireUrgence = mongoose.model('FormulaireUrgence', formulaireUrgenceSchema);

module.exports = FormulaireUrgence;
