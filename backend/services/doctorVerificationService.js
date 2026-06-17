const Doctor = require('../models/Doctor');

const DOCTOR_VERIFICATION_MESSAGES = {
  pending:
    'Votre inscription est en attente de validation par un administrateur. Vous recevrez un accès après approbation.',
  rejected:
    'Votre demande d\'inscription a été refusée. Contactez le support si vous pensez qu\'il s\'agit d\'une erreur.',
};

function doctorVerificationHttpResponse(status) {
  if (status === 'verified') return null;
  const code =
    status === 'rejected' ? 'DOCTOR_REGISTRATION_REJECTED' : 'DOCTOR_PENDING_APPROVAL';
  const message =
    status === 'rejected'
      ? DOCTOR_VERIFICATION_MESSAGES.rejected
      : DOCTOR_VERIFICATION_MESSAGES.pending;
  return {
    status: 403,
    body: { message, code, verificationStatus: status || 'pending' },
  };
}

async function loadDoctorVerificationStatus(doctorId) {
  if (!doctorId) return null;
  const doctor = await Doctor.findById(doctorId).select('verificationStatus').lean();
  return doctor ? doctor.verificationStatus || 'pending' : null;
}

async function assertDoctorVerifiedForRequest(req, res) {
  if (!req.auth || req.auth.role !== 'doctor') return true;
  const status = await loadDoctorVerificationStatus(req.auth.sub);
  if (!status) {
    res.status(401).json({ message: 'Compte médecin introuvable.' });
    return false;
  }
  const block = doctorVerificationHttpResponse(status);
  if (block) {
    res.status(block.status).json(block.body);
    return false;
  }
  return true;
}

module.exports = {
  DOCTOR_VERIFICATION_MESSAGES,
  doctorVerificationHttpResponse,
  loadDoctorVerificationStatus,
  assertDoctorVerifiedForRequest,
};
