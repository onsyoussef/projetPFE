const mongoose = require('mongoose');
const WaitingRoomSession = require('../models/WaitingRoomSession');
const { waitingRooms } = require('../sockets/state');
async function persistWaitingRoomEnter(conversationId, patientId, doctorId, patientName) {
  const cid = String(conversationId || '').trim();
  const pid = String(patientId || '').trim();
  const did = String(doctorId || '').trim();
  if (
    !mongoose.Types.ObjectId.isValid(cid) ||
    !mongoose.Types.ObjectId.isValid(pid) ||
    !mongoose.Types.ObjectId.isValid(did)
  ) {
    return null;
  }
  const doc = await WaitingRoomSession.findOneAndUpdate(
    { conversation: cid },
    {
      $set: {
        patient: pid,
        doctor: did,
        patientName: String(patientName || 'Patient').trim() || 'Patient',
        enteredAt: new Date(),
      },
      $setOnInsert: { conversation: cid },
    },
    { upsert: true, returnDocument: 'after' }
  ).exec();
  return doc;
}

async function persistWaitingRoomLeave(conversationId, patientId) {
  const cid = String(conversationId || '').trim();
  const pid = String(patientId || '').trim();
  if (!mongoose.Types.ObjectId.isValid(cid) || !mongoose.Types.ObjectId.isValid(pid)) return;
  await WaitingRoomSession.deleteOne({ conversation: cid, patient: pid }).exec();
}

async function hydrateWaitingRoomsFromDb() {
  try {
    const rows = await WaitingRoomSession.find({}).lean();
    for (const r of rows) {
      const cid = String(r.conversation);
      waitingRooms.set(cid, {
        patientId: String(r.patient),
        doctorId: String(r.doctor),
        patientName: r.patientName || 'Patient',
        enteredAt: new Date(r.enteredAt).getTime(),
        notified: false,
      });
    }
    console.log(`[WAITING] hydraté ${rows.length} session(s) depuis MongoDB`);
  } catch (err) {
    console.error('[WAITING] hydrate MongoDB', err);
  }
}

module.exports = {
  persistWaitingRoomEnter,
  persistWaitingRoomLeave,
  hydrateWaitingRoomsFromDb
};
