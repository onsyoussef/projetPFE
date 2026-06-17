const mongoose = require('mongoose');

const bloodPressureAlertSchema = new mongoose.Schema(
  {
    patient: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Patient',
      required: true,
      index: true,
    },
    measurement: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'BloodPressureMeasurement',
    },
    type: {
      type: String,
      enum: ['hypotension', 'hypertension', 'high', 'low'],
      required: true,
    },
    severity: {
      type: String,
      enum: ['info', 'normal', 'high'],
      default: 'high',
    },
    message: { type: String, required: true, trim: true },
    systolic: { type: Number, min: 0 },
    diastolic: { type: Number, min: 0 },
  },
  { timestamps: true },
);

bloodPressureAlertSchema.index({ patient: 1, createdAt: -1 });

module.exports = mongoose.model('BloodPressureAlert', bloodPressureAlertSchema);
