const bcrypt = require('bcrypt');
const crypto = require('crypto');
const fs = require('fs/promises');

const Patient = require('../models/Patient');
const Doctor = require('../models/Doctor');
const PasswordResetCode = require('../models/PasswordResetCode');

const { signPatientToken, signDoctorToken } = require('../middleware/authJwt');
const { sendResetCodeEmail } = require('../services/emailService');
const { isValidEmailFormat, assertPasswordMin8 } = require('../services/utilsService');
const { encrypt, hashEmail, decryptPatient, decryptDoctor } = require('../services/cryptoService');
const {
  uploadFileToCloudinary,
  isConfigured: isCloudinaryConfigured,
  resourceTypeFromMimetype,
} = require('../config/cloudinaryConfig');
const { doctorVerificationHttpResponse } = require('../services/doctorVerificationService');

/** TEST : passer à `true` pour exiger le scan du diplôme à l'inscription médecin. */
const DOCTOR_REGISTER_REQUIRE_DIPLOMA = false;

async function registerPatient(req, res) {
  try {
    const { fullName, email, password, country, addressExact, phone } = req.body;

    if (!fullName || !email || !password || !country || !addressExact || !phone) {
      return res.status(400).json({ message: 'Champs manquants.' });
    }
    const emailNorm = String(email).trim().toLowerCase();
    if (!isValidEmailFormat(emailNorm)) {
      return res.status(400).json({ message: 'Format d\'email invalide.' });
    }
    const pwdErr = assertPasswordMin8(password);
    if (pwdErr) {
      return res.status(400).json({ message: pwdErr });
    }

    const existing = await Patient.findOne({ emailHash: hashEmail(emailNorm) });
    if (existing) {
      return res.status(409).json({ message: 'Email déjà utilisé.' });
    }

    const passwordHash = await bcrypt.hash(password, 10);
    const patient = new Patient({
      fullName: encrypt(fullName),
      email: encrypt(emailNorm),
      emailHash: hashEmail(emailNorm),
      passwordHash,
      country: encrypt(country),
      addressExact: encrypt(addressExact),
      phone: encrypt(phone),
    });

    await patient.save();
    const token = signPatientToken(patient._id);
    return res.status(201).json({
      message: 'Patient créé avec succès.',
      token,
      patient: decryptPatient(patient),
    });
  } catch (err) {
    console.error('Erreur /auth/register', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function loginPatient(req, res) {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({ message: 'Email et mot de passe requis.' });
    }

    const emailNorm = String(email).trim().toLowerCase();
    const patient = await Patient.findOne({ emailHash: hashEmail(emailNorm) });
    if (!patient) {
      return res.status(401).json({ message: 'Identifiants invalides.' });
    }

    const match = await bcrypt.compare(password, patient.passwordHash);
    if (!match) {
      return res.status(401).json({ message: 'Identifiants invalides.' });
    }

    const token = signPatientToken(patient._id);
    return res.json({
      message: 'Connexion réussie.',
      token,
      patient: decryptPatient(patient),
    });
  } catch (err) {
    console.error('Erreur /auth/login', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function registerDoctor(req, res) {
  try {
    const { fullName, email, password, specialty, governorate, address, phone, orderNumber, country } =
      req.body;

    if (!fullName || !email || !password || !specialty || !governorate || !address || !phone) {
      return res.status(400).json({ message: 'Champs manquants.' });
    }
    if (DOCTOR_REGISTER_REQUIRE_DIPLOMA && !req.file) {
      return res.status(400).json({
        message: 'Veuillez scanner votre carte de médecin ou justificatif (diplôme).',
      });
    }
    const emailNorm = String(email).trim().toLowerCase();
    if (!isValidEmailFormat(emailNorm)) {
      return res.status(400).json({ message: 'Format d\'email invalide.' });
    }
    const pwdErr = assertPasswordMin8(password);
    if (pwdErr) {
      return res.status(400).json({ message: pwdErr });
    }
    const orderNumberNorm = orderNumber != null ? String(orderNumber).trim() : '';
    if (orderNumberNorm && !/^\d{1,5}$/.test(orderNumberNorm)) {
      return res.status(400).json({
        message: 'Le numéro d\'ordre doit contenir au maximum 5 chiffres.',
      });
    }

    const existing = await Doctor.findOne({ emailHash: hashEmail(emailNorm) });
    if (existing) {
      return res.status(409).json({ message: 'Email déjà utilisé.' });
    }

    let diplomaPath;
    let diplomaCloudinaryPublicId;
    // Upload justificatif (diplôme) — désactivé en test si DOCTOR_REGISTER_REQUIRE_DIPLOMA = false
    if (req.file) {
      if (isCloudinaryConfigured) {
        const resourceType = resourceTypeFromMimetype(req.file.mimetype);
        const cloudUpload = await uploadFileToCloudinary(
          req.file.path,
          'telemedecine/doctors/diplomas',
          resourceType,
        );
        if (!cloudUpload?.url || !cloudUpload.publicId) {
          return res.status(500).json({ message: 'Échec envoi du justificatif.' });
        }
        diplomaPath = cloudUpload.url;
        diplomaCloudinaryPublicId = cloudUpload.publicId;
      } else {
        diplomaPath = `/uploads/${req.file.filename}`;
      }
    }

    const passwordHash = await bcrypt.hash(password, 10);
    const doctor = new Doctor({
      fullName: encrypt(fullName),
      specialty: encrypt(String(specialty).trim()),
      governorate: encrypt(governorate),
      address: encrypt(address),
      email: encrypt(emailNorm),
      emailHash: hashEmail(emailNorm),
      phone: encrypt(phone),
      passwordHash,
      orderNumber: orderNumberNorm || undefined,
      country: country ? encrypt(String(country).trim()) : undefined,
      ...(diplomaPath
        ? { diplomaPath, diplomaCloudinaryPublicId }
        : {}),
      verificationStatus: 'pending',
    });

    await doctor.save();
    return res.status(201).json({
      message:
        'Demande d\'inscription enregistrée. Un administrateur doit approuver votre compte avant toute connexion.',
      pendingApproval: true,
      doctor: {
        id: doctor._id,
        verificationStatus: 'pending',
      },
    });
  } catch (err) {
    console.error('Erreur /auth/doctor/register', err);
    if (err && err.code === 11000) {
      return res.status(409).json({ message: 'Email déjà utilisé.' });
    }
    const msg = err && err.message ? String(err.message) : '';
    if (
      msg.includes('ENCRYPTION_KEY') ||
      msg.includes('HMAC_KEY') ||
      msg.includes('clé hex')
    ) {
      console.error(
        '[auth/doctor/register] Configuration chiffrement invalide (voir ENCRYPTION_KEY / HMAC_KEY sur l’hébergeur).',
      );
    }
    return res.status(500).json({ message: 'Erreur serveur.' });
  } finally {
    if (req.file?.path) {
      try {
        await fs.unlink(req.file.path);
      } catch (_) {}
    }
  }
}

async function loginDoctor(req, res) {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({ message: 'Email et mot de passe requis.' });
    }

    const emailNorm = String(email).trim().toLowerCase();
    const doctor = await Doctor.findOne({ emailHash: hashEmail(emailNorm) });
    if (!doctor || !doctor.passwordHash) {
      return res.status(401).json({ message: 'Identifiants invalides.' });
    }

    const match = await bcrypt.compare(password, doctor.passwordHash);
    if (!match) {
      return res.status(401).json({ message: 'Identifiants invalides.' });
    }

    const verificationBlock = doctorVerificationHttpResponse(
      doctor.verificationStatus || 'pending',
    );
    if (verificationBlock) {
      return res.status(verificationBlock.status).json(verificationBlock.body);
    }

    const token = signDoctorToken(doctor._id);
    return res.json({
      message: 'Connexion médecin réussie.',
      token,
      doctor: {
        ...decryptDoctor(doctor),
        verificationStatus: 'verified',
      },
    });
  } catch (err) {
    console.error('Erreur /auth/doctor/login', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function requestResetCode(req, res) {
  try {
    const email = req.body.email ? String(req.body.email).trim().toLowerCase() : '';
    if (!email || !email.includes('@')) {
      return res.status(400).json({ message: 'Adresse email requise.' });
    }

    const emailHash = hashEmail(email);
    const patient = await Patient.findOne({ emailHash });
    const doctor = await Doctor.findOne({ emailHash });
    if (!patient && !doctor) {
      return res.json({
        message: 'Si un compte existe avec cette adresse, un code a été envoyé par email.',
      });
    }

    const code = String(crypto.randomInt(100000, 1000000));
    const expiresAt = new Date(Date.now() + 15 * 60 * 1000);

    await PasswordResetCode.deleteMany({ email });
    await PasswordResetCode.create({ email, code, expiresAt });
    await sendResetCodeEmail(email, code);

    return res.json({
      message: 'Si un compte existe avec cette adresse, un code a été envoyé par email.',
    });
  } catch (err) {
    console.error('Erreur /auth/request-reset-code', err.message || err);
    const msg = err.message || 'Impossible d\'envoyer l\'email. Réessayez plus tard.';
    return res.status(500).json({
      message: msg.startsWith('Envoi d\'email') ? msg : `Envoi échoué : ${msg}`,
    });
  }
}

async function verifyResetCode(req, res) {
  try {
    const email = req.body.email ? String(req.body.email).trim().toLowerCase() : '';
    const code = req.body.code ? String(req.body.code).trim() : '';

    if (!email || !code) {
      return res.status(400).json({ message: 'Email et code requis.' });
    }

    const record = await PasswordResetCode.findOne({
      email,
      code,
      expiresAt: { $gt: new Date() },
    });
    if (!record) {
      return res.status(400).json({
        message: 'Code invalide ou expiré. Demandez un nouveau code.',
      });
    }

    return res.json({ message: 'Code vérifié avec succès.' });
  } catch (err) {
    console.error('Erreur /auth/verify-reset-code', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function verifyResetPassword(req, res) {
  try {
    const email = req.body.email ? String(req.body.email).trim().toLowerCase() : '';
    const code = req.body.code ? String(req.body.code).trim() : '';
    const newPassword = req.body.newPassword ? String(req.body.newPassword) : '';

    if (!email || !code || !newPassword) {
      return res.status(400).json({ message: 'Email, code et nouveau mot de passe requis.' });
    }
    const pwdErr = assertPasswordMin8(newPassword);
    if (pwdErr) {
      return res.status(400).json({ message: pwdErr });
    }

    const record = await PasswordResetCode.findOne({
      email,
      code,
      expiresAt: { $gt: new Date() },
    });
    if (!record) {
      return res.status(400).json({
        message: 'Code invalide ou expiré. Demandez un nouveau code.',
      });
    }

    const emailHash = hashEmail(email);
    let account = await Patient.findOne({ emailHash });
    let isDoctor = false;
    if (!account) {
      account = await Doctor.findOne({ emailHash });
      isDoctor = true;
    }
    if (!account) {
      return res.status(404).json({ message: 'Compte introuvable.' });
    }

    const passwordHash = await bcrypt.hash(newPassword, 10);
    account.passwordHash = passwordHash;
    await account.save();
    await PasswordResetCode.deleteMany({ email });

    return res.json({
      message: `Mot de passe mis à jour avec succès pour le ${isDoctor ? 'médecin' : 'patient'}.`,
    });
  } catch (err) {
    console.error('Erreur /auth/verify-reset-password', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

module.exports = {
  registerPatient,
  loginPatient,
  registerDoctor,
  loginDoctor,
  requestResetCode,
  verifyResetCode,
  verifyResetPassword,
};
