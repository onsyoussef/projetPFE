const path = require('path');
const mongoose = require('mongoose');
const Patient = require('../models/Patient');
const Doctor = require('../models/Doctor');
const Conversation = require('../models/Conversation');
const { emitToUserId } = require('./realtimeGateway');
const { sendPushToUser, sendDataOnlyToUser, sendIncomingCallToUser } = require('./pushNotificationService');
const { conversationIdFromCallRoomId } = require('./callService');
const { decrypt, decryptField } = require('./cryptoService');
const EMAIL_FORMAT_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
function fixUploadFilename(name) {
  if (name == null || typeof name !== 'string') return '';
  const s = name.trim();
  if (!s) return '';
  if (!s.includes('Ã') && !s.includes('Â')) return s;
  try {
    const decoded = Buffer.from(s, 'latin1').toString('utf8');
    return decoded.includes('\uFFFD') ? s : decoded;
  } catch {
    return s;
  }
}

function parseMaybeJson(value, fallback) {
  if (value == null) return fallback;
  if (typeof value === 'object') return value;
  if (typeof value !== 'string') return fallback;
  const s = value.trim();
  if (!s) return fallback;
  try {
    return JSON.parse(s);
  } catch {
    return fallback;
  }
}

function splitName(fullName = '') {
  const n = String(fullName || '').trim();
  if (!n) return { lastName: '', firstName: '' };
  const parts = n.split(/\s+/);
  const firstName = parts.shift() || '';
  const lastName = parts.join(' ');
  return { firstName, lastName };
}

function isValidEmailFormat(email) {
  return typeof email === 'string' && EMAIL_FORMAT_REGEX.test(email.trim());
}

function assertPasswordMin8(password) {
  const raw = String(password || '');
  const errors = [];
  if (/\s/.test(raw)) errors.push('sans espaces');
  if (raw.length < 8) errors.push('au moins 8 caractères');
  if (!/[A-Z]/.test(raw)) errors.push('au moins 1 lettre majuscule (A-Z)');
  if (!/[a-z]/.test(raw)) errors.push('au moins 1 lettre minuscule (a-z)');
  if (!/[0-9]/.test(raw)) errors.push('au moins 1 chiffre (0-9)');
  if (!/[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\;/`~]/.test(raw)) {
    errors.push('au moins 1 caractère spécial (@, #, $, %, &, !, ?…)');
  }
  if (errors.length === 0) return null;
  return `Mot de passe invalide : ${errors.join(', ')}.`;
}

function getEffectiveDoctorStatus(doctor) {
  return doctor.status ?? 'available';
}

function escapeRegex(s) {
  return String(s || '').replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function patientPhotoPathFromPopulated(p) {
  if (!p || typeof p !== 'object') return null;
  return p.photoPath || null;
}

function dossierPublicUrl(pathStr) {
  if (pathStr == null || typeof pathStr !== 'string') return pathStr;
  const t = pathStr.trim();
  if (t.startsWith('http://') || t.startsWith('https://')) return t;
  const base = String(process.env.API_BASE_URL || 'http://localhost:3000').replace(/\/$/, '');
  return t.startsWith('/') ? `${base}${t}` : `${base}/${t}`;
}

function validatePatientDossierUpload(category, mimetype, filename) {
  const m = String(mimetype || '').toLowerCase();
  const base = String(filename || '').toLowerCase();
  const ext = path.extname(base);
  const isPdf = m === 'application/pdf' || ext === '.pdf';
  const isJpgPng =
    m === 'image/jpeg' ||
    m === 'image/png' ||
    m === 'image/jpg' ||
    ['.jpg', '.jpeg', '.png'].includes(ext);
  if (category === 'analyses' || category === 'ordonnances') {
    if (isPdf || isJpgPng) return { ok: true };
    return {
      ok: false,
      message: 'Formats acceptés : PDF, JPG, PNG.',
    };
  }
  if (category === 'images') {
    if (isJpgPng && !isPdf) return { ok: true };
    return { ok: false, message: 'Formats acceptés : JPG, PNG uniquement.' };
  }
  if (category === 'fichiers') {
    const okOffice =
      m.includes('wordprocessingml') ||
      m.includes('msword') ||
      m === 'application/msword' ||
      m.includes('spreadsheetml') ||
      m.includes('excel') ||
      m === 'application/vnd.ms-excel' ||
      m === 'text/plain' ||
      ext === '.txt' ||
      ext === '.doc' ||
      ext === '.docx' ||
      ext === '.xls' ||
      ext === '.xlsx';
    if (isPdf || okOffice) return { ok: true };
    return {
      ok: false,
      message: 'Formats acceptés : PDF, Word, Excel, texte.',
    };
  }
  return { ok: false, message: 'Catégorie invalide.' };
}

function dossierCloudinaryDestroyType(mimetype) {
  const m = String(mimetype || '').toLowerCase();
  if (m.startsWith('image/')) return 'image';
  if (m.startsWith('video/') || m.startsWith('audio/')) return 'video';
  return 'raw';
}

function normalizedTeleconsultFormStatus(f) {
  let st = f.status || 'pending';
  if (!f.status && f.workflowStatus && f.workflowStatus !== 'pending') {
    st = 'accepted';
  }
  return st;
}

/** Filtre téléconsultations rattachées à un médecin (champs directs ou conversation héritée). */
async function teleconsultConversationIdsForDoctor(doctorId) {
  return Conversation.find({ doctor: doctorId }).distinct('_id');
}

function teleconsultRequestDoctorScope(doctorId, convIds) {
  return { $or: [{ doctor: doctorId }, { conversation: { $in: convIds } }] };
}

function teleconsultFormDoctorScope(doctorId, convIds) {
  return { $or: [{ doctor: doctorId }, { conversation: { $in: convIds } }] };
}

async function canDoctorAccessTeleconsultForm(doctorId, form) {
  if (!form) return false;
  if (form.doctor && String(form.doctor) === String(doctorId)) return true;
  if (!form.conversation) return false;
  const conv = await Conversation.findById(form.conversation).select('doctor').lean();
  return conv && String(conv.doctor) === String(doctorId);
}

const _patientInboxCountableTypes = new Set([
  'text',
  'attachment',
  'file',
  'request_teleconsult',
  'form_teleconsult',
  'teleconsult_scheduled',
  'prescription',
]);

/** Badge tableau de bord médecin : nouveau message côté patient (POST /messages ou upload fichier). */
async function notifyDoctorInboxNewMessage(conversationId, fromType, msgType, messageId) {
  if (fromType !== 'patient' || !_patientInboxCountableTypes.has(msgType)) return;
  const convDoctor = await Conversation.findById(conversationId).select('doctor patient').lean();
  const docId = convDoctor && convDoctor.doctor ? String(convDoctor.doctor) : '';
  if (!docId) return;
  let patientName = 'Patient';
  if (convDoctor && convDoctor.patient) {
    const p = await Patient.findById(convDoctor.patient).select('fullName').lean();
    if (p && p.fullName) patientName = String(decrypt(p.fullName));
  }
  emitToUserId(docId, 'doctor:inbox_new_message', {
    conversationId: String(conversationId),
    messageId: String(messageId),
  });
  await sendPushToUser({
    userId: docId,
    role: 'doctor',
    appName: 'doctor',
    title: 'Nouveau message',
    body: `${patientName} vous a envoyé un message.`,
    data: {
      type: 'chat_message',
      conversationId: String(conversationId),
      messageId: String(messageId),
    },
  });
}

/** Badge tableau de bord patient : nouveau message côté médecin (POST /messages ou upload fichier). */
/**
 * Push data-only « incoming_call » (FCM haute priorité + CallKit côté Flutter).
 * Complète Socket.IO lorsque l’app est en arrière-plan ou terminée.
 */
async function notifyPatientIncomingCall({ patientUserId, roomId, callerUserId, mediaType }) {
  const callerInfo = await getUserInfoByUserId(callerUserId);
  const video = mediaType === 'video';
  const doctorName = callerInfo.name || 'Médecin';
  const doctorAvatarUrl = callerInfo.avatarUrl ? String(callerInfo.avatarUrl) : '';
  const convId = conversationIdFromCallRoomId(String(roomId || '')) || '';
  let doctorId = String(callerUserId);
  if (convId && mongoose.Types.ObjectId.isValid(convId)) {
    const c = await Conversation.findById(convId).select('doctor').lean();
    if (c && c.doctor) doctorId = String(c.doctor);
  }
  const callId = String(roomId);
  await sendIncomingCallToUser({
    userId: patientUserId,
    role: 'patient',
    appName: 'patient',
    data: {
      type: 'incoming_call',
      callId,
      roomId: String(roomId),
      callerId: String(callerUserId),
      callerName: doctorName,
      callerAvatar: doctorAvatarUrl,
      callType: video ? 'video' : 'audio',
      fromUserId: String(callerUserId),
      doctorId,
      mediaType: video ? 'video' : 'audio',
      doctorName,
      doctorAvatarUrl,
      conversationId: convId,
    },
  });
}

/** Annule la notification locale d’appel entrant (raccroché médecin, timeout, etc.). */
async function notifyCancelIncomingCallPush({ patientUserId, roomId }) {
  if (!roomId) return;
  await sendDataOnlyToUser({
    userId: patientUserId,
    role: 'patient',
    appName: 'patient',
    data: {
      type: 'cancel_incoming_call',
      roomId: String(roomId),
    },
  });
}

/** Notification push patient : appel manqué (message système `call_event` / `call_log`). */
async function notifyPatientCallMissedPush(conversationId, messageId, payload) {
  const oc = payload && payload.outcome != null ? String(payload.outcome).trim() : '';
  if (!payload || payload.kind !== 'call_log' || oc !== 'missed') return;
  const mt = payload.mediaType === 'video' ? 'video' : 'audio';
  const conv = await Conversation.findById(conversationId).select('patient doctor').lean();
  const patientId = conv && conv.patient ? String(conv.patient) : '';
  if (!patientId) return;
  let doctorName = 'Votre médecin';
  if (conv && conv.doctor) {
    const d = await Doctor.findById(conv.doctor).select('fullName').lean();
    if (d && d.fullName) doctorName = String(decrypt(d.fullName));
  }
  const video = mt === 'video';
  const when = new Date().toLocaleString('fr-FR', {
    dateStyle: 'short',
    timeStyle: 'short',
  });
  const title = 'Appel manqué';
  const body = video
    ? `Vous avez manqué un appel vidéo de ${doctorName}.\n${when}`
    : `Vous avez manqué un appel de ${doctorName}.\n${when}`;
  await sendPushToUser({
    userId: patientId,
    role: 'patient',
    appName: 'patient',
    title,
    body,
    data: {
      type: 'call_missed',
      conversationId: String(conversationId),
      messageId: String(messageId),
      mediaType: video ? 'video' : 'audio',
      missedAt: new Date().toISOString(),
      doctorId: conv && conv.doctor ? String(conv.doctor) : '',
      doctorName,
    },
  });
}

async function notifyDoctorNoAnswerPush({ doctorUserId, patientUserId, mediaType }) {
  const doctorId = String(doctorUserId || '').trim();
  if (!doctorId) return;
  const patientInfo = await getUserInfoByUserId(patientUserId);
  const patientName = patientInfo.name || 'Le patient';
  const video = mediaType === 'video';
  await sendPushToUser({
    userId: doctorId,
    role: 'doctor',
    appName: 'doctor',
    title: 'Appel sans réponse',
    body: video
      ? `${patientName} n'a pas répondu à votre appel vidéo.`
      : `${patientName} n'a pas répondu à votre appel audio.`,
    data: {
      type: 'call_no_answer',
      patientId: String(patientUserId || ''),
      patientName,
      mediaType: video ? 'video' : 'audio',
    },
  });
}

async function notifyPatientInboxNewMessage(conversationId, fromType, msgType, messageId) {
  if (fromType !== 'doctor' || !_patientInboxCountableTypes.has(msgType)) return;
  const convPatient = await Conversation.findById(conversationId).select('patient doctor').lean();
  const patientId = convPatient && convPatient.patient ? String(convPatient.patient) : '';
  if (!patientId) return;
  let doctorName = 'Médecin';
  if (convPatient && convPatient.doctor) {
    const d = await Doctor.findById(convPatient.doctor).select('fullName').lean();
    if (d && d.fullName) doctorName = String(decrypt(d.fullName));
  }
  emitToUserId(patientId, 'patient:inbox_new_message', {
    conversationId: String(conversationId),
    messageId: String(messageId),
  });
  await sendPushToUser({
    userId: patientId,
    role: 'patient',
    appName: 'patient',
    title: 'Nouveau message',
    body: `${doctorName} vous a envoyé un message.`,
    data: {
      type: 'chat_message',
      conversationId: String(conversationId),
      messageId: String(messageId),
    },
  });
}

async function getUserInfoByUserId(userId) {
  if (!userId || !mongoose.Types.ObjectId.isValid(String(userId))) {
    return { id: String(userId || ''), name: 'Utilisateur', avatarUrl: null, role: 'unknown' };
  }
  const uid = String(userId);
  const p = await Patient.findById(uid).select('fullName photoPath').lean();
  if (p) {
    return {
      id: uid,
      name: decrypt(p.fullName) || 'Utilisateur',
      avatarUrl: p.photoPath || null,
      role: 'patient',
    };
  }
  const d = await Doctor.findById(uid).select('fullName photoPath specialty').lean();
  if (d) {
    return {
      id: uid,
      name: decrypt(d.fullName) || 'Utilisateur',
      avatarUrl: d.photoPath || null,
      specialty: d.specialty ? decryptField(d.specialty) : '',
      role: 'doctor',
    };
  }
  return { id: String(userId), name: 'Utilisateur', avatarUrl: null, role: 'unknown' };
}

module.exports = {
  escapeRegex,
  teleconsultConversationIdsForDoctor,
  teleconsultRequestDoctorScope,
  teleconsultFormDoctorScope,
  canDoctorAccessTeleconsultForm,
  notifyDoctorInboxNewMessage,
  notifyPatientInboxNewMessage,
  notifyPatientIncomingCall,
  notifyCancelIncomingCallPush,
  notifyPatientCallMissedPush,
  notifyDoctorNoAnswerPush,
  fixUploadFilename,
  parseMaybeJson,
  splitName,
  isValidEmailFormat,
  assertPasswordMin8,
  getEffectiveDoctorStatus,
  patientPhotoPathFromPopulated,
  dossierPublicUrl,
  validatePatientDossierUpload,
  dossierCloudinaryDestroyType,
  normalizedTeleconsultFormStatus,
  getUserInfoByUserId
};
