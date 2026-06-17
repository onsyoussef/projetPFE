const mongoose = require('mongoose');

const teleconsultAttachmentSchema = new mongoose.Schema(
  {
    path: { type: String, required: true },
    publicId: String,
    filename: String,
    mimetype: String,
    size: Number,
    uploadedAt: { type: Date, default: Date.now },
  },
  { _id: false }
);

const teleconsultationFormSchema = new mongoose.Schema(
  {
    doctor: { type: mongoose.Schema.Types.ObjectId, ref: 'Doctor' },
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'Patient' },
    conversation: { type: mongoose.Schema.Types.ObjectId, ref: 'Conversation' },
    motif: String,
    symptomes: String,
    dateDerniereConsultation: Date,
    traitements: String,
    allergies: String,
    attachments: { type: [teleconsultAttachmentSchema], default: [] },
    /** Décision métier sur le dossier (indépendante du chat). */
    status: {
      type: String,
      enum: ['pending', 'accepted', 'rejected'],
      default: 'pending',
    },
    /** Après acceptation : planification ou réponse. */
    workflowStatus: {
      type: String,
      enum: ['pending', 'scheduled', 'replied'],
      default: 'pending',
    },
  },
  { timestamps: true }
);
teleconsultationFormSchema.index({ doctor: 1, status: 1 });
teleconsultationFormSchema.index({ patient: 1, createdAt: -1 });
const TeleconsultationForm = mongoose.model('TeleconsultationForm', teleconsultationFormSchema);

module.exports = TeleconsultationForm;
