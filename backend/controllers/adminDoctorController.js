const mongoose = require('mongoose');
const Doctor = require('../models/Doctor');
const { decrypt } = require('../services/cryptoService');
const { notifyDoctorVerificationDecision } = require('../services/doctorVerificationNotifyService');

function mapStatus(verificationStatus) {
  const s = verificationStatus || 'pending';
  if (s === 'verified') return 'approved';
  if (s === 'rejected') return 'rejected';
  return 'pending';
}

function mapAdminDoctor(d, extra = {}) {
  return {
    id: d._id.toString(),
    fullName: decrypt(d.fullName),
    email: decrypt(d.email),
    phone: decrypt(d.phone),
    specialty: decrypt(d.specialty),
    city: decrypt(d.governorate),
    governorate: decrypt(d.governorate),
    address: decrypt(d.address),
    country: decrypt(d.country),
    orderNumber: d.orderNumber || null,
    yearsExperience: typeof d.yearsExperience === 'number' ? d.yearsExperience : 0,
    hospitalOrClinic: d.hospitalOrClinic || null,
    diplomaPath: d.diplomaPath || null,
    photoPath: d.photoPath || null,
    birthdate: d.birthdate || null,
    status: mapStatus(d.verificationStatus),
    verificationStatus: d.verificationStatus || 'pending',
    rejectionReason: d.verificationRejectedReason || null,
    reviewedAt: d.verificationReviewedAt || null,
    createdAt: d.createdAt,
    updatedAt: d.updatedAt,
    ...extra,
  };
}

function buildStatusFilter(statusParam) {
  const status = String(statusParam || 'all').trim().toLowerCase();
  if (status === 'approved' || status === 'verified') return { verificationStatus: 'verified' };
  if (status === 'rejected') return { verificationStatus: 'rejected' };
  if (status === 'pending') return { verificationStatus: 'pending' };
  return {};
}

async function listDoctors(req, res) {
  try {
    const status = String(req.query.status || 'all').trim();
    const search = String(req.query.search || '').trim().toLowerCase();
    const page = Math.max(1, parseInt(String(req.query.page || '1'), 10) || 1);
    const pageSize = Math.min(50, Math.max(1, parseInt(String(req.query.pageSize || '10'), 10) || 10));

    const filter = buildStatusFilter(status);
    const doctors = await Doctor.find(filter)
      .select(
        'fullName email phone specialty governorate address country orderNumber yearsExperience hospitalOrClinic diplomaPath photoPath birthdate verificationStatus verificationRejectedReason verificationReviewedAt createdAt updatedAt',
      )
      .sort({ createdAt: -1 })
      .lean();

    let mapped = doctors.map((d) => mapAdminDoctor(d));
    if (search) {
      mapped = mapped.filter((d) => {
        const hay = `${d.fullName} ${d.email} ${d.specialty} ${d.city}`.toLowerCase();
        return hay.includes(search);
      });
    }

    const total = mapped.length;
    const start = (page - 1) * pageSize;
    const items = mapped.slice(start, start + pageSize);

    return res.json({
      doctors: items,
      total,
      page,
      pageSize,
    });
  } catch (err) {
    console.error('Erreur GET /admin/doctors', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getDoctorById(req, res) {
  try {
    const { doctorId } = req.params;
    if (!mongoose.Types.ObjectId.isValid(doctorId)) {
      return res.status(400).json({ message: 'Identifiant médecin invalide.' });
    }
    const doctor = await Doctor.findById(doctorId).lean();
    if (!doctor) {
      return res.status(404).json({ message: 'Médecin introuvable.' });
    }
    const documents = [];
    if (doctor.diplomaPath) {
      documents.push({
        id: 'diploma',
        label: 'Justificatif / diplôme',
        url: doctor.diplomaPath,
        type: 'diploma',
      });
    }
    return res.json({
      doctor: mapAdminDoctor(doctor, { documents }),
    });
  } catch (err) {
    console.error('Erreur GET /admin/doctors/:doctorId', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getDashboardStats(req, res) {
  try {
    const [total, pending, approved, rejected] = await Promise.all([
      Doctor.countDocuments({}),
      Doctor.countDocuments({ verificationStatus: 'pending' }),
      Doctor.countDocuments({ verificationStatus: 'verified' }),
      Doctor.countDocuments({ verificationStatus: 'rejected' }),
    ]);

    const recentPending = await Doctor.find({ verificationStatus: 'pending' })
      .select(
        'fullName email specialty governorate verificationStatus createdAt',
      )
      .sort({ createdAt: -1 })
      .limit(5)
      .lean();

    const recentReviewed = await Doctor.find({
      verificationStatus: { $in: ['verified', 'rejected'] },
      verificationReviewedAt: { $ne: null },
    })
      .select('fullName verificationStatus verificationReviewedAt')
      .sort({ verificationReviewedAt: -1 })
      .limit(8)
      .lean();

    const activity = recentReviewed.map((d) => ({
      id: d._id.toString(),
      doctorName: decrypt(d.fullName),
      action: d.verificationStatus === 'verified' ? 'approved' : 'rejected',
      at: d.verificationReviewedAt,
    }));

    return res.json({
      stats: { total, pending, approved, rejected },
      recentPending: recentPending.map((d) => mapAdminDoctor(d)),
      activity,
    });
  } catch (err) {
    console.error('Erreur GET /admin/dashboard/stats', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function patchDoctorVerification(req, res) {
  try {
    const { doctorId } = req.params;
    const status = String(req.body?.status || '').trim();
    const reason = req.body?.reason != null ? String(req.body.reason).trim() : '';

    if (!mongoose.Types.ObjectId.isValid(doctorId)) {
      return res.status(400).json({ message: 'Identifiant médecin invalide.' });
    }
    if (status !== 'verified' && status !== 'rejected') {
      return res.status(400).json({
        message: 'Statut invalide. Utilisez "verified" ou "rejected".',
      });
    }
    if (status === 'rejected' && !reason) {
      return res.status(400).json({ message: 'Motif de refus requis.' });
    }

    const update = {
      verificationStatus: status,
      verificationReviewedAt: new Date(),
      verificationRejectedReason: status === 'rejected' ? reason : null,
    };

    const doctor = await Doctor.findByIdAndUpdate(doctorId, update, {
      new: true,
      runValidators: true,
    }).lean();

    if (!doctor) {
      return res.status(404).json({ message: 'Médecin introuvable.' });
    }

    void notifyDoctorVerificationDecision(doctor, {
      status,
      reason: status === 'rejected' ? reason : null,
    }).catch((err) => {
      console.error('[VERIFY-NOTIFY] échec notification médecin:', err);
    });

    return res.json({
      message:
        status === 'verified'
          ? 'Compte médecin approuvé. Le médecin sera notifié par e-mail et notification.'
          : 'Inscription refusée. Le médecin sera notifié par e-mail et notification.',
      doctor: mapAdminDoctor(doctor),
    });
  } catch (err) {
    console.error('Erreur PATCH /admin/doctors/:doctorId/verification', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

module.exports = {
  listDoctors,
  getDoctorById,
  getDashboardStats,
  patchDoctorVerification,
};
