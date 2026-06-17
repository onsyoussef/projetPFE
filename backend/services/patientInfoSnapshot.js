const { decrypt } = require('./cryptoService');

function computeAgeYears(birthDate) {
  if (!birthDate) return null;
  const b = birthDate instanceof Date ? birthDate : new Date(birthDate);
  if (Number.isNaN(b.getTime())) return null;
  const now = new Date();
  let age = now.getFullYear() - b.getFullYear();
  const monthDiff = now.getMonth() - b.getMonth();
  if (monthDiff < 0 || (monthDiff === 0 && now.getDate() < b.getDate())) {
    age -= 1;
  }
  return age >= 0 && age <= 150 ? age : null;
}

/** Profil patient déchiffré + âge, pour fiche d'urgence. */
function buildPatientInfoSnapshot(patient) {
  if (!patient) {
    return {
      fullName: '',
      birthDate: null,
      ageYears: null,
      sex: null,
      bloodGroup: '',
      weightKg: null,
      heightCm: null,
    };
  }
  const birthDate = patient.birthDate || null;
  return {
    fullName: decrypt(patient.fullName) || '',
    birthDate,
    ageYears: computeAgeYears(birthDate),
    sex: patient.sex || null,
    bloodGroup: patient.bloodGroup ? String(patient.bloodGroup).trim() : '',
    weightKg: patient.weightKg != null && !Number.isNaN(Number(patient.weightKg)) ? Number(patient.weightKg) : null,
    heightCm: patient.heightCm != null && !Number.isNaN(Number(patient.heightCm)) ? Number(patient.heightCm) : null,
  };
}

module.exports = { computeAgeYears, buildPatientInfoSnapshot };
