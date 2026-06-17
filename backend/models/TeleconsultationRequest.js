const mongoose = require('mongoose');

const teleconsultationRequestSchema = new mongoose.Schema(
  {
    conversation: { type: mongoose.Schema.Types.ObjectId, ref: 'Conversation', required: true },
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'Patient' },
    doctor: { type: mongoose.Schema.Types.ObjectId, ref: 'Doctor' },
    status: { type: String, enum: ['pending', 'accepted', 'rejected'], default: 'pending' },
    motif: { type: String },
    /** Texte intégral de la demande type (lettre) tel qu’affiché et certifié par le patient. */
    letterBody: { type: String },
    /** Motif saisi par le médecin en cas de refus (optionnel). */
    rejectionMotif: { type: String },
  },
  { timestamps: true }
);
teleconsultationRequestSchema.index({ doctor: 1, status: 1 });
const TeleconsultationRequest = mongoose.model('TeleconsultationRequest', teleconsultationRequestSchema);

module.exports = TeleconsultationRequest;
