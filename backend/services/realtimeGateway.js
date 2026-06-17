const {
  socketByUserId,
} = require('../sockets/state');

let ioInstance = null;

function setIo(io) {
  ioInstance = io;
}

function getIo() {
  if (!ioInstance) {
    throw new Error('Socket.IO instance is not initialized');
  }
  return ioInstance;
}

function resolveSocketId(target) {
  const io = getIo();
  const t = String(target || '').trim();
  if (!t) return null;
  const byUser = socketByUserId.get(t);
  if (byUser) return byUser;
  // Tolère le cas où `to` est déjà un socket.id (race auth:bind).
  if (io.sockets.sockets.get(t)) return t;
  return null;
}

/** Patient / médecin rejoignent `conv:${conversationId}` pour les événements téléconsult. */
function emitToConversation(conversationId, event, payload) {
  const io = getIo();
  const cid = String(conversationId || '').trim();
  if (!cid) return;
  io.to(`conv:${cid}`).emit(event, payload);
}

/** Notification ciblée par `userId` (patient ou médecin) après `auth:bind`. */
function emitToUserId(userId, event, payload) {
  const io = getIo();
  const sid = resolveSocketId(String(userId || '').trim());
  if (!sid) return;
  io.to(sid).emit(event, payload);
}

module.exports = {
  setIo,
  getIo,
  resolveSocketId,
  emitToConversation,
  emitToUserId,
};
