const mongoose = require('mongoose');

// 🔹 Modèle Patient
const patientSchema = new mongoose.Schema(
  {
    fullName: { type: String, required: true },
    email: { type: String, required: true },
    emailHash: { type: String, unique: true, sparse: true },
    passwordHash: { type: String, required: true },
    country: { type: String, required: true },
    addressExact: { type: String, required: true },
    photoPath: { type: String },
    /** public_id Cloudinary (serveur uniquement, pour suppression à remplacement) */
    photoCloudinaryPublicId: { type: String },
    birthDate: { type: Date },
    sex: { type: String, enum: ['homme', 'femme'] },
    phone: { type: String, required: true },
    /** Groupe sanguin affiché côté patient (ex. A+, O-) */
    bloodGroup: { type: String },
    weightKg: { type: Number },
    heightCm: { type: Number },
    /** Texte libre, chiffré comme les autres champs sensibles */
    knownAllergies: { type: String },
  },
  { timestamps: true }
);

const Patient = mongoose.model('Patient', patientSchema);

module.exports = Patient;
