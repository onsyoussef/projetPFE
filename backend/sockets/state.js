const socketByUserId = new Map();
const userBySocketId = new Map();
const activeCalls = new Map();
/** conversationId -> { patientId, doctorId, patientName, enteredAt, notified } */
const waitingRooms = new Map();
/** patientUserId -> true si l’app patient est au premier plan (Socket `patient:app_lifecycle`). */
const patientAppForeground = new Map();

module.exports = {
  socketByUserId,
  userBySocketId,
  activeCalls,
  waitingRooms,
  patientAppForeground,
};
