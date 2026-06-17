const mongoose = require('mongoose');

const messageSchema = new mongoose.Schema(
  {
    conversation: { type: mongoose.Schema.Types.ObjectId, ref: 'Conversation', required: true },
    fromType: { type: String, enum: ['patient', 'doctor', 'system'], required: true },
    from: { type: mongoose.Schema.Types.ObjectId },
    type: {
      type: String,
      enum: [
        'text',
        'attachment',
        'file',
        'question_physique',
        'request_teleconsult',
        'form_teleconsult',
        // Prompts systèmes pour afficher les cartes côté patient
        'form_teleconsult_prompt',
        'system',
        'accept_request',
        'chat_closed',
        'chat_reopened',
        'teleconsult_scheduled',
        /** RDV enregistré via POST /api/rendezvous (phrase dédiée patient). */
        'rdv_teleconsult_programme',
        /** Annulation via DELETE /api/rendezvous/:id */
        'rdv_teleconsult_annule',
        'call_event',
        /** Ordonnance PDF (médecin → patient). */
        'prescription',
      ],
      default: 'text',
    },
    content: { type: String, default: '' },
    payload: { type: Object },
    /** Lu par le destinataire (double coches côté client). */
    readAt: { type: Date },
  },
  { timestamps: true }
);
messageSchema.index({ conversation: 1, createdAt: 1 });
const Message = mongoose.model('Message', messageSchema);

module.exports = Message;
