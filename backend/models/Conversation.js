const mongoose = require('mongoose');

// 🔹 Modèles pour chat & téléconsultation
const conversationSchema = new mongoose.Schema(
  {
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'Patient', required: true },
    doctor: { type: mongoose.Schema.Types.ObjectId, ref: 'Doctor', required: true },
    /** `open` = échanges libres ; `cloture` = plus d’envoi (sauf messages système serveur). */
    sessionStatus: {
      type: String,
      enum: ['open', 'cloture'],
      default: 'open',
    },
  },
  { timestamps: true }
);
conversationSchema.index({ patient: 1, doctor: 1 }, { unique: true });
const Conversation = mongoose.model('Conversation', conversationSchema);

module.exports = Conversation;
