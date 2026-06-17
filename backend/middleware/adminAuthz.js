const jwt = require('jsonwebtoken');

const JWT_SECRET = String(process.env.JWT_SECRET || '').trim();

function requireAdminAuth(req, res, next) {
  const expectedKey = String(process.env.ADMIN_API_KEY || '').trim();
  const headerKey = String(req.headers['x-admin-key'] || '').trim();
  if (expectedKey && headerKey && headerKey === expectedKey) {
    req.admin = { id: 'api-key', email: 'admin@headsapp.local', name: 'Administrateur' };
    return next();
  }

  const auth = req.headers.authorization || '';
  const m = /^Bearer\s+(.+)$/i.exec(auth);
  if (!m) {
    return res.status(401).json({ message: 'Authentification administrateur requise.' });
  }
  try {
    const payload = jwt.verify(m[1], JWT_SECRET);
    if (payload.role !== 'admin') {
      return res.status(403).json({ message: 'Accès réservé aux administrateurs.' });
    }
    req.admin = {
      id: payload.sub,
      email: payload.email,
      name: payload.name,
    };
    return next();
  } catch (_) {
    return res.status(401).json({ message: 'Jeton invalide ou expiré.' });
  }
}

module.exports = { requireAdminAuth };
