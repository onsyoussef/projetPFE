const { buildIceServersForUser } = require('../services/webrtcService');

async function getIceConfig(req, res) {
  try {
    const userId =
      String(req.query.userId || '').trim() ||
      String(req.auth?.sub || '').trim();
    const iceServersRaw = await buildIceServersForUser(userId);
    const iceServers = Array.isArray(iceServersRaw) ? iceServersRaw : [];
    console.log(`[WEBRTC] GET /webrtc/ice-config user=${userId || 'unknown'} servers=${iceServers.length}`);
    console.log('[WEBRTC] /webrtc/ice-config payload:', JSON.stringify(iceServers));
    return res.json({
      iceServers,
      generatedAt: new Date().toISOString(),
    });
  } catch (err) {
    console.error('GET /webrtc/ice-config', err);
    return res.status(500).json({ message: 'Erreur config ICE.' });
  }
}

module.exports = {
  getIceConfig,
};
