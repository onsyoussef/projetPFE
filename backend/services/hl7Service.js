const HL7 = require('hl7-standard');
const mongoose = require('mongoose');
const Hl7Message = require('../models/Hl7Message');
const Message = require('../models/Message');
const Conversation = require('../models/Conversation');
const Patient = require('../models/Patient');
const { splitName } = require('./utilsService');
const { decrypt } = require('./cryptoService');
function buildHl7FromJson(body = {}) {
  const patient = body.patient || {};
  const measures = Array.isArray(body.measures) ? body.measures : [];
  const files = Array.isArray(body.files) ? body.files : [];
  const { firstName, lastName } = splitName(patient.fullName);
  const msgTs = hl7NowTs();
  const ctrl = `MSG${Date.now()}`;

  const msh = [
    'MSH',
    '^~\\&',
    'TELEMED_FLUTTER',
    'MOBILE',
    'TELEMED_BACKEND',
    'NODE',
    msgTs,
    '',
    'ORU^R01',
    ctrl,
    'P',
    '2.5',
  ].join('|');

  const pid = [
    'PID',
    '1',
    '',
    hl7Escape(patient.id || patient.patientId || ''),
    '',
    `${hl7Escape(lastName)}^${hl7Escape(firstName)}`,
    '',
    hl7Escape(patient.dob || ''),
    hl7Escape(patient.sex || ''),
    '',
    '',
    hl7Escape(patient.address || ''),
    '',
    hl7Escape(patient.phone || ''),
  ].join('|');

  const obxSegments = [];
  let idx = 1;
  for (const m of measures) {
    const t = String(m.type || '').toUpperCase();
    const valueType = t === 'NM' || typeof m.value === 'number' ? 'NM' : 'TX';
    obxSegments.push(
      [
        'OBX',
        String(idx++),
        valueType,
        `${hl7Escape(m.code || 'MEASURE')}^${hl7Escape(m.label || m.code || 'Mesure')}^L`,
        '',
        hl7Escape(m.value ?? ''),
        hl7Escape(m.unit || ''),
        '',
        '',
        'F',
        '',
        '',
        msgTs,
      ].join('|')
    );
  }

  for (const f of files) {
    if (!f || !f.url) continue;
    obxSegments.push(
      [
        'OBX',
        String(idx++),
        'ED',
        `${hl7Escape(f.label || 'MED_FILE')}^${hl7Escape(f.mimetype || 'file')}^L`,
        '',
        `URL^${hl7Escape(f.url)}`,
        '',
        '',
        '',
        'F',
        '',
        '',
        msgTs,
      ].join('|')
    );
  }

  return [msh, pid, ...obxSegments].join('\r');
}

function parsePidName(nameField = '') {
  const [lastName = '', firstName = ''] = String(nameField).split('^');
  return { firstName, lastName };
}

function parseHl7Message(raw = '') {
  const text = String(raw || '').trim();
  if (!text) return { msh: {}, pid: {}, obx: [] };
  const lines = text.split(/\r\n|\n|\r/).filter(Boolean);
  const out = { msh: {}, pid: {}, obx: [] };

  for (const line of lines) {
    const f = line.split('|');
    const seg = f[0];
    if (seg === 'MSH') {
      out.msh = {
        sendingApplication: f[2] || '',
        sendingFacility: f[3] || '',
        receivingApplication: f[4] || '',
        receivingFacility: f[5] || '',
        messageDateTime: f[6] || '',
        messageType: f[8] || '',
        controlId: f[9] || '',
        version: f[11] || '',
      };
    } else if (seg === 'PID') {
      const n = parsePidName(f[5] || '');
      out.pid = {
        patientId: f[3] || '',
        ...n,
        dob: f[7] || '',
        sex: f[8] || '',
        address: f[11] || '',
        phone: f[13] || '',
      };
    } else if (seg === 'OBX') {
      const idParts = String(f[3] || '').split('^');
      out.obx.push({
        setId: f[1] || '',
        valueType: f[2] || '',
        code: idParts[0] || '',
        label: idParts[1] || '',
        value: f[5] || '',
        unit: f[6] || '',
        status: f[10] || '',
        observedAt: f[13] || '',
      });
    }
  }
  return out;
}

function validateAndNormalizeHl7(hl7Raw = '') {
  try {
    const h = new HL7(String(hl7Raw || ''));
    h.transform();
    const normalized = h.build();
    return { ok: true, normalized: normalized || hl7Raw };
  } catch (e) {
    return { ok: false, error: e };
  }
}

async function persistAutoHl7ForConversation({
  conversationId,
  source,
  fromType,
  content = '',
  payload = {},
  files = [],
}) {
  try {
    const patient = await loadConversationPatientForHl7(conversationId);
    if (!patient) return null;
    const measures = [];
    const p = payload && typeof payload === 'object' ? payload : {};

    if (typeof content === 'string' && content.trim()) {
      measures.push({
        code: 'CHAT_NOTE',
        label: fromType === 'doctor' ? 'Doctor note' : 'Patient note',
        value: content.trim(),
        unit: '',
        type: 'TX',
      });
    }
    if (p.motif || p.symptomes || p.traitements || p.allergies) {
      measures.push({
        code: 'TELECONSULT_FORM',
        label: 'Teleconsult form summary',
        value: JSON.stringify({
          motif: p.motif || '',
          symptomes: p.symptomes || '',
          traitements: p.traitements || '',
          allergies: p.allergies || '',
        }),
        unit: '',
        type: 'TX',
      });
    }
    if (p.systolic != null || p.diastolic != null || p.heartRate != null || p.temperature != null) {
      if (p.systolic != null) {
        measures.push({ code: '8480-6', label: 'Systolic blood pressure', value: p.systolic, unit: 'mm[Hg]', type: 'NM' });
      }
      if (p.diastolic != null) {
        measures.push({ code: '8462-4', label: 'Diastolic blood pressure', value: p.diastolic, unit: 'mm[Hg]', type: 'NM' });
      }
      if (p.heartRate != null) {
        measures.push({ code: '8867-4', label: 'Heart rate', value: p.heartRate, unit: '/min', type: 'NM' });
      }
      if (p.temperature != null) {
        measures.push({ code: '8310-5', label: 'Body temperature', value: p.temperature, unit: 'Cel', type: 'NM' });
      }
    }

    const payloadJson = {
      patient,
      measures,
      files: Array.isArray(files) ? files : [],
    };
    let hl7Message = buildHl7FromJson(payloadJson);
    const check = validateAndNormalizeHl7(hl7Message);
    if (!check.ok) {
      console.warn('HL7 auto validation failed:', check.error?.message || check.error);
      return null;
    }
    hl7Message = check.normalized;
    const parsed = parseHl7Message(hl7Message);
    await Hl7Message.create({
      direction: 'outbound',
      source: source || 'auto-chat',
      patientExternalId: String(patient.id || ''),
      hl7Raw: hl7Message,
      jsonPayload: payloadJson,
      parsed,
      status: 'generated',
    });
    return true;
  } catch (e) {
    console.warn('persistAutoHl7ForConversation:', e.message);
    return null;
  }
}

async function loadConversationPatientForHl7(conversationId) {
  if (!conversationId || !mongoose.Types.ObjectId.isValid(String(conversationId))) return null;
  const conv = await Conversation.findById(conversationId).lean();
  if (!conv) return null;
  const p = await Patient.findById(conv.patient).lean();
  if (!p) return null;
  return {
    id: p._id?.toString() || '',
    fullName: decrypt(p.fullName) || '',
    phone: decrypt(p.phone) || '',
    address: decrypt(p.addressExact) || '',
    sex: '',
    dob: '',
  };
}

function hl7Escape(v) {
  return String(v ?? '')
    .replace(/\\/g, '\\E\\')
    .replace(/\|/g, '\\F\\')
    .replace(/\^/g, '\\S\\')
    .replace(/&/g, '\\T\\')
    .replace(/~/g, '\\R\\');
}

function hl7NowTs() {
  const d = new Date();
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  const hh = String(d.getHours()).padStart(2, '0');
  const mi = String(d.getMinutes()).padStart(2, '0');
  const ss = String(d.getSeconds()).padStart(2, '0');
  return `${yyyy}${mm}${dd}${hh}${mi}${ss}`;
}

module.exports = {
  buildHl7FromJson,
  parseHl7Message,
  validateAndNormalizeHl7,
  persistAutoHl7ForConversation,
  loadConversationPatientForHl7,
  hl7Escape,
  hl7NowTs
};
