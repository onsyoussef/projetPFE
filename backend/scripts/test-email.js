#!/usr/bin/env node
/**
 * Vérifie la configuration e-mail et envoie un message de test.
 * Usage : node scripts/test-email.js destinataire@example.com
 */
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const { verifySmtpConnection, sendEmail, isEmailConfigured } = require('../services/emailService');

async function main() {
  const to = process.argv[2];
  if (!to || !to.includes('@')) {
    console.error('Usage: node scripts/test-email.js destinataire@example.com');
    process.exit(1);
  }

  if (!isEmailConfigured()) {
    console.error('Aucun provider e-mail configuré dans backend/.env');
    process.exit(1);
  }

  console.log('Vérification des providers…');
  const check = await verifySmtpConnection();
  console.log(JSON.stringify(check, null, 2));

  if (!check.ok) {
    console.error('\nÉchec : aucun provider disponible. Corrigez backend/.env puis relancez.');
    process.exit(1);
  }

  console.log(`\nEnvoi d'un e-mail de test à ${to}…`);
  await sendEmail({
    to,
    subject: 'HeadsApp — test e-mail',
    text: 'Si vous recevez ce message, l\'envoi e-mail HeadsApp fonctionne.',
    html: '<p>Si vous recevez ce message, l\'envoi e-mail <strong>HeadsApp</strong> fonctionne.</p>',
  });
  console.log('E-mail de test envoyé avec succès.');
}

main().catch((err) => {
  console.error('Erreur:', err.message || err);
  process.exit(1);
});
