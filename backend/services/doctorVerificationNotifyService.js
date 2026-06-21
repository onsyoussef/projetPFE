const { decrypt } = require('./cryptoService');
const { sendDoctorVerificationDecisionEmail } = require('./emailService');
const { sendPushToUser } = require('./pushNotificationService');

/**
 * Informe le médecin (e-mail + push FCM si appareil enregistré) après approbation / refus admin.
 */
async function notifyDoctorVerificationDecision(
  doctorDoc,
  { status, reason, emailOverride, fullNameOverride } = {},
) {
  if (!doctorDoc) {
    return { emailSent: false, pushSent: false, errors: ['Médecin introuvable'] };
  }

  const approved = status === 'verified';
  const doctorId = String(doctorDoc._id);
  let email = String(emailOverride || '').trim();
  let fullName = String(fullNameOverride || '').trim() || 'Médecin';

  if (!email) {
    try {
      email = decrypt(doctorDoc.email) || '';
      fullName = decrypt(doctorDoc.fullName) || fullName;
    } catch (e) {
      console.error('[VERIFY-NOTIFY] déchiffrement:', e.message);
    }
  }

  email = email.trim().toLowerCase();

  const pushTitle = approved ? 'Compte approuvé' : 'Inscription refusée';
  const pushBody = approved
    ? 'Votre compte HeadsApp est validé. Vous pouvez vous connecter.'
    : `Votre inscription a été refusée. ${reason ? `Motif : ${reason}` : ''}`.trim();

  const errors = [];
  let emailSent = false;
  let pushSent = false;

  if (email && email.includes('@')) {
    try {
      await sendDoctorVerificationDecisionEmail({
        toEmail: email,
        fullName,
        approved,
        rejectionReason: reason,
      });
      emailSent = true;
      console.log(
        `[VERIFY-NOTIFY] e-mail envoyé à ${email} (${approved ? 'approuvé' : 'refusé'})`,
      );
    } catch (err) {
      const msg = err?.message || String(err);
      errors.push(`E-mail : ${msg}`);
      console.error('[VERIFY-NOTIFY] échec e-mail:', msg);
    }
  } else {
    errors.push('E-mail médecin indisponible');
    console.warn('[VERIFY-NOTIFY] e-mail médecin indisponible pour', doctorId);
  }

  try {
    await sendPushToUser({
      userId: doctorId,
      role: 'doctor',
      appName: 'doctor',
      title: pushTitle,
      body: pushBody,
      data: {
        type: 'doctor_verification',
        status: approved ? 'approved' : 'rejected',
        doctorId,
        rejectionReason: reason || '',
      },
    });
    pushSent = true;
  } catch (err) {
    const msg = err?.message || String(err);
    errors.push(`Push : ${msg}`);
    console.warn('[VERIFY-NOTIFY] push ignoré:', msg);
  }

  return { emailSent, pushSent, errors };
}

module.exports = { notifyDoctorVerificationDecision };
