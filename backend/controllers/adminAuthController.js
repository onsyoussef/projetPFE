const bcrypt = require('bcrypt');
const { signAdminToken } = require('../middleware/authJwt');

async function loginAdmin(req, res) {
  try {
    const email = String(req.body?.email || '')
      .trim()
      .toLowerCase();
    const password = String(req.body?.password || '');

    if (!email || !password) {
      return res.status(400).json({ message: 'Email et mot de passe requis.' });
    }

    const adminEmail = String(process.env.ADMIN_EMAIL || 'admin@headsapp.tn')
      .trim()
      .toLowerCase();
    const adminPassword = String(process.env.ADMIN_PASSWORD || '');
    const adminPasswordHash = String(process.env.ADMIN_PASSWORD_HASH || '').trim();
    const adminName = String(process.env.ADMIN_NAME || 'Administrateur HeadsApp').trim();

    if (!adminPassword && !adminPasswordHash) {
      return res.status(503).json({
        message:
          'Connexion admin non configurée. Ajoutez ADMIN_EMAIL et ADMIN_PASSWORD dans backend/.env (pas seulement .env.example), puis redémarrez le serveur.',
      });
    }

    if (email !== adminEmail) {
      return res.status(401).json({ message: 'Identifiants invalides.' });
    }

    let valid = false;
    if (adminPasswordHash) {
      valid = await bcrypt.compare(password, adminPasswordHash);
    } else {
      valid = password === adminPassword;
    }
    if (!valid) {
      return res.status(401).json({ message: 'Identifiants invalides.' });
    }

    const token = signAdminToken('admin', adminEmail, adminName);
    return res.json({
      message: 'Connexion réussie.',
      token,
      admin: { id: 'admin', email: adminEmail, name: adminName },
    });
  } catch (err) {
    console.error('Erreur POST /admin/auth/login', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

module.exports = { loginAdmin };
