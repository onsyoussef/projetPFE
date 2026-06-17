const nodemailer = require('nodemailer');
function sendResetCodeEmail(toEmail, code) {
  const smtpUser = process.env.SMTP_USER;
  const smtpPass = process.env.SMTP_PASS;

  if (!smtpUser || !smtpPass) {
    return Promise.reject(
      new Error(
        'Envoi d\'email non configuré. Créez un fichier .env avec SMTP_USER et SMTP_PASS (ex. Gmail avec mot de passe d\'application). Voir .env.example.'
      )
    );
  }

  const transporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST || 'smtp.gmail.com',
    port: parseInt(process.env.SMTP_PORT || '587', 10),
    secure: false,
    auth: { user: smtpUser, pass: smtpPass },
  });

  return transporter.sendMail({
    from: process.env.SMTP_FROM || smtpUser,
    to: toEmail,
    subject: 'Code de réinitialisation - Télémedecine',
    text: `Votre code de réinitialisation est : ${code}\n\nIl est valide 15 minutes.`,
    html: `<p>Votre code de réinitialisation est : <strong>${code}</strong></p><p>Il est valide 15 minutes.</p>`,
  }).catch((err) => {
    console.error('Erreur envoi email:', err.message);
    throw err;
  });
}

function buildTransporter() {
  const smtpUser = process.env.SMTP_USER;
  const smtpPass = process.env.SMTP_PASS;
  if (!smtpUser || !smtpPass) {
    throw new Error(
      'Envoi d\'email non configuré. Définissez SMTP_USER et SMTP_PASS dans backend/.env.',
    );
  }
  return nodemailer.createTransport({
    host: process.env.SMTP_HOST || 'smtp.gmail.com',
    port: parseInt(process.env.SMTP_PORT || '587', 10),
    secure: false,
    auth: { user: smtpUser, pass: smtpPass },
  });
}

/**
 * Notifie le médecin après décision admin (compte approuvé ou refusé).
 */
function sendDoctorVerificationDecisionEmail({ toEmail, fullName, approved, rejectionReason }) {
  const smtpUser = process.env.SMTP_USER;
  const smtpPass = process.env.SMTP_PASS;
  if (!smtpUser || !smtpPass) {
    return Promise.reject(
      new Error('Envoi d\'email non configuré (SMTP_USER / SMTP_PASS).'),
    );
  }

  const name = String(fullName || 'Docteur').trim() || 'Docteur';
  const subject = approved
    ? 'HeadsApp — Votre compte médecin est approuvé'
    : 'HeadsApp — Décision sur votre inscription';

  const intro = approved
    ? `Bonjour ${name},<br/><br/>Bonne nouvelle : un administrateur a <strong>approuvé</strong> votre inscription sur HeadsApp.`
    : `Bonjour ${name},<br/><br/>Nous sommes au regret de vous informer que votre demande d'inscription sur HeadsApp a été <strong>refusée</strong>.`;

  const nextSteps = approved
    ? `<p style="margin:16px 0 0;color:#1A202C;">Vous pouvez dès maintenant ouvrir l'application médecin HeadsApp et vous connecter avec l'adresse e-mail utilisée lors de l'inscription.</p>`
    : `<p style="margin:16px 0 0;color:#1A202C;"><strong>Motif :</strong> ${String(rejectionReason || 'Non précisé').replace(/</g, '&lt;')}</p>
       <p style="margin:12px 0 0;color:#718096;">Pour toute question, contactez le support HeadsApp.</p>`;

  const html = `
    <div style="font-family:Inter,Arial,sans-serif;max-width:560px;margin:0 auto;padding:24px;">
      <div style="background:#1A6B8A;color:#fff;padding:16px 20px;border-radius:12px 12px 0 0;">
        <strong style="font-size:18px;">HeadsApp</strong>
        <span style="opacity:0.9;font-size:13px;display:block;margin-top:4px;">Espace médecin</span>
      </div>
      <div style="background:#fff;padding:24px;border:1px solid #E2E8F0;border-top:none;border-radius:0 0 12px 12px;">
        <p style="color:#1A202C;line-height:1.6;margin:0;">${intro}</p>
        ${nextSteps}
      </div>
    </div>`;

  const text = approved
    ? `Bonjour ${name},\n\nVotre compte médecin HeadsApp est approuvé. Connectez-vous à l'application avec votre e-mail d'inscription.`
    : `Bonjour ${name},\n\nVotre inscription HeadsApp a été refusée.\nMotif : ${rejectionReason || 'Non précisé'}`;

  const transporter = buildTransporter();
  return transporter
    .sendMail({
      from: process.env.SMTP_FROM || smtpUser,
      to: toEmail,
      subject,
      text,
      html,
    })
    .catch((err) => {
      console.error('[EMAIL] doctor verification:', err.message);
      throw err;
    });
}

module.exports = {
  sendResetCodeEmail,
  sendDoctorVerificationDecisionEmail,
};
