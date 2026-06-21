const Conversation = require('../models/Conversation');
const Patient = require('../models/Patient');
const { decrypt } = require('./cryptoService');
const { emitToConversation, emitToUserId } = require('./realtimeGateway');
const { sendPushToUser } = require('./pushNotificationService');
const {
  createAppNotification,
  buildDoctorDedupeKey,
} = require('./appNotificationService');

async function loadConversationPatientContext(conversationId) {
  const conv = await Conversation.findById(conversationId)
    .populate('patient', 'fullName photoPath')
    .select('doctor patient')
    .lean();
  if (!conv) return null;

  const doctorId = conv.doctor ? String(conv.doctor) : '';
  const patientId = conv.patient?._id
    ? String(conv.patient._id)
    : String(conv.patient || '');
  let patientName = 'Patient';
  if (conv.patient?.fullName) {
    try {
      patientName = decrypt(conv.patient.fullName) || patientName;
    } catch (_) {
      // ignore
    }
  }

  return {
    conversationId: String(conversationId),
    doctorId,
    patientId,
    patientName,
    patientPhotoPath: conv.patient?.photoPath || null,
  };
}

async function resolvePatientName(patientId) {
  if (!patientId) return 'Patient';
  const patient = await Patient.findById(patientId).select('fullName').lean();
  if (!patient?.fullName) return 'Patient';
  try {
    return decrypt(patient.fullName) || 'Patient';
  } catch (_) {
    return 'Patient';
  }
}

async function notifyDoctorPushAndSocket({
  doctorId,
  eventType,
  title,
  body,
  payload = {},
}) {
  if (!doctorId) return;

  const socketPayload = {
    type: eventType,
    title: String(title || ''),
    body: String(body || ''),
    ...payload,
  };

  emitToUserId(doctorId, 'doctor:notification', socketPayload);

  if (
    eventType === 'teleconsult_request' ||
    eventType === 'teleconsult_form' ||
    eventType === 'chat_message'
  ) {
    emitToUserId(doctorId, 'doctor:inbox_new_message', {
      conversationId: payload.conversationId ? String(payload.conversationId) : '',
      messageId: payload.messageId ? String(payload.messageId) : '',
      notificationType: eventType,
    });
  }

  const pushData = { type: eventType };
  for (const [key, value] of Object.entries(payload)) {
    pushData[String(key)] = String(value ?? '');
  }

  await sendPushToUser({
    userId: doctorId,
    role: 'doctor',
    appName: 'doctor',
    title: String(title || 'Télémedecine'),
    body: String(body || ''),
    data: pushData,
  });

  try {
    await createAppNotification({
      recipientRole: 'doctor',
      recipientId: doctorId,
      type: String(eventType || 'doctor_notice'),
      title,
      body,
      payload: socketPayload,
      dedupeKey: buildDoctorDedupeKey(doctorId, eventType, socketPayload),
    });
  } catch (e) {
    console.error('[NOTIFICATION] doctor persist', e);
  }
}

async function notifyDoctorTeleconsultRequest({
  conversationId,
  requestId,
  messageId,
  motif,
}) {
  const ctx = await loadConversationPatientContext(conversationId);
  if (!ctx?.doctorId) return;

  const snippet = motif ? String(motif).trim().slice(0, 140) : '';
  await notifyDoctorPushAndSocket({
    doctorId: ctx.doctorId,
    eventType: 'teleconsult_request',
    title: 'Nouvelle demande',
    body: snippet
      ? `${ctx.patientName} : ${snippet}`
      : `${ctx.patientName} a envoyé une demande de téléconsultation.`,
    payload: {
      conversationId: ctx.conversationId,
      patientId: ctx.patientId,
      patientName: ctx.patientName,
      requestId: String(requestId || ''),
      messageId: messageId ? String(messageId) : '',
    },
  });

  emitToConversation(ctx.conversationId, 'chat:new_activity', {
    conversationId: ctx.conversationId,
    messageId: messageId ? String(messageId) : '',
    type: 'request_teleconsult',
  });
}

async function notifyDoctorTeleconsultForm({
  conversationId,
  formId,
  messageId,
  motif,
  symptomes,
}) {
  const ctx = await loadConversationPatientContext(conversationId);
  if (!ctx?.doctorId) return;

  const detail = [motif, symptomes]
    .map((v) => (v ? String(v).trim() : ''))
    .filter(Boolean)
    .join(' — ')
    .slice(0, 140);

  await notifyDoctorPushAndSocket({
    doctorId: ctx.doctorId,
    eventType: 'teleconsult_form',
    title: 'Nouveau formulaire',
    body: detail
      ? `${ctx.patientName} : ${detail}`
      : `${ctx.patientName} a envoyé un formulaire de téléconsultation.`,
    payload: {
      conversationId: ctx.conversationId,
      patientId: ctx.patientId,
      patientName: ctx.patientName,
      formId: String(formId || ''),
      messageId: messageId ? String(messageId) : '',
    },
  });

  if (messageId) {
    emitToConversation(ctx.conversationId, 'chat:new_activity', {
      conversationId: ctx.conversationId,
      messageId: String(messageId),
      type: 'form_teleconsult',
    });
  }
}

async function notifyDoctorWaitingRoom({
  conversationId,
  doctorId,
  patientId,
  patientName,
  enteredAt,
}) {
  const did = String(doctorId || '').trim();
  if (!did) return;

  const name = String(patientName || '').trim() || (await resolvePatientName(patientId));
  const enteredIso = enteredAt ? new Date(enteredAt).toISOString() : new Date().toISOString();

  await notifyDoctorPushAndSocket({
    doctorId: did,
    eventType: 'waiting_room',
    title: 'Salle d\'attente',
    body: `${name} est en attente de téléconsultation.`,
    payload: {
      conversationId: String(conversationId || ''),
      patientId: String(patientId || ''),
      patientName: name,
      enteredAt: enteredIso,
    },
  });
}

async function notifyDoctorBloodPressureAlert({
  doctorId,
  patientId,
  patientName,
  conversationId,
  alert,
}) {
  const did = String(doctorId || '').trim();
  if (!did || !alert) return;

  const name = String(patientName || '').trim() || (await resolvePatientName(patientId));
  const alertType = String(alert.type || 'Alerte').trim();
  const alertMessage = String(alert.message || '').trim();
  const body = alertMessage
    ? `${name} : ${alertMessage}`
    : `${name} — ${alertType} (${alert.systolic}/${alert.diastolic} mmHg)`;

  await notifyDoctorPushAndSocket({
    doctorId: did,
    eventType: 'blood_pressure_alert',
    title: 'Alerte tension',
    body,
    payload: {
      conversationId: conversationId ? String(conversationId) : '',
      patientId: String(patientId || ''),
      patientName: name,
      alertType,
      severity: String(alert.severity || ''),
      alertId: alert.id ? String(alert.id) : '',
    },
  });
}

module.exports = {
  notifyDoctorTeleconsultRequest,
  notifyDoctorTeleconsultForm,
  notifyDoctorWaitingRoom,
  notifyDoctorBloodPressureAlert,
};
