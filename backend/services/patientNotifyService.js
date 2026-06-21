const { emitToUserId } = require('./realtimeGateway');
const { sendPushToUser } = require('./pushNotificationService');

function stringifyPushData(payload = {}, pushType) {
  const pushData = { type: String(pushType || 'patient_notice') };
  for (const [key, value] of Object.entries(payload || {})) {
    if (value === true) {
      pushData[String(key)] = 'true';
    } else if (value === false) {
      pushData[String(key)] = 'false';
    } else {
      pushData[String(key)] = String(value ?? '');
    }
  }
  return pushData;
}

async function notifyPatientPushAndSocket({
  patientId,
  socketEvent,
  title,
  body,
  payload = {},
  pushType,
}) {
  const pid = String(patientId || '').trim();
  if (!pid) return;

  const socketPayload = {
    title: String(title || ''),
    body: String(body || ''),
    ...payload,
  };

  if (socketEvent) {
    emitToUserId(pid, socketEvent, socketPayload);
  }

  try {
    await sendPushToUser({
      userId: pid,
      role: 'patient',
      appName: 'patient',
      title: String(title || 'HeadsApp'),
      body: String(body || ''),
      data: stringifyPushData(payload, pushType),
    });
  } catch (e) {
    console.error('[PUSH] notifyPatientPushAndSocket', e);
  }
}

module.exports = {
  notifyPatientPushAndSocket,
  stringifyPushData,
};
