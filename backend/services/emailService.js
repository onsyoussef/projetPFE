const nodemailer = require('nodemailer');

function normalizeSmtpPass(raw) {
  return String(raw || '').replace(/\s+/g, '').trim();
}

function getSmtpConfig() {
  const smtpUser = String(process.env.SMTP_USER || '').trim();
  const smtpPass = normalizeSmtpPass(process.env.SMTP_PASS);
  return { smtpUser, smtpPass };
}

function isSmtpConfigured() {
  const { smtpUser, smtpPass } = getSmtpConfig();
  return Boolean(smtpUser && smtpPass);
}

function isBrevoConfigured() {
  return Boolean(String(process.env.BREVO_API_KEY || '').trim());
}

function isResendConfigured() {
  return Boolean(String(process.env.RESEND_API_KEY || '').trim());
}

function isEmailConfigured() {
  return isBrevoConfigured() || isResendConfigured() || isSmtpConfigured();
}

/** Affiche le code dans le terminal après un envoi réussi (debug local uniquement). */
function isSmtpDevLogEnabled() {
  const flag = String(process.env.SMTP_DEV_LOG || '').trim().toLowerCase();
  return flag === '1' || flag === 'true' || flag === 'yes';
}

function getFromAddress() {
  const explicit = String(process.env.EMAIL_FROM || process.env.SMTP_FROM || '').trim();
  if (explicit) return explicit;
  const { smtpUser } = getSmtpConfig();
  if (smtpUser) return smtpUser;
  return 'HeadsApp <noreply@headsapp.com>';
}

function logDevResetCode(toEmail, code) {
  console.log(
    `[EMAIL][DEV] Code réinitialisation pour ${toEmail} : ${code} (valide 15 min)`,
  );
}

function buildResetCodeContent(code) {
  const subject = 'Code de réinitialisation - HeadsApp';
  const text = `Bonjour,

Votre code de réinitialisation HeadsApp est : ${code}

Il est valide 15 minutes. Ne le partagez avec personne.

— L'équipe HeadsApp`;

  const html = `
    <div style="font-family:Inter,Arial,sans-serif;max-width:560px;margin:0 auto;padding:24px;">
      <div style="background:#1A6B8A;color:#fff;padding:16px 20px;border-radius:12px 12px 0 0;">
        <strong style="font-size:18px;">HeadsApp</strong>
        <span style="opacity:0.9;font-size:13px;display:block;margin-top:4px;">Réinitialisation du mot de passe</span>
      </div>
      <div style="background:#fff;padding:24px;border:1px solid #E2E8F0;border-top:none;border-radius:0 0 12px 12px;">
        <p style="color:#1A202C;line-height:1.6;margin:0 0 16px;">Bonjour,</p>
        <p style="color:#1A202C;line-height:1.6;margin:0 0 16px;">Utilisez le code ci-dessous pour réinitialiser votre mot de passe :</p>
        <p style="font-size:32px;font-weight:700;letter-spacing:8px;color:#1A6B8A;text-align:center;margin:24px 0;">${code}</p>
        <p style="color:#718096;font-size:14px;line-height:1.5;margin:0;">Ce code expire dans <strong>15 minutes</strong>. Ne le partagez avec personne.</p>
      </div>
    </div>`;

  return { subject, text, html };
}

function buildTransporter() {
  const { smtpUser, smtpPass } = getSmtpConfig();
  if (!smtpUser || !smtpPass) {
    throw new Error(
      'Envoi d\'email non configuré. Définissez SMTP_USER et SMTP_PASS dans backend/.env.',
    );
  }

  const port = parseInt(process.env.SMTP_PORT || '587', 10);
  const secure = port === 465;

  return nodemailer.createTransport({
    host: process.env.SMTP_HOST || 'smtp.gmail.com',
    port,
    secure,
    requireTLS: !secure,
    auth: { user: smtpUser, pass: smtpPass },
  });
}

async function sendViaSmtp({ to, subject, text, html }) {
  const transporter = buildTransporter();
  const from = getFromAddress();
  await transporter.sendMail({ from, to, subject, text, html });
  return { provider: 'smtp' };
}

async function sendViaBrevo({ to, subject, text, html }) {
  const apiKey = String(process.env.BREVO_API_KEY || '').trim();
  if (!apiKey) {
    throw new Error('BREVO_API_KEY absent.');
  }

  const from = getFromAddress();
  const senderMatch = from.match(/^(.+?)\s*<([^>]+)>$/);
  const sender = senderMatch
    ? { name: senderMatch[1].trim(), email: senderMatch[2].trim() }
    : { name: 'HeadsApp', email: from.includes('@') ? from : process.env.SMTP_USER };

  const response = await fetch('https://api.brevo.com/v3/smtp/email', {
    method: 'POST',
    headers: {
      accept: 'application/json',
      'content-type': 'application/json',
      'api-key': apiKey,
    },
    body: JSON.stringify({
      sender,
      to: [{ email: to }],
      subject,
      textContent: text,
      htmlContent: html,
    }),
  });

  if (!response.ok) {
    const body = await response.text().catch(() => '');
    throw new Error(`Brevo ${response.status}: ${body || response.statusText}`);
  }

  return { provider: 'brevo' };
}

async function sendViaResend({ to, subject, text, html }) {
  const apiKey = String(process.env.RESEND_API_KEY || '').trim();
  if (!apiKey) {
    throw new Error('RESEND_API_KEY absent.');
  }

  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: getFromAddress(),
      to: [to],
      subject,
      text,
      html,
    }),
  });

  if (!response.ok) {
    const body = await response.text().catch(() => '');
    throw new Error(`Resend ${response.status}: ${body || response.statusText}`);
  }

  return { provider: 'resend' };
}

/**
 * Envoie un e-mail via le premier provider disponible (Brevo → Resend → SMTP).
 * Échoue explicitement si aucun envoi n'a réussi.
 */
async function sendEmail({ to, subject, text, html }) {
  const email = String(to || '').trim();
  if (!email || !email.includes('@')) {
    throw new Error('Adresse e-mail destinataire invalide.');
  }

  const attempts = [];

  if (isBrevoConfigured()) {
    attempts.push({ name: 'brevo', fn: () => sendViaBrevo({ to: email, subject, text, html }) });
  }
  if (isResendConfigured()) {
    attempts.push({ name: 'resend', fn: () => sendViaResend({ to: email, subject, text, html }) });
  }
  if (isSmtpConfigured()) {
    attempts.push({ name: 'smtp', fn: () => sendViaSmtp({ to: email, subject, text, html }) });
  }

  if (attempts.length === 0) {
    throw new Error(
      'Envoi d\'email non configuré. Définissez BREVO_API_KEY, RESEND_API_KEY ou SMTP_USER/SMTP_PASS dans backend/.env.',
    );
  }

  const errors = [];
  for (const attempt of attempts) {
    try {
      const result = await attempt.fn();
      console.log(`[EMAIL] envoyé via ${result.provider} → ${email}`);
      return result;
    } catch (err) {
      const message = err?.message || String(err);
      console.error(`[EMAIL] échec ${attempt.name}:`, message);
      errors.push(`${attempt.name}: ${message}`);
    }
  }

  throw new Error(
    `Impossible d'envoyer l'e-mail (${errors.join(' | ')}). ` +
      'Vérifiez vos identifiants SMTP (mot de passe d\'application Gmail) ou configurez BREVO_API_KEY.',
  );
}

/** Vérifie les identifiants au démarrage (sans bloquer le serveur). */
async function verifySmtpConnection() {
  if (!isEmailConfigured()) {
    return { ok: false, skipped: true, message: 'Aucun provider e-mail configuré.' };
  }

  const checks = [];

  if (isBrevoConfigured()) {
    checks.push(
      fetch('https://api.brevo.com/v3/account', {
        headers: { accept: 'application/json', 'api-key': process.env.BREVO_API_KEY.trim() },
      })
        .then((r) => (r.ok ? { provider: 'brevo', ok: true } : { provider: 'brevo', ok: false, message: `HTTP ${r.status}` }))
        .catch((err) => ({ provider: 'brevo', ok: false, message: err.message })),
    );
  }

  if (isResendConfigured()) {
    checks.push(
      fetch('https://api.resend.com/domains', {
        headers: { Authorization: `Bearer ${process.env.RESEND_API_KEY.trim()}` },
      })
        .then((r) => (r.ok ? { provider: 'resend', ok: true } : { provider: 'resend', ok: false, message: `HTTP ${r.status}` }))
        .catch((err) => ({ provider: 'resend', ok: false, message: err.message })),
    );
  }

  if (isSmtpConfigured()) {
    checks.push(
      buildTransporter()
        .verify()
        .then(() => ({ provider: 'smtp', ok: true }))
        .catch((err) => ({ provider: 'smtp', ok: false, message: err.message })),
    );
  }

  const results = await Promise.all(checks);
  const working = results.filter((r) => r.ok);
  if (working.length > 0) {
    return { ok: true, providers: working.map((r) => r.provider) };
  }

  const failed = results.map((r) => `${r.provider}: ${r.message}`).join(' | ');
  return { ok: false, message: failed };
}

async function sendResetCodeEmail(toEmail, code) {
  const { subject, text, html } = buildResetCodeContent(code);
  await sendEmail({ to: toEmail, subject, text, html });
  if (isSmtpDevLogEnabled()) {
    logDevResetCode(toEmail, code);
  }
}

/**
 * Notifie le médecin après décision admin (compte approuvé ou refusé).
 */
async function sendDoctorVerificationDecisionEmail({ toEmail, fullName, approved, rejectionReason }) {
  const email = String(toEmail || '').trim();
  if (!email || !email.includes('@')) {
    throw new Error('Adresse e-mail du médecin invalide ou indisponible.');
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

  await sendEmail({ to: email, subject, text, html });
}

module.exports = {
  sendResetCodeEmail,
  sendDoctorVerificationDecisionEmail,
  sendEmail,
  isSmtpConfigured,
  isEmailConfigured,
  isSmtpDevLogEnabled,
  verifySmtpConnection,
};
