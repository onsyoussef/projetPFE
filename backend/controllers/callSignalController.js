const mongoose = require('mongoose');

const { getIo, resolveSocketId } = require('../services/realtimeGateway');
const { activeCalls } = require('../sockets/state');
const { conversationIdFromCallRoomId, saveCallLogMessage } = require('../services/callService');

async function declinePatientCall(req, res) {
  try {
    if (req.auth.role !== 'patient') {
      return res.status(403).json({ message: 'Réservé aux patients.' });
    }
    const patientId = String(req.auth.sub);
    const paramCallId = String(req.params.callId || '').trim();
    const { doctorUserId, roomId } = req.body || {};
    const rId = String(roomId || paramCallId || '').trim();
    const doctorId = String(doctorUserId || '').trim();
    if (!rId || !doctorId) {
      return res.status(400).json({ message: 'doctorUserId et roomId requis.' });
    }
    const call = activeCalls.get(rId);
    if (call && String(call.callee) !== patientId) {
      return res.status(403).json({ message: 'Appel non destiné à ce patient.' });
    }
    if (call && call.timeoutId) {
      clearTimeout(call.timeoutId);
      call.timeoutId = null;
    }
    if (call) activeCalls.delete(rId);

    const io = getIo();
    const targetSocketId = resolveSocketId(doctorId);
    if (targetSocketId) {
      io.to(targetSocketId).emit('call:reject', {
        from: '',
        fromUserId: patientId,
        roomId: rId,
      });
    }

    const convId = conversationIdFromCallRoomId(rId);
    if (convId && mongoose.Types.ObjectId.isValid(convId)) {
      await saveCallLogMessage(convId, {
        mediaType: call && call.mediaType ? call.mediaType : 'audio',
        outcome: 'refused',
        durationSeconds: 0,
        roomId: rId,
      }).catch((e) => console.error('[CALL] decline saveCallLog', e));
    }

    return res.json({ ok: true });
  } catch (e) {
    console.error('[CALL] decline HTTP', e);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function markMissedPatientCall(req, res) {
  try {
    if (req.auth.role !== 'patient') {
      return res.status(403).json({ message: 'Réservé aux patients.' });
    }
    return res.json({ ok: true });
  } catch (e) {
    console.error('[CALL] missed HTTP', e);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

module.exports = {
  declinePatientCall,
  markMissedPatientCall,
};
