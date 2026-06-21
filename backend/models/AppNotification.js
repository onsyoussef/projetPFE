const mongoose = require('mongoose');

const appNotificationSchema = new mongoose.Schema(
  {
    recipientRole: {
      type: String,
      enum: ['patient', 'doctor'],
      required: true,
      index: true,
    },
    recipientId: {
      type: mongoose.Schema.Types.ObjectId,
      required: true,
      index: true,
    },
    type: { type: String, required: true, trim: true, index: true },
    title: { type: String, default: '', trim: true },
    body: { type: String, default: '', trim: true },
    payload: { type: mongoose.Schema.Types.Mixed, default: {} },
    dedupeKey: { type: String, trim: true, sparse: true, unique: true },
    readAt: { type: Date, default: null, index: true },
  },
  { timestamps: true },
);

appNotificationSchema.index({ recipientRole: 1, recipientId: 1, createdAt: -1 });

module.exports = mongoose.model('AppNotification', appNotificationSchema);
