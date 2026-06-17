const mongoose = require('mongoose');

/** Rendez-vous téléconsultation (planification dédiée, hors seul message chat). */
const rendezVousSchema = new mongoose.Schema(
  {
    medecinId: { type: mongoose.Schema.Types.ObjectId, ref: 'Doctor', required: true },
    patientId: { type: mongoose.Schema.Types.ObjectId, ref: 'Patient', required: true },
    formulaireId: { type: mongoose.Schema.Types.ObjectId, ref: 'TeleconsultationForm' },
    date: { type: String, required: true },
    heure: { type: String, required: true },
    startAt: { type: Date, required: true },
    type: { type: String, default: 'teleconsultation' },
    statut: {
      type: String,
      enum: ['confirme', 'termine', 'annule'],
      default: 'confirme',
    },
    motifAnnulation: { type: String, default: '' },
  },
  { timestamps: true }
);
rendezVousSchema.index({ medecinId: 1, startAt: 1 });
rendezVousSchema.index({ patientId: 1, startAt: -1 });
const RendezVous = mongoose.model('RendezVous', rendezVousSchema);

module.exports = RendezVous;
