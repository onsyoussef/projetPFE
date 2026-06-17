const mongoose = require('mongoose');
const Message = require('../models/Message');
const { emitToConversation } = require('./realtimeGateway');
async function saveCallLogMessage(conversationId, { mediaType, outcome, durationSeconds, roomId }) {
  const cid = String(conversationId || '').trim();
  if (!cid || !mongoose.Types.ObjectId.isValid(cid)) return null;
  const mt = mediaType === 'video' ? 'video' : 'audio';
  const oc =
    outcome === 'refused' ? 'refused' : outcome === 'missed' ? 'missed' : 'ended';
  const dur = Math.max(0, parseInt(String(durationSeconds), 10) || 0);

  let content = '';
  if (mt === 'video') {
    if (oc === 'refused') content = 'Appel vidéo refusé';
    else if (oc === 'missed') content = 'Appel vidéo manqué';
    else content = 'Appel vidéo terminé';
  } else {
    if (oc === 'refused') content = 'Appel audio refusé';
    else if (oc === 'missed') content = 'Appel manqué';
    else content = 'Appel audio terminé';
  }

  try {
    const msg = await Message.create({
      conversation: cid,
      fromType: 'system',
      type: 'call_event',
      content,
      payload: {
        kind: 'call_log',
        mediaType: mt,
        outcome: oc,
        durationSeconds: dur,
        roomId: String(roomId || ''),
      },
    });
    console.log(
      `[CALL] call_log saved conv=${cid} outcome=${oc} media=${mt} dur=${dur}s roomId=${String(roomId || '')}`
    );
    emitToConversation(cid, 'chat:call_summary', {
      conversationId: cid,
      messageId: String(msg._id),
      mediaType: mt,
      outcome: oc,
      durationSeconds: dur,
    });
    return msg;
  } catch (e) {
    console.error('[CALL] saveCallLogMessage', e.message || e);
    return null;
  }
}

function conversationIdFromCallRoomId(roomId) {
  const s = String(roomId || '').trim();
  if (!s.startsWith('room_')) return null;
  const rest = s.slice('room_'.length);
  const lastUnderscore = rest.lastIndexOf('_');
  if (lastUnderscore <= 0) return null;
  const convPart = rest.slice(0, lastUnderscore);
  const ts = rest.slice(lastUnderscore + 1);
  if (!/^\d+$/.test(ts)) return null;
  if (!mongoose.Types.ObjectId.isValid(convPart)) return null;
  return convPart;
}

module.exports = {
  saveCallLogMessage,
  conversationIdFromCallRoomId
};
