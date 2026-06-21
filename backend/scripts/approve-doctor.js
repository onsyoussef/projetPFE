/**
 * Approuve un compte médecin (verificationStatus = verified).
 *
 * Usage:
 *   node scripts/approve-doctor.js <doctorId>
 *
 * Variables d'environnement : MONGODB_URI (via .env à la racine backend).
 */
require('dotenv').config();
const mongoose = require('mongoose');
const Doctor = require('../models/Doctor');

async function main() {
  const doctorId = process.argv[2];
  if (!doctorId) {
    console.error('Usage: node scripts/approve-doctor.js <doctorId>');
    process.exit(1);
  }
  await mongoose.connect(process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/telemedecine');
  const doctor = await Doctor.findByIdAndUpdate(
    doctorId,
    { verificationStatus: 'verified' },
    { returnDocument: 'after' },
  ).select('verificationStatus specialty');
  if (!doctor) {
    console.error('Médecin introuvable:', doctorId);
    process.exit(1);
  }
  console.log('Médecin approuvé:', doctorId, '→', doctor.verificationStatus);
  await mongoose.disconnect();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
