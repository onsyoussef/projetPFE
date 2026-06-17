const mongoose = require('mongoose');

// 🔹 Modèle code de réinitialisation (email, code à 6 chiffres, expiration 15 min)
const passwordResetCodeSchema = new mongoose.Schema(
  {
    email: { type: String, required: true, lowercase: true, trim: true },
    code: { type: String, required: true },
    expiresAt: { type: Date, required: true },
  },
  { timestamps: true }
);
passwordResetCodeSchema.index({ email: 1 });
passwordResetCodeSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 }); // TTL optionnel
const PasswordResetCode = mongoose.model('PasswordResetCode', passwordResetCodeSchema);

module.exports = PasswordResetCode;
