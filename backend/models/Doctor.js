const mongoose = require('mongoose');

// 🔹 Modèle Médecin (avec compte + adresse + latitude/longitude optionnels pour tri par distance)
const doctorSchema = new mongoose.Schema(
  {
    fullName: { type: String, required: true },
    specialty: { type: String, required: true },
    governorate: { type: String, required: true },
    address: { type: String },
    email: { type: String },
    emailHash: { type: String, unique: true, sparse: true },
    phone: { type: String },
    passwordHash: { type: String },
    latitude: { type: Number },
    longitude: { type: Number },
    orderNumber: { type: String },
    country: { type: String },
    yearsExperience: { type: Number, default: 0 },
    hospitalOrClinic: { type: String },
    photoPath: { type: String },
    photoCloudinaryPublicId: { type: String },
    diplomaPath: { type: String },
    diplomaCloudinaryPublicId: { type: String },
    verificationStatus: {
      type: String,
      enum: ['pending', 'verified', 'rejected'],
      default: 'pending',
    },
    verificationRejectedReason: { type: String },
    verificationReviewedAt: { type: Date },
    // Réglages disponibilité & absence
    workingHoursStart: { type: String, default: '09:00' },
    workingHoursEnd: { type: String, default: '18:00' },
    workingTimeSlots: {
      type: [
        {
          start: { type: String, required: true },
          end: { type: String, required: true },
        },
      ],
      default: [],
    },
    availableDays: { type: [Number], default: [1, 2, 3, 4, 5] }, // 0=Dim, 1=Lun, ..., 6=Sam
    absenceMessage: { type: String, default: '' },
    autoReplyEnabled: { type: Boolean, default: false },
    absenceEmergencyOnly: { type: Boolean, default: false },
    status: { type: String, enum: ['available', 'busy', 'unavailable'], default: 'available' },
    statusUpdatedAt: { type: Date },
  },
  { timestamps: true }
);

const Doctor = mongoose.model('Doctor', doctorSchema);

module.exports = Doctor;
