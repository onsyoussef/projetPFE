const { decrypt } = require('./cryptoService');
const { sendDoctorVerificationDecisionEmail } = require('./emailService');
const { sendPushToUser } = require('./pushNotificationService');

/**
 * Informe le médecin (e-mail + push FCM si appareil enregistré) après approbation / refus admin.
 * N'interrompt pas la réponse API en cas d'échec d'envoi.
 */
async function notifyDoctorVerificationDecision(doctorDoc, { status, reason }) {
  if (!doctorDoc) return;

  const approved = status === 'verified';
  const doctorId = String(doctorDoc._id);
  let email = '';
  let fullName = 'Médecin';
  try {
    email = decrypt(doctorDoc.email) || '';
    fullName = decrypt(doctorDoc.fullName) || fullName;
  } catch (e) {
    console.error('[VERIFY-NOTIFY] déchiffrement:', e.message);
  }

  const pushTitle = approved ? 'Compte approuvé' : 'Inscription refusée';
  const pushBody = approved
    ? 'Votre compte HeadsApp est validé. Vous pouvez vous connecter.'
    : `Votre inscription a été refusée. ${reason ? `Motif : ${reason}` : ''}`.trim();

  const results = await Promise.allSettled([
    email
      ? sendDoctorVerificationDecisionEmail({
          toEmail: email,
          fullName,
          approved,
          rejectionReason: reason,
        })
      : Promise.reject(new Error('E-mail médecin indisponible')),
    sendPushToUser({
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
    }),
  ]);

  for (const r of results) {
    if (r.status === 'rejected') {
      console.warn('[VERIFY-NOTIFY]', r.reason?.message || r.reason);
    }
  }
  if (results[0]?.status === 'fulfilled') {
    console.log(`[VERIFY-NOTIFY] e-mail envoyé à ${email} (${approved ? 'approuvé' : 'refusé'})`);
  }
}

module.exports = { notifyDoctorVerificationDecision };
