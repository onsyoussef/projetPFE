const mongoose = require('mongoose');

const medicationLineSchema = new mongoose.Schema(
  {
    name: { type: String, required: true },
    posologie: { type: String, default: '' },
    duree: { type: String, default: '' },
    instructions: { type: String, default: '' },
  },
  { _id: false }
);

const prescriptionSchema = new mongoose.Schema(
  {
    conversation: { type: mongoose.Schema.Types.ObjectId, ref: 'Conversation', required: true },
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'Patient', required: true },
    doctor: { type: mongoose.Schema.Types.ObjectId, ref: 'Doctor', required: true },
    message: { type: mongoose.Schema.Types.ObjectId, ref: 'Message' },
    pdfUrl: { type: String, required: true },
    pdfPublicId: { type: String },
    city: { type: String, required: true },
    medications: { type: [medicationLineSchema], default: [] },
    notes: { type: String, default: '' },
    patientDisplayName: { type: String, required: true },
    doctorDisplayName: { type: String, required: true },
    doctorSpecialty: { type: String, required: true },
    prescriptionDate: { type: Date, required: true },
    source: { type: String, enum: ['chat', 'teleconsult'], required: true },
    consultationCallRoomId: { type: String },
    status: { type: String, enum: ['sent'], default: 'sent' },
  },
  { timestamps: true }
);

prescriptionSchema.index({ conversation: 1, createdAt: -1 });

module.exports = mongoose.model('Prescription', prescriptionSchema);
