const Conversation = require('../models/Conversation');
const Message = require('../models/Message');
const Doctor = require('../models/Doctor');
const { emitToConversation } = require('./realtimeGateway');

function normalizedAbsenceText(value) {
  return String(value || '').trim();
}

function isPatientMessageUrgent(payload) {
  if (!payload || typeof payload !== 'object') return false;
  if (payload.urgency === 'urgent') return true;
  const importance = String(payload.importance || '').trim().toLowerCase();
  return importance === 'très important' || importance === 'tres important';
}

async function postAbsenceNoticeToConversation(conversationId, doctorId, absenceMessage) {
  const text = normalizedAbsenceText(absenceMessage);
  if (!text) return null;

  const msg = await Message.create({
    conversation: conversationId,
    fromType: 'doctor',
    from: doctorId,
    type: 'doctor_absence',
    content: text,
    payload: { source: 'absence_mode' },
  });

  emitToConversation(String(conversationId), 'chat:new_activity', {
    conversationId: String(conversationId),
    messageId: String(msg._id),
    fromType: 'doctor',
    type: 'doctor_absence',
  });

  return msg;
}

async function broadcastDoctorAbsence({
  doctorId,
  absenceMessage,
  previousEnabled,
  previousMessage,
}) {
  const text = normalizedAbsenceText(absenceMessage);
  if (!text) return { posted: 0 };

  const messageChanged = text !== normalizedAbsenceText(previousMessage);
  const toggledOn = previousEnabled !== true;
  if (!toggledOn && !messageChanged) {
    return { posted: 0, skipped: true };
  }

  const convos = await Conversation.find({ doctor: doctorId }).select('_id').lean();
  let posted = 0;
  for (const c of convos) {
    if (!c?._id) continue;
    await postAbsenceNoticeToConversation(c._id, doctorId, text);
    posted += 1;
  }
  return { posted };
}

async function emitDoctorStatusToConversations(doctor) {
  const convos = await Conversation.find({ doctor: doctor._id }).select('_id').lean();
  for (const c of convos) {
    const convId = c && c._id ? String(c._id) : '';
    if (!convId) continue;
    emitToConversation(convId, 'doctor:status_updated', {
      conversationId: convId,
      doctorId: String(doctor._id),
      status: doctor.status,
      statusUpdatedAt: doctor.statusUpdatedAt,
      absenceMessage: doctor.absenceMessage || null,
      autoReplyEnabled: doctor.autoReplyEnabled === true,
      photoPath: doctor.photoPath || null,
    });
  }
}

async function ensureAbsenceNoticeInConversation(conversationId, doctorId) {
  const doctor = await Doctor.findById(doctorId)
    .select('autoReplyEnabled absenceMessage')
    .lean();
  if (!doctor?.autoReplyEnabled) return null;

  const text = normalizedAbsenceText(doctor.absenceMessage);
  if (!text) return null;

  const existing = await Message.findOne({
    conversation: conversationId,
    type: 'doctor_absence',
    content: text,
  })
    .sort({ createdAt: -1 })
    .lean();
  if (existing) return null;

  return postAbsenceNoticeToConversation(conversationId, doctorId, text);
}

async function maybeSendDoctorAbsenceAutoReply(conversationId, patientMessage) {
  const conv = await Conversation.findById(conversationId).select('doctor').lean();
  if (!conv?.doctor) return null;

  const doctor = await Doctor.findById(conv.doctor)
    .select('autoReplyEnabled absenceMessage')
    .lean();
  if (!doctor?.autoReplyEnabled) return null;

  const text = normalizedAbsenceText(doctor.absenceMessage);
  if (!text) return null;

  const msgType = patientMessage?.type || 'text';
  if (msgType !== 'text' && msgType !== 'attachment' && msgType !== 'file') {
    return null;
  }

  const payload = patientMessage?.payload || {};
  if (isPatientMessageUrgent(payload)) return null;

  return postAbsenceNoticeToConversation(conversationId, conv.doctor, text);
}

module.exports = {
  postAbsenceNoticeToConversation,
  broadcastDoctorAbsence,
  emitDoctorStatusToConversations,
  ensureAbsenceNoticeInConversation,
  maybeSendDoctorAbsenceAutoReply,
};
