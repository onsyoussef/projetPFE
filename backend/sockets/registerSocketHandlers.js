const mongoose = require('mongoose');
const jwt = require('jsonwebtoken');
const Patient = require('../models/Patient');
const Doctor = require('../models/Doctor');
const Conversation = require('../models/Conversation');
const Message = require('../models/Message');
const { socketByUserId, userBySocketId, activeCalls, waitingRooms, patientAppForeground } = require('./state');
const { resolveSocketId, emitToConversation, emitToUserId } = require('../services/realtimeGateway');
const { saveCallLogMessage, conversationIdFromCallRoomId } = require('../services/callService');
const { persistWaitingRoomEnter, persistWaitingRoomLeave } = require('../services/waitingRoomService');
const {
  getUserInfoByUserId,
  notifyPatientIncomingCall,
  notifyCancelIncomingCallPush,
  notifyPatientCallMissedPush,
  notifyDoctorNoAnswerPush,
} = require('../services/utilsService');
const JWT_SECRET = String(process.env.JWT_SECRET || '').trim();

function clearCallTimeout(call) {
  if (call && call.timeoutId) {
    clearTimeout(call.timeoutId);
    call.timeoutId = null;
  }
}

function scheduleIncomingCallTimeout(io, roomId) {
  const rId = String(roomId || '').trim();
  if (!rId) return;
  const existingCall = activeCalls.get(rId);
  if (!existingCall) return;
  clearCallTimeout(existingCall);
  existingCall.timeoutId = setTimeout(() => {
    const call = activeCalls.get(rId);
    if (!call || call.startTime) return;
    const convId = conversationIdFromCallRoomId(rId);
    void (async () => {
      try {
        if (convId) {
          const msg = await saveCallLogMessage(convId, {
            mediaType: call.mediaType || 'audio',
            outcome: 'missed',
            durationSeconds: 0,
            roomId: rId,
          });
          if (msg) {
            await notifyPatientCallMissedPush(convId, String(msg._id), {
              kind: 'call_log',
              outcome: 'missed',
              mediaType: call.mediaType || 'audio',
            });
          }
        }
        await notifyCancelIncomingCallPush({ patientUserId: String(call.callee), roomId: rId });
        await notifyDoctorNoAnswerPush({
          doctorUserId: String(call.caller),
          patientUserId: String(call.callee),
          mediaType: call.mediaType || 'audio',
        });
      } catch (e) {
        console.error('[CALL][timeout]', e);
      }
      const callerSocketId = resolveSocketId(String(call.caller));
      const calleeSocketId = resolveSocketId(String(call.callee));
      if (callerSocketId) {
        io.to(callerSocketId).emit('call:end', {
          roomId: rId,
          reason: 'no_answer',
          fromUserId: String(call.callee),
        });
      }
      if (calleeSocketId) {
        io.to(calleeSocketId).emit('call:end', {
          roomId: rId,
          reason: 'missed',
          fromUserId: String(call.caller),
        });
      }
      activeCalls.delete(rId);
    })();
  }, 30000);
}

function registerSocketHandlers(io) {
  io.on('connection', (socket) => {
  console.log(`[SOCKET] connected socketId=${socket.id}`);

  socket.on('patient:app_lifecycle', ({ inForeground } = {}) => {
    const uid = userBySocketId.get(socket.id);
    if (!uid) return;
    patientAppForeground.set(String(uid), !!inForeground);
  });

  socket.on('auth:bind', ({ userId } = {}) => {
    const id = String(userId || '').trim();
    if (!id) return;
    const token =
      (socket.handshake.auth && socket.handshake.auth.token) ||
      (socket.handshake.query && socket.handshake.query.token) ||
      '';
    if (token) {
      try {
        const p = jwt.verify(String(token), JWT_SECRET);
        if (String(p.sub) !== id) {
          socket.emit('auth:error', { message: 'Jeton incompatible avec cet utilisateur.' });
          return;
        }
      } catch (e) {
        socket.emit('auth:error', { message: 'Jeton invalide ou expiré.' });
        return;
      }
    }
    socketByUserId.set(id, socket.id);
    userBySocketId.set(socket.id, id);
    socket.emit('auth:ok', { userId: id });
    console.log(`[SOCKET] auth:bind userId=${id} socketId=${socket.id}`);

    for (const [convId, wr] of waitingRooms.entries()) {
      if (String(wr.doctorId) !== id) continue;
      if (wr.notified) continue;
      io.to(socket.id).emit('consultation:patient_waiting', {
        conversationId: convId,
        patientId: wr.patientId,
        patientName: wr.patientName,
        enteredAt: new Date(wr.enteredAt).toISOString(),
      });
      wr.notified = true;
      waitingRooms.set(convId, wr);
      console.log(`[WAITING] deferred notify conv=${convId} doctor=${id} socket=${socket.id}`);
    }
  });

  // Salle d'attente virtuelle (téléconsultation) + persistance MongoDB
  socket.on('patient:entered_waiting_room', async (payload = {}) => {
    const conversationId = String(payload.conversationId || '').trim();
    const patientId = String(payload.patientId || '').trim();
    const doctorId = String(payload.doctorId || '').trim();
    const patientName = String(payload.patientName || 'Patient').trim() || 'Patient';
    if (!conversationId || !patientId || !doctorId) return;
    socket.join(`conv:${conversationId}`);
    let enteredAtMs = Date.now();
    try {
      const doc = await persistWaitingRoomEnter(conversationId, patientId, doctorId, patientName);
      if (doc && doc.enteredAt) enteredAtMs = new Date(doc.enteredAt).getTime();
    } catch (err) {
      console.error('[WAITING] persist enter', err);
    }
    const doctorSocketId = resolveSocketId(doctorId);
    const notified = !!doctorSocketId;
    waitingRooms.set(conversationId, {
      patientId,
      doctorId,
      patientName,
      enteredAt: enteredAtMs,
      notified,
    });
    console.log(
      `[WAITING] entered conv=${conversationId} patient=${patientId} doctorSocket=${doctorSocketId || 'NOT_FOUND'} notified=${notified}`
    );
    if (doctorSocketId) {
      io.to(doctorSocketId).emit('consultation:patient_waiting', {
        conversationId,
        patientId,
        patientName,
        enteredAt: new Date(enteredAtMs).toISOString(),
      });
    }
  });

  socket.on('patient:left_waiting_room', async (payload = {}) => {
    const conversationId = String(payload.conversationId || '').trim();
    const patientId = String(payload.patientId || '').trim();
    const doctorId = String(payload.doctorId || '').trim();
    if (!conversationId) return;
    const boundUser = userBySocketId.get(socket.id);
    if (!boundUser || String(boundUser) !== String(patientId)) {
      return;
    }
    const cur = waitingRooms.get(conversationId);
    if (cur && cur.patientId === patientId) {
      waitingRooms.delete(conversationId);
    }
    try {
      await persistWaitingRoomLeave(conversationId, patientId);
    } catch (err) {
      console.error('[WAITING] persist leave', err);
    }
    const targetDoctor = doctorId || (cur && cur.doctorId) || '';
    const doctorSocketId = resolveSocketId(targetDoctor);
    console.log(`[WAITING] left conv=${conversationId} patient=${patientId}`);
    if (!doctorSocketId) return;
    io.to(doctorSocketId).emit('consultation:patient_left_waiting', {
      conversationId,
      patientId,
    });
  });

  socket.on('call:join-room', ({ conversationId }) => {
    if (!conversationId) return;
    socket.join(`conv:${conversationId}`);
  });

  socket.on('call:leave-room', ({ conversationId }) => {
    if (!conversationId) return;
    socket.leave(`conv:${conversationId}`);
  });

  /** Indicateur « en train d’écrire… » (relai vers l’autre participant de la conversation). */
  socket.on('chat:typing', (payload = {}) => {
    const cid = String(payload.conversationId || '').trim();
    if (!cid) return;
    socket.to(`conv:${cid}`).emit('chat:typing', {
      conversationId: cid,
      typing: !!payload.typing,
      role: String(payload.role || ''),
    });
  });

  socket.on('call:ring', (payload = {}) => {
    const conversationId = payload.conversationId;
    if (!conversationId) return;
    socket.to(`conv:${conversationId}`).emit('call:ring', payload);
  });

  socket.on('call:accept', (payload = {}) => {
    const conversationId = payload.conversationId;
    if (!conversationId) return;
    socket.to(`conv:${conversationId}`).emit('call:accept', payload);
  });

  // WebRTC SDP/ICE signaling
  socket.on('webrtc:offer', (payload = {}) => {
    const conversationId = payload.conversationId;
    if (!conversationId) return;
    socket.to(`conv:${conversationId}`).emit('webrtc:offer', payload);
  });
  socket.on('webrtc:answer', (payload = {}) => {
    const conversationId = payload.conversationId;
    if (!conversationId) return;
    socket.to(`conv:${conversationId}`).emit('webrtc:answer', payload);
  });
  socket.on('webrtc:ice-candidate', (payload = {}) => {
    const conversationId = payload.conversationId;
    if (!conversationId) return;
    socket.to(`conv:${conversationId}`).emit('webrtc:ice-candidate', payload);
  });

  // Nouveau pipeline de signalisation direct user -> user
  socket.on('call:offer', async ({ to, sdp, roomId, from, mediaType } = {}) => {
    const target = String(to || '').trim();
    const source = String(from || '').trim() || userBySocketId.get(socket.id) || socket.id;
    if (!target || !sdp || !roomId) return;
    activeCalls.set(String(roomId), {
      caller: source,
      callee: target,
      startTime: null,
      mediaType: mediaType === 'video' ? 'video' : 'audio',
      pendingOffer: sdp,
    });
    scheduleIncomingCallTimeout(io, roomId);
    void notifyPatientIncomingCall({
      patientUserId: target,
      roomId,
      callerUserId: source,
      mediaType: mediaType === 'video' ? 'video' : 'audio',
    }).catch((e) => console.error('[CALL][offer] push incoming_call', e));
    const targetSocketId = resolveSocketId(target);
    console.log(
      `[CALL][offer] roomId=${roomId} from=${source} fromSocket=${socket.id} to=${target} targetSocketId=${targetSocketId || 'NOT_FOUND'} sdpType=${
        sdp && sdp.type ? sdp.type : ''
      }`
    );
    const callerInfo = await getUserInfoByUserId(source);
    const incomingPayload = {
      from: socket.id,
      fromUserId: source,
      mediaType: mediaType === 'video' ? 'video' : 'audio',
      sdp,
      roomId,
      callerInfo,
    };
    const offerPayload = {
      from: socket.id,
      fromUserId: source,
      mediaType: mediaType === 'video' ? 'video' : 'audio',
      sdp,
      roomId,
    };

    const convId = conversationIdFromCallRoomId(String(roomId));
    if (targetSocketId) {
      io.to(targetSocketId).emit('call:incoming', incomingPayload);
      io.to(targetSocketId).emit('call:offer', offerPayload);
      console.log(`[CALL][offer] direct socket=${targetSocketId} roomId=${roomId}`);
    } else {
      console.warn(`[CALL][offer] targetSocketId NOT_FOUND to=${target} roomId=${roomId}`);
    }
    if (convId) {
      io.to(`conv:${convId}`).except(socket.id).emit('call:incoming', incomingPayload);
      io.to(`conv:${convId}`).except(socket.id).emit('call:offer', offerPayload);
      console.log(`[CALL][offer] broadcast conv=${convId} roomId=${roomId}`);
    } else if (!targetSocketId) {
      console.warn(`[CALL][offer] no socket and no conv from roomId=${roomId}`);
    }
  });

  socket.on('call:request_pending_offer', async ({ roomId, userId } = {}) => {
    let uid = userBySocketId.get(socket.id);
    if (!uid) {
      await new Promise((r) => setTimeout(r, 120));
      uid = userBySocketId.get(socket.id);
    }
    if (!uid) {
      await new Promise((r) => setTimeout(r, 350));
      uid = userBySocketId.get(socket.id);
    }
    if (!uid) {
      const hint = String(
        userId || (socket.handshake && socket.handshake.auth && socket.handshake.auth.userId) || '',
      ).trim();
      if (hint) {
        socketByUserId.set(hint, socket.id);
        userBySocketId.set(socket.id, hint);
        uid = hint;
        console.log(`[CALL][request_pending_offer] late bind userId=${hint} socketId=${socket.id}`);
      }
    }
    const rId = roomId ? String(roomId) : '';
    if (!uid || !rId) {
      console.warn(`[CALL][request_pending_offer] missing uid or roomId socketId=${socket.id} uid=${uid || ''} roomId=${rId}`);
      return;
    }
    const call = activeCalls.get(rId);
    if (!call || !call.pendingOffer) {
      console.warn(`[CALL][request_pending_offer] no pending offer roomId=${rId} socketId=${socket.id}`);
      return;
    }
    if (String(call.callee) !== String(uid)) {
      console.warn(
        `[CALL][request_pending_offer] callee mismatch roomId=${rId} socketUid=${uid} call.callee=${call.callee}`
      );
      return;
    }
    const callerSocketId = resolveSocketId(call.caller);
    if (!callerSocketId) {
      console.warn(
        `[CALL][request_pending_offer] caller hors ligne — rejeu SDP vers patient quand même roomId=${rId}`
      );
    }
    const sdp = call.pendingOffer;
    const mt = call.mediaType === 'video' ? 'video' : 'audio';
    const fromField = callerSocketId || '';
    io.to(socket.id).emit('call:incoming', {
      from: fromField,
      fromUserId: call.caller,
      mediaType: mt,
      sdp,
      roomId: rId,
      callerInfo: await getUserInfoByUserId(call.caller),
    });
    io.to(socket.id).emit('call:offer', {
      from: fromField,
      fromUserId: call.caller,
      mediaType: mt,
      sdp,
      roomId: rId,
    });
    console.log(`[CALL][request_pending_offer] ok roomId=${rId} calleeSocket=${socket.id}`);
  });

  socket.on('call:answer', ({ to, sdp, roomId, from, mediaType } = {}) => {
    const target = String(to || '').trim();
    const source = String(from || '').trim() || userBySocketId.get(socket.id) || socket.id;
    if (!target || !sdp || !roomId) return;
    const call = activeCalls.get(String(roomId));
    if (call) {
      clearCallTimeout(call);
      call.startTime = Date.now();
      if (mediaType === 'video') call.mediaType = 'video';
    }
    const targetSocketId = resolveSocketId(target);
    console.log(
      `[CALL][answer] roomId=${roomId} from=${source} fromSocket=${socket.id} to=${target} targetSocketId=${targetSocketId || 'NOT_FOUND'} sdpType=${
        sdp && sdp.type ? sdp.type : ''
      }`
    );
    const answerPayload = {
      from: socket.id,
      fromUserId: source,
      mediaType: mediaType === 'video' ? 'video' : 'audio',
      sdp,
      roomId,
    };
    if (targetSocketId) {
      io.to(targetSocketId).emit('call:answer', answerPayload);
      return;
    }
    const convAns = conversationIdFromCallRoomId(String(roomId || ''));
    if (convAns) {
      io.to(`conv:${convAns}`).except(socket.id).emit('call:answer', answerPayload);
    }
  });

  socket.on('call:ice', ({ to, candidate, roomId, from } = {}) => {
    const target = String(to || '').trim();
    const source = String(from || '').trim() || userBySocketId.get(socket.id) || socket.id;
    if (!target || !candidate) return;
    const targetSocketId = resolveSocketId(target);
    const cand = candidate && typeof candidate.candidate === 'string' ? candidate.candidate : '';
    const candType = cand.includes(' typ relay')
      ? 'relay'
      : cand.includes(' typ srflx')
      ? 'srflx'
      : cand.includes(' typ host')
      ? 'host'
      : 'unknown';
    console.log(
      `[CALL][ice] roomId=${roomId || ''} from=${source} fromSocket=${socket.id} to=${target} targetSocketId=${
        targetSocketId || 'NOT_FOUND'
      } candType=${candType}`
    );
    if (targetSocketId) {
      io.to(targetSocketId).emit('call:ice', { from: socket.id, fromUserId: source, candidate, roomId });
      return;
    }
    const convIce = conversationIdFromCallRoomId(String(roomId || ''));
    if (convIce) {
      io.to(`conv:${convIce}`).except(socket.id).emit('call:ice', {
        from: socket.id,
        fromUserId: source,
        candidate,
        roomId,
      });
    }
  });

  socket.on('call:reject', (payload = {}) => {
    const { to, roomId, from, conversationId: convFromPayload } = payload || {};
    const target = String(to || '').trim();
    const source = String(from || '').trim() || userBySocketId.get(socket.id) || socket.id;
    if (!target) return;
    const rId = roomId ? String(roomId) : '';
    const call = rId ? activeCalls.get(rId) : null;
    if (rId && call) {
      clearCallTimeout(call);
      let convId = conversationIdFromCallRoomId(rId);
      if (!convId && convFromPayload && mongoose.Types.ObjectId.isValid(String(convFromPayload))) {
        convId = String(convFromPayload);
      }
      if (convId) {
        void saveCallLogMessage(convId, {
          mediaType: call.mediaType || 'audio',
          outcome: 'refused',
          durationSeconds: 0,
          roomId: rId,
        }).catch((e) => console.error('[CALL] reject save', e));
      } else {
        console.log(`[CALL] no conversationId for roomId=${rId}`);
      }
      const calleeId = String(call.callee);
      void (async () => {
        try {
          const inf = await getUserInfoByUserId(calleeId);
          if (inf.role === 'patient') {
            await notifyCancelIncomingCallPush({ patientUserId: calleeId, roomId: rId });
          }
        } catch (e) {
          console.error('[CALL][reject] cancel push', e);
        }
      })();
      activeCalls.delete(rId);
    } else if (rId) {
      activeCalls.delete(rId);
    }
    const targetSocketId = resolveSocketId(target);
    console.log(
      `[CALL][reject] roomId=${roomId || ''} from=${source} fromSocket=${socket.id} to=${target} targetSocketId=${
        targetSocketId || 'NOT_FOUND'
      }`
    );
    const rejectPayload = { from: socket.id, fromUserId: source, roomId };
    if (targetSocketId) {
      io.to(targetSocketId).emit('call:reject', rejectPayload);
      return;
    }
    const convReject = conversationIdFromCallRoomId(String(roomId || '')) ||
      (convFromPayload && mongoose.Types.ObjectId.isValid(String(convFromPayload)) ? String(convFromPayload) : null);
    if (convReject) {
      io.to(`conv:${convReject}`).except(socket.id).emit('call:reject', rejectPayload);
    }
  });

  socket.on('call:end', (payload = {}) => {
    const { to, roomId, reason, from, conversationId: convFromPayload } = payload || {};
    const target = String(to || '').trim();
    const source = String(from || '').trim() || userBySocketId.get(socket.id) || socket.id;
    const rId = roomId ? String(roomId) : '';
    const call = rId ? activeCalls.get(rId) : null;
    if (rId && call) {
      clearCallTimeout(call);
      let convId = conversationIdFromCallRoomId(rId);
      if (!convId && convFromPayload && mongoose.Types.ObjectId.isValid(String(convFromPayload))) {
        convId = String(convFromPayload);
      }
      if (convId) {
        const durationSec = call.startTime
          ? Math.max(0, Math.floor((Date.now() - call.startTime) / 1000))
          : 0;
        void saveCallLogMessage(convId, {
          mediaType: call.mediaType || 'audio',
          outcome: 'ended',
          durationSeconds: durationSec,
          roomId: rId,
        }).catch((e) => console.error('[CALL] end save', e));
      } else {
        console.log(`[CALL] no conversationId for roomId=${rId}`);
      }
      const calleeEnd = String(call.callee);
      void (async () => {
        try {
          const inf = await getUserInfoByUserId(calleeEnd);
          if (inf.role === 'patient') {
            await notifyCancelIncomingCallPush({ patientUserId: calleeEnd, roomId: rId });
          }
        } catch (e) {
          console.error('[CALL][end] cancel push', e);
        }
      })();
      activeCalls.delete(rId);
    } else if (rId) {
      activeCalls.delete(rId);
    }
    if (!target) return;
    const targetSocketId = resolveSocketId(target);
    console.log(
      `[CALL][end] roomId=${roomId || ''} from=${source} fromSocket=${socket.id} to=${target} targetSocketId=${
        targetSocketId || 'NOT_FOUND'
      } reason=${reason || ''}`
    );
    const endPayload = {
      from: socket.id,
      fromUserId: source,
      roomId,
      reason: reason || null,
    };
    if (targetSocketId) {
      io.to(targetSocketId).emit('call:end', endPayload);
      return;
    }
    let convEnd = conversationIdFromCallRoomId(String(roomId || ''));
    if (!convEnd && convFromPayload && mongoose.Types.ObjectId.isValid(String(convFromPayload))) {
      convEnd = String(convFromPayload);
    }
    if (convEnd) {
      io.to(`conv:${convEnd}`).except(socket.id).emit('call:end', endPayload);
    }
  });

  socket.on('disconnect', () => {
    const userId = userBySocketId.get(socket.id);
    console.log(`[SOCKET] disconnect socketId=${socket.id} userId=${userId || ''}`);

    if (userId) {
      for (const [convId, wr] of Array.from(waitingRooms.entries())) {
        if (wr.patientId === userId) {
          waitingRooms.delete(convId);
          void persistWaitingRoomLeave(convId, userId).catch((e) =>
            console.error('[WAITING] persist leave on disconnect', e)
          );
          const doctorSocketId = resolveSocketId(wr.doctorId);
          if (doctorSocketId) {
            io.to(doctorSocketId).emit('consultation:patient_left_waiting', {
              conversationId: convId,
              patientId: userId,
            });
          }
        }
      }
    }

    if (userId) {
      patientAppForeground.delete(String(userId));
      const currentSocketId = socketByUserId.get(userId);
      if (currentSocketId === socket.id) {
        socketByUserId.delete(userId);
      }
      userBySocketId.delete(socket.id);
    }

    for (const [roomId, call] of Array.from(activeCalls.entries())) {
      if (call.caller === userId || call.callee === userId) {
        clearCallTimeout(call);
        const convId = conversationIdFromCallRoomId(roomId);
        if (convId) {
          const durationSec = call.startTime
            ? Math.max(0, Math.floor((Date.now() - call.startTime) / 1000))
            : 0;
          void saveCallLogMessage(convId, {
            mediaType: call.mediaType || 'audio',
            outcome: 'ended',
            durationSeconds: durationSec,
            roomId,
          }).catch((e) => console.error('[CALL] disconnect save', e));
        }
        const other = call.caller === userId ? call.callee : call.caller;
        const otherSocketId = socketByUserId.get(other);
        if (otherSocketId) {
          io.to(otherSocketId).emit('call:end', {
            roomId,
            reason: 'deconnecte',
          });
        }
        activeCalls.delete(roomId);
      }
    }
  });
  });
}

module.exports = registerSocketHandlers;
