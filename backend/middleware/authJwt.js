const jwt = require('jsonwebtoken');
const rateLimit = require('express-rate-limit');
const JWT_SECRET = String(process.env.JWT_SECRET || '').trim();
if (!JWT_SECRET) {
  console.error('[FATAL] JWT_SECRET manquant. Définissez process.env.JWT_SECRET avant de démarrer.');
  process.exit(1);
}
function signPatientToken(patientId) {
  return jwt.sign({ sub: String(patientId), role: 'patient' }, JWT_SECRET, { expiresIn: '7d' });
}

function signDoctorToken(doctorId) {
  return jwt.sign({ sub: String(doctorId), role: 'doctor' }, JWT_SECRET, { expiresIn: '7d' });
}

function signAdminToken(adminId, email, name) {
  return jwt.sign(
    { sub: String(adminId), role: 'admin', email: String(email || ''), name: String(name || '') },
    JWT_SECRET,
    { expiresIn: '7d' },
  );
}

function verifyToken(req, res, next) {
  const auth = req.headers.authorization || '';
  const m = /^Bearer\s+(.+)$/i.exec(auth);
  if (!m) {
    return res.status(401).json({ message: 'Authentification requise.' });
  }
  try {
    const payload = jwt.verify(m[1], JWT_SECRET);
    req.auth = payload;
    next();
  } catch (e) {
    return res.status(401).json({ message: 'Jeton invalide ou expiré.' });
  }
}

const authLoginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { message: 'Trop de tentatives. Réessayez dans 15 minutes.' },
  skip: (req) => req.method === 'OPTIONS',
  // Render / reverse proxy : évite ValidationError → 500 « Erreur serveur inattendue »
  validate: { trustProxy: true },
});

module.exports = {
  signPatientToken,
  signDoctorToken,
  signAdminToken,
  verifyToken,
  authLoginLimiter,
};
