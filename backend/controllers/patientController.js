const fs = require('fs/promises');
const bcrypt = require('bcrypt');
const mongoose = require('mongoose');
const path = require('path');

const {
  uploadFileToCloudinary,
  isConfigured: isCloudinaryConfigured,
  resourceTypeFromMimetype,
  destroyByPublicId,
  tryParseCloudinaryImagePublicId,
} = require(path.join(__dirname, '..', 'config', 'cloudinaryConfig'));

const Patient = require('../models/Patient');
const Conversation = require('../models/Conversation');
const Message = require('../models/Message');
const TeleconsultationRequest = require('../models/TeleconsultationRequest');

const { getEffectiveDoctorStatus, isValidEmailFormat, assertPasswordMin8 } = require('../services/utilsService');
const { decrypt, encrypt, hashEmail, decryptDoctor, decryptPatient } = require('../services/cryptoService');

async function getPatientConversations(req, res) {
  try {
    const { patientId } = req.query;
    if (!patientId) {
      return res.status(400).json({ message: 'patientId requis.' });
    }

    const convos = await Conversation.find({ patient: patientId })
      .populate(
        'doctor',
        'fullName specialty governorate photoPath status statusUpdatedAt absenceMessage autoReplyEnabled workingHoursStart workingHoursEnd availableDays',
      )
      .lean();

    const convIds = convos.map((c) => c._id);
    const lastMessages = await Message.aggregate([
      { $match: { conversation: { $in: convIds } } },
      { $sort: { createdAt: -1 } },
      {
        $group: {
          _id: '$conversation',
          lastMessage: { $first: '$content' },
          lastMessageAt: { $first: '$createdAt' },
          lastFromType: { $first: '$fromType' },
          lastType: { $first: '$type' },
          lastPatientMessageAt: {
            $max: {
              $cond: [{ $eq: ['$fromType', 'patient'] }, '$createdAt', null],
            },
          },
          lastDoctorMessageAt: {
            $max: {
              $cond: [{ $eq: ['$fromType', 'doctor'] }, '$createdAt', null],
            },
          },
        },
      },
    ]).exec();

    const lastByConv = new Map(
      lastMessages.map((m) => [
        m._id.toString(),
        {
          content: m.lastMessage ?? '',
          at: m.lastMessageAt,
          fromType: m.lastFromType || null,
          type: m.lastType || null,
          lastPatientAt: m.lastPatientMessageAt || null,
          lastDoctorAt: m.lastDoctorMessageAt || null,
        },
      ]),
    );

    const unreadByConv = await Message.aggregate([
      {
        $match: {
          conversation: { $in: convIds },
          fromType: 'doctor',
          readAt: null,
        },
      },
      { $group: { _id: '$conversation', count: { $sum: 1 } } },
    ]).exec();

    const unreadMap = new Map(
      unreadByConv.map((row) => [row._id.toString(), row.count]),
    );

    const list = convos.map((c) => {
      const doctor = c.doctor;
      const did = doctor?._id ? doctor._id.toString() : '';
      const cid = c._id.toString();
      const effectiveStatus = doctor ? getEffectiveDoctorStatus(doctor) : 'available';
      const last = lastByConv.get(cid);
      const unreadCount = unreadMap.get(cid) || 0;
      const hasUnreadFromDoctor = unreadCount > 0;

      return {
        conversationId: cid,
        doctorId: did,
        doctorName: decrypt(doctor?.fullName) ?? 'Médecin',
        doctorSpecialty: decrypt(doctor?.specialty) || '',
        doctorGovernorate: decrypt(doctor?.governorate) || '',
        doctorPhotoPath: doctor?.photoPath ?? null,
        doctorStatus: effectiveStatus,
        doctorStatusUpdatedAt: doctor?.statusUpdatedAt || null,
        lastMessage: last?.content ?? null,
        lastMessageAt: last?.at ?? null,
        lastMessageFromType: last?.fromType ?? null,
        lastMessageType: last?.type ?? null,
        hasUnreadFromDoctor,
        unreadCount,
      };
    });

    return res.json({ conversations: list });
  } catch (err) {
    console.error('Erreur GET /patient/conversations', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getPatientScheduledTeleconsults(req, res) {
  try {
    const { patientId } = req.params;
    if (!mongoose.Types.ObjectId.isValid(patientId)) {
      return res.status(400).json({ message: 'patientId invalide.' });
    }

    const convos = await Conversation.find({ patient: patientId })
      .populate('doctor', 'fullName photoPath')
      .lean();
    if (!convos.length) {
      return res.json({ slots: [] });
    }

    const convIds = convos.map((c) => c._id);
    const byConv = new Map(convos.map((c) => [c._id.toString(), c]));

    const msgs = await Message.find({
      conversation: { $in: convIds },
      fromType: 'doctor',
      type: 'teleconsult_scheduled',
    })
      .sort({ createdAt: -1 })
      .lean();

    const slots = msgs
      .map((m) => {
        const convId = m.conversation?.toString() || '';
        const conv = byConv.get(convId);
        const doctor = conv?.doctor;
        const scheduledAt = m?.payload?.scheduledAt;
        if (!scheduledAt || typeof scheduledAt !== 'string') return null;
        return {
          messageId: m._id.toString(),
          conversationId: convId,
          doctorId: doctor?._id ? doctor._id.toString() : '',
          doctorName: decrypt(doctor?.fullName) || 'Médecin',
          doctorPhotoPath: doctor?.photoPath || null,
          scheduledAt,
          content: m.content || '',
          createdAt: m.createdAt || null,
        };
      })
      .filter(Boolean);

    return res.json({ slots });
  } catch (err) {
    console.error('Erreur GET /patient/:patientId/scheduled-teleconsults', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getPatientTeleconsultRequests(req, res) {
  try {
    const { patientId } = req.params;
    if (!mongoose.Types.ObjectId.isValid(patientId)) {
      return res.status(400).json({ message: 'patientId invalide.' });
    }
    const list = await TeleconsultationRequest.find({ patient: patientId })
      .sort({ createdAt: -1 })
      .lean();
    const items = list.map((r) => ({
      id: String(r._id),
      conversationId: r.conversation ? String(r.conversation) : '',
      doctorId: r.doctor ? String(r.doctor) : '',
      motif: r.motif || '',
      letterBody: r.letterBody || '',
      status: r.status,
      rejectionMotif: r.rejectionMotif || '',
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
    }));
    return res.json({ items });
  } catch (err) {
    console.error('Erreur GET /patient/:patientId/teleconsult-requests', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getPatientProfile(req, res) {
  try {
    const { patientId } = req.params;
    const patient = await Patient.findById(patientId).lean();
    if (!patient) {
      return res.status(404).json({ message: 'Patient introuvable.' });
    }
    return res.json({
      id: patient._id.toString(),
      fullName: decrypt(patient.fullName),
      email: decrypt(patient.email),
      country: decrypt(patient.country),
      addressExact: decrypt(patient.addressExact),
      birthDate: patient.birthDate || null,
      sex: patient.sex || null,
      phone: decrypt(patient.phone),
      photoPath: patient.photoPath ?? null,
      createdAt: patient.createdAt || null,
      bloodGroup: patient.bloodGroup ? String(patient.bloodGroup).trim() || null : null,
      weightKg: patient.weightKg != null ? Number(patient.weightKg) : null,
      heightCm: patient.heightCm != null ? Number(patient.heightCm) : null,
      knownAllergies: patient.knownAllergies
        ? decrypt(patient.knownAllergies) ?? ''
        : '',
    });
  } catch (err) {
    console.error('Erreur GET /patient/:patientId', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function patchPatientName(req, res) {
  try {
    const { patientId } = req.params;
    const { fullName } = req.body || {};
    if (!fullName || !String(fullName).trim()) {
      return res.status(400).json({ message: 'fullName requis.' });
    }

    const patient = await Patient.findByIdAndUpdate(
      patientId,
      { fullName: encrypt(String(fullName).trim()) },
      { returnDocument: 'after', runValidators: false },
    );
    if (!patient) {
      return res.status(404).json({ message: 'Patient introuvable.' });
    }
    return res.json({
      message: 'Nom mis à jour.',
      fullName: decrypt(patient.fullName),
    });
  } catch (err) {
    console.error('Erreur PATCH /patient/:patientId/name', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function patchPatientProfile(req, res) {
  try {
    const { patientId } = req.params;
    const {
      fullName,
      birthDate,
      sex,
      phone,
      email,
      addressExact,
      country,
      bloodGroup,
      weightKg,
      heightCm,
      knownAllergies,
    } = req.body || {};

    const updates = {};
    if (fullName != null) {
      const v = String(fullName).trim();
      if (!v) return res.status(400).json({ message: 'Nom requis.' });
      updates.fullName = encrypt(v);
    }
    if (birthDate != null && String(birthDate).trim()) {
      const d = new Date(String(birthDate));
      if (Number.isNaN(d.getTime())) {
        return res.status(400).json({ message: 'Date de naissance invalide.' });
      }
      updates.birthDate = d;
    }
    if (sex != null) {
      const s = String(sex).trim().toLowerCase();
      if (s && s !== 'homme' && s !== 'femme') {
        return res.status(400).json({ message: 'Sexe invalide (homme/femme).' });
      }
      updates.sex = s || null;
    }
    if (phone != null) updates.phone = encrypt(String(phone).trim());
    if (addressExact != null) updates.addressExact = encrypt(String(addressExact).trim());
    if (country != null) updates.country = encrypt(String(country).trim());
    if (email != null) {
      const e = String(email).trim().toLowerCase();
      if (!isValidEmailFormat(e)) {
        return res.status(400).json({ message: 'Format d\'email invalide.' });
      }
      const existing = await Patient.findOne({ emailHash: hashEmail(e) }).select('_id').lean();
      if (existing && String(existing._id) !== String(patientId)) {
        return res.status(409).json({ message: 'Email déjà utilisé.' });
      }
      updates.email = encrypt(e);
      updates.emailHash = hashEmail(e);
    }

    if (bloodGroup !== undefined) {
      const bg = String(bloodGroup ?? '').trim();
      updates.bloodGroup = bg || null;
    }
    if (weightKg !== undefined) {
      if (weightKg === null || weightKg === '') {
        updates.weightKg = null;
      } else {
        const w = Number(weightKg);
        if (Number.isNaN(w) || w < 1 || w > 500) {
          return res.status(400).json({ message: 'Poids invalide (1–500 kg).' });
        }
        updates.weightKg = w;
      }
    }
    if (heightCm !== undefined) {
      if (heightCm === null || heightCm === '') {
        updates.heightCm = null;
      } else {
        const h = Number(heightCm);
        if (Number.isNaN(h) || h < 30 || h > 280) {
          return res.status(400).json({ message: 'Taille invalide (30–280 cm).' });
        }
        updates.heightCm = h;
      }
    }
    if (knownAllergies !== undefined) {
      const a = String(knownAllergies ?? '').trim();
      updates.knownAllergies = a ? encrypt(a) : null;
    }

    const patient = await Patient.findByIdAndUpdate(
      patientId,
      updates,
      { returnDocument: 'after', runValidators: false },
    );
    if (!patient) {
      return res.status(404).json({ message: 'Patient introuvable.' });
    }
    return res.json({
      message: 'Profil mis à jour.',
      patient: {
        ...decryptPatient(patient),
        id: patient._id.toString(),
        birthDate: patient.birthDate || null,
        sex: patient.sex || null,
        photoPath: patient.photoPath ?? null,
        bloodGroup: patient.bloodGroup ? String(patient.bloodGroup).trim() || null : null,
        weightKg: patient.weightKg != null ? Number(patient.weightKg) : null,
        heightCm: patient.heightCm != null ? Number(patient.heightCm) : null,
        knownAllergies: patient.knownAllergies
          ? decrypt(patient.knownAllergies) ?? ''
          : '',
      },
    });
  } catch (err) {
    console.error('Erreur PATCH /patient/:patientId/profile', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function uploadPatientPhoto(req, res) {
  try {
    const { patientId } = req.params;
    if (!mongoose.Types.ObjectId.isValid(patientId)) {
      return res.status(400).json({ message: 'patientId invalide.' });
    }
    if (!req.file) {
      return res.status(400).json({ message: 'Fichier photo requis.' });
    }
    if (!isCloudinaryConfigured) {
      return res.status(503).json({
        message:
          'Stockage cloud non configuré. Ajoutez CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY et CLOUDINARY_API_SECRET dans .env.',
      });
    }

    const existing = await Patient.findById(patientId).select('photoPath photoCloudinaryPublicId');
    if (!existing) {
      return res.status(404).json({ message: 'Patient introuvable.' });
    }

    const resourceType = resourceTypeFromMimetype(req.file.mimetype);
    const cloudUpload = await uploadFileToCloudinary(
      req.file.path,
      'telemedecine/patients',
      resourceType,
    );
    if (!cloudUpload?.url || !cloudUpload.publicId) {
      return res.status(500).json({ message: 'Échec upload vers le stockage cloud.' });
    }

    const oldPublicId =
      existing.photoCloudinaryPublicId ||
      tryParseCloudinaryImagePublicId(existing.photoPath);
    if (oldPublicId) {
      await destroyByPublicId(oldPublicId, 'image');
    }

    const patient = await Patient.findByIdAndUpdate(
      patientId,
      {
        photoPath: cloudUpload.url,
        photoCloudinaryPublicId: cloudUpload.publicId,
      },
      { returnDocument: 'after', runValidators: false },
    );
    if (!patient) {
      return res.status(404).json({ message: 'Patient introuvable.' });
    }
    return res.status(201).json({
      message: 'Photo mise à jour.',
      photoPath: patient.photoPath,
    });
  } catch (err) {
    console.error('Erreur POST /patient/:patientId/photo', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  } finally {
    if (req.file?.path) {
      try {
        await fs.unlink(req.file.path);
      } catch (_) {}
    }
  }
}

async function changePatientPassword(req, res) {
  try {
    const { patientId } = req.params;
    if (!mongoose.Types.ObjectId.isValid(patientId)) {
      return res.status(400).json({ message: 'patientId invalide.' });
    }
    const body = (req && typeof req.body === 'object' && req.body) ? req.body : {};
    const oldPassword = String(body.oldPassword || '');
    const newPassword = String(body.newPassword || '');
    if (!oldPassword || !newPassword) {
      return res.status(400).json({ message: 'Ancien et nouveau mot de passe requis.' });
    }
    const pwdErr = assertPasswordMin8(newPassword);
    if (pwdErr) {
      return res.status(400).json({ message: pwdErr });
    }
    if (oldPassword === newPassword) {
      return res.status(400).json({ message: 'Le nouveau mot de passe doit être différent de l\'ancien.' });
    }

    const patient = await Patient.findById(patientId).select('passwordHash');
    if (!patient) {
      return res.status(404).json({ message: 'Patient introuvable.' });
    }
    const match = await bcrypt.compare(oldPassword, patient.passwordHash);
    if (!match) {
      return res.status(401).json({ message: 'Ancien mot de passe incorrect.' });
    }

    const passwordHash = await bcrypt.hash(newPassword, 10);
    await Patient.findByIdAndUpdate(patientId, { passwordHash }, { runValidators: false });

    return res.json({ message: 'Mot de passe mis à jour.' });
  } catch (err) {
    console.error('Erreur POST /patient/:patientId/change-password', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

module.exports = {
  getPatientConversations,
  getPatientScheduledTeleconsults,
  getPatientTeleconsultRequests,
  getPatientProfile,
  patchPatientName,
  patchPatientProfile,
  uploadPatientPhoto,
  changePatientPassword,
};
