const mongoose = require('mongoose');

/** Documents du dossier médical personnel du patient (hors chat). */
const patientMedicalDocumentSchema = new mongoose.Schema(
  {
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'Patient', required: true, index: true },
    category: {
      type: String,
      enum: ['analyses', 'ordonnances', 'fichiers', 'images'],
      required: true,
    },
    title: { type: String, default: '' },
    /** Date « médicale » optionnelle (ex. date du compte rendu). */
    documentDate: { type: Date },
    filename: { type: String, required: true },
    mimetype: { type: String, default: '' },
    size: { type: Number, default: 0 },
    path: { type: String, required: true },
    publicId: { type: String, default: '' },
    /** Pour suppression Cloudinary : image | raw | video */
    cloudinaryResourceType: { type: String, default: 'raw' },
    /** Lien métier optionnel avec une ordonnance électronique. */
    linkedPrescriptionId: { type: String, default: '' },
  },
  { timestamps: true }
);
patientMedicalDocumentSchema.index({ patient: 1, category: 1, createdAt: -1 });
const PatientMedicalDocument = mongoose.model('PatientMedicalDocument', patientMedicalDocumentSchema);

module.exports = PatientMedicalDocument;
