const mongoose = require('mongoose');

const pushDeviceSchema = new mongoose.Schema(
  {
    userId: { type: mongoose.Schema.Types.ObjectId, required: true, index: true },
    role: { type: String, enum: ['patient', 'doctor'], required: true, index: true },
    token: { type: String, required: true, unique: true, index: true },
    /** iOS PushKit (VoIP) — distinct du token FCM ; utilisé pour APNs voip si configuré côté serveur. */
    voipToken: { type: String, default: '', index: false },
    platform: { type: String, default: 'unknown' },
    appName: { type: String, enum: ['patient', 'doctor'], required: true, index: true },
    active: { type: Boolean, default: true, index: true },
    lastSeenAt: { type: Date, default: Date.now },
  },
  { timestamps: true }
);

module.exports = mongoose.model('PushDevice', pushDeviceSchema);
