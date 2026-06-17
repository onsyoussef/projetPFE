const mongoose = require('mongoose');

const surveillanceActiveSchema = new mongoose.Schema(
  {
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'Patient', required: true },
    horodatageAlerte: { type: Date, required: true },
    symptomesCritiques: { type: [String], default: [] },
    etat: { type: String, enum: ['SURVEILLANCE_ACTIVE'], default: 'SURVEILLANCE_ACTIVE' },
  },
  { timestamps: true },
);

surveillanceActiveSchema.index({ patient: 1, createdAt: -1 });

module.exports = mongoose.model('SurveillanceActive', surveillanceActiveSchema);
