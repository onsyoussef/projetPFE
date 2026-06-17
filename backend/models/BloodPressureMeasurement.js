const mongoose = require('mongoose');

const bloodPressureMeasurementSchema = new mongoose.Schema(
  {
    patient: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Patient',
      required: true,
      index: true,
    },
    systolic: { type: Number, required: true, min: 0 },
    diastolic: { type: Number, required: true, min: 0 },
    meanArterialPressure: { type: Number, min: 0 },
    heartRate: { type: Number, min: 0 },
    measuredAt: { type: Date, required: true, index: true },
    source: {
      type: String,
      enum: ['ble_esp32', 'manual'],
      default: 'ble_esp32',
    },
    deviceName: { type: String, trim: true },
  },
  { timestamps: true },
);

bloodPressureMeasurementSchema.index({ patient: 1, measuredAt: -1 });

module.exports = mongoose.model(
  'BloodPressureMeasurement',
  bloodPressureMeasurementSchema,
);
