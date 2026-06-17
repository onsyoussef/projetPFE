const mongoose = require('mongoose');
const fs = require('fs/promises');
const path = require('path');
const bcrypt = require('bcrypt');

const Doctor = require('../models/Doctor');
const Conversation = require('../models/Conversation');
const WaitingRoomSession = require('../models/WaitingRoomSession');
const TeleconsultationRequest = require('../models/TeleconsultationRequest');
const TeleconsultationForm = require('../models/TeleconsultationForm');
const Message = require('../models/Message');

const {
  uploadFileToCloudinary,
  isConfigured: isCloudinaryConfigured,
  resourceTypeFromMimetype,
  destroyByPublicId,
  tryParseCloudinaryImagePublicId,
} = require(path.join(__dirname, '..', 'config', 'cloudinaryConfig'));

const { haversineKm } = require('../services/geoService');
const { buildDoctorAgendaListFromRendezVous } = require('../services/rendezvousService');
const { decrypt, encrypt, hashEmail, decryptPatient, decryptDoctor } = require('../services/cryptoService');
const {
  escapeRegex,
  getEffectiveDoctorStatus,
  patientPhotoPathFromPopulated,
  normalizedTeleconsultFormStatus,
  teleconsultConversationIdsForDoctor,
  teleconsultRequestDoctorScope,
  teleconsultFormDoctorScope,
  assertPasswordMin8,
} = require('../services/utilsService');
const { emitToConversation } = require('../services/realtimeGateway');

async function getDoctorConversations(req, res) {
  try {
    const { doctorId, filter } = req.query;
    if (!doctorId) {
      return res.status(400).json({ message: 'doctorId requis.' });
    }
    const convos = await Conversation.find({ doctor: doctorId })
      .populate('patient', 'fullName _id photoPath')
      .sort({ updatedAt: -1 })
      .lean();

    const convIds = convos.map((c) => c._id);
    const convosWithDemande = new Set(
      (await Message.find({
        conversation: { $in: convIds },
        type: 'request_teleconsult',
      })
        .select('conversation')
        .lean())
        .map((m) => m.conversation?.toString())
        .filter(Boolean),
    );
    const convosWithFormulaire = new Set(
      (await Message.find({
        conversation: { $in: convIds },
        type: 'form_teleconsult',
      })
        .select('conversation')
        .lean())
        .map((m) => m.conversation?.toString())
        .filter(Boolean),
    );

    const lastMessages = await Message.aggregate([
      { $match: { conversation: { $in: convos.map((c) => c._id) } } },
      { $sort: { createdAt: -1 } },
      {
        $group: {
          _id: '$conversation',
          lastMessage: { $first: '$content' },
          lastMessageAt: { $first: '$createdAt' },
          lastFromType: { $first: '$fromType' },
          lastType: { $first: '$type' },
          lastPatientMessageAt: {
            $max: { $cond: [{ $eq: ['$fromType', 'patient'] }, '$createdAt', null] },
          },
          lastDoctorMessageAt: {
            $max: { $cond: [{ $eq: ['$fromType', 'doctor'] }, '$createdAt', null] },
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

    let list = convos.map((c) => {
      const pid = c.patient?._id?.toString() ?? '';
      const cid = c._id.toString();
      const tags = [];
      if (convosWithDemande.has(cid)) tags.push('demande');
      if (convosWithFormulaire.has(cid)) tags.push('formulaire');
      const last = lastByConv.get(cid);
      const hasUnreadFromPatient = !!(
        last?.lastPatientAt &&
        (!last?.lastDoctorAt || new Date(last.lastPatientAt) > new Date(last.lastDoctorAt))
      );
      return {
        conversationId: cid,
        patientId: pid,
        patientName: decrypt(c.patient?.fullName) ?? 'Patient',
        patientPhotoPath: c.patient?.photoPath ?? null,
        updatedAt: c.updatedAt,
        lastMessage: last?.content ?? null,
        lastMessageAt: last?.at ?? c.updatedAt,
        lastMessageFromType: last?.fromType ?? null,
        lastMessageType: last?.type ?? null,
        hasUnreadFromPatient,
        unreadCount: hasUnreadFromPatient ? 1 : 0,
        tags,
      };
    });

    const filterVal = String(filter || 'all').toLowerCase();
    if (filterVal === 'demande') {
      list = list.filter((item) => item.tags.includes('demande'));
    }
    return res.json({ conversations: list });
  } catch (err) {
    console.error('Erreur GET /doctor/conversations', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getDoctorScheduledTeleconsults(req, res) {
  try {
    const { doctorId } = req.params;
    if (!mongoose.Types.ObjectId.isValid(doctorId)) {
      return res.status(400).json({ message: 'doctorId invalide.' });
    }
    const rows = await buildDoctorAgendaListFromRendezVous(doctorId);
    const slots = rows.map((r) => ({
      messageId: null,
      rendezvousId: r.rendezvousId,
      conversationId: r.conversationId,
      patientId: r.patientId,
      patientName: r.patientNom,
      patientPhotoPath: r.patientPhotoPath,
      scheduledAt: r.dateHeure,
    }));
    return res.json({ slots });
  } catch (err) {
    console.error('Erreur GET /doctor/:doctorId/scheduled-teleconsults', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function uploadDoctorPhoto(req, res) {
  try {
    const { doctorId } = req.params;
    if (!mongoose.Types.ObjectId.isValid(doctorId)) {
      return res.status(400).json({ message: 'doctorId invalide.' });
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
    const existing = await Doctor.findById(doctorId).select('photoPath photoCloudinaryPublicId');
    if (!existing) {
      return res.status(404).json({ message: 'Médecin introuvable.' });
    }

    const resourceType = resourceTypeFromMimetype(req.file.mimetype);
    const cloudUpload = await uploadFileToCloudinary(req.file.path, 'telemedecine/doctors', resourceType);
    if (!cloudUpload?.url || !cloudUpload.publicId) {
      return res.status(500).json({ message: 'Échec upload vers le stockage cloud.' });
    }

    const oldPublicId =
      existing.photoCloudinaryPublicId || tryParseCloudinaryImagePublicId(existing.photoPath);
    if (oldPublicId) {
      await destroyByPublicId(oldPublicId, 'image');
    }

    const doctor = await Doctor.findByIdAndUpdate(
      doctorId,
      {
        photoPath: cloudUpload.url,
        photoCloudinaryPublicId: cloudUpload.publicId,
      },
      { returnDocument: 'after', runValidators: false },
    );
    if (!doctor) {
      return res.status(404).json({ message: 'Médecin introuvable.' });
    }
    return res.status(201).json({
      message: 'Photo mise à jour.',
      photoPath: doctor.photoPath,
    });
  } catch (err) {
    console.error('Erreur POST /doctor/:doctorId/photo', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  } finally {
    if (req.file?.path) {
      try {
        await fs.unlink(req.file.path);
      } catch (_) {}
    }
  }
}

async function listDoctors(req, res) {
  try {
    const { specialty, name, governorate, latitude, longitude } = req.query;
    const filter = { verificationStatus: 'verified' };

    const specialtyQ = specialty && String(specialty).trim() ? String(specialty).trim() : '';
    const nameQ = name && String(name).trim() ? String(name).trim() : '';
    const governorateQ = governorate && String(governorate).trim() ? String(governorate).trim() : '';

    const lat = latitude != null && latitude !== '' ? parseFloat(latitude) : null;
    const lon = longitude != null && longitude !== '' ? parseFloat(longitude) : null;
    const useLocation = lat != null && lon != null && !Number.isNaN(lat) && !Number.isNaN(lon);

    const doctors = await Doctor.find(filter)
      .select('fullName specialty governorate address latitude longitude orderNumber country status statusUpdatedAt workingHoursStart workingHoursEnd availableDays photoPath hospitalOrClinic yearsExperience')
      .sort(useLocation ? {} : { fullName: 1 })
      .lean();

    let result = doctors.map((d) => {
      const doc = {
        id: d._id.toString(),
        fullName: decrypt(d.fullName),
        specialty: decrypt(d.specialty),
        governorate: decrypt(d.governorate),
        address: decrypt(d.address) || null,
        orderNumber: d.orderNumber || null,
        country: decrypt(d.country) || null,
        photoPath: d.photoPath || null,
        hospitalOrClinic: d.hospitalOrClinic || null,
        yearsExperience: typeof d.yearsExperience === 'number' ? d.yearsExperience : 0,
        status: getEffectiveDoctorStatus(d),
        statusUpdatedAt: d.statusUpdatedAt || null,
      };
      if (useLocation && d.latitude != null && d.longitude != null) {
        doc.distanceKm = Math.round(haversineKm(lat, lon, d.latitude, d.longitude) * 10) / 10;
      } else if (useLocation) {
        doc.distanceKm = null;
      }
      return doc;
    });

    if (nameQ) {
      const re = new RegExp(escapeRegex(nameQ), 'i');
      result = result.filter((d) => re.test(String(d.fullName || '')));
    }
    if (specialtyQ) {
      const re = new RegExp(escapeRegex(specialtyQ), 'i');
      result = result.filter((d) => re.test(String(d.specialty || '')));
    }
    if (governorateQ) {
      const re = new RegExp(`^${escapeRegex(governorateQ)}$`, 'i');
      result = result.filter((d) => re.test(String(d.governorate || '')));
    }

    if (useLocation) {
      result = result.sort((a, b) => {
        const da = a.distanceKm == null ? Infinity : a.distanceKm;
        const db = b.distanceKm == null ? Infinity : b.distanceKm;
        return da - db;
      });
    }

    return res.json({ doctors: result });
  } catch (err) {
    console.error('Erreur /doctors', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getDoctorProfile(req, res) {
  try {
    const { doctorId } = req.params;
    if (!mongoose.Types.ObjectId.isValid(doctorId)) {
      return res.status(400).json({ message: 'doctorId invalide.' });
    }
    const doctor = await Doctor.findById(doctorId).lean();
    if (!doctor) {
      return res.status(404).json({ message: 'Médecin introuvable.' });
    }
    return res.json({
      id: doctor._id.toString(),
      fullName: decrypt(doctor.fullName),
      email: decrypt(doctor.email),
      phone: decrypt(doctor.phone) ?? '',
      specialty: decrypt(doctor.specialty),
      governorate: decrypt(doctor.governorate),
      address: decrypt(doctor.address) ?? '',
      yearsExperience: typeof doctor.yearsExperience === 'number' ? doctor.yearsExperience : 0,
      hospitalOrClinic: doctor.hospitalOrClinic ?? '',
      orderNumber: doctor.orderNumber ?? '',
      country: decrypt(doctor.country) ?? '',
      photoPath: doctor.photoPath ?? null,
    });
  } catch (err) {
    console.error('Erreur GET /doctor/:doctorId/profile', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function patchDoctorName(req, res) {
  try {
    const { doctorId } = req.params;
    const { fullName } = req.body || {};
    if (!fullName || !String(fullName).trim()) {
      return res.status(400).json({ message: 'fullName requis.' });
    }
    if (!mongoose.Types.ObjectId.isValid(doctorId)) {
      return res.status(400).json({ message: 'doctorId invalide.' });
    }
    const doctor = await Doctor.findByIdAndUpdate(
      doctorId,
      { fullName: encrypt(String(fullName).trim()) },
      { returnDocument: 'after', runValidators: false },
    );
    if (!doctor) {
      return res.status(404).json({ message: 'Médecin introuvable.' });
    }
    return res.json({
      message: 'Nom mis à jour.',
      fullName: decrypt(doctor.fullName),
    });
  } catch (err) {
    console.error('Erreur PATCH /doctor/:doctorId/name', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function patchDoctorProfile(req, res) {
  try {
    const { doctorId } = req.params;
    if (!mongoose.Types.ObjectId.isValid(doctorId)) {
      return res.status(400).json({ message: 'doctorId invalide.' });
    }
    const body = req.body || {};
    const doctor = await Doctor.findById(doctorId);
    if (!doctor) {
      return res.status(404).json({ message: 'Médecin introuvable.' });
    }
    if (body.fullName != null && String(body.fullName).trim()) {
      doctor.fullName = encrypt(String(body.fullName).trim());
    }
    if (body.specialty != null && String(body.specialty).trim()) {
      doctor.specialty = encrypt(String(body.specialty).trim());
    }
    if (body.governorate != null && String(body.governorate).trim()) {
      doctor.governorate = encrypt(String(body.governorate).trim());
    }
    if (body.address != null) {
      doctor.address = encrypt(String(body.address).trim());
    }
    if (body.phone != null) {
      doctor.phone = encrypt(String(body.phone).trim());
    }
    if (body.orderNumber != null) {
      doctor.orderNumber = String(body.orderNumber).trim() || undefined;
    }
    if (body.country != null) {
      doctor.country = body.country != null && String(body.country).trim()
        ? encrypt(String(body.country).trim())
        : undefined;
    }
    if (body.yearsExperience != null) {
      const n = parseInt(String(body.yearsExperience), 10);
      if (Number.isNaN(n) || n < 0 || n > 80) {
        return res.status(400).json({ message: 'Années d\'expérience invalides.' });
      }
      doctor.yearsExperience = n;
    }
    if (body.hospitalOrClinic != null) {
      doctor.hospitalOrClinic = String(body.hospitalOrClinic).trim() || undefined;
    }
    await doctor.save();
    return res.json({
      id: doctor._id.toString(),
      fullName: decrypt(doctor.fullName),
      email: decrypt(doctor.email),
      phone: decrypt(doctor.phone) ?? '',
      specialty: decrypt(doctor.specialty),
      governorate: decrypt(doctor.governorate),
      address: decrypt(doctor.address) ?? '',
      yearsExperience: typeof doctor.yearsExperience === 'number' ? doctor.yearsExperience : 0,
      hospitalOrClinic: doctor.hospitalOrClinic ?? '',
      orderNumber: doctor.orderNumber ?? '',
      country: decrypt(doctor.country) ?? '',
      photoPath: doctor.photoPath ?? null,
    });
  } catch (err) {
    console.error('Erreur PATCH /doctor/:doctorId/profile', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getDoctorPublic(req, res) {
  try {
    const { doctorId } = req.params;
    const doctor = await Doctor.findById(doctorId)
      .select(
        'fullName specialty status statusUpdatedAt absenceMessage autoReplyEnabled workingHoursStart workingHoursEnd availableDays photoPath hospitalOrClinic governorate address yearsExperience verificationStatus',
      )
      .lean();
    if (!doctor) {
      return res.status(404).json({ message: 'Médecin introuvable.' });
    }
    if (
      req.auth?.role === 'patient' &&
      (doctor.verificationStatus || 'pending') !== 'verified'
    ) {
      return res.status(404).json({ message: 'Médecin introuvable.' });
    }
    const effectiveStatus = getEffectiveDoctorStatus(doctor);
    return res.json({
      id: doctor._id.toString(),
      fullName: decrypt(doctor.fullName),
      specialty: decrypt(doctor.specialty) || '',
      status: effectiveStatus,
      statusUpdatedAt: doctor.statusUpdatedAt || null,
      absenceMessage: doctor.absenceMessage || '',
      autoReplyEnabled: !!doctor.autoReplyEnabled,
      photoPath: doctor.photoPath ?? null,
      hospitalOrClinic: doctor.hospitalOrClinic ?? '',
      governorate: decrypt(doctor.governorate) ?? '',
      address: decrypt(doctor.address) ?? '',
      yearsExperience: typeof doctor.yearsExperience === 'number' ? doctor.yearsExperience : 0,
    });
  } catch (err) {
    console.error('Erreur GET /doctor/:doctorId', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getDoctorSettings(req, res) {
  try {
    const { doctorId } = req.params;
    const doctor = await Doctor.findById(doctorId).lean();
    if (!doctor) {
      return res.status(404).json({ message: 'Médecin introuvable.' });
    }
    const workingHoursStart = doctor.workingHoursStart ?? '09:00';
    const workingHoursEnd = doctor.workingHoursEnd ?? '18:00';
    let workingTimeSlots = Array.isArray(doctor.workingTimeSlots) ? doctor.workingTimeSlots : [];
    if (workingTimeSlots.length === 0) {
      workingTimeSlots = [{ start: workingHoursStart, end: workingHoursEnd }];
    }
    return res.json({
      workingHoursStart,
      workingHoursEnd,
      workingTimeSlots,
      availableDays: Array.isArray(doctor.availableDays) ? doctor.availableDays : [1, 2, 3, 4, 5],
      absenceMessage: doctor.absenceMessage ?? '',
      autoReplyEnabled: !!doctor.autoReplyEnabled,
      absenceEmergencyOnly: !!doctor.absenceEmergencyOnly,
      status: doctor.status ?? 'available',
      statusUpdatedAt: doctor.statusUpdatedAt || null,
    });
  } catch (err) {
    console.error('Erreur GET /doctor/:doctorId/settings', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function patchDoctorSettings(req, res) {
  try {
    const { doctorId } = req.params;
    const body = req.body || {};
    const doctor = await Doctor.findById(doctorId);
    if (!doctor) {
      return res.status(404).json({ message: 'Médecin introuvable.' });
    }
    if (Array.isArray(body.workingTimeSlots) && body.workingTimeSlots.length > 0) {
      doctor.workingTimeSlots = body.workingTimeSlots.map((slot) => ({
        start: String(slot.start || '09:00'),
        end: String(slot.end || '12:00'),
      }));
      doctor.workingHoursStart = doctor.workingTimeSlots[0].start;
      doctor.workingHoursEnd = doctor.workingTimeSlots[doctor.workingTimeSlots.length - 1].end;
    } else {
      if (body.workingHoursStart != null) doctor.workingHoursStart = String(body.workingHoursStart);
      if (body.workingHoursEnd != null) doctor.workingHoursEnd = String(body.workingHoursEnd);
      doctor.workingTimeSlots = [{
        start: doctor.workingHoursStart ?? '09:00',
        end: doctor.workingHoursEnd ?? '18:00',
      }];
    }
    if (Array.isArray(body.availableDays)) doctor.availableDays = body.availableDays;
    if (body.absenceMessage != null) doctor.absenceMessage = String(body.absenceMessage);
    if (typeof body.autoReplyEnabled === 'boolean') doctor.autoReplyEnabled = body.autoReplyEnabled;
    if (typeof body.absenceEmergencyOnly === 'boolean') {
      doctor.absenceEmergencyOnly = body.absenceEmergencyOnly;
    }
    await doctor.save();
    const workingTimeSlots = Array.isArray(doctor.workingTimeSlots) && doctor.workingTimeSlots.length > 0
      ? doctor.workingTimeSlots
      : [{ start: doctor.workingHoursStart ?? '09:00', end: doctor.workingHoursEnd ?? '18:00' }];
    return res.json({
      workingHoursStart: doctor.workingHoursStart,
      workingHoursEnd: doctor.workingHoursEnd,
      workingTimeSlots,
      availableDays: doctor.availableDays,
      absenceMessage: doctor.absenceMessage,
      autoReplyEnabled: doctor.autoReplyEnabled,
      absenceEmergencyOnly: doctor.absenceEmergencyOnly,
      status: doctor.status,
      statusUpdatedAt: doctor.statusUpdatedAt,
    });
  } catch (err) {
    console.error('Erreur PATCH /doctor/:doctorId/settings', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function patchDoctorStatus(req, res) {
  try {
    const { doctorId } = req.params;
    const { status } = req.body || {};
    const valid = ['available', 'busy', 'unavailable'];
    if (!valid.includes(status)) {
      return res.status(400).json({ message: 'Statut invalide. Valeurs: available, busy, unavailable.' });
    }
    const doctor = await Doctor.findById(doctorId);
    if (!doctor) {
      return res.status(404).json({ message: 'Médecin introuvable.' });
    }
    doctor.status = status;
    doctor.statusUpdatedAt = new Date();
    await doctor.save();
    const convos = await Conversation.find({ doctor: doctorId }).select('_id').lean();
    for (const c of convos) {
      const convId = c && c._id ? String(c._id) : '';
      if (!convId) continue;
      emitToConversation(convId, 'doctor:status_updated', {
        conversationId: convId,
        doctorId: String(doctorId),
        status: doctor.status,
        statusUpdatedAt: doctor.statusUpdatedAt,
        absenceMessage: doctor.absenceMessage || null,
        autoReplyEnabled: doctor.autoReplyEnabled === true,
        photoPath: doctor.photoPath || null,
      });
    }
    return res.json({
      status: doctor.status,
      statusUpdatedAt: doctor.statusUpdatedAt,
    });
  } catch (err) {
    console.error('Erreur PATCH /doctor/:doctorId/status', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getDoctorWaitingRooms(req, res) {
  try {
    const { doctorId } = req.params;
    if (!doctorId || !mongoose.Types.ObjectId.isValid(String(doctorId))) {
      return res.status(400).json({ message: 'doctorId invalide.' });
    }
    const rows = await WaitingRoomSession.find({ doctor: doctorId }).sort({ enteredAt: -1 }).lean();
    const items = rows.map((r) => ({
      conversationId: String(r.conversation),
      patientId: String(r.patient),
      patientName: r.patientName || 'Patient',
      enteredAt: new Date(r.enteredAt).toISOString(),
    }));
    return res.json({ items });
  } catch (err) {
    console.error('Erreur GET /doctor/:doctorId/waiting-rooms', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getDoctorTeleconsultStats(req, res) {
  try {
    const { doctorId } = req.params;
    if (!mongoose.Types.ObjectId.isValid(doctorId)) {
      return res.status(400).json({ message: 'doctorId invalide.' });
    }
    const convIds = await teleconsultConversationIdsForDoctor(doctorId);
    const rScope = teleconsultRequestDoctorScope(doctorId, convIds);
    const fScope = teleconsultFormDoctorScope(doctorId, convIds);
    const [rqP, rqA, rqR, forms] = await Promise.all([
      TeleconsultationRequest.countDocuments({ $and: [rScope, { status: 'pending' }] }),
      TeleconsultationRequest.countDocuments({ $and: [rScope, { status: 'accepted' }] }),
      TeleconsultationRequest.countDocuments({ $and: [rScope, { status: 'rejected' }] }),
      TeleconsultationForm.find(fScope).select('status workflowStatus').lean(),
    ]);
    let fp = 0;
    let fa = 0;
    let fr = 0;
    let fws = 0;
    let fwr = 0;
    let awaitingDoctorAction = 0;
    for (const f of forms) {
      const st = normalizedTeleconsultFormStatus(f);
      const wf = f.workflowStatus || 'pending';
      if (st === 'pending') {
        fp += 1;
        awaitingDoctorAction += 1;
      } else if (st === 'accepted') {
        fa += 1;
        if (wf === 'pending') awaitingDoctorAction += 1;
      } else if (st === 'rejected') {
        fr += 1;
      }
      if (wf === 'scheduled') fws += 1;
      if (wf === 'replied') fwr += 1;
    }
    return res.json({
      requests: { pending: rqP, accepted: rqA, rejected: rqR },
      forms: {
        pending: fp,
        accepted: fa,
        rejected: fr,
        workflowScheduled: fws,
        workflowReplied: fwr,
        awaitingDoctorAction,
      },
    });
  } catch (err) {
    console.error('Erreur GET teleconsult-stats', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getDoctorTeleconsultRequests(req, res) {
  try {
    const { doctorId } = req.params;
    const statusQ = String(req.query.status || '').trim().toLowerCase();
    if (!mongoose.Types.ObjectId.isValid(doctorId)) {
      return res.status(400).json({ message: 'doctorId invalide.' });
    }
    const convos = await Conversation.find({ doctor: doctorId })
      .select('_id patient')
      .populate('patient', 'fullName photoPath')
      .lean();
    const convById = new Map(convos.map((c) => [c._id.toString(), c]));
    const convIds = convos.map((c) => c._id);
    const scope = teleconsultRequestDoctorScope(doctorId, convIds);
    const query =
      statusQ === 'pending' || statusQ === 'accepted' || statusQ === 'rejected'
        ? { $and: [scope, { status: statusQ }] }
        : scope;

    const requests = await TeleconsultationRequest.find(query)
      .populate('patient', 'fullName photoPath')
      .sort({ createdAt: -1 })
      .lean();

    const items = requests.map((r) => {
      let patientId = r.patient && r.patient._id ? String(r.patient._id) : '';
      let patientName = decrypt(r.patient && r.patient.fullName) || 'Patient';
      let patientPhotoPath = patientPhotoPathFromPopulated(r.patient);
      if (!patientId && r.conversation) {
        const c = convById.get(String(r.conversation));
        const p = c && c.patient;
        if (p && p._id) patientId = String(p._id);
        if ((p && p.fullName) || patientName === 'Patient') {
          patientName = decrypt(p && p.fullName) || patientName;
        }
        if (!patientPhotoPath) patientPhotoPath = patientPhotoPathFromPopulated(p);
      }
      return {
        id: String(r._id),
        conversationId: r.conversation ? String(r.conversation) : '',
        patientId,
        patientName,
        patientPhotoPath,
        motif: r.motif || '',
        letterBody: r.letterBody || '',
        rejectionMotif: r.rejectionMotif || '',
        status: r.status,
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
      };
    });
    return res.json({ items });
  } catch (err) {
    console.error('Erreur GET /doctor/:doctorId/teleconsult-requests', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getDoctorTeleconsultForms(req, res) {
  try {
    const { doctorId } = req.params;
    const statusQ = String(req.query.status || '').trim().toLowerCase();
    if (!mongoose.Types.ObjectId.isValid(doctorId)) {
      return res.status(400).json({ message: 'doctorId invalide.' });
    }
    const convos = await Conversation.find({ doctor: doctorId })
      .select('_id patient')
      .populate('patient', 'fullName photoPath')
      .lean();
    const convById = new Map(convos.map((c) => [c._id.toString(), c]));
    const convIds = convos.map((c) => c._id);
    const scope = teleconsultFormDoctorScope(doctorId, convIds);
    const query =
      statusQ === 'pending' || statusQ === 'accepted' || statusQ === 'rejected'
        ? { $and: [scope, { status: statusQ }] }
        : scope;

    const forms = await TeleconsultationForm.find(query)
      .populate('patient', 'fullName photoPath')
      .sort({ createdAt: -1 })
      .lean();

    const items = forms.map((f) => {
      let patientId = f.patient && f.patient._id ? String(f.patient._id) : '';
      let patientName = decrypt(f.patient && f.patient.fullName) || 'Patient';
      let patientPhotoPath = patientPhotoPathFromPopulated(f.patient);
      if (!patientId && f.conversation) {
        const c = convById.get(String(f.conversation));
        const p = c && c.patient;
        if (p && p._id) patientId = String(p._id);
        if ((p && p.fullName) || patientName === 'Patient') {
          patientName = decrypt(p && p.fullName) || patientName;
        }
        if (!patientPhotoPath) patientPhotoPath = patientPhotoPathFromPopulated(p);
      }
      const wf = f.workflowStatus || 'pending';
      const st = normalizedTeleconsultFormStatus(f);
      return {
        id: String(f._id),
        doctorId: f.doctor ? String(f.doctor) : '',
        patientId,
        patientName,
        patientPhotoPath,
        conversationId: f.conversation ? String(f.conversation) : '',
        motif: f.motif || '',
        symptomes: f.symptomes || '',
        traitements: f.traitements || '',
        allergies: f.allergies || '',
        dateDerniereConsultation: f.dateDerniereConsultation || null,
        attachments: Array.isArray(f.attachments) ? f.attachments : [],
        status: st,
        workflowStatus: wf,
        createdAt: f.createdAt,
        updatedAt: f.updatedAt,
      };
    });
    return res.json({ items });
  } catch (err) {
    console.error('Erreur GET teleconsult-forms', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function changeDoctorPassword(req, res) {
  try {
    const { doctorId } = req.params;
    if (!mongoose.Types.ObjectId.isValid(doctorId)) {
      return res.status(400).json({ message: 'doctorId invalide.' });
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

    const doctor = await Doctor.findById(doctorId).select('passwordHash');
    if (!doctor) {
      return res.status(404).json({ message: 'Médecin introuvable.' });
    }
    const match = await bcrypt.compare(oldPassword, doctor.passwordHash);
    if (!match) {
      return res.status(401).json({ message: 'Ancien mot de passe incorrect.' });
    }

    const passwordHash = await bcrypt.hash(newPassword, 10);
    await Doctor.findByIdAndUpdate(doctorId, { passwordHash }, { runValidators: false });

    return res.json({ message: 'Mot de passe mis à jour.' });
  } catch (err) {
    console.error('Erreur POST /doctor/:doctorId/change-password', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

module.exports = {
  listDoctors,
  getDoctorConversations,
  getDoctorScheduledTeleconsults,
  getDoctorProfile,
  patchDoctorName,
  patchDoctorProfile,
  uploadDoctorPhoto,
  getDoctorPublic,
  getDoctorSettings,
  patchDoctorSettings,
  patchDoctorStatus,
  getDoctorWaitingRooms,
  getDoctorTeleconsultStats,
  getDoctorTeleconsultRequests,
  getDoctorTeleconsultForms,
  changeDoctorPassword,
};
