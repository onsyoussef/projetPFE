/**
 * RDV téléconsultation : message système dans la conversation + `chat:new_activity` (Socket.IO),
 * plus notification push FCM si Firebase est initialisé (`initPushNotifications` dans app.js).
 */
const RendezVous = require('../models/RendezVous');
const Conversation = require('../models/Conversation');
const Message = require('../models/Message');
const { emitToConversation, emitToUserId } = require('../services/realtimeGateway');
const { sendPushToUser } = require('./pushNotificationService');
const { stringifyPushData } = require('./patientNotifyService');
const { patientPhotoPathFromPopulated } = require('./utilsService');
const { decrypt } = require('./cryptoService');
const MOIS_FR_RDV = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

async function notifyPatientRdv(patientId, title, body, data = {}) {
  const pid = String(patientId || '').trim();
  if (!pid) return;
  try {
    const socketPayload = {
      title: String(title || ''),
      body: String(body || ''),
      ...data,
    };
    emitToUserId(pid, 'patient:rdv_notification', socketPayload);
    await sendPushToUser({
      userId: pid,
      role: 'patient',
      appName: 'patient',
      title: String(title || 'Télémedecine'),
      body: String(body || ''),
      data: stringifyPushData({ ...data, openChat: true }, 'rdv_update'),
    });
  } catch (e) {
    console.error('[RDV notify]', e);
  }
}

async function notifyAndMessagePatientRdvProgramme(opts) {
  const {
    conversationId,
    patientId,
    doctorId,
    rendezvousId,
    scheduledAt,
    dateYmd,
    heureHHmm,
    kind,
  } = opts;
  const content =
    kind === 'reprogramme'
      ? phraseRdvTeleconsultReprogramme(dateYmd, heureHHmm)
      : phraseRdvTeleconsultProgramme(dateYmd, heureHHmm);

  const msg = await Message.create({
    conversation: conversationId,
    fromType: 'system',
    type: 'rdv_teleconsult_programme',
    content,
    payload: {
      rendezvousId: String(rendezvousId),
      date: dateYmd,
      heure: padHeureHHmm(heureHHmm),
      kind: kind === 'reprogramme' ? 'reprogramme' : 'programme',
    },
  });

  emitToConversation(String(conversationId), 'chat:new_activity', {
    conversationId: String(conversationId),
    messageId: String(msg._id),
    fromType: 'system',
    type: 'rdv_teleconsult_programme',
  });

  const pushTitle =
    kind === 'reprogramme'
        ? 'Rendez-vous modifié'
        : 'Téléconsultation planifiée';
  await notifyPatientRdv(patientId, pushTitle, content, {
    rendezvousId: String(rendezvousId),
    kind: kind === 'reprogramme' ? 'reprogramme' : 'programme',
    conversationId: String(conversationId || ''),
    doctorId: doctorId ? String(doctorId) : '',
    scheduledAt: scheduledAt ? String(scheduledAt) : '',
  });
  return msg;
}

async function notifyAndMessagePatientRdvAnnule(opts) {
  const {
    conversationId,
    patientId,
    rendezvousId,
    dateYmd,
    heureHHmm,
    motif,
    content,
  } = opts;
  const msg = await Message.create({
    conversation: conversationId,
    fromType: 'system',
    type: 'rdv_teleconsult_annule',
    content,
    payload: {
      rendezvousId: String(rendezvousId),
      date: dateYmd,
      heure: padHeureHHmm(heureHHmm),
      motif: motif ? String(motif) : '',
    },
  });
  emitToConversation(String(conversationId), 'chat:new_activity', {
    conversationId: String(conversationId),
    messageId: String(msg._id),
    fromType: 'system',
    type: 'rdv_teleconsult_annule',
  });
  await notifyPatientRdv(patientId, 'Rendez-vous annulé', content, {
    rendezvousId: String(rendezvousId),
    kind: 'annule',
  });
  return msg;
}

async function buildDoctorAgendaListFromRendezVous(doctorId, opts = {}) {
  const dateFilter = String(opts.dateFilter || '').trim();
  const rvs = await RendezVous.find({
    medecinId: doctorId,
    statut: { $ne: 'annule' },
  })
    .populate('patientId', 'fullName photoPath')
    .populate('formulaireId', 'motif symptomes')
    .sort({ startAt: 1 })
    .lean();

  const convos = await Conversation.find({ doctor: doctorId }).lean();
  const convIdByPatientId = new Map();
  for (const c of convos) {
    const pid = c.patient != null ? String(c.patient) : '';
    if (pid) convIdByPatientId.set(pid, c._id.toString());
  }

  const list = [];
  for (const rv of rvs) {
    const dt = new Date(rv.startAt);
    if (Number.isNaN(dt.getTime())) continue;
    if (dateFilter) {
      const dayKey = dt.toISOString().slice(0, 10);
      if (dayKey !== dateFilter) continue;
    }
    const p = rv.patientId;
    const patientId =
      p && typeof p === 'object' && p._id != null ? String(p._id) : String(rv.patientId);
    const eff = effectiveRdvStatut(rv);
    const conversationId = convIdByPatientId.get(patientId) || '';
    let motif = 'Téléconsultation';
    const form = rv.formulaireId;
    if (form && typeof form === 'object') {
      const raw = form.motif || form.symptomes;
      if (typeof raw === 'string' && raw.trim()) motif = raw.trim().slice(0, 300);
    }

    list.push({
      id: String(rv._id),
      rendezvousId: String(rv._id),
      conversationId,
      patientId,
      patientNom: decrypt(p && p.fullName) || 'Patient',
      patientPhotoPath: patientPhotoPathFromPopulated(p),
      dateHeure: dt.toISOString(),
      duree: 30,
      motif,
      statut: eff,
      type: rv.type || 'teleconsultation',
    });
  }
  list.sort((a, b) => new Date(a.dateHeure) - new Date(b.dateHeure));
  return list;
}

/**
 * Créneau déjà pris pour le médecin (messages planifiés + collection RendezVous).
 * @returns {Promise<null | { kind: 'message'|'rendezvous', patientNom?: string, date?: string, heure?: string }>}
 */
async function doctorMinuteOccupied(doctorId, scheduledAtIso, opts = {}) {
  const excludeMessageId = opts.excludeMessageId ? String(opts.excludeMessageId) : null;
  const excludeRdvId = opts.excludeRdvId ? String(opts.excludeRdvId) : null;
  const chosenMs = new Date(scheduledAtIso).getTime();
  if (Number.isNaN(chosenMs)) return null;
  const chosenMinute = Math.floor(chosenMs / 60000);

  const convos = await Conversation.find({ doctor: doctorId }).select('_id').lean();
  const convIds = convos.map((c) => c._id);
  const existingMsgs = await Message.find({
    conversation: { $in: convIds },
    type: 'teleconsult_scheduled',
  }).lean();
  for (const m of existingMsgs) {
    if (excludeMessageId && String(m._id) === excludeMessageId) continue;
    const iso = m.payload && m.payload.scheduledAt;
    if (!iso) continue;
    const t = new Date(iso).getTime();
    if (Number.isNaN(t)) continue;
    if (Math.floor(t / 60000) !== chosenMinute) continue;
    let patientNom = 'Patient';
    try {
      const c = await Conversation.findById(m.conversation)
        .populate('patient', 'fullName')
        .lean();
      if (c && c.patient && c.patient.fullName) patientNom = decrypt(c.patient.fullName);
    } catch (_) {}
    const d = new Date(iso);
    return {
      kind: 'message',
      patientNom,
      date: d.toISOString().slice(0, 10),
      heure: `${String(d.getUTCHours()).padStart(2, '0')}:${String(d.getUTCMinutes()).padStart(2, '0')}`,
    };
  }

  const rvs = await RendezVous.find({
    medecinId: doctorId,
    statut: { $ne: 'annule' },
  })
    .populate('patientId', 'fullName')
    .lean();
  for (const r of rvs) {
    if (excludeRdvId && String(r._id) === excludeRdvId) continue;
    const t = new Date(r.startAt).getTime();
    if (Number.isNaN(t)) continue;
    if (Math.floor(t / 60000) !== chosenMinute) continue;
    return {
      kind: 'rendezvous',
      patientNom: decrypt(r.patientId && r.patientId.fullName) || 'Patient',
      date: r.date,
      heure: r.heure,
    };
  }
  return null;
}

function effectiveRdvStatut(r) {
  if (!r || r.statut === 'annule') return 'annule';
  if (r.statut === 'termine') return 'termine';
  const end = new Date(r.startAt).getTime() + 30 * 60000;
  if (Date.now() > end) return 'termine';
  return 'confirme';
}

function formatRdvJson(doc, patientPop, medecinPop) {
  const p = patientPop || doc.patientId;
  const m = medecinPop || doc.medecinId;
  const eff = effectiveRdvStatut(doc);
  return {
    id: String(doc._id),
    medecinId: String(doc.medecinId),
    patientId: String(doc.patientId),
    formulaireId: doc.formulaireId ? String(doc.formulaireId) : null,
    date: doc.date,
    heure: doc.heure,
    startAt: doc.startAt ? new Date(doc.startAt).toISOString() : null,
    type: doc.type || 'teleconsultation',
    statut: doc.statut,
    statutEffectif: eff,
    motifAnnulation: doc.motifAnnulation || '',
    patientNom: decrypt(p && p.fullName) || 'Patient',
    patientPhotoPath: patientPhotoPathFromPopulated(p),
    medecinNom: decrypt(m && m.fullName) || 'Médecin',
    medecinPhotoPath: m && m.photoPath ? m.photoPath : null,
    createdAt: doc.createdAt,
    updatedAt: doc.updatedAt,
  };
}

function phraseRdvTeleconsultProgramme(dateYmd, heureHHmm) {
  const dateFr = formattedFrenchDateFromYmd(dateYmd) || String(dateYmd);
  const h = padHeureHHmm(heureHHmm);
  return (
    `Votre rendez-vous de téléconsultation a été programmé pour le ${dateFr} à ${h}. ` +
    "Merci de vous connecter quelques minutes à l'avance."
  );
}

function phraseRdvTeleconsultReprogramme(dateYmd, heureHHmm) {
  const dateFr = formattedFrenchDateFromYmd(dateYmd) || String(dateYmd);
  const h = padHeureHHmm(heureHHmm);
  return (
    `Votre rendez-vous de téléconsultation a été reprogrammé pour le ${dateFr} à ${h}. ` +
    "Merci de vous connecter quelques minutes à l'avance."
  );
}

function formattedFrenchDateFromYmd(dateYmd) {
  const m = String(dateYmd || '').match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!m) return null;
  const y = parseInt(m[1], 10);
  const mo = parseInt(m[2], 10);
  const d = parseInt(m[3], 10);
  if (mo < 1 || mo > 12) return null;
  return `${d} ${MOIS_FR_RDV[mo - 1]} ${y}`;
}

function padHeureHHmm(h) {
  const parts = String(h || '').split(':');
  if (parts.length !== 2) return String(h || '').trim();
  return `${parts[0].padStart(2, '0')}:${parts[1].padStart(2, '0')}`;
}

module.exports = {
  notifyPatientRdv,
  notifyAndMessagePatientRdvProgramme,
  notifyAndMessagePatientRdvAnnule,
  buildDoctorAgendaListFromRendezVous,
  doctorMinuteOccupied,
  effectiveRdvStatut,
  formatRdvJson,
  phraseRdvTeleconsultProgramme,
  phraseRdvTeleconsultReprogramme,
  formattedFrenchDateFromYmd,
  padHeureHHmm
};
