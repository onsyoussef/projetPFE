const {
  registerPushDevice,
  unregisterPushDevice,
} = require('../services/pushNotificationService');
const { assertDoctorVerifiedForRequest } = require('../services/doctorVerificationService');

async function registerDevice(req, res) {
  try {
    const { token, platform, appName, voipToken } = req.body || {};
    const auth = req.auth || {};
    if (auth.role === 'doctor' && !(await assertDoctorVerifiedForRequest(req, res))) return;
    const role = auth.role === 'doctor' ? 'doctor' : 'patient';
    const userId = String(auth.sub || '');
    if (!token || !appName) {
      return res.status(400).json({ message: 'token et appName requis.' });
    }
    await registerPushDevice({
      userId,
      role,
      token,
      platform,
      appName,
      voipToken,
    });
    return res.json({ message: 'Device push enregistré.' });
  } catch (err) {
    console.error('Erreur /push/register-device', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function unregisterDevice(req, res) {
  try {
    const { token } = req.body || {};
    if (!token) return res.status(400).json({ message: 'token requis.' });
    await unregisterPushDevice({ token });
    return res.json({ message: 'Device push désactivé.' });
  } catch (err) {
    console.error('Erreur /push/unregister-device', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

module.exports = {
  registerDevice,
  unregisterDevice,
};
