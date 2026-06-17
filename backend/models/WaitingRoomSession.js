const mongoose = require('mongoose');

/** Salle d’attente téléconsult : persiste l’état (redémarrage serveur / reconnexion médecin). */
const waitingRoomSessionSchema = new mongoose.Schema(
  {
    conversation: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Conversation',
      required: true,
      unique: true,
    },
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'Patient', required: true },
    doctor: { type: mongoose.Schema.Types.ObjectId, ref: 'Doctor', required: true },
    patientName: { type: String, default: 'Patient' },
    enteredAt: { type: Date, default: Date.now },
  },
  { timestamps: true }
);
waitingRoomSessionSchema.index({ doctor: 1 });
const WaitingRoomSession = mongoose.model('WaitingRoomSession', waitingRoomSessionSchema);

module.exports = WaitingRoomSession;
