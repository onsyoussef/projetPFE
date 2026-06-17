const mongoose = require('mongoose');

// 🔹 Modèle HL7 (messages entrants/sortants)
const hl7MessageSchema = new mongoose.Schema(
  {
    direction: { type: String, enum: ['inbound', 'outbound'], required: true },
    source: { type: String, default: 'telemedecine-app' },
    patientExternalId: { type: String, index: true },
    hl7Raw: { type: String, required: true },
    jsonPayload: { type: Object },
    parsed: { type: Object },
    status: { type: String, default: 'stored' },
  },
  { timestamps: true }
);
hl7MessageSchema.index({ createdAt: -1 });
const Hl7Message = mongoose.model('Hl7Message', hl7MessageSchema);

module.exports = Hl7Message;
