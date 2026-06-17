require('dotenv').config();
const express = require('express');
const mongoose = require('mongoose');
const bcrypt = require('bcrypt');
const cors = require('cors');
const nodemailer = require('nodemailer');
const multer = require('multer');
const path = require('path');
const fs = require('fs/promises');
const http = require('http');
const https = require('https');
const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const rateLimit = require('express-rate-limit');
const { URL } = require('url');
const { initPushNotifications, sendPushToUser } = require('./pushNotificationService');
const { notifyPatientCallMissedPush } = require('./utilsService');
const { decrypt, decryptPatient, decryptDoctor, hashEmail } = require('./cryptoService');
const { buildPatientInfoSnapshot } = require('./patientInfoSnapshot');

process.on('unhandledRejection', (reason) => {
  console.error('[FATAL] Unhandled promise rejection:', reason);
});

process.on('uncaughtException', (err) => {
  console.error('[FATAL] Uncaught exception:', err);
  process.exit(1);
});

const JWT_SECRET = String(process.env.JWT_SECRET || '').trim();
if (!JWT_SECRET) {
  console.error('[FATAL] JWT_SECRET manquant. Définissez process.env.JWT_SECRET avant de démarrer.');
  process.exit(1);
}
const { Server } = require('socket.io');
const HL7 = require('hl7-standard');
const {
  uploadFileToCloudinary,
  uploadChatFileToCloudinary,
  isConfigured: isCloudinaryConfigured,
  resourceTypeFromMimetype,
  cloudinaryInlineDeliveryUrl,
  destroyByPublicId,
  tryParseCloudinaryImagePublicId,
} = require(path.join(__dirname, 'config', 'cloudinaryConfig'));

const app = express();
const server = http.createServer(app);
app.use(express.json());
const allowedOrigins = String(process.env.ALLOWED_ORIGINS || 'http://localhost:3000')
  .split(',')
  .map((v) => v.trim())
  .filter(Boolean);
const corsOptions = {
  origin(origin, callback) {
    // Autorise les clients non-browser (origin absent), sinon vérifie whitelist.
    if (!origin || allowedOrigins.includes(origin)) return callback(null, true);
    return callback(new Error('Origine non autorisée par CORS.'));
  },
  credentials: true,
};
app.use(cors(corsOptions));

// Dossier statique pour les pièces jointes
const uploadsDir = path.join(__dirname, 'uploads');
app.use('/uploads', express.static(uploadsDir));

// 🔹 Socket.IO (signalisation appels audio/vidéo WebRTC)
const io = new Server(server, {
  cors: {
    origin: allowedOrigins,
    methods: ['GET', 'POST'],
    credentials: true,
  },
});

const socketByUserId = new Map();
const userBySocketId = new Map();
const activeCalls = new Map();
/** conversationId -> { patientId, doctorId, patientName, enteredAt, notified } */
const waitingRooms = new Map();

// 🔹 Modèle Patient
const patientSchema = new mongoose.Schema(
  {
    fullName: { type: String, required: true },
    email: { type: String, required: true, unique: true },
    passwordHash: { type: String, required: true },
    country: { type: String, required: true },
    addressExact: { type: String, required: true },
    photoPath: { type: String },
    /** public_id Cloudinary (serveur uniquement, pour suppression à remplacement) */
    photoCloudinaryPublicId: { type: String },
    phone: { type: String, required: true },
  },
  { timestamps: true }
);

const Patient = mongoose.model('Patient', patientSchema);

// 🔹 Modèle Médecin (avec compte + adresse + latitude/longitude optionnels pour tri par distance)
const doctorSchema = new mongoose.Schema(
  {
    fullName: { type: String, required: true },
    specialty: { type: String, required: true },
    governorate: { type: String, required: true },
    address: { type: String },
    email: {
      type: String,
      lowercase: true,
      trim: true,
      unique: true,
      sparse: true,
    },
    phone: { type: String },
    passwordHash: { type: String },
    latitude: { type: Number },
    longitude: { type: Number },
    orderNumber: { type: String },
    country: { type: String },
    photoPath: { type: String },
    photoCloudinaryPublicId: { type: String },
    diplomaPath: { type: String },
    diplomaCloudinaryPublicId: { type: String },
    verificationStatus: {
      type: String,
      enum: ['pending', 'verified', 'rejected'],
      default: 'pending',
    },
    // Réglages disponibilité & absence
    workingHoursStart: { type: String, default: '09:00' },
    workingHoursEnd: { type: String, default: '18:00' },
    availableDays: { type: [Number], default: [1, 2, 3, 4, 5] }, // 0=Dim, 1=Lun, ..., 6=Sam
    absenceMessage: { type: String, default: '' },
    autoReplyEnabled: { type: Boolean, default: false },
    status: { type: String, enum: ['available', 'busy', 'unavailable'], default: 'available' },
    statusUpdatedAt: { type: Date },
  },
  { timestamps: true }
);

const Doctor = mongoose.model('Doctor', doctorSchema);

// 🔹 Modèle code de réinitialisation (email, code à 6 chiffres, expiration 15 min)
const passwordResetCodeSchema = new mongoose.Schema(
  {
    email: { type: String, required: true, lowercase: true, trim: true },
    code: { type: String, required: true },
    expiresAt: { type: Date, required: true },
  },
  { timestamps: true }
);
passwordResetCodeSchema.index({ email: 1 });
passwordResetCodeSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 }); // TTL optionnel
const PasswordResetCode = mongoose.model('PasswordResetCode', passwordResetCodeSchema);

// 🔹 Modèle formulaire d'urgence (un enregistrement par soumission)
const formulaireUrgenceSchema = new mongoose.Schema(
  {
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'Patient', required: true },
    patientInfo: {
      fullName: { type: String, default: '' },
      birthDate: { type: Date },
      ageYears: { type: Number },
      sex: { type: String },
      bloodGroup: { type: String, default: '' },
      weightKg: { type: Number },
      heightCm: { type: Number },
    },
    symptomes: { type: [String], required: true },
    alerteAcceptee: { type: Boolean, default: false },
    /** Consultation vue par médecin (marquage « Consulté » côté app médecin). */
    doctorViews: [
      {
        doctor: { type: mongoose.Schema.Types.ObjectId, ref: 'Doctor', required: true },
        consultedAt: { type: Date, default: Date.now },
      },
    ],
  },
  { timestamps: true }
);
formulaireUrgenceSchema.index({ patient: 1, createdAt: -1 });
const FormulaireUrgence = mongoose.model('FormulaireUrgence', formulaireUrgenceSchema);

// 🔹 Modèles pour chat & téléconsultation
const conversationSchema = new mongoose.Schema(
  {
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'Patient', required: true },
    doctor: { type: mongoose.Schema.Types.ObjectId, ref: 'Doctor', required: true },
    /** `open` = échanges libres ; `cloture` = plus d’envoi (sauf messages système serveur). */
    sessionStatus: {
      type: String,
      enum: ['open', 'cloture'],
      default: 'open',
    },
  },
  { timestamps: true }
);
conversationSchema.index({ patient: 1, doctor: 1 }, { unique: true });
const Conversation = mongoose.model('Conversation', conversationSchema);

/** Salle d’attente téléconsult : persiste l’état (redémarrage serveur / reconnexion médecin). */
const waitingRoomSessionSchema = new mongoose.Schema(
  {
    conversation: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Conversation',
      required: true,
      unique: true,
    },
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'Patient', required: true },
    doctor: { type: mongoose.Schema.Types.ObjectId, ref: 'Doctor', required: true },
    patientName: { type: String, default: 'Patient' },
    enteredAt: { type: Date, default: Date.now },
  },
  { timestamps: true }
);
waitingRoomSessionSchema.index({ doctor: 1 });
const WaitingRoomSession = mongoose.model('WaitingRoomSession', waitingRoomSessionSchema);

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
    { upsert: true, new: true }
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

const messageSchema = new mongoose.Schema(
  {
    conversation: { type: mongoose.Schema.Types.ObjectId, ref: 'Conversation', required: true },
    fromType: { type: String, enum: ['patient', 'doctor', 'system'], required: true },
    from: { type: mongoose.Schema.Types.ObjectId },
    type: {
      type: String,
      enum: [
        'text',
        'attachment',
        'file',
        'question_physique',
        'request_teleconsult',
        'form_teleconsult',
        // Prompts systèmes pour afficher les cartes côté patient
        'form_teleconsult_prompt',
        'system',
        'accept_request',
        'chat_closed',
        'chat_reopened',
        'teleconsult_scheduled',
        /** RDV enregistré via POST /api/rendezvous (phrase dédiée patient). */
        'rdv_teleconsult_programme',
        'rdv_teleconsult_annule',
        'call_event',
      ],
      default: 'text',
    },
    content: { type: String, default: '' },
    payload: { type: Object },
    /** Lu par le destinataire (double coches côté client). */
    readAt: { type: Date },
  },
  { timestamps: true }
);
messageSchema.index({ conversation: 1, createdAt: 1 });
const Message = mongoose.model('Message', messageSchema);

/** Documents du dossier médical personnel du patient (hors chat). */
const patientMedicalDocumentSchema = new mongoose.Schema(
  {
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'Patient', required: true, index: true },
    category: {
      type: String,
      enum: ['analyses', 'ordonnances', 'fichiers', 'images'],
      required: true,
    },
    title: { type: String, default: '' },
    /** Date « médicale » optionnelle (ex. date du compte rendu). */
    documentDate: { type: Date },
    filename: { type: String, required: true },
    mimetype: { type: String, default: '' },
    size: { type: Number, default: 0 },
    path: { type: String, required: true },
    publicId: { type: String, default: '' },
    /** Pour suppression Cloudinary : image | raw | video */
    cloudinaryResourceType: { type: String, default: 'raw' },
  },
  { timestamps: true }
);
patientMedicalDocumentSchema.index({ patient: 1, category: 1, createdAt: -1 });
const PatientMedicalDocument = mongoose.model('PatientMedicalDocument', patientMedicalDocumentSchema);

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

/** Extrait l'ObjectId conversation depuis `room_<conversationId>_<timestamp>`. */
function conversationIdFromCallRoomId(roomId) {
  const s = String(roomId || '').trim();
  if (!s.startsWith('room_')) return null;
  const rest = s.slice('room_'.length);
  const lastUnderscore = rest.lastIndexOf('_');
  if (lastUnderscore <= 0) return null;
  const convPart = rest.slice(0, lastUnderscore);
  const ts = rest.slice(lastUnderscore + 1);
  if (!/^\d+$/.test(ts)) return null;
  if (!mongoose.Types.ObjectId.isValid(convPart)) return null;
  return convPart;
}

/**
 * Enregistre un message système d'appel (audio/vidéo, terminé/refusé) et notifie la room `conv:`.
 */
async function saveCallLogMessage(conversationId, { mediaType, outcome, durationSeconds, roomId }) {
  const cid = String(conversationId || '').trim();
  if (!cid || !mongoose.Types.ObjectId.isValid(cid)) return null;
  const mt = mediaType === 'video' ? 'video' : 'audio';
  const oc =
    outcome === 'refused' ? 'refused' : outcome === 'missed' ? 'missed' : 'ended';
  const dur = Math.max(0, parseInt(String(durationSeconds), 10) || 0);

  let content = '';
  if (mt === 'video') {
    if (oc === 'refused') content = 'Appel vidéo refusé';
    else if (oc === 'missed') content = 'Appel vidéo manqué';
    else content = 'Appel vidéo terminé';
  } else {
    if (oc === 'refused') content = 'Appel audio refusé';
    else if (oc === 'missed') content = 'Appel manqué';
    else content = 'Appel audio terminé';
  }

  try {
    const msg = await Message.create({
      conversation: cid,
      fromType: 'system',
      type: 'call_event',
      content,
      payload: {
        kind: 'call_log',
        mediaType: mt,
        outcome: oc,
        durationSeconds: dur,
        roomId: String(roomId || ''),
      },
    });
    console.log(
      `[CALL] call_log saved conv=${cid} outcome=${oc} media=${mt} dur=${dur}s roomId=${String(roomId || '')}`
    );
    emitToConversation(cid, 'chat:call_summary', {
      conversationId: cid,
      messageId: String(msg._id),
      mediaType: mt,
      outcome: oc,
      durationSeconds: dur,
    });
    return msg;
  } catch (e) {
    console.error('[CALL] saveCallLogMessage', e.message || e);
    return null;
  }
}

const teleconsultationRequestSchema = new mongoose.Schema(
  {
    conversation: { type: mongoose.Schema.Types.ObjectId, ref: 'Conversation', required: true },
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'Patient' },
    doctor: { type: mongoose.Schema.Types.ObjectId, ref: 'Doctor' },
    status: { type: String, enum: ['pending', 'accepted', 'rejected'], default: 'pending' },
    motif: { type: String },
    /** Texte intégral de la demande type (lettre) tel qu’affiché et certifié par le patient. */
    letterBody: { type: String },
    /** Motif saisi par le médecin en cas de refus (optionnel). */
    rejectionMotif: { type: String },
  },
  { timestamps: true }
);
teleconsultationRequestSchema.index({ doctor: 1, status: 1 });
const TeleconsultationRequest = mongoose.model('TeleconsultationRequest', teleconsultationRequestSchema);

const teleconsultAttachmentSchema = new mongoose.Schema(
  {
    path: { type: String, required: true },
    publicId: String,
    filename: String,
    mimetype: String,
    size: Number,
    uploadedAt: { type: Date, default: Date.now },
  },
  { _id: false }
);

const teleconsultationFormSchema = new mongoose.Schema(
  {
    doctor: { type: mongoose.Schema.Types.ObjectId, ref: 'Doctor' },
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'Patient' },
    conversation: { type: mongoose.Schema.Types.ObjectId, ref: 'Conversation' },
    motif: String,
    symptomes: String,
    dateDerniereConsultation: Date,
    traitements: String,
    allergies: String,
    attachments: { type: [teleconsultAttachmentSchema], default: [] },
    /** Décision métier sur le dossier (indépendante du chat). */
    status: {
      type: String,
      enum: ['pending', 'accepted', 'rejected'],
      default: 'pending',
    },
    /** Après acceptation : planification ou réponse. */
    workflowStatus: {
      type: String,
      enum: ['pending', 'scheduled', 'replied'],
      default: 'pending',
    },
  },
  { timestamps: true }
);
teleconsultationFormSchema.index({ doctor: 1, status: 1 });
teleconsultationFormSchema.index({ patient: 1, createdAt: -1 });
const TeleconsultationForm = mongoose.model('TeleconsultationForm', teleconsultationFormSchema);

/** Rendez-vous téléconsultation (planification dédiée, hors seul message chat). */
const rendezVousSchema = new mongoose.Schema(
  {
    medecinId: { type: mongoose.Schema.Types.ObjectId, ref: 'Doctor', required: true },
    patientId: { type: mongoose.Schema.Types.ObjectId, ref: 'Patient', required: true },
    formulaireId: { type: mongoose.Schema.Types.ObjectId, ref: 'TeleconsultationForm' },
    date: { type: String, required: true },
    heure: { type: String, required: true },
    startAt: { type: Date, required: true },
    type: { type: String, default: 'teleconsultation' },
    statut: {
      type: String,
      enum: ['confirme', 'termine', 'annule'],
      default: 'confirme',
    },
    motifAnnulation: { type: String, default: '' },
  },
  { timestamps: true }
);
rendezVousSchema.index({ medecinId: 1, startAt: 1 });
rendezVousSchema.index({ patientId: 1, startAt: -1 });
const RendezVous = mongoose.model('RendezVous', rendezVousSchema);

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
    medecinNom: (m && m.fullName) || 'Médecin',
    medecinPhotoPath: m && m.photoPath ? m.photoPath : null,
    createdAt: doc.createdAt,
    updatedAt: doc.updatedAt,
  };
}

/**
 * Agenda médecin (app) : uniquement la collection RendezVous (plus de messages teleconsult_scheduled).
 * @param {string} doctorId
 * @param {{ dateFilter?: string }} opts - dateFilter YYYY-MM-DD optionnel
 */
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

/** Socket temps réel + push FCM si Firebase initialisé (voir initPushNotifications). */
async function notifyPatientRdv(patientId, title, body, data = {}) {
  const pid = String(patientId || '').trim();
  if (!pid) return;
  try {
    emitToUserId(pid, 'patient:rdv_notification', {
      title: String(title || ''),
      body: String(body || ''),
    });
    const flat = { type: 'rdv_update' };
    for (const [k, v] of Object.entries(data || {})) {
      flat[String(k)] = String(v ?? '');
    }
    await sendPushToUser({
      userId: pid,
      role: 'patient',
      appName: 'patient',
      title: String(title || 'Télémedecine'),
      body: String(body || ''),
      data: flat,
    });
  } catch (e) {
    console.error('[RDV notify]', e);
  }
}

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

/**
 * Message système dans le chat + socket + push FCM si configuré.
 * @param {object} opts
 * @param {string} opts.conversationId
 * @param {string} opts.patientId
 * @param {string} opts.rendezvousId
 * @param {string} opts.dateYmd
 * @param {string} opts.heureHHmm
 * @param {'programme'|'reprogramme'} opts.kind
 */
async function notifyAndMessagePatientRdvProgramme(opts) {
  const {
    conversationId,
    patientId,
    rendezvousId,
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

/** Anciens dossiers sans `status` : si workflow déjà avancé, considérer accepté. */
function normalizedTeleconsultFormStatus(f) {
  let st = f.status || 'pending';
  if (!f.status && f.workflowStatus && f.workflowStatus !== 'pending') {
    st = 'accepted';
  }
  return st;
}

function patientPhotoPathFromPopulated(p) {
  if (!p || typeof p !== 'object') return null;
  return p.photoPath || null;
}

// 🔹 Modèle HL7 (messages entrants/sortants)
const hl7MessageSchema = new mongoose.Schema(
  {
    direction: { type: String, enum: ['inbound', 'outbound'], required: true },
    source: { type: String, default: 'telemedecine-app' },
    patientExternalId: { type: String, index: true },
    hl7Raw: { type: String, required: true },
    jsonPayload: { type: Object },
    parsed: { type: Object },
    status: { type: String, default: 'stored' },
  },
  { timestamps: true }
);
hl7MessageSchema.index({ createdAt: -1 });
const Hl7Message = mongoose.model('Hl7Message', hl7MessageSchema);

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
  const d = await Doctor.findById(uid).select('fullName photoPath').lean();
  if (d) {
    return {
      id: uid,
      name: decrypt(d.fullName) || 'Utilisateur',
      avatarUrl: d.photoPath || null,
      role: 'doctor',
    };
  }
  return { id: String(userId), name: 'Utilisateur', avatarUrl: null, role: 'unknown' };
}

function resolveSocketId(target) {
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
  const cid = String(conversationId || '').trim();
  if (!cid) return;
  io.to(`conv:${cid}`).emit(event, payload);
}

/** Notification ciblée par `userId` (patient ou médecin) après `auth:bind`. */
function emitToUserId(userId, event, payload) {
  const sid = resolveSocketId(String(userId || '').trim());
  if (!sid) return;
  io.to(sid).emit(event, payload);
}

const _patientInboxCountableTypes = new Set([
  'text',
  'attachment',
  'file',
  'request_teleconsult',
  'form_teleconsult',
  'teleconsult_scheduled',
]);

/** Badge tableau de bord médecin : nouveau message côté patient (POST /messages ou upload fichier). */
async function notifyDoctorInboxNewMessage(conversationId, fromType, msgType, messageId) {
  if (fromType !== 'patient' || !_patientInboxCountableTypes.has(msgType)) return;
  const convDoctor = await Conversation.findById(conversationId).select('doctor').lean();
  const docId = convDoctor && convDoctor.doctor ? String(convDoctor.doctor) : '';
  if (!docId) return;
  emitToUserId(docId, 'doctor:inbox_new_message', {
    conversationId: String(conversationId),
    messageId: String(messageId),
  });
}

function csvList(raw, fallback = []) {
  const src = String(raw || '').trim();
  if (!src) return fallback;
  return src
    .split(',')
    .map((x) => x.trim())
    .filter(Boolean);
}

function escapeRegex(s) {
  return String(s || '').replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function buildIceServersForUser(userId = '') {
  const stunUrls = csvList(
    process.env.STUN_URLS,
    ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302']
  );
  const turnUrls = csvList(process.env.TURN_URLS, []);
  const servers = [];
  if (stunUrls.length) servers.push({ urls: stunUrls });
  if (!turnUrls.length) return servers;

  const turnSecret = String(process.env.TURN_SECRET || '').trim();
  const staticUser = String(process.env.TURN_USERNAME || '').trim();
  const staticPass = String(process.env.TURN_PASSWORD || '').trim();
  const ttlSeconds = Math.max(parseInt(process.env.TURN_TTL_SECONDS || '3600', 10) || 3600, 60);

  if (turnSecret) {
    const exp = Math.floor(Date.now() / 1000) + ttlSeconds;
    const uname = `${exp}:${userId || 'telemed-user'}`;
    const credential = crypto.createHmac('sha1', turnSecret).update(uname).digest('base64');
    servers.push({
      urls: turnUrls,
      username: uname,
      credential,
    });
    return servers;
  }

  if (staticUser && staticPass) {
    servers.push({
      urls: turnUrls,
      username: staticUser,
      credential: staticPass,
    });
  }
  return servers;
}

io.on('connection', (socket) => {
  console.log(`[SOCKET] connected socketId=${socket.id}`);
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
    });
    const targetSocketId = resolveSocketId(target);
    console.log(
      `[CALL][offer] roomId=${roomId} from=${source} fromSocket=${socket.id} to=${target} targetSocketId=${targetSocketId || 'NOT_FOUND'} sdpType=${
        sdp && sdp.type ? sdp.type : ''
      }`
    );
    if (!targetSocketId) {
      return;
    }
    io.to(targetSocketId).emit('call:incoming', {
      from: socket.id,
      fromUserId: source,
      mediaType: mediaType === 'video' ? 'video' : 'audio',
      sdp,
      roomId,
      callerInfo: await getUserInfoByUserId(source),
    });
    io.to(targetSocketId).emit('call:offer', {
      from: socket.id,
      fromUserId: source,
      mediaType: mediaType === 'video' ? 'video' : 'audio',
      sdp,
      roomId,
    });
  });

  socket.on('call:answer', ({ to, sdp, roomId, from, mediaType } = {}) => {
    const target = String(to || '').trim();
    const source = String(from || '').trim() || userBySocketId.get(socket.id) || socket.id;
    if (!target || !sdp || !roomId) return;
    const call = activeCalls.get(String(roomId));
    if (call) {
      call.startTime = Date.now();
      if (mediaType === 'video') call.mediaType = 'video';
    }
    const targetSocketId = resolveSocketId(target);
    console.log(
      `[CALL][answer] roomId=${roomId} from=${source} fromSocket=${socket.id} to=${target} targetSocketId=${targetSocketId || 'NOT_FOUND'} sdpType=${
        sdp && sdp.type ? sdp.type : ''
      }`
    );
    if (!targetSocketId) return;
    io.to(targetSocketId).emit('call:answer', {
      from: socket.id,
      fromUserId: source,
      mediaType: mediaType === 'video' ? 'video' : 'audio',
      sdp,
      roomId,
    });
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
    if (!targetSocketId) return;
    io.to(targetSocketId).emit('call:ice', { from: socket.id, fromUserId: source, candidate, roomId });
  });

  socket.on('call:reject', (payload = {}) => {
    const { to, roomId, from, conversationId: convFromPayload } = payload || {};
    const target = String(to || '').trim();
    const source = String(from || '').trim() || userBySocketId.get(socket.id) || socket.id;
    if (!target) return;
    const rId = roomId ? String(roomId) : '';
    const call = rId ? activeCalls.get(rId) : null;
    if (rId && call) {
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
    if (!targetSocketId) return;
    io.to(targetSocketId).emit('call:reject', { from: socket.id, fromUserId: source, roomId });
  });

  socket.on('call:end', (payload = {}) => {
    const { to, roomId, reason, from, conversationId: convFromPayload } = payload || {};
    const target = String(to || '').trim();
    const source = String(from || '').trim() || userBySocketId.get(socket.id) || socket.id;
    const rId = roomId ? String(roomId) : '';
    const call = rId ? activeCalls.get(rId) : null;
    if (rId && call) {
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
    if (!targetSocketId) return;
    io.to(targetSocketId).emit('call:end', {
      from: socket.id,
      fromUserId: source,
      roomId,
      reason: reason || null,
    });
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
      const currentSocketId = socketByUserId.get(userId);
      if (currentSocketId === socket.id) {
        socketByUserId.delete(userId);
      }
      userBySocketId.delete(socket.id);
    }

    for (const [roomId, call] of Array.from(activeCalls.entries())) {
      if (call.caller === userId || call.callee === userId) {
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

// 🔹 ICE config dynamique (STUN/TURN) pour WebRTC
app.get('/webrtc/ice-config', verifyToken, (req, res) => {
  try {
    const userId = String(req.query.userId || '').trim();
    const iceServers = buildIceServersForUser(userId);
    return res.json({
      iceServers,
      generatedAt: new Date().toISOString(),
    });
  } catch (err) {
    console.error('GET /webrtc/ice-config', err);
    return res.status(500).json({ message: 'Erreur config ICE.' });
  }
});

// 🔹 Connexion MongoDB
mongoose
  .connect(process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/telemedecine')
  .then(async () => {
    console.log('MongoDB connecté ');
    initPushNotifications();
    await hydrateWaitingRoomsFromDb();
  })
  .catch((err) => {
    console.error('Erreur MongoDB ', err);
    process.exit(1);
  });


// 🔹 Configuration upload fichiers (pièces jointes téléconsultation)
const upload = multer({
  dest: uploadsDir,
});

const CHAT_UPLOAD_MAX_BYTES = parseInt(
  process.env.CHAT_UPLOAD_MAX_BYTES || String(25 * 1024 * 1024),
  10
);

function chatUploadFileFilter(req, file, cb) {
  const m = String(file.mimetype || '').toLowerCase();
  const name = String(file.originalname || '').toLowerCase();
  const ok =
    m.startsWith('image/') ||
    m.startsWith('audio/') ||
    m.startsWith('video/') ||
    m === 'application/pdf' ||
    m.includes('pdf') ||
    m.includes('wordprocessingml') ||
    m.includes('msword') ||
    m.includes('spreadsheet') ||
    m.includes('presentation') ||
    m.includes('officedocument') ||
    m === 'application/zip' ||
    m === 'application/x-zip-compressed' ||
    m.startsWith('text/') ||
    m === 'application/octet-stream' ||
    name.endsWith('.m4a') ||
    name.endsWith('.webm') ||
    name.endsWith('.aac');
  if (ok) return cb(null, true);
  cb(new Error('Type de fichier non autorisé pour le chat.'));
}

const uploadChat = multer({
  dest: uploadsDir,
  limits: { fileSize: CHAT_UPLOAD_MAX_BYTES },
  fileFilter: chatUploadFileFilter,
});

/** Corrige les noms UTF-8 interprétés en latin1 par Multer (ex. gÃ©nÃ©rale → générale). */
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

function splitName(fullName = '') {
  const n = String(fullName || '').trim();
  if (!n) return { lastName: '', firstName: '' };
  const parts = n.split(/\s+/);
  const firstName = parts.shift() || '';
  const lastName = parts.join(' ');
  return { firstName, lastName };
}

/**
 * Construit un message HL7 ORU^R01 depuis du JSON.
 * Body attendu:
 * {
 *   patient: { id, fullName, dob, sex, phone, address },
 *   measures: [{ code, label, value, unit, type }],
 *   files: [{ url, label, mimetype }]
 * }
 */
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

function requireHl7Auth(req, res, next) {
  const shared = process.env.HL7_SHARED_SECRET;
  if (!shared) return next();
  const got = req.headers['x-hl7-key'];
  if (!got || String(got) !== String(shared)) {
    return res.status(401).json({ message: 'Unauthorized HL7 access.' });
  }
  return next();
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

// 🔹 Envoi du code par email vers l'adresse saisie par l'utilisateur (SMTP requis)
function sendResetCodeEmail(toEmail, code) {
  const smtpUser = process.env.SMTP_USER;
  const smtpPass = process.env.SMTP_PASS;

  if (!smtpUser || !smtpPass) {
    return Promise.reject(
      new Error(
        'Envoi d\'email non configuré. Créez un fichier .env avec SMTP_USER et SMTP_PASS (ex. Gmail avec mot de passe d\'application). Voir .env.example.'
      )
    );
  }

  const transporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST || 'smtp.gmail.com',
    port: parseInt(process.env.SMTP_PORT || '587', 10),
    secure: false,
    auth: { user: smtpUser, pass: smtpPass },
  });

  return transporter.sendMail({
    from: process.env.SMTP_FROM || smtpUser,
    to: toEmail,
    subject: 'Code de réinitialisation - Télémedecine',
    text: `Votre code de réinitialisation est : ${code}\n\nIl est valide 15 minutes.`,
    html: `<p>Votre code de réinitialisation est : <strong>${code}</strong></p><p>Il est valide 15 minutes.</p>`,
  }).catch((err) => {
    console.error('Erreur envoi email:', err.message);
    throw err;
  });
}

// Distance en km (formule de Haversine)
function haversineKm(lat1, lon1, lat2, lon2) {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

/** Retourne le statut du médecin tel qu'il l'a défini.
 *  Le patient voit donc directement "Disponible", "Occupé" ou "Non disponible"
 *  sans recalcul automatique selon les horaires. */
function getEffectiveDoctorStatus(doctor) {
  return doctor.status ?? 'available';
}

const EMAIL_FORMAT_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

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

function signPatientToken(patientId) {
  return jwt.sign({ sub: String(patientId), role: 'patient' }, JWT_SECRET, { expiresIn: '7d' });
}

function signDoctorToken(doctorId) {
  return jwt.sign({ sub: String(doctorId), role: 'doctor' }, JWT_SECRET, { expiresIn: '7d' });
}

function verifyToken(req, res, next) {
  const auth = req.headers.authorization || '';
  const m = /^Bearer\s+(.+)$/i.exec(auth);
  if (!m) {
    return res.status(401).json({ message: 'Authentification requise.' });
  }
  try {
    const payload = jwt.verify(m[1], JWT_SECRET);
    req.auth = payload;
    next();
  } catch (e) {
    return res.status(401).json({ message: 'Jeton invalide ou expiré.' });
  }
}

function requirePatientParam(req, res, next) {
  const pid = String(req.params.patientId || '').trim();
  if (!req.auth || req.auth.role !== 'patient') {
    return res.status(403).json({ message: 'Accès réservé aux patients.' });
  }
  if (String(req.auth.sub) !== pid) {
    return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
  }
  next();
}

function requireDoctorParam(req, res, next) {
  const did = String(req.params.doctorId || '').trim();
  if (!req.auth || req.auth.role !== 'doctor') {
    return res.status(403).json({ message: 'Accès réservé aux médecins.' });
  }
  if (String(req.auth.sub) !== did) {
    return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
  }
  next();
}

/** Fiche médecin : patient authentifié ou médecin consultant sa propre fiche. */
function requireDoctorPublicRead(req, res, next) {
  const did = String(req.params.doctorId || '').trim();
  if (!req.auth) return res.status(401).json({ message: 'Authentification requise.' });
  if (req.auth.role === 'patient') return next();
  if (req.auth.role === 'doctor' && String(req.auth.sub) === did) return next();
  return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
}

function requirePatientQuery(req, res, next) {
  const pid = String(req.query.patientId || '').trim();
  if (!req.auth || req.auth.role !== 'patient') {
    return res.status(403).json({ message: 'Accès réservé aux patients.' });
  }
  if (String(req.auth.sub) !== pid) {
    return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
  }
  next();
}

function requireDoctorQuery(req, res, next) {
  const did = String(req.query.doctorId || '').trim();
  if (!req.auth || req.auth.role !== 'doctor') {
    return res.status(403).json({ message: 'Accès réservé aux médecins.' });
  }
  if (String(req.auth.sub) !== did) {
    return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
  }
  next();
}

function requireDoctorRole(req, res, next) {
  if (!req.auth || req.auth.role !== 'doctor') {
    return res.status(403).json({ message: 'Accès réservé aux médecins.' });
  }
  next();
}

function requireConversationCreate(req, res, next) {
  const { patientId, doctorId } = req.body || {};
  const role = req.auth && req.auth.role;
  const sub = String(req.auth && req.auth.sub);
  if (role === 'patient' && patientId && String(patientId) === sub) return next();
  if (role === 'doctor' && doctorId && String(doctorId) === sub) return next();
  return res.status(403).json({ message: 'Accès non autorisé.' });
}

async function requireConversationAccess(req, res, next) {
  try {
    let conversationId =
      req.query.conversationId ||
      (req.body && req.body.conversationId) ||
      (req.params && req.params.conversationId);
    const messageId = req.params && req.params.messageId;
    if (!conversationId && messageId && mongoose.Types.ObjectId.isValid(String(messageId))) {
      const msg = await Message.findById(messageId).select('conversation').lean();
      if (msg && msg.conversation) conversationId = String(msg.conversation);
    }
    if (!conversationId || !mongoose.Types.ObjectId.isValid(String(conversationId))) {
      return res.status(400).json({ message: 'conversationId requis ou invalide.' });
    }
    const conv = await Conversation.findById(conversationId).select('patient doctor').lean();
    if (!conv) return res.status(404).json({ message: 'Conversation introuvable.' });
    const uid = req.auth && req.auth.sub;
    const role = req.auth && req.auth.role;
    if (role === 'patient' && String(conv.patient) !== String(uid)) {
      return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
    }
    if (role === 'doctor' && String(conv.doctor) !== String(uid)) {
      return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
    }
    if (role !== 'patient' && role !== 'doctor') {
      return res.status(403).json({ message: 'Accès non autorisé.' });
    }
    req.conversationIdResolved = String(conversationId);
    next();
  } catch (e) {
    console.error('requireConversationAccess', e);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function requirePatientConversationBody(req, res, next) {
  try {
    const conversationId = String(req.body.conversationId || '').trim();
    if (!mongoose.Types.ObjectId.isValid(conversationId)) {
      return res.status(400).json({ message: 'conversationId requis ou invalide.' });
    }
    if (!req.auth || req.auth.role !== 'patient') {
      return res.status(403).json({ message: 'Accès réservé aux patients.' });
    }
    const conv = await Conversation.findById(conversationId).select('patient').lean();
    if (!conv) return res.status(404).json({ message: 'Conversation introuvable.' });
    if (String(conv.patient) !== String(req.auth.sub)) {
      return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
    }
    next();
  } catch (e) {
    console.error('requirePatientConversationBody', e);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function requireConversationParamParticipant(req, res, next) {
  try {
    const conversationId = String(req.params.conversationId || '').trim();
    if (!mongoose.Types.ObjectId.isValid(conversationId)) {
      return res.status(400).json({ message: 'conversationId invalide.' });
    }
    const conv = await Conversation.findById(conversationId).select('patient doctor').lean();
    if (!conv) return res.status(404).json({ message: 'Conversation introuvable.' });
    const uid = req.auth && req.auth.sub;
    const role = req.auth && req.auth.role;
    if (role === 'patient' && String(conv.patient) === String(uid)) return next();
    if (role === 'doctor' && String(conv.doctor) === String(uid)) return next();
    return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
  } catch (e) {
    console.error('requireConversationParamParticipant', e);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function requireFormulaireUrgenceRead(req, res, next) {
  try {
    const patientId = String(req.query.patientId || '').trim();
    if (!mongoose.Types.ObjectId.isValid(patientId)) {
      return res.status(400).json({ message: 'patientId invalide.' });
    }
    if (!req.auth) return res.status(401).json({ message: 'Authentification requise.' });
    if (req.auth.role === 'patient' && String(req.auth.sub) === patientId) return next();
    if (req.auth.role === 'doctor') {
      const conv = await Conversation.findOne({ patient: patientId, doctor: req.auth.sub }).lean();
      if (conv) return next();
    }
    return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
  } catch (e) {
    console.error('requireFormulaireUrgenceRead', e);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

function requireFormulaireUrgenceWrite(req, res, next) {
  const patientId = String(req.body.patientId || '').trim();
  if (!mongoose.Types.ObjectId.isValid(patientId)) {
    return res.status(400).json({ message: 'patientId invalide.' });
  }
  if (!req.auth || req.auth.role !== 'patient' || String(req.auth.sub) !== patientId) {
    return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
  }
  next();
}

function requirePatientBodyPatientId(req, res, next) {
  const patientId = String(req.body.patientId || '').trim();
  if (!mongoose.Types.ObjectId.isValid(patientId)) {
    return res.status(400).json({ message: 'patientId invalide.' });
  }
  if (!req.auth || req.auth.role !== 'patient' || String(req.auth.sub) !== patientId) {
    return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
  }
  next();
}

function requireDoctorBodyMatches(req, res, next) {
  const doctorId = String(req.body.doctorId || '').trim();
  if (!req.auth || req.auth.role !== 'doctor' || String(req.auth.sub) !== doctorId) {
    return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
  }
  next();
}

function requireRdvPostDoctor(req, res, next) {
  const medecinId = String(req.body.medecinId || '').trim();
  if (!req.auth || req.auth.role !== 'doctor' || String(req.auth.sub) !== medecinId) {
    return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
  }
  next();
}

function requireRdvPatientGet(req, res, next) {
  const pid = String(req.query.patientId || '').trim();
  if (!req.auth || req.auth.role !== 'patient' || String(req.auth.sub) !== pid) {
    return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
  }
  next();
}

function requireRdvDoctorGetQuery(req, res, next) {
  const mid = String(req.query.medecinId || '').trim();
  if (!req.auth || req.auth.role !== 'doctor' || String(req.auth.sub) !== mid) {
    return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
  }
  next();
}

function requireRdvMutateDoctor(req, res, next) {
  const medecinId = String(req.body.medecinId || req.query.medecinId || '').trim();
  if (!req.auth || req.auth.role !== 'doctor' || String(req.auth.sub) !== medecinId) {
    return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
  }
  next();
}

function dossierPublicUrl(pathStr) {
  if (pathStr == null || typeof pathStr !== 'string') return pathStr;
  const t = pathStr.trim();
  if (t.startsWith('http://') || t.startsWith('https://')) return t;
  const base = String(process.env.API_BASE_URL || 'http://localhost:3000').replace(/\/$/, '');
  return t.startsWith('/') ? `${base}${t}` : `${base}/${t}`;
}

const authLoginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { message: 'Trop de tentatives. Réessayez dans 15 minutes.' },
});

// 🔹 Route test
app.get('/', (req, res) => {
  res.send('API Telemedecine fonctionne avec MongoDB ');
});

// 🔹 Inscription patient
app.post('/auth/register', authLoginLimiter, async (req, res) => {
  try {
    const { fullName, email, password, country, addressExact, phone } = req.body;

    if (!fullName || !email || !password || !country || !addressExact || !phone) {
      return res.status(400).json({ message: 'Champs manquants.' });
    }
    if (!isValidEmailFormat(email)) {
      return res.status(400).json({ message: 'Format d\'email invalide.' });
    }
    const pwdErr = assertPasswordMin8(password);
    if (pwdErr) {
      return res.status(400).json({ message: pwdErr });
    }

    const emailNorm = String(email).trim().toLowerCase();
    const existing = await Patient.findOne({
      $or: [{ emailHash: hashEmail(emailNorm) }, { email: emailNorm }],
    });
    if (existing) {
      return res.status(409).json({ message: 'Email déjà utilisé.' });
    }

    const passwordHash = await bcrypt.hash(password, 10);

    const patient = new Patient({
      fullName,
      email,
      passwordHash,
      country,
      addressExact,
      phone,
    });

    await patient.save();

    const token = signPatientToken(patient._id);
    return res.status(201).json({
      message: 'Patient créé avec succès.',
      token,
      patient: {
        id: patient._id,
        ...decryptPatient(patient),
      },
    });
  } catch (err) {
    console.error('Erreur /auth/register', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Login patient
app.post('/auth/login', authLoginLimiter, async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({ message: 'Email et mot de passe requis.' });
    }

    const emailNorm = String(email).trim().toLowerCase();
    const patient = await Patient.findOne({
      $or: [{ emailHash: hashEmail(emailNorm) }, { email: emailNorm }],
    });
    if (!patient) {
      return res.status(401).json({ message: 'Identifiants invalides.' });
    }

    const match = await bcrypt.compare(password, patient.passwordHash);
    if (!match) {
      return res.status(401).json({ message: 'Identifiants invalides.' });
    }

    const token = signPatientToken(patient._id);
    return res.json({
      message: 'Connexion réussie.',
      token,
      patient: {
        id: patient._id,
        ...decryptPatient(patient),
      },
    });
  } catch (err) {
    console.error('Erreur /auth/login', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Liste des conversations du patient
app.get('/patient/conversations', verifyToken, requirePatientQuery, async (req, res) => {
  try {
    const { patientId } = req.query;
    if (!patientId) {
      return res.status(400).json({ message: 'patientId requis.' });
    }

    const convos = await Conversation.find({ patient: patientId })
      .populate(
        'doctor',
        'fullName specialty governorate photoPath status statusUpdatedAt absenceMessage autoReplyEnabled workingHoursStart workingHoursEnd availableDays'
      )
      .lean();

    const convIds = convos.map((c) => c._id);

    const lastMessages = await Message.aggregate([
      { $match: { conversation: { $in: convIds } } },
      { $sort: { createdAt: -1 } },
      {
        $group: {
          _id: '$conversation',
          lastMessage: { $first: '$content' },
          lastMessageAt: { $first: '$createdAt' },
          lastFromType: { $first: '$fromType' },
          lastType: { $first: '$type' },
          lastPatientMessageAt: {
            $max: {
              $cond: [{ $eq: ['$fromType', 'patient'] }, '$createdAt', null],
            },
          },
          lastDoctorMessageAt: {
            $max: {
              $cond: [{ $eq: ['$fromType', 'doctor'] }, '$createdAt', null],
            },
          },
        },
      },
    ]).exec();

    const lastByConv = new Map(
      lastMessages.map((m) => [
        m._id.toString(),
        {
          content: m.lastMessage ?? '',
          at: m.lastMessageAt,
          fromType: m.lastFromType || null,
          type: m.lastType || null,
          lastPatientAt: m.lastPatientMessageAt || null,
          lastDoctorAt: m.lastDoctorMessageAt || null,
        },
      ])
    );

    const unreadByConv = await Message.aggregate([
      {
        $match: {
          conversation: { $in: convIds },
          fromType: 'doctor',
          readAt: null,
        },
      },
      { $group: { _id: '$conversation', count: { $sum: 1 } } },
    ]).exec();

    const unreadMap = new Map(
      unreadByConv.map((row) => [row._id.toString(), row.count])
    );

    const list = convos.map((c) => {
      const doctor = c.doctor;
      const did = doctor?._id ? doctor._id.toString() : '';
      const cid = c._id.toString();
      const effectiveStatus = doctor ? getEffectiveDoctorStatus(doctor) : 'available';
      const last = lastByConv.get(cid);
      const unreadCount = unreadMap.get(cid) || 0;
      const hasUnreadFromDoctor = unreadCount > 0;

      return {
        conversationId: cid,
        doctorId: did,
        doctorName: decrypt(doctor?.fullName) ?? 'Médecin',
        doctorSpecialty: doctor?.specialty ? decrypt(doctor.specialty) : '',
        doctorGovernorate: doctor?.governorate ? decrypt(doctor.governorate) : '',
        doctorPhotoPath: doctor?.photoPath ?? null,
        doctorStatus: effectiveStatus,
        doctorStatusUpdatedAt: doctor?.statusUpdatedAt || null,
        lastMessage: last?.content ?? null,
        lastMessageAt: last?.at ?? null,
        lastMessageFromType: last?.fromType ?? null,
        lastMessageType: last?.type ?? null,
        hasUnreadFromDoctor,
        unreadCount,
      };
    });

    return res.json({ conversations: list });
  } catch (err) {
    console.error('Erreur GET /patient/conversations', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Tous les créneaux `teleconsult_scheduled` d'un patient (toutes conversations)
// Doit être déclaré avant GET /patient/:patientId pour éviter la collision de route.
app.get('/patient/:patientId/scheduled-teleconsults', verifyToken, requirePatientParam, async (req, res) => {
  try {
    const { patientId } = req.params;
    if (!mongoose.Types.ObjectId.isValid(patientId)) {
      return res.status(400).json({ message: 'patientId invalide.' });
    }

    const convos = await Conversation.find({ patient: patientId })
      .populate('doctor', 'fullName photoPath')
      .lean();
    if (!convos.length) {
      return res.json({ slots: [] });
    }

    const convIds = convos.map((c) => c._id);
    const byConv = new Map(convos.map((c) => [c._id.toString(), c]));

    const msgs = await Message.find({
      conversation: { $in: convIds },
      fromType: 'doctor',
      type: 'teleconsult_scheduled',
    })
      .sort({ createdAt: -1 })
      .lean();

    const slots = msgs
      .map((m) => {
        const convId = m.conversation?.toString() || '';
        const conv = byConv.get(convId);
        const doctor = conv?.doctor;
        const scheduledAt = m?.payload?.scheduledAt;
        if (!scheduledAt || typeof scheduledAt !== 'string') return null;
        return {
          messageId: m._id.toString(),
          conversationId: convId,
          doctorId: doctor?._id ? doctor._id.toString() : '',
          doctorName: decrypt(doctor?.fullName) || 'Médecin',
          doctorPhotoPath: doctor?.photoPath || null,
          scheduledAt,
          content: m.content || '',
          createdAt: m.createdAt || null,
        };
      })
      .filter(Boolean);

    return res.json({ slots });
  } catch (err) {
    console.error('Erreur GET /patient/:patientId/scheduled-teleconsults', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Demandes de téléconsultation du patient (statut affiché côté app patient)
app.get('/patient/:patientId/teleconsult-requests', verifyToken, requirePatientParam, async (req, res) => {
  try {
    const { patientId } = req.params;
    if (!mongoose.Types.ObjectId.isValid(patientId)) {
      return res.status(400).json({ message: 'patientId invalide.' });
    }
    const list = await TeleconsultationRequest.find({ patient: patientId })
      .sort({ createdAt: -1 })
      .lean();
    const items = list.map((r) => ({
      id: String(r._id),
      conversationId: r.conversation ? String(r.conversation) : '',
      doctorId: r.doctor ? String(r.doctor) : '',
      motif: r.motif || '',
      letterBody: r.letterBody || '',
      status: r.status,
      rejectionMotif: r.rejectionMotif || '',
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
    }));
    return res.json({ items });
  } catch (err) {
    console.error('Erreur GET /patient/:patientId/teleconsult-requests', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Profil patient (nom + photo)
app.get('/patient/:patientId', verifyToken, requirePatientParam, async (req, res) => {
  try {
    const { patientId } = req.params;
    const patient = await Patient.findById(patientId).lean();
    if (!patient) {
      return res.status(404).json({ message: 'Patient introuvable.' });
    }
    return res.json({
      id: patient._id.toString(),
      fullName: decrypt(patient.fullName),
      email: decrypt(patient.email),
      country: decrypt(patient.country),
      addressExact: decrypt(patient.addressExact),
      phone: decrypt(patient.phone),
      photoPath: patient.photoPath ?? null,
    });
  } catch (err) {
    console.error('Erreur GET /patient/:patientId', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

app.patch('/patient/:patientId/name', verifyToken, requirePatientParam, async (req, res) => {
  try {
    const { patientId } = req.params;
    const { fullName } = req.body || {};
    if (!fullName || !String(fullName).trim()) {
      return res.status(400).json({ message: 'fullName requis.' });
    }

    const patient = await Patient.findByIdAndUpdate(
      patientId,
      { fullName: String(fullName).trim() },
      { new: true, runValidators: false }
    );
    if (!patient) {
      return res.status(404).json({ message: 'Patient introuvable.' });
    }
    return res.json({
      message: 'Nom mis à jour.',
      fullName: decrypt(patient.fullName),
    });
  } catch (err) {
    console.error('Erreur PATCH /patient/:patientId/name', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

app.post(
  '/patient/:patientId/photo',
  verifyToken,
  requirePatientParam,
  upload.single('photo'),
  async (req, res) => {
    try {
      const { patientId } = req.params;
      if (!mongoose.Types.ObjectId.isValid(patientId)) {
        return res.status(400).json({ message: 'patientId invalide.' });
      }
      if (!req.file) {
        return res.status(400).json({ message: 'Fichier photo requis.' });
      }
      if (!isCloudinaryConfigured) {
        return res.status(503).json({
          message:
            'Stockage cloud non configuré. Ajoutez CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY et CLOUDINARY_API_SECRET dans .env.',
        });
      }

      const existing = await Patient.findById(patientId).select(
        'photoPath photoCloudinaryPublicId'
      );
      if (!existing) {
        return res.status(404).json({ message: 'Patient introuvable.' });
      }

      const resourceType = resourceTypeFromMimetype(req.file.mimetype);
      const cloudUpload = await uploadFileToCloudinary(
        req.file.path,
        'telemedecine/patients',
        resourceType
      );
      if (!cloudUpload?.url || !cloudUpload.publicId) {
        return res.status(500).json({ message: 'Échec upload vers le stockage cloud.' });
      }

      const oldPublicId =
        existing.photoCloudinaryPublicId ||
        tryParseCloudinaryImagePublicId(existing.photoPath);
      if (oldPublicId) {
        await destroyByPublicId(oldPublicId, 'image');
      }

      const patient = await Patient.findByIdAndUpdate(
        patientId,
        {
          photoPath: cloudUpload.url,
          photoCloudinaryPublicId: cloudUpload.publicId,
        },
        { new: true, runValidators: false }
      );
      if (!patient) {
        return res.status(404).json({ message: 'Patient introuvable.' });
      }
      return res.status(201).json({
        message: 'Photo mise à jour.',
        photoPath: patient.photoPath,
      });
    } catch (err) {
      console.error('Erreur POST /patient/:patientId/photo', err);
      return res.status(500).json({ message: 'Erreur serveur.' });
    } finally {
      if (req.file?.path) {
        try {
          await fs.unlink(req.file.path);
        } catch (_) {}
      }
    }
  }
);

// 🔹 Inscription médecin
app.post('/auth/doctor/register', authLoginLimiter, upload.single('diploma'), async (req, res) => {
  try {
    const { fullName, email, password, specialty, governorate, address, phone, orderNumber, country } =
      req.body;

    if (!fullName || !email || !password || !specialty || !governorate || !address || !phone) {
      return res.status(400).json({ message: 'Champs manquants.' });
    }
    if (!req.file) {
      return res.status(400).json({
        message: 'Veuillez scanner votre carte de médecin ou justificatif (diplôme).',
      });
    }
    if (!isValidEmailFormat(email)) {
      return res.status(400).json({ message: 'Format d\'email invalide.' });
    }
    const pwdErr = assertPasswordMin8(password);
    if (pwdErr) {
      return res.status(400).json({ message: pwdErr });
    }
    const orderNumberNorm = orderNumber != null ? String(orderNumber).trim() : '';
    if (orderNumberNorm && !/^\d{1,5}$/.test(orderNumberNorm)) {
      return res.status(400).json({
        message: 'Le numéro d\'ordre doit contenir au maximum 5 chiffres.',
      });
    }

    const emailNorm = String(email).trim().toLowerCase();

    const existing = await Doctor.findOne({
      $or: [{ emailHash: hashEmail(emailNorm) }, { email: emailNorm }],
    });
    if (existing) {
      return res.status(409).json({ message: 'Email déjà utilisé.' });
    }

    let diplomaPath;
    let diplomaCloudinaryPublicId;
    if (isCloudinaryConfigured) {
      const resourceType = resourceTypeFromMimetype(req.file.mimetype);
      const cloudUpload = await uploadFileToCloudinary(
        req.file.path,
        'telemedecine/doctors/diplomas',
        resourceType,
      );
      if (!cloudUpload?.url || !cloudUpload.publicId) {
        return res.status(500).json({ message: 'Échec envoi du justificatif.' });
      }
      diplomaPath = cloudUpload.url;
      diplomaCloudinaryPublicId = cloudUpload.publicId;
    } else {
      diplomaPath = `/uploads/${req.file.filename}`;
    }

    const passwordHash = await bcrypt.hash(password, 10);

    const doctor = new Doctor({
      fullName,
      specialty,
      governorate,
      address,
      email: emailNorm,
      phone,
      passwordHash,
      orderNumber: orderNumberNorm || undefined,
      country: country ? String(country).trim() : undefined,
      diplomaPath,
      diplomaCloudinaryPublicId,
      verificationStatus: 'pending',
    });

    await doctor.save();

    const token = signDoctorToken(doctor._id);
    return res.status(201).json({
      message: 'Médecin créé avec succès. Votre justificatif sera vérifié.',
      token,
      doctor: {
        id: doctor._id,
        ...decryptDoctor(doctor),
      },
    });
  } catch (err) {
    console.error('Erreur /auth/doctor/register', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  } finally {
    if (req.file?.path) {
      try {
        await fs.promises.unlink(req.file.path);
      } catch (_) {}
    }
  }
});

// 🔹 Login médecin
app.post('/auth/doctor/login', authLoginLimiter, async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({ message: 'Email et mot de passe requis.' });
    }

    const emailNorm = String(email).trim().toLowerCase();

    const doctor = await Doctor.findOne({
      $or: [{ emailHash: hashEmail(emailNorm) }, { email: emailNorm }],
    });
    if (!doctor || !doctor.passwordHash) {
      return res.status(401).json({ message: 'Identifiants invalides.' });
    }

    const match = await bcrypt.compare(password, doctor.passwordHash);
    if (!match) {
      return res.status(401).json({ message: 'Identifiants invalides.' });
    }

    const token = signDoctorToken(doctor._id);
    return res.json({
      message: 'Connexion médecin réussie.',
      token,
      doctor: {
        id: doctor._id,
        ...decryptDoctor(doctor),
      },
    });
  } catch (err) {
    console.error('Erreur /auth/doctor/login', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Liste des médecins (filtres : spécialité, nom, gouvernorat ; optionnel : latitude, longitude pour tri par distance)
app.get('/doctors', async (req, res) => {
  try {
    const { specialty, name, governorate, latitude, longitude } = req.query;
    const filter = {};

    if (specialty && String(specialty).trim()) {
      filter.specialty = new RegExp(escapeRegex(String(specialty).trim()), 'i');
    }
    const nameQ = name && String(name).trim() ? String(name).trim() : '';
    const governorateQ = governorate && String(governorate).trim() ? String(governorate).trim() : '';

    const lat = latitude != null && latitude !== '' ? parseFloat(latitude) : null;
    const lon = longitude != null && longitude !== '' ? parseFloat(longitude) : null;
    const useLocation = lat != null && lon != null && !Number.isNaN(lat) && !Number.isNaN(lon);

    const doctors = await Doctor.find(filter)
      .select('fullName specialty governorate address latitude longitude orderNumber country status statusUpdatedAt workingHoursStart workingHoursEnd availableDays photoPath')
      .sort(useLocation ? {} : { fullName: 1 })
      .lean();

    let result = doctors.map((d) => {
      const doc = {
        id: d._id.toString(),
        fullName: decrypt(d.fullName),
        specialty: d.specialty,
        governorate: decrypt(d.governorate),
        address: decrypt(d.address) || null,
        orderNumber: d.orderNumber || null,
        country: decrypt(d.country) || null,
        photoPath: d.photoPath || null,
        status: getEffectiveDoctorStatus(d),
        statusUpdatedAt: d.statusUpdatedAt || null,
      };
      if (useLocation && d.latitude != null && d.longitude != null) {
        doc.distanceKm = Math.round(haversineKm(lat, lon, d.latitude, d.longitude) * 10) / 10;
      } else if (useLocation) {
        doc.distanceKm = null;
      }
      return doc;
    });

    if (nameQ) {
      const re = new RegExp(escapeRegex(nameQ), 'i');
      result = result.filter((d) => re.test(String(d.fullName || '')));
    }
    if (governorateQ) {
      const re = new RegExp(`^${escapeRegex(governorateQ)}$`, 'i');
      result = result.filter((d) => re.test(String(d.governorate || '')));
    }

    if (useLocation) {
      result = result.sort((a, b) => {
        const da = a.distanceKm == null ? Infinity : a.distanceKm;
        const db = b.distanceKm == null ? Infinity : b.distanceKm;
        return da - db;
      });
    }

    return res.json({ doctors: result });
  } catch (err) {
    console.error('Erreur /doctors', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Liste des patients (pour le médecin : choisir un patient pour démarrer une discussion)
app.get('/patients', verifyToken, requireDoctorRole, async (req, res) => {
  try {
    const patients = await Patient.find()
      .select('fullName photoPath')
      .sort({ fullName: 1 })
      .lean();
    const list = patients.map((p) => ({
      id: p._id.toString(),
      fullName: decrypt(p.fullName),
      photoPath: p.photoPath ?? null,
    }));
    return res.json({ patients: list });
  } catch (err) {
    console.error('Erreur GET /patients', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Demande de code de réinitialisation (envoi par email)
app.post('/auth/request-reset-code', authLoginLimiter, async (req, res) => {
  try {
    const email = req.body.email ? String(req.body.email).trim().toLowerCase() : '';
    if (!email || !email.includes('@')) {
      return res.status(400).json({ message: 'Adresse email requise.' });
    }

    // On accepte maintenant patients ET médecins.
    const patient = await Patient.findOne({
      $or: [{ emailHash: hashEmail(email) }, { email }],
    });
    const doctor = await Doctor.findOne({
      $or: [{ emailHash: hashEmail(email) }, { email }],
    });
    if (!patient && !doctor) {
      return res.json({
        message: 'Si un compte existe avec cette adresse, un code a été envoyé par email.',
      });
    }

    const code = String(crypto.randomInt(100000, 1000000));
    const expiresAt = new Date(Date.now() + 15 * 60 * 1000);

    await PasswordResetCode.deleteMany({ email });
    await PasswordResetCode.create({ email, code, expiresAt });

    await sendResetCodeEmail(email, code);

    return res.json({
      message: 'Si un compte existe avec cette adresse, un code a été envoyé par email.',
    });
  } catch (err) {
    console.error('Erreur /auth/request-reset-code', err.message || err);
    const msg = err.message || 'Impossible d\'envoyer l\'email. Réessayez plus tard.';
    return res.status(500).json({
      message: msg.startsWith('Envoi d\'email') ? msg : `Envoi échoué : ${msg}`,
    });
  }
});

// 🔹 Vérification simple du code (sans changer le mot de passe)
app.post('/auth/verify-reset-code', async (req, res) => {
  try {
    const email = req.body.email ? String(req.body.email).trim().toLowerCase() : '';
    const code = req.body.code ? String(req.body.code).trim() : '';

    if (!email || !code) {
      return res.status(400).json({ message: 'Email et code requis.' });
    }

    const record = await PasswordResetCode.findOne({
      email,
      code,
      expiresAt: { $gt: new Date() },
    });
    if (!record) {
      return res.status(400).json({
        message: 'Code invalide ou expiré. Demandez un nouveau code.',
      });
    }

    return res.json({ message: 'Code vérifié avec succès.' });
  } catch (err) {
    console.error('Erreur /auth/verify-reset-code', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Vérification du code et changement du mot de passe
app.post('/auth/verify-reset-password', async (req, res) => {
  try {
    const email = req.body.email ? String(req.body.email).trim().toLowerCase() : '';
    const code = req.body.code ? String(req.body.code).trim() : '';
    const newPassword = req.body.newPassword ? String(req.body.newPassword) : '';

    if (!email || !code || !newPassword) {
      return res
        .status(400)
        .json({ message: 'Email, code et nouveau mot de passe requis.' });
    }
    const pwdErr = assertPasswordMin8(newPassword);
    if (pwdErr) {
      return res.status(400).json({ message: pwdErr });
    }

    const record = await PasswordResetCode.findOne({
      email,
      code,
      expiresAt: { $gt: new Date() },
    });
    if (!record) {
      return res.status(400).json({
        message: 'Code invalide ou expiré. Demandez un nouveau code.',
      });
    }

    // On cherche d'abord un patient, sinon un médecin.
    let account = await Patient.findOne({
      $or: [{ emailHash: hashEmail(email) }, { email }],
    });
    let isDoctor = false;
    if (!account) {
      account = await Doctor.findOne({
        $or: [{ emailHash: hashEmail(email) }, { email }],
      });
      isDoctor = true;
    }
    if (!account) {
      return res.status(404).json({ message: 'Compte introuvable.' });
    }

    const passwordHash = await bcrypt.hash(newPassword, 10);
    account.passwordHash = passwordHash;
    await account.save();
    await PasswordResetCode.deleteMany({ email });

    return res.json({
      message: `Mot de passe mis à jour avec succès pour le ${isDoctor ? 'médecin' : 'patient'}.`,
    });
  } catch (err) {
    console.error('Erreur /auth/verify-reset-password', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Enregistrement d'un formulaire d'urgence
app.post('/formulaire-urgence', verifyToken, requireFormulaireUrgenceWrite, async (req, res) => {
  try {
    const { patientId, symptomes, alerteAcceptee } = req.body;

    if (!patientId || !Array.isArray(symptomes)) {
      return res.status(400).json({
        message: 'patientId et symptomes (tableau) requis.',
      });
    }

    const patient = await Patient.findById(patientId);
    if (!patient) {
      return res.status(404).json({ message: 'Patient introuvable.' });
    }

    const doc = await FormulaireUrgence.create({
      patient: patientId,
      patientInfo: buildPatientInfoSnapshot(patient),
      symptomes,
      alerteAcceptee: Boolean(alerteAcceptee),
    });

    return res.status(201).json({
      message: 'Formulaire enregistré.',
      id: doc._id.toString(),
    });
  } catch (err) {
    console.error('Erreur /formulaire-urgence', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Dernier formulaire d'urgence d'un patient (pour le médecin)
app.get('/formulaire-urgence', verifyToken, requireFormulaireUrgenceRead, async (req, res) => {
  try {
    const { patientId } = req.query;
    if (!patientId) {
      return res.status(400).json({ message: 'patientId requis.' });
    }
    const doc = await FormulaireUrgence.findOne({ patient: patientId })
      .sort({ createdAt: -1 })
      .lean();
    if (!doc) {
      return res.json({ formulaire: null });
    }
    return res.json({
      formulaire: {
        id: doc._id.toString(),
        symptomes: doc.symptomes || [],
        alerteAcceptee: doc.alerteAcceptee,
        createdAt: doc.createdAt,
      },
    });
  } catch (err) {
    console.error('Erreur GET /formulaire-urgence', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Liste des conversations du médecin (discussions avec les patients)
// query: doctorId, optionnel filter = all | urgent | demande
app.get('/doctor/conversations', verifyToken, requireDoctorQuery, async (req, res) => {
  try {
    const { doctorId, filter } = req.query;
    if (!doctorId) {
      return res.status(400).json({ message: 'doctorId requis.' });
    }
    const convos = await Conversation.find({ doctor: doctorId })
      .populate('patient', 'fullName _id photoPath')
      .sort({ updatedAt: -1 })
      .lean();

    const convIds = convos.map((c) => c._id);
    const patientObjectIds = convos.map((c) => c.patient?._id).filter(Boolean);

    // Patients avec alerte urgence (formulaire d'urgence avec alerteAcceptee = true)
    const urgentPatientIds = new Set(
      (await FormulaireUrgence.find({ patient: { $in: patientObjectIds }, alerteAcceptee: true })
        .select('patient')
        .lean())
        .map((f) => f.patient?.toString())
        .filter(Boolean)
    );

    // Conversations contenant au moins une demande de téléconsultation
    const convosWithDemande = new Set(
      (await Message.find({
        conversation: { $in: convIds },
        type: 'request_teleconsult',
      })
        .select('conversation')
        .lean())
        .map((m) => m.conversation?.toString())
        .filter(Boolean)
    );

    const convosWithFormulaire = new Set(
      (await Message.find({
        conversation: { $in: convIds },
        type: 'form_teleconsult',
      })
        .select('conversation')
        .lean())
        .map((m) => m.conversation?.toString())
        .filter(Boolean)
    );

    const doctorIdStr = String(doctorId);
    const urgencePendingByPatient = new Map();
    const urgenceForms = await FormulaireUrgence.find({
      patient: { $in: patientObjectIds },
      alerteAcceptee: true,
    })
      .select('patient doctorViews createdAt')
      .sort({ createdAt: -1 })
      .lean();
    for (const row of urgenceForms) {
      const pid = row.patient ? String(row.patient) : '';
      if (!pid || urgencePendingByPatient.has(pid)) continue;
      const views = Array.isArray(row.doctorViews) ? row.doctorViews : [];
      const mine = views.find((v) => String(v.doctor) === doctorIdStr);
      urgencePendingByPatient.set(pid, !mine);
    }

    // Dernier message par conversation (pour aperçu + heure selon dernier message)
    const lastMessages = await Message.aggregate([
      { $match: { conversation: { $in: convos.map((c) => c._id) } } },
      { $sort: { createdAt: -1 } },
      {
        $group: {
          _id: '$conversation',
          lastMessage: { $first: '$content' },
          lastMessageAt: { $first: '$createdAt' },
          lastFromType: { $first: '$fromType' },
          lastType: { $first: '$type' },
          lastPatientMessageAt: {
            $max: {
              $cond: [{ $eq: ['$fromType', 'patient'] }, '$createdAt', null],
            },
          },
          lastDoctorMessageAt: {
            $max: {
              $cond: [{ $eq: ['$fromType', 'doctor'] }, '$createdAt', null],
            },
          },
        },
      },
    ]).exec();
    const lastByConv = new Map(
      lastMessages.map((m) => [
        m._id.toString(),
        {
          content: m.lastMessage ?? '',
          at: m.lastMessageAt,
          fromType: m.lastFromType || null,
          type: m.lastType || null,
          lastPatientAt: m.lastPatientMessageAt || null,
          lastDoctorAt: m.lastDoctorMessageAt || null,
        },
      ])
    );

    let list = convos.map((c) => {
      const pid = c.patient?._id?.toString() ?? '';
      const cid = c._id.toString();
      const tags = [];
      if (urgentPatientIds.has(pid)) tags.push('urgent');
      if (convosWithDemande.has(cid)) tags.push('demande');
      if (convosWithFormulaire.has(cid)) tags.push('formulaire');
      const last = lastByConv.get(cid);
      const hasUnreadFromPatient = !!(
        last?.lastPatientAt &&
        (!last?.lastDoctorAt || new Date(last.lastPatientAt) > new Date(last.lastDoctorAt))
      );
      return {
        conversationId: cid,
        patientId: pid,
        patientName: decrypt(c.patient?.fullName) ?? 'Patient',
        patientPhotoPath: c.patient?.photoPath ?? null,
        updatedAt: c.updatedAt,
        lastMessage: last?.content ?? null,
        lastMessageAt: last?.at ?? c.updatedAt,
        lastMessageFromType: last?.fromType ?? null,
        lastMessageType: last?.type ?? null,
        hasUnreadFromPatient,
        unreadCount: hasUnreadFromPatient ? 1 : 0,
        tags,
        urgenceFormulairePending: urgencePendingByPatient.get(pid) === true,
      };
    });

    const filterVal = String(filter || 'all').toLowerCase();
    if (filterVal === 'urgent') {
      list = list.filter((item) => item.tags.includes('urgent'));
    } else if (filterVal === 'demande') {
      list = list.filter((item) => item.tags.includes('demande'));
    }

    return res.json({ conversations: list });
  } catch (err) {
    console.error('Erreur GET /doctor/conversations', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Créneaux téléconsultation : uniquement collection RendezVous (compat. ancien format `slots`).
// Doit être déclaré avant GET /doctor/:doctorId pour éviter les collisions de route.
app.get('/doctor/:doctorId/scheduled-teleconsults', verifyToken, requireDoctorParam, async (req, res) => {
  try {
    const { doctorId } = req.params;
    if (!mongoose.Types.ObjectId.isValid(doctorId)) {
      return res.status(400).json({ message: 'doctorId invalide.' });
    }

    const rows = await buildDoctorAgendaListFromRendezVous(doctorId);
    const slots = rows.map((r) => ({
      messageId: null,
      rendezvousId: r.rendezvousId,
      conversationId: r.conversationId,
      patientId: r.patientId,
      patientName: r.patientNom,
      patientPhotoPath: r.patientPhotoPath,
      scheduledAt: r.dateHeure,
    }));
    return res.json({ slots });
  } catch (err) {
    console.error('Erreur GET /doctor/:doctorId/scheduled-teleconsults', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Formulaires d’urgence : liste médecin (patients de ses conversations)
app.get('/doctor/:doctorId/urgence-formulaires', verifyToken, requireDoctorParam, async (req, res) => {
  try {
    const { doctorId } = req.params;
    if (!mongoose.Types.ObjectId.isValid(doctorId)) {
      return res.status(400).json({ message: 'doctorId invalide.' });
    }
    const convos = await Conversation.find({ doctor: doctorId }).select('patient').lean();
    const patientIds = convos.map((c) => c.patient);
    if (patientIds.length === 0) {
      return res.json({ items: [] });
    }
    const forms = await FormulaireUrgence.find({
      patient: { $in: patientIds },
      alerteAcceptee: true,
    })
      .populate('patient', 'fullName photoPath')
      .sort({ createdAt: -1 })
      .lean();

    const items = forms.map((f) => {
      const views = Array.isArray(f.doctorViews) ? f.doctorViews : [];
      const mine = views.find((v) => String(v.doctor) === String(doctorId));
      const pat = f.patient;
      const patientId = pat && pat._id ? pat._id : f.patient;
      return {
        id: String(f._id),
        patientId: String(patientId),
        patientName: (pat && pat.fullName) || 'Patient',
        patientPhotoPath: patientPhotoPathFromPopulated(pat),
        symptomes: f.symptomes,
        alerteAcceptee: f.alerteAcceptee,
        createdAt: f.createdAt,
        consulted: !!mine,
        consultedAt: mine ? mine.consultedAt : null,
      };
    });

    items.sort((a, b) => {
      if (a.consulted !== b.consulted) return a.consulted ? 1 : -1;
      return new Date(b.createdAt) - new Date(a.createdAt);
    });

    return res.json({ items });
  } catch (err) {
    console.error('Erreur GET /doctor/:doctorId/urgence-formulaires', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

app.get('/formulaire-urgence/:formId/for-doctor', verifyToken, requireDoctorQuery, async (req, res) => {
  try {
    const { formId } = req.params;
    const doctorId = String(req.query.doctorId || '').trim();
    if (!mongoose.Types.ObjectId.isValid(formId) || !mongoose.Types.ObjectId.isValid(doctorId)) {
      return res.status(400).json({ message: 'Identifiants invalides.' });
    }
    const form = await FormulaireUrgence.findById(formId).populate('patient', 'fullName photoPath').lean();
    if (!form) return res.status(404).json({ message: 'Formulaire introuvable.' });
    const patientId = form.patient && form.patient._id ? form.patient._id : form.patient;
    const conv = await Conversation.findOne({ doctor: doctorId, patient: patientId });
    if (!conv) return res.status(403).json({ message: 'Accès refusé.' });
    const views = Array.isArray(form.doctorViews) ? form.doctorViews : [];
    const mine = views.find((v) => String(v.doctor) === String(doctorId));
    return res.json({
      id: String(form._id),
      patientId: String(patientId),
      patientName: decrypt(form.patient && form.patient.fullName) || 'Patient',
      patientPhotoPath: patientPhotoPathFromPopulated(form.patient),
      symptomes: form.symptomes,
      alerteAcceptee: form.alerteAcceptee,
      createdAt: form.createdAt,
      consulted: !!mine,
      consultedAt: mine ? mine.consultedAt : null,
    });
  } catch (err) {
    console.error('Erreur GET /formulaire-urgence/:formId/for-doctor', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

app.patch('/formulaire-urgence/:formId/mark-consulted', verifyToken, requireDoctorBodyMatches, async (req, res) => {
  try {
    const { formId } = req.params;
    const doctorId = String(req.body.doctorId || '').trim();
    if (!mongoose.Types.ObjectId.isValid(formId) || !mongoose.Types.ObjectId.isValid(doctorId)) {
      return res.status(400).json({ message: 'Identifiants invalides.' });
    }
    const doc = await FormulaireUrgence.findById(formId);
    if (!doc) return res.status(404).json({ message: 'Formulaire introuvable.' });
    const conv = await Conversation.findOne({ doctor: doctorId, patient: doc.patient });
    if (!conv) return res.status(403).json({ message: 'Accès refusé.' });
    doc.doctorViews = (doc.doctorViews || []).filter((v) => String(v.doctor) !== String(doctorId));
    doc.doctorViews.push({ doctor: doctorId, consultedAt: new Date() });
    await doc.save();
    const last = doc.doctorViews[doc.doctorViews.length - 1];
    return res.json({ ok: true, consultedAt: last.consultedAt });
  } catch (err) {
    console.error('Erreur PATCH mark-consulted urgence', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Agenda médecin : uniquement collection RendezVous (plus de messages teleconsult_scheduled).
// GET /api/medecin/rendez-vous?medecinId=X&date=YYYY-MM-DD
app.get('/api/medecin/rendez-vous', verifyToken, requireRdvDoctorGetQuery, async (req, res) => {
  try {
    const medecinId = String(req.query.medecinId || '').trim();
    const dateFilter = String(req.query.date || '').trim();
    if (!mongoose.Types.ObjectId.isValid(medecinId)) {
      return res.status(400).json({ message: 'medecinId invalide.' });
    }

    const list = await buildDoctorAgendaListFromRendezVous(medecinId, { dateFilter });
    return res.json({ rendezVous: list });
  } catch (err) {
    console.error('Erreur GET /api/medecin/rendez-vous', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Rendez-vous téléconsultation (agenda dédié + app patient)
app.get('/api/rendezvous/patient', verifyToken, requireRdvPatientGet, async (req, res) => {
  try {
    const patientId = String(req.query.patientId || '').trim();
    if (!mongoose.Types.ObjectId.isValid(patientId)) {
      return res.status(400).json({ message: 'patientId invalide.' });
    }
    const now = Date.now();
    const list = await RendezVous.find({ patientId })
      .populate('medecinId', 'fullName photoPath')
      .populate('patientId', 'fullName photoPath')
      .sort({ startAt: -1 })
      .lean();
    const aVenir = [];
    const historique = [];
    for (const r of list) {
      const json = formatRdvJson(r, r.patientId, r.medecinId);
      if (r.statut === 'annule') {
        json.statutEffectif = 'annule';
        historique.push(json);
        continue;
      }
      const eff = effectiveRdvStatut(r);
      json.statutEffectif = eff;
      const end = new Date(r.startAt).getTime() + 30 * 60000;
      if (eff === 'termine' || end < now) {
        historique.push(json);
      } else {
        aVenir.push(json);
      }
    }
    aVenir.sort((a, b) => new Date(a.startAt) - new Date(b.startAt));
    historique.sort((a, b) => new Date(b.startAt) - new Date(a.startAt));
    return res.json({ aVenir, historique });
  } catch (err) {
    console.error('Erreur GET /api/rendezvous/patient', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

app.get('/api/rendezvous', verifyToken, requireRdvDoctorGetQuery, async (req, res) => {
  try {
    const medecinId = String(req.query.medecinId || '').trim();
    const mois = String(req.query.mois || '').trim();
    if (!mongoose.Types.ObjectId.isValid(medecinId)) {
      return res.status(400).json({ message: 'medecinId invalide.' });
    }
    if (!/^\d{4}-\d{2}$/.test(mois)) {
      return res.status(400).json({ message: 'mois requis (YYYY-MM).' });
    }
    const docs = await RendezVous.find({
      medecinId,
      statut: { $ne: 'annule' },
      date: new RegExp(`^${mois}-`),
    })
      .populate('patientId', 'fullName photoPath')
      .sort({ date: 1, heure: 1 })
      .lean();
    const rendezvous = docs.map((d) => formatRdvJson(d, d.patientId, null));
    const dateSet = new Set();
    for (const d of docs) {
      if (d.date) dateSet.add(d.date);
    }
    return res.json({ rendezvous, datesOccupees: [...dateSet].sort() });
  } catch (err) {
    console.error('Erreur GET /api/rendezvous', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

app.get('/api/rendezvous/date/:date', verifyToken, requireRdvDoctorGetQuery, async (req, res) => {
  try {
    const date = String(req.params.date || '').trim();
    const medecinId = String(req.query.medecinId || '').trim();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      return res.status(400).json({ message: 'date invalide (YYYY-MM-DD).' });
    }
    if (!mongoose.Types.ObjectId.isValid(medecinId)) {
      return res.status(400).json({ message: 'medecinId invalide.' });
    }
    const docs = await RendezVous.find({
      medecinId,
      date,
      statut: { $ne: 'annule' },
    })
      .populate('patientId', 'fullName photoPath')
      .sort({ heure: 1 })
      .lean();
    const rendezvous = docs.map((d) => formatRdvJson(d, d.patientId, null));
    const creneauxOccupes = rendezvous.map((r) => r.heure).filter(Boolean);
    return res.json({ rendezvous, creneauxOccupes });
  } catch (err) {
    console.error('Erreur GET /api/rendezvous/date', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

app.post('/api/rendezvous', verifyToken, requireRdvPostDoctor, async (req, res) => {
  try {
    const medecinId = String(req.body.medecinId || '').trim();
    const patientId = String(req.body.patientId || '').trim();
    const formulaireId = req.body.formulaireId ? String(req.body.formulaireId).trim() : '';
    const date = String(req.body.date || '').trim();
    const heure = String(req.body.heure || '').trim();
    const type = String(req.body.type || 'teleconsultation').trim();
    const startAtRaw = req.body.startAt;

    if (!mongoose.Types.ObjectId.isValid(medecinId) || !mongoose.Types.ObjectId.isValid(patientId)) {
      return res.status(400).json({ message: 'medecinId ou patientId invalide.' });
    }
    if (!date || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      return res.status(400).json({ message: 'date requise (YYYY-MM-DD).' });
    }
    if (!heure || !/^\d{1,2}:\d{2}$/.test(heure)) {
      return res.status(400).json({ message: 'heure requise (HH:mm).' });
    }
    const conv = await Conversation.findOne({ doctor: medecinId, patient: patientId }).lean();
    if (!conv) {
      return res.status(400).json({ message: 'Aucune conversation avec ce patient.' });
    }

    let start;
    if (startAtRaw && typeof startAtRaw === 'string') {
      start = new Date(startAtRaw);
    } else {
      return res.status(400).json({ message: 'startAt (ISO UTC) requis.' });
    }
    if (Number.isNaN(start.getTime())) {
      return res.status(400).json({ message: 'startAt invalide.' });
    }

    const hit = await doctorMinuteOccupied(medecinId, start.toISOString(), {});
    if (hit) {
      return res.status(409).json({
        message: 'Ce créneau est déjà réservé.',
        conflictWith: {
          patientNom: hit.patientNom,
          date: hit.date || date,
          heure: hit.heure || heure,
        },
      });
    }

    const padHeure = (h) => {
      const parts = String(h).split(':');
      if (parts.length !== 2) return h;
      return `${parts[0].padStart(2, '0')}:${parts[1].padStart(2, '0')}`;
    };
    const heureNorm = padHeure(heure);

    const rv = await RendezVous.create({
      medecinId,
      patientId,
      formulaireId:
        formulaireId && mongoose.Types.ObjectId.isValid(formulaireId) ? formulaireId : undefined,
      date,
      heure: heureNorm,
      startAt: start,
      type,
      statut: 'confirme',
    });

    const pop = await RendezVous.findById(rv._id)
      .populate('patientId', 'fullName photoPath')
      .populate('medecinId', 'fullName')
      .lean();
    await notifyAndMessagePatientRdvProgramme({
      conversationId: String(conv._id),
      patientId,
      rendezvousId: String(rv._id),
      dateYmd: date,
      heureHHmm: heureNorm,
      kind: 'programme',
    });

    return res.status(201).json({
      success: true,
      rendezvousId: String(rv._id),
      rendezvous: formatRdvJson(pop, pop.patientId, pop.medecinId),
    });
  } catch (err) {
    console.error('Erreur POST /api/rendezvous', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

app.put('/api/rendezvous/:id', verifyToken, requireRdvMutateDoctor, async (req, res) => {
  try {
    const id = String(req.params.id || '').trim();
    const medecinId = String(req.body.medecinId || '').trim();
    const date = String(req.body.date || '').trim();
    const heure = String(req.body.heure || '').trim();
    const startAtRaw = req.body.startAt;

    if (!mongoose.Types.ObjectId.isValid(id) || !mongoose.Types.ObjectId.isValid(medecinId)) {
      return res.status(400).json({ message: 'id ou medecinId invalide.' });
    }

    const existing = await RendezVous.findOne({ _id: id, medecinId }).lean();
    if (!existing || existing.statut === 'annule') {
      return res.status(404).json({ message: 'Rendez-vous introuvable.' });
    }

    let start;
    if (startAtRaw && typeof startAtRaw === 'string') {
      start = new Date(startAtRaw);
    } else {
      return res.status(400).json({ message: 'startAt (ISO UTC) requis.' });
    }
    if (Number.isNaN(start.getTime())) {
      return res.status(400).json({ message: 'startAt invalide.' });
    }

    const hit = await doctorMinuteOccupied(medecinId, start.toISOString(), { excludeRdvId: id });
    if (hit) {
      return res.status(409).json({
        message: 'Ce créneau est déjà réservé.',
        conflictWith: {
          patientNom: hit.patientNom,
          date: hit.date || date,
          heure: hit.heure || heure,
        },
      });
    }

    const d = date || existing.date;
    const h = heure || existing.heure;
    const updated = await RendezVous.findByIdAndUpdate(
      id,
      {
        $set: {
          startAt: start,
          date: d,
          heure: h,
        },
      },
      { new: true }
    )
      .populate('patientId', 'fullName photoPath')
      .populate('medecinId', 'fullName')
      .lean();

    const convPut = await Conversation.findOne({
      doctor: medecinId,
      patient: existing.patientId,
    })
      .select('_id')
      .lean();
    if (convPut && convPut._id) {
      await notifyAndMessagePatientRdvProgramme({
        conversationId: String(convPut._id),
        patientId: String(existing.patientId),
        rendezvousId: String(id),
        dateYmd: d,
        heureHHmm: h,
        kind: 'reprogramme',
      });
    } else {
      await notifyPatientRdv(
        String(existing.patientId),
        'Rendez-vous modifié',
        phraseRdvTeleconsultReprogramme(d, h),
        { rendezvousId: String(id), kind: 'reprogramme' },
      );
    }

    return res.json({
      success: true,
      rendezvous: formatRdvJson(updated, updated.patientId, updated.medecinId),
    });
  } catch (err) {
    console.error('Erreur PUT /api/rendezvous/:id', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

app.delete('/api/rendezvous/:id', verifyToken, requireRdvMutateDoctor, async (req, res) => {
  try {
    const id = String(req.params.id || '').trim();
    const medecinId = String(req.body.medecinId || req.query.medecinId || '').trim();
    const motif = String(req.body.motif || req.query.motif || '').trim();

    if (!mongoose.Types.ObjectId.isValid(id) || !mongoose.Types.ObjectId.isValid(medecinId)) {
      return res.status(400).json({ message: 'id ou medecinId invalide.' });
    }

    const existing = await RendezVous.findOne({ _id: id, medecinId }).lean();
    if (!existing || existing.statut === 'annule') {
      return res.status(404).json({ message: 'Rendez-vous introuvable.' });
    }

    await RendezVous.updateOne(
      { _id: id },
      { $set: { statut: 'annule', motifAnnulation: motif } }
    );

    const pop = await Doctor.findById(medecinId).lean();
    const drName = pop && pop.fullName ? `Dr. ${decrypt(pop.fullName)}` : 'Votre médecin';
    let body = `${drName} a annulé votre RDV du ${existing.date} à ${existing.heure}.`;
    if (motif) body += ` Motif : ${motif}`;

    const convDel = await Conversation.findOne({
      doctor: medecinId,
      patient: existing.patientId,
    })
      .select('_id')
      .lean();
    if (convDel && convDel._id) {
      await notifyAndMessagePatientRdvAnnule({
        conversationId: String(convDel._id),
        patientId: String(existing.patientId),
        rendezvousId: String(id),
        dateYmd: existing.date,
        heureHHmm: existing.heure,
        motif,
        content: body,
      });
    } else {
      await notifyPatientRdv(String(existing.patientId), 'Rendez-vous annulé', body, {
        rendezvousId: String(id),
        kind: 'annule',
      });
    }

    return res.json({ success: true });
  } catch (err) {
    console.error('Erreur DELETE /api/rendezvous/:id', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Profil médecin (app médecin : compte + photo)
app.get('/doctor/:doctorId/profile', verifyToken, requireDoctorParam, async (req, res) => {
  try {
    const { doctorId } = req.params;
    if (!mongoose.Types.ObjectId.isValid(doctorId)) {
      return res.status(400).json({ message: 'doctorId invalide.' });
    }
    const doctor = await Doctor.findById(doctorId).lean();
    if (!doctor) {
      return res.status(404).json({ message: 'Médecin introuvable.' });
    }
    return res.json({
      id: doctor._id.toString(),
      fullName: decrypt(doctor.fullName),
      email: decrypt(doctor.email),
      phone: decrypt(doctor.phone) ?? '',
      specialty: doctor.specialty,
      governorate: decrypt(doctor.governorate),
      address: decrypt(doctor.address) ?? '',
      orderNumber: doctor.orderNumber ?? '',
      country: decrypt(doctor.country) ?? '',
      photoPath: doctor.photoPath ?? null,
    });
  } catch (err) {
    console.error('Erreur GET /doctor/:doctorId/profile', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

app.patch('/doctor/:doctorId/name', verifyToken, requireDoctorParam, async (req, res) => {
  try {
    const { doctorId } = req.params;
    const { fullName } = req.body || {};
    if (!fullName || !String(fullName).trim()) {
      return res.status(400).json({ message: 'fullName requis.' });
    }
    if (!mongoose.Types.ObjectId.isValid(doctorId)) {
      return res.status(400).json({ message: 'doctorId invalide.' });
    }
    const doctor = await Doctor.findByIdAndUpdate(
      doctorId,
      { fullName: String(fullName).trim() },
      { new: true, runValidators: false }
    );
    if (!doctor) {
      return res.status(404).json({ message: 'Médecin introuvable.' });
    }
    return res.json({
      message: 'Nom mis à jour.',
      fullName: decrypt(doctor.fullName),
    });
  } catch (err) {
    console.error('Erreur PATCH /doctor/:doctorId/name', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Profil médecin : mise à jour (nom, spécialité, gouvernorat, adresse, téléphone)
app.patch('/doctor/:doctorId/profile', verifyToken, requireDoctorParam, async (req, res) => {
  try {
    const { doctorId } = req.params;
    if (!mongoose.Types.ObjectId.isValid(doctorId)) {
      return res.status(400).json({ message: 'doctorId invalide.' });
    }
    const body = req.body || {};
    const doctor = await Doctor.findById(doctorId);
    if (!doctor) {
      return res.status(404).json({ message: 'Médecin introuvable.' });
    }
    if (body.fullName != null && String(body.fullName).trim()) {
      doctor.fullName = String(body.fullName).trim();
    }
    if (body.specialty != null && String(body.specialty).trim()) {
      doctor.specialty = String(body.specialty).trim();
    }
    if (body.governorate != null && String(body.governorate).trim()) {
      doctor.governorate = String(body.governorate).trim();
    }
    if (body.address != null) {
      doctor.address = String(body.address).trim();
    }
    if (body.phone != null) {
      doctor.phone = String(body.phone).trim();
    }
    if (body.orderNumber != null) {
      doctor.orderNumber = String(body.orderNumber).trim() || undefined;
    }
    if (body.country != null) {
      doctor.country = String(body.country).trim() || undefined;
    }
    await doctor.save();
    return res.json({
      id: doctor._id.toString(),
      fullName: decrypt(doctor.fullName),
      email: decrypt(doctor.email),
      phone: decrypt(doctor.phone) ?? '',
      specialty: doctor.specialty,
      governorate: decrypt(doctor.governorate),
      address: decrypt(doctor.address) ?? '',
      orderNumber: doctor.orderNumber ?? '',
      country: decrypt(doctor.country) ?? '',
      photoPath: doctor.photoPath ?? null,
    });
  } catch (err) {
    console.error('Erreur PATCH /doctor/:doctorId/profile', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

app.post(
  '/doctor/:doctorId/photo',
  verifyToken,
  requireDoctorParam,
  upload.single('photo'),
  async (req, res) => {
    try {
      const { doctorId } = req.params;
      if (!mongoose.Types.ObjectId.isValid(doctorId)) {
        return res.status(400).json({ message: 'doctorId invalide.' });
      }
      if (!req.file) {
        return res.status(400).json({ message: 'Fichier photo requis.' });
      }
      if (!isCloudinaryConfigured) {
        return res.status(503).json({
          message:
            'Stockage cloud non configuré. Ajoutez CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY et CLOUDINARY_API_SECRET dans .env.',
        });
      }
      const existing = await Doctor.findById(doctorId).select(
        'photoPath photoCloudinaryPublicId'
      );
      if (!existing) {
        return res.status(404).json({ message: 'Médecin introuvable.' });
      }

      const resourceType = resourceTypeFromMimetype(req.file.mimetype);
      const cloudUpload = await uploadFileToCloudinary(
        req.file.path,
        'telemedecine/doctors',
        resourceType
      );
      if (!cloudUpload?.url || !cloudUpload.publicId) {
        return res.status(500).json({ message: 'Échec upload vers le stockage cloud.' });
      }

      const oldPublicId =
        existing.photoCloudinaryPublicId ||
        tryParseCloudinaryImagePublicId(existing.photoPath);
      if (oldPublicId) {
        await destroyByPublicId(oldPublicId, 'image');
      }

      const doctor = await Doctor.findByIdAndUpdate(
        doctorId,
        {
          photoPath: cloudUpload.url,
          photoCloudinaryPublicId: cloudUpload.publicId,
        },
        { new: true, runValidators: false }
      );
      if (!doctor) {
        return res.status(404).json({ message: 'Médecin introuvable.' });
      }
      return res.status(201).json({
        message: 'Photo mise à jour.',
        photoPath: doctor.photoPath,
      });
    } catch (err) {
      console.error('Erreur POST /doctor/:doctorId/photo', err);
      return res.status(500).json({ message: 'Erreur serveur.' });
    } finally {
      if (req.file?.path) {
        try {
          await fs.unlink(req.file.path);
        } catch (_) {}
      }
    }
  }
);

// 🔹 Infos publiques d'un médecin (pour le patient : nom + statut)
app.get('/doctor/:doctorId', verifyToken, requireDoctorPublicRead, async (req, res) => {
  try {
    const { doctorId } = req.params;
    const doctor = await Doctor.findById(doctorId)
      .select(
        'fullName specialty status statusUpdatedAt absenceMessage autoReplyEnabled workingHoursStart workingHoursEnd availableDays photoPath hospitalOrClinic governorate address yearsExperience'
      )
      .lean();
    if (!doctor) {
      return res.status(404).json({ message: 'Médecin introuvable.' });
    }
    const effectiveStatus = getEffectiveDoctorStatus(doctor);
    return res.json({
      id: doctor._id.toString(),
      fullName: decrypt(doctor.fullName),
      specialty: doctor.specialty || '',
      status: effectiveStatus,
      statusUpdatedAt: doctor.statusUpdatedAt || null,
      absenceMessage: doctor.absenceMessage || '',
      autoReplyEnabled: !!doctor.autoReplyEnabled,
      photoPath: doctor.photoPath ?? null,
      hospitalOrClinic: doctor.hospitalOrClinic ?? '',
      governorate: decrypt(doctor.governorate) ?? '',
      address: decrypt(doctor.address) ?? '',
      yearsExperience: typeof doctor.yearsExperience === 'number' ? doctor.yearsExperience : 0,
    });
  } catch (err) {
    console.error('Erreur GET /doctor/:doctorId', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Réglages médecin : récupération
app.get('/doctor/:doctorId/settings', verifyToken, requireDoctorParam, async (req, res) => {
  try {
    const { doctorId } = req.params;
    const doctor = await Doctor.findById(doctorId).lean();
    if (!doctor) {
      return res.status(404).json({ message: 'Médecin introuvable.' });
    }
    return res.json({
      workingHoursStart: doctor.workingHoursStart ?? '09:00',
      workingHoursEnd: doctor.workingHoursEnd ?? '18:00',
      availableDays: Array.isArray(doctor.availableDays) ? doctor.availableDays : [1, 2, 3, 4, 5],
      absenceMessage: doctor.absenceMessage ?? '',
      autoReplyEnabled: !!doctor.autoReplyEnabled,
      status: doctor.status ?? 'available',
      statusUpdatedAt: doctor.statusUpdatedAt || null,
    });
  } catch (err) {
    console.error('Erreur GET /doctor/:doctorId/settings', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Réglages médecin : mise à jour (disponibilités + message d'absence)
app.patch('/doctor/:doctorId/settings', verifyToken, requireDoctorParam, async (req, res) => {
  try {
    const { doctorId } = req.params;
    const body = req.body || {};
    const doctor = await Doctor.findById(doctorId);
    if (!doctor) {
      return res.status(404).json({ message: 'Médecin introuvable.' });
    }
    if (body.workingHoursStart != null) doctor.workingHoursStart = String(body.workingHoursStart);
    if (body.workingHoursEnd != null) doctor.workingHoursEnd = String(body.workingHoursEnd);
    if (Array.isArray(body.availableDays)) doctor.availableDays = body.availableDays;
    if (body.absenceMessage != null) doctor.absenceMessage = String(body.absenceMessage);
    if (typeof body.autoReplyEnabled === 'boolean') doctor.autoReplyEnabled = body.autoReplyEnabled;
    await doctor.save();
    return res.json({
      workingHoursStart: doctor.workingHoursStart,
      workingHoursEnd: doctor.workingHoursEnd,
      availableDays: doctor.availableDays,
      absenceMessage: doctor.absenceMessage,
      autoReplyEnabled: doctor.autoReplyEnabled,
      status: doctor.status,
      statusUpdatedAt: doctor.statusUpdatedAt,
    });
  } catch (err) {
    console.error('Erreur PATCH /doctor/:doctorId/settings', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Statut médecin : mise à jour (available | busy | unavailable)
app.patch('/doctor/:doctorId/status', verifyToken, requireDoctorParam, async (req, res) => {
  try {
    const { doctorId } = req.params;
    const { status } = req.body || {};
    const valid = ['available', 'busy', 'unavailable'];
    if (!valid.includes(status)) {
      return res.status(400).json({ message: 'Statut invalide. Valeurs: available, busy, unavailable.' });
    }
    const doctor = await Doctor.findById(doctorId);
    if (!doctor) {
      return res.status(404).json({ message: 'Médecin introuvable.' });
    }
    doctor.status = status;
    doctor.statusUpdatedAt = new Date();
    await doctor.save();
    return res.json({
      status: doctor.status,
      statusUpdatedAt: doctor.statusUpdatedAt,
    });
  } catch (err) {
    console.error('Erreur PATCH /doctor/:doctorId/status', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Conversation patient–médecin (création ou récupération)
app.post('/conversations', verifyToken, requireConversationCreate, async (req, res) => {
  try {
    const { patientId, doctorId } = req.body;

    if (!patientId || !doctorId) {
      return res.status(400).json({ message: 'patientId et doctorId requis.' });
    }

    let conv = await Conversation.findOne({ patient: patientId, doctor: doctorId });
    if (!conv) {
      conv = await Conversation.create({ patient: patientId, doctor: doctorId });
      // premier message système : question consultation physique
      await Message.create({
        conversation: conv._id,
        fromType: 'system',
        type: 'question_physique',
        content: 'Avez‑vous déjà eu une consultation physique avec ce médecin ?',
      });
    }

    return res.json({ conversationId: conv._id.toString() });
  } catch (err) {
    console.error('Erreur /conversations', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

/**
 * Force HTTPS pour les livraisons Cloudinary (le proxy refuse http:).
 */
function normalizeCloudinaryDeliveryUrl(urlStr) {
  if (!urlStr || typeof urlStr !== 'string') return urlStr;
  const t = urlStr.trim();
  if (t.startsWith('http://res.cloudinary.com')) {
    return 'https://' + t.slice('http://'.length);
  }
  return t;
}

function isTrustedCloudinaryDeliveryUrl(urlStr) {
  if (!urlStr || typeof urlStr !== 'string') return false;
  const normalized = normalizeCloudinaryDeliveryUrl(urlStr);
  const cloud = process.env.CLOUDINARY_CLOUD_NAME;
  try {
    const u = new URL(normalized);
    if (u.hostname !== 'res.cloudinary.com') return false;
    const parts = u.pathname.split('/').filter(Boolean);
    if (parts.length < 3) return false;
    const first = parts[0];
    if (cloud && String(cloud).trim()) {
      return first.toLowerCase() === String(cloud).trim().toLowerCase();
    }
    // Sans CLOUDINARY_CLOUD_NAME : accepter toute URL de livraison standard (évite 400 en dev).
    return /^(image|video|raw)$/.test(parts[1]);
  } catch {
    return false;
  }
}

/** Si la livraison `fl_inline` échoue (404), retenter sans ce flag. */
function stripFlInlineFromCloudinaryUrl(urlStr) {
  if (!urlStr || typeof urlStr !== 'string') return urlStr;
  return urlStr
    .replace('/raw/upload/fl_inline/', '/raw/upload/')
    .replace('/video/upload/fl_inline/', '/video/upload/');
}

/**
 * Relaie un fichier Cloudinary vers le client (même origine que l’API) pour éviter
 * les blocages des visionneurs tiers et forcer l’affichage inline quand le navigateur le permet.
 */
function streamHttpsUrlToClient(targetUrl, res, { filename, mimetype, disposition = 'inline' }, depth = 0) {
  if (depth > 5) {
    if (!res.headersSent) res.status(502).json({ message: 'Trop de redirections.' });
    return;
  }
  const normalizedTarget = normalizeCloudinaryDeliveryUrl(targetUrl);
  if (!isTrustedCloudinaryDeliveryUrl(normalizedTarget)) {
    if (!res.headersSent) {
      res
        .status(400)
        .set('Content-Type', 'text/plain; charset=utf-8')
        .send('URL de fichier non autorisée (Cloudinary attendu).');
    }
    return;
  }
  let u;
  try {
    u = new URL(normalizedTarget);
  } catch {
    if (!res.headersSent) {
      res.status(400).set('Content-Type', 'text/plain; charset=utf-8').send('URL invalide.');
    }
    return;
  }
  if (u.protocol !== 'https:') {
    if (!res.headersSent) {
      res.status(400).set('Content-Type', 'text/plain; charset=utf-8').send('HTTPS requis.');
    }
    return;
  }
  const opts = {
    hostname: u.hostname,
    path: u.pathname + u.search,
    method: 'GET',
    headers: { 'User-Agent': 'TelemedecineBackend/1.0' },
  };
  const reqOut = https.request(opts, (upstream) => {
    if (upstream.statusCode >= 300 && upstream.statusCode < 400 && upstream.headers.location) {
      upstream.resume();
      const next = normalizeCloudinaryDeliveryUrl(new URL(upstream.headers.location, normalizedTarget).href);
      streamHttpsUrlToClient(next, res, { filename, mimetype, disposition }, depth + 1);
      return;
    }
    if (upstream.statusCode !== 200) {
      upstream.resume();
      const stripped = stripFlInlineFromCloudinaryUrl(normalizedTarget);
      if (depth === 0 && stripped !== normalizedTarget && isTrustedCloudinaryDeliveryUrl(stripped)) {
        streamHttpsUrlToClient(stripped, res, { filename, mimetype, disposition }, depth + 1);
        return;
      }
      if (!res.headersSent) {
        res.status(502).json({ message: 'Fichier indisponible sur le stockage.' });
      }
      return;
    }
    const ct = mimetype || upstream.headers['content-type'] || 'application/octet-stream';
    res.setHeader('Content-Type', ct);
    const dispName = String(filename || 'fichier').replace(/[\r\n"]/g, '_');
    const safeDisp = disposition === 'attachment' ? 'attachment' : 'inline';
    res.setHeader('Content-Disposition', `${safeDisp}; filename*=UTF-8''${encodeURIComponent(dispName)}`);
    res.setHeader('Cache-Control', 'private, max-age=300');
    upstream.pipe(res);
  });
  reqOut.on('error', (err) => {
    console.error('streamHttpsUrlToClient', err);
    if (!res.headersSent) res.status(502).json({ message: 'Erreur lecture fichier.' });
  });
  reqOut.end();
}

// 🔹 État salle d'attente (MongoDB, cohérent avec la mémoire process)
app.get('/waiting-room/:conversationId', verifyToken, requireConversationParamParticipant, async (req, res) => {
  try {
    const { conversationId } = req.params;
    if (!conversationId || !mongoose.Types.ObjectId.isValid(String(conversationId))) {
      return res.status(400).json({ message: 'conversationId invalide.' });
    }
    const mem = waitingRooms.get(conversationId);
    if (mem) {
      return res.json({
        waiting: true,
        patientId: String(mem.patientId),
        patientName: mem.patientName || 'Patient',
        enteredAt: new Date(mem.enteredAt).toISOString(),
      });
    }
    const row = await WaitingRoomSession.findOne({ conversation: conversationId }).lean();
    if (!row) {
      return res.json({ waiting: false });
    }
    return res.json({
      waiting: true,
      patientId: String(row.patient),
      patientName: row.patientName || 'Patient',
      enteredAt: new Date(row.enteredAt).toISOString(),
    });
  } catch (err) {
    console.error('Erreur GET /waiting-room/:conversationId', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Liste des patients en salle d'attente pour un médecin (reconnexion app)
app.get('/doctor/:doctorId/waiting-rooms', verifyToken, requireDoctorParam, async (req, res) => {
  try {
    const { doctorId } = req.params;
    if (!doctorId || !mongoose.Types.ObjectId.isValid(String(doctorId))) {
      return res.status(400).json({ message: 'doctorId invalide.' });
    }
    const rows = await WaitingRoomSession.find({ doctor: doctorId }).sort({ enteredAt: -1 }).lean();
    const items = rows.map((r) => ({
      conversationId: String(r.conversation),
      patientId: String(r.patient),
      patientName: r.patientName || 'Patient',
      enteredAt: new Date(r.enteredAt).toISOString(),
    }));
    return res.json({ items });
  } catch (err) {
    console.error('Erreur GET /doctor/:doctorId/waiting-rooms', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Récupération des messages d'une conversation
app.get('/messages', verifyToken, requireConversationAccess, async (req, res) => {
  try {
    const { conversationId } = req.query;
    if (!conversationId) {
      return res.status(400).json({ message: 'conversationId requis.' });
    }

    const msgs = await Message.find({ conversation: conversationId })
      .sort({ createdAt: 1 })
      .lean();

    const conv = await Conversation.findById(conversationId).select('sessionStatus').lean();
    const sessionStatus = conv && conv.sessionStatus === 'cloture' ? 'cloture' : 'open';

    return res.json({ messages: msgs, sessionStatus });
  } catch (err) {
    console.error('Erreur /messages', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Récupération incrémentale des nouveaux messages d'une conversation
// Permet de rendre le chat plus "instantané" (poll léger).
app.get('/messages/after', verifyToken, requireConversationAccess, async (req, res) => {
  try {
    const { conversationId, afterId } = req.query;
    if (!conversationId) {
      return res.status(400).json({ message: 'conversationId requis.' });
    }

    const query = { conversation: conversationId };
    if (afterId) {
      // afterId est un ObjectId : `$gt` permet de récupérer uniquement les messages plus récents.
      if (!mongoose.Types.ObjectId.isValid(afterId)) {
        return res.status(400).json({ message: 'afterId invalide.' });
      }
      query._id = { $gt: afterId };
    }

    const msgs = await Message.find(query)
      .sort({ _id: 1 })
      .limit(100)
      .lean();

    const conv = await Conversation.findById(conversationId).select('sessionStatus').lean();
    const sessionStatus = conv && conv.sessionStatus === 'cloture' ? 'cloture' : 'open';

    return res.json({ messages: msgs, sessionStatus });
  } catch (err) {
    console.error('Erreur /messages/after', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Fichier pièce jointe (proxy Cloudinary → navigateur, pour PDF / Office / etc.)
app.get('/messages/:messageId/file', verifyToken, requireConversationAccess, async (req, res) => {
  try {
    const { messageId } = req.params;
    const { conversationId, download } = req.query;
    if (!conversationId || !mongoose.Types.ObjectId.isValid(messageId)) {
      return res.status(400).json({ message: 'Paramètres invalides.' });
    }
    if (!mongoose.Types.ObjectId.isValid(String(conversationId))) {
      return res.status(400).json({ message: 'conversationId invalide.' });
    }
    const msg = await Message.findOne({
      _id: messageId,
      conversation: conversationId,
      type: { $in: ['attachment', 'file'] },
    }).lean();
    if (!msg) {
      return res.status(404).json({ message: 'Pièce jointe introuvable.' });
    }
    const rawPath = msg.payload && msg.payload.path;
    if (!rawPath || typeof rawPath !== 'string' || !rawPath.startsWith('http')) {
      return res.status(404).json({ message: 'Fichier introuvable.' });
    }
    streamHttpsUrlToClient(rawPath, res, {
      filename: msg.content || (msg.payload && msg.payload.filename) || 'fichier',
      mimetype: msg.payload && msg.payload.mimetype,
      disposition: download === '1' ? 'attachment' : 'inline',
    });
  } catch (err) {
    console.error('GET /messages/:messageId/file', err);
    if (!res.headersSent) res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Dossier médical personnel patient (uploads hors chat)
app.get('/api/patient/dossier-medical', verifyToken, requirePatientQuery, async (req, res) => {
  try {
    const patientId = String(req.query.patientId || '').trim();
    if (!mongoose.Types.ObjectId.isValid(patientId)) {
      return res.status(400).json({ message: 'patientId invalide.' });
    }

    const docs = await PatientMedicalDocument.find({ patient: patientId })
      .sort({ createdAt: -1 })
      .lean();

    const items = docs.map((d) => {
      const mimetype = String(d.mimetype || '');
      const fn = String(d.filename || '').toLowerCase();
      const isImage =
        mimetype.startsWith('image/') ||
        fn.endsWith('.jpg') ||
        fn.endsWith('.jpeg') ||
        fn.endsWith('.png');
      return {
        id: String(d._id),
        category: d.category,
        title: d.title || '',
        documentDate: d.documentDate ? new Date(d.documentDate).toISOString() : null,
        filename: d.filename,
        mimetype,
        size: Number(d.size || 0),
        url: dossierPublicUrl(d.path),
        type: isImage ? 'image' : 'file',
        createdAt: d.createdAt,
      };
    });

    return res.json({ items });
  } catch (err) {
    console.error('Erreur GET /api/patient/dossier-medical', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

app.post(
  '/api/patient/dossier-medical',
  verifyToken,
  requirePatientBodyPatientId,
  (req, res, next) => {
    uploadChat.single('file')(req, res, (err) => {
      if (err) {
        if (err instanceof multer.MulterError && err.code === 'LIMIT_FILE_SIZE') {
          return res.status(400).json({
            message: `Fichier trop volumineux (max ${Math.round(CHAT_UPLOAD_MAX_BYTES / (1024 * 1024))} Mo).`,
          });
        }
        const msg =
          typeof err.message === 'string' && err.message.length ? err.message : 'Upload refusé.';
        return res.status(400).json({ message: msg });
      }
      next();
    });
  },
  async (req, res) => {
    try {
      const patientId = String(req.body.patientId || '').trim();
      const category = String(req.body.category || '').trim().toLowerCase();
      const titleRaw = req.body.title != null ? String(req.body.title).trim() : '';
      const documentDateRaw = req.body.documentDate != null ? String(req.body.documentDate).trim() : '';

      if (!mongoose.Types.ObjectId.isValid(patientId)) {
        return res.status(400).json({ message: 'patientId invalide.' });
      }
      if (!['analyses', 'ordonnances', 'fichiers', 'images'].includes(category)) {
        return res.status(400).json({ message: 'Catégorie invalide.' });
      }
      if (!req.file) {
        return res.status(400).json({ message: 'Fichier requis.' });
      }

      const patient = await Patient.findById(patientId).select('_id').lean();
      if (!patient) {
        return res.status(404).json({ message: 'Patient introuvable.' });
      }

      const check = validatePatientDossierUpload(category, req.file.mimetype, req.file.originalname);
      if (!check.ok) {
        return res.status(400).json({ message: check.message || 'Fichier non accepté pour cette catégorie.' });
      }

      let documentDate = undefined;
      if (documentDateRaw) {
        const d = new Date(documentDateRaw);
        if (!Number.isNaN(d.getTime())) documentDate = d;
      }

      const displayName = fixUploadFilename(req.file.originalname);
      let pathValue;
      let publicId = '';
      let cloudinaryResourceType = dossierCloudinaryDestroyType(req.file.mimetype);

      if (isCloudinaryConfigured) {
        const cloudUpload = await uploadChatFileToCloudinary(
          req.file.path,
          'telemedecine/patient-dossier',
          req.file.mimetype,
          req.file.originalname
        );
        if (!cloudUpload?.url || !cloudUpload.publicId) {
          return res.status(500).json({ message: 'Échec upload vers le stockage cloud.' });
        }
        pathValue = cloudUpload.url;
        publicId = cloudUpload.publicId;
        cloudinaryResourceType = String(cloudUpload.resourceType || dossierCloudinaryDestroyType(req.file.mimetype));
      } else {
        const ext = path.extname(req.file.originalname || '') || '';
        const safeName = `${crypto.randomBytes(16).toString('hex')}${ext}`;
        const dest = path.join(uploadsDir, safeName);
        await fs.copyFile(req.file.path, dest);
        pathValue = `/uploads/${safeName}`;
        console.log(`[DOSSIER] local fallback stored path=${pathValue}`);
      }

      const doc = await PatientMedicalDocument.create({
        patient: patientId,
        category,
        title: titleRaw,
        documentDate,
        filename: displayName || 'fichier',
        mimetype: req.file.mimetype || '',
        size: Number(req.file.size ?? 0),
        path: pathValue,
        publicId,
        cloudinaryResourceType,
      });

      return res.status(201).json({
        ok: true,
        item: {
          id: String(doc._id),
          category: doc.category,
          title: doc.title || '',
          documentDate: doc.documentDate ? doc.documentDate.toISOString() : null,
          filename: doc.filename,
          mimetype: doc.mimetype,
          size: doc.size,
          url: dossierPublicUrl(doc.path),
          createdAt: doc.createdAt,
        },
      });
    } catch (err) {
      console.error('POST /api/patient/dossier-medical', err);
      return res.status(500).json({ message: 'Erreur serveur.' });
    } finally {
      if (req.file?.path) {
        try {
          await fs.unlink(req.file.path);
        } catch (_) {}
      }
    }
  }
);

// 🔹 Suppression d'un document du dossier personnel
app.delete('/api/patient/dossier-medical/:documentId', verifyToken, requirePatientQuery, async (req, res) => {
  try {
    const patientId = String(req.query.patientId || '').trim();
    const { documentId } = req.params;
    if (!mongoose.Types.ObjectId.isValid(patientId) || !mongoose.Types.ObjectId.isValid(documentId)) {
      return res.status(400).json({ message: 'Paramètres invalides.' });
    }

    const doc = await PatientMedicalDocument.findOne({
      _id: documentId,
      patient: patientId,
    }).lean();
    if (!doc) {
      return res.status(404).json({ message: 'Document introuvable.' });
    }

    const rtRaw = doc.cloudinaryResourceType && String(doc.cloudinaryResourceType).trim();
    const rt = rtRaw || dossierCloudinaryDestroyType(doc.mimetype);
    const destroyType = rt === 'image' ? 'image' : rt === 'video' ? 'video' : 'raw';
    if (doc.path && typeof doc.path === 'string' && doc.path.startsWith('/uploads/')) {
      const fp = path.join(uploadsDir, path.basename(doc.path));
      try {
        await fs.unlink(fp);
      } catch (_) {}
    } else if (doc.publicId) {
      console.log(`[DOSSIER] destroy publicId=${doc.publicId} type=${destroyType}`);
      await destroyByPublicId(doc.publicId, destroyType);
    }

    await PatientMedicalDocument.deleteOne({ _id: documentId });
    return res.status(204).send();
  } catch (err) {
    console.error('Erreur DELETE /api/patient/dossier-medical/:documentId', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Partager des documents du dossier personnel vers une conversation médecin (message pièce jointe)
app.post('/api/patient/dossier-medical/share', verifyToken, requirePatientBodyPatientId, async (req, res) => {
  try {
    const patientId = String(req.body.patientId || '').trim();
    const doctorId = String(req.body.doctorId || '').trim();
    const itemIds = Array.isArray(req.body.itemIds) ? req.body.itemIds.map((x) => String(x)) : [];
    if (
      !mongoose.Types.ObjectId.isValid(patientId) ||
      !mongoose.Types.ObjectId.isValid(doctorId) ||
      itemIds.length === 0
    ) {
      return res.status(400).json({ message: 'patientId, doctorId et itemIds sont requis.' });
    }

    const oids = itemIds.filter((id) => mongoose.Types.ObjectId.isValid(id));
    if (oids.length === 0) {
      return res.status(400).json({ message: 'Aucun identifiant de document valide fourni.' });
    }

    let conv = await Conversation.findOne({ patient: patientId, doctor: doctorId }).lean();
    if (!conv) {
      const created = await Conversation.create({ patient: patientId, doctor: doctorId });
      conv = created.toObject();
    }
    if (conv.sessionStatus === 'cloture') {
      return res.status(403).json({
        message: 'La session de chat est clôturée. Impossible de partager des documents.',
      });
    }

    const docs = await PatientMedicalDocument.find({
      _id: { $in: oids },
      patient: patientId,
    }).lean();

    if (!docs.length) {
      return res.status(404).json({ message: 'Aucun document valide à partager.' });
    }

    const toInsert = docs.map((d) => ({
      conversation: conv._id,
      fromType: 'patient',
      type: 'attachment',
      content: d.filename || 'fichier',
      payload: {
        path: d.path,
        mimetype: d.mimetype || '',
        size: Number(d.size || 0),
        filename: d.filename,
        sharedFromPatientDossierId: String(d._id),
        sharedAt: new Date().toISOString(),
      },
    }));
    await Message.insertMany(toInsert);

    const convStr = String(conv._id);
    emitToConversation(convStr, 'chat:new_activity', { conversationId: convStr });

    const doctor = await Doctor.findById(doctorId).select('fullName').lean();
    return res.status(201).json({
      message: 'Documents envoyés dans la conversation.',
      doctorName: decrypt(doctor && doctor.fullName) || 'Médecin',
      sharedCount: toInsert.length,
      conversationId: convStr,
    });
  } catch (err) {
    console.error('Erreur POST /api/patient/dossier-medical/share', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

/**
 * Vérifie si le médecin a déjà un créneau téléconsult à la même minute UTC.
 * @param {string} excludeMessageId - id Mongo du message modifié (à ignorer)
 * @returns {Promise<'ok'|'notfound'|'conflict'>}
 */
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
      const c = await Conversation.findById(m.conversation).populate('patient', 'fullName').lean();
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

async function doctorTeleconsultSlotConflict(conversationId, scheduledAtIso, excludeMessageId) {
  const conv = await Conversation.findById(conversationId).lean();
  if (!conv) return 'notfound';
  const hit = await doctorMinuteOccupied(conv.doctor, scheduledAtIso, {
    excludeMessageId,
  });
  return hit ? 'conflict' : 'ok';
}

// 🔹 Envoi d'un message texte générique
app.post('/messages', verifyToken, requireConversationAccess, async (req, res) => {
  try {
    const { conversationId, fromType, from, type, content, payload } = req.body;

    if (!conversationId || !fromType) {
      return res.status(400).json({ message: 'conversationId et fromType requis.' });
    }

    const convForSession = await Conversation.findById(conversationId).select('sessionStatus').lean();
    if (!convForSession) {
      return res.status(404).json({ message: 'Conversation introuvable.' });
    }
    if (convForSession.sessionStatus === 'cloture' && fromType !== 'system') {
      return res.status(403).json({
        message: "Cette session est clôturée. Impossible d'envoyer un message.",
      });
    }

    const msgType = type || 'text';
    if (msgType === 'teleconsult_scheduled' && fromType === 'doctor' && payload && payload.scheduledAt) {
      const st = await doctorTeleconsultSlotConflict(conversationId, payload.scheduledAt, null);
      if (st === 'notfound') {
        return res.status(404).json({ message: 'Conversation introuvable.' });
      }
      if (st === 'conflict') {
        return res.status(409).json({
          message:
            'Un créneau existe déjà à cette heure pour vous (tous patients). Choisissez une autre heure.',
        });
      }
    }

    const msg = await Message.create({
      conversation: conversationId,
      fromType,
      from,
      type: type || 'text',
      content: content || '',
      payload: payload || {},
    });

    emitToConversation(conversationId, 'chat:new_activity', {
      conversationId: String(conversationId),
      messageId: String(msg._id),
      fromType,
      type: msgType,
    });

    await notifyDoctorInboxNewMessage(conversationId, fromType, msgType, msg._id);

    if (msgType === 'call_event' && fromType === 'system' && payload) {
      try {
        await notifyPatientCallMissedPush(conversationId, String(msg._id), payload);
      } catch (e) {
        console.error('[PUSH] notifyPatientCallMissedPush', e);
      }
    }

    if (msgType === 'teleconsult_scheduled' && payload && payload.scheduledAt) {
      emitToConversation(conversationId, 'consultation:scheduled', {
        conversationId,
        messageId: String(msg._id),
        scheduledAt: payload.scheduledAt,
      });
    }

    if (msgType === 'call_event' && payload && payload.kind === 'call_log') {
      emitToConversation(conversationId, 'chat:call_summary', {
        conversationId,
        messageId: String(msg._id),
        mediaType: payload.mediaType === 'video' ? 'video' : 'audio',
        outcome: payload.outcome || 'ended',
        durationSeconds: parseInt(String(payload.durationSeconds || 0), 10) || 0,
      });
    }

    await persistAutoHl7ForConversation({
      conversationId,
      source: 'auto-message',
      fromType,
      content: content || '',
      payload: payload || {},
    });

    // Si le médecin clôture le chat, on ajoute automatiquement un message
    // système pour reproposer le formulaire de téléconsultation au patient
    // lors d'une prochaine ouverture de la conversation.
    if (type === 'chat_closed' && fromType === 'doctor') {
      await Message.create({
        conversation: conversationId,
        fromType: 'system',
        type: 'form_teleconsult_prompt',
        content: 'Le chat a été clôturé. Vous pouvez remplir à nouveau le formulaire.',
        payload: {},
      });
    }

    return res.status(201).json({ message: msg });
  } catch (err) {
    console.error('Erreur /messages POST', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

/**
 * Marque comme lus les messages de l’interlocuteur (double coches côté client).
 * body: { conversationId, readerFromType: 'patient' | 'doctor' }
 */
app.post('/messages/mark-read', verifyToken, requireConversationAccess, async (req, res) => {
  try {
    const conversationId = String(req.body.conversationId || '').trim();
    const readerFromType = String(req.body.readerFromType || '').trim();
    if (!conversationId || !mongoose.Types.ObjectId.isValid(conversationId)) {
      return res.status(400).json({ message: 'conversationId invalide.' });
    }
    if (readerFromType !== 'patient' && readerFromType !== 'doctor') {
      return res.status(400).json({ message: 'readerFromType doit être patient ou doctor.' });
    }
    const now = new Date();
    const filter =
      readerFromType === 'doctor'
        ? {
            conversation: conversationId,
            fromType: 'patient',
            type: { $in: ['text', 'attachment', 'file'] },
            readAt: null,
          }
        : {
            conversation: conversationId,
            fromType: 'doctor',
            readAt: null,
          };
    const result = await Message.updateMany(filter, { $set: { readAt: now } });
    emitToConversation(conversationId, 'chat:messages_read', {
      conversationId,
      readerFromType,
      readAt: now.toISOString(),
    });
    return res.json({ ok: true, modifiedCount: result.modifiedCount || 0 });
  } catch (err) {
    console.error('Erreur POST /messages/mark-read', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Clôture de session chat par le médecin (message système + socket + notification patient)
app.put('/api/conversations/:conversationId/cloturer', verifyToken, requireDoctorBodyMatches, async (req, res) => {
  try {
    const { conversationId } = req.params;
    const doctorId = String(req.body.doctorId || '').trim();
    if (!mongoose.Types.ObjectId.isValid(conversationId) || !mongoose.Types.ObjectId.isValid(doctorId)) {
      return res.status(400).json({ message: 'Identifiants invalides.' });
    }
    const conv = await Conversation.findById(conversationId);
    if (!conv) {
      return res.status(404).json({ message: 'Conversation introuvable.' });
    }
    if (String(conv.doctor) !== doctorId) {
      return res.status(403).json({ message: 'Accès refusé.' });
    }
    if (conv.sessionStatus === 'cloture') {
      return res.json({ ok: true, sessionStatus: 'cloture', idempotent: true });
    }
    conv.sessionStatus = 'cloture';
    await conv.save();

    const sysMsg = await Message.create({
      conversation: conversationId,
      fromType: 'system',
      type: 'chat_closed',
      content: '🔒 La session a été clôturée par le médecin.',
      payload: {},
    });

    const doctor = await Doctor.findById(doctorId).select('fullName').lean();
    const doctorName = decrypt(doctor?.fullName) || 'Médecin';
    const patientId = String(conv.patient);
    const convStr = String(conversationId);

    emitToConversation(convStr, 'chat:new_activity', {
      conversationId: convStr,
      messageId: String(sysMsg._id),
    });
    emitToConversation(convStr, 'chat:session_closed', { conversationId: convStr });
    emitToUserId(patientId, 'patient:chat_session_closed', {
      title: 'Session terminée 🔒',
      body: `Dr. ${doctorName} a clôturé la session de chat.`,
      conversationId: convStr,
      doctorId,
      doctorName,
      openChat: true,
    });

    return res.json({
      ok: true,
      sessionStatus: 'cloture',
      message: sysMsg,
    });
  } catch (err) {
    console.error('Erreur PUT /api/conversations/:conversationId/cloturer', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Réouverture de session chat par le médecin (message système + socket + notification patient)
app.put('/api/conversations/:conversationId/rouvrir', verifyToken, requireDoctorBodyMatches, async (req, res) => {
  try {
    const { conversationId } = req.params;
    const doctorId = String(req.body.doctorId || '').trim();
    if (!mongoose.Types.ObjectId.isValid(conversationId) || !mongoose.Types.ObjectId.isValid(doctorId)) {
      return res.status(400).json({ message: 'Identifiants invalides.' });
    }
    const conv = await Conversation.findById(conversationId);
    if (!conv) {
      return res.status(404).json({ message: 'Conversation introuvable.' });
    }
    if (String(conv.doctor) !== doctorId) {
      return res.status(403).json({ message: 'Accès refusé.' });
    }
    if (conv.sessionStatus !== 'cloture') {
      return res.json({ ok: true, sessionStatus: 'open', idempotent: true });
    }
    conv.sessionStatus = 'open';
    await conv.save();

    const sysMsg = await Message.create({
      conversation: conversationId,
      fromType: 'system',
      type: 'chat_reopened',
      content: '🔓 La session a été réouverte par le médecin.',
      payload: {},
    });

    const doctor = await Doctor.findById(doctorId).select('fullName photoPath').lean();
    const doctorName = decrypt(doctor?.fullName) || 'Médecin';
    const patientId = String(conv.patient);
    const convStr = String(conversationId);

    emitToConversation(convStr, 'chat:new_activity', {
      conversationId: convStr,
      messageId: String(sysMsg._id),
    });
    emitToConversation(convStr, 'chat:session_reopened', { conversationId: convStr });
    emitToUserId(patientId, 'patient:chat_session_reopened', {
      title: 'Session réouverte 🔓',
      body: `Dr. ${doctorName} a réouvert la session de chat. Vous pouvez de nouveau envoyer des messages.`,
      conversationId: convStr,
      doctorId,
      doctorName,
      doctorPhotoPath: doctor?.photoPath || null,
      openChat: true,
    });

    return res.json({
      ok: true,
      sessionStatus: 'open',
      message: sysMsg,
    });
  } catch (err) {
    console.error('Erreur PUT /api/conversations/:conversationId/rouvrir', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Modifier un message (ex. date/heure d'une téléconsultation planifiée)
app.patch('/messages/:messageId', verifyToken, requireConversationAccess, async (req, res) => {
  try {
    const { messageId } = req.params;
    const { conversationId, fromType, content, payload } = req.body;

    if (!conversationId || fromType !== 'doctor') {
      return res.status(400).json({ message: 'conversationId et fromType doctor requis.' });
    }
    if (!mongoose.Types.ObjectId.isValid(messageId)) {
      return res.status(400).json({ message: 'messageId invalide.' });
    }

    const existing = await Message.findOne({
      _id: messageId,
      conversation: conversationId,
    }).lean();

    if (!existing) {
      return res.status(404).json({ message: 'Message introuvable.' });
    }
    if (existing.type !== 'teleconsult_scheduled' || existing.fromType !== 'doctor') {
      return res.status(403).json({ message: 'Ce message ne peut pas être modifié.' });
    }

    const newPayload = { ...(existing.payload || {}), ...(payload || {}) };
    const newContent = content != null ? String(content) : existing.content;
    const scheduledAt = newPayload.scheduledAt;
    if (scheduledAt && typeof scheduledAt === 'string') {
      const st = await doctorTeleconsultSlotConflict(conversationId, scheduledAt, messageId);
      if (st === 'notfound') {
        return res.status(404).json({ message: 'Conversation introuvable.' });
      }
      if (st === 'conflict') {
        return res.status(409).json({
          message:
            'Un créneau existe déjà à cette heure pour vous (tous patients). Choisissez une autre heure.',
        });
      }
    }

    const updated = await Message.findByIdAndUpdate(
      messageId,
      { $set: { content: newContent, payload: newPayload } },
      { new: true }
    ).lean();

    emitToConversation(conversationId, 'consultation:updated', {
      conversationId,
      messageId: String(messageId),
      scheduledAt: (updated.payload && updated.payload.scheduledAt) || null,
    });

    return res.json({ message: updated });
  } catch (err) {
    console.error('Erreur PATCH /messages/:messageId', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Supprimer un message (ex. annuler une téléconsultation planifiée)
app.delete('/messages/:messageId', verifyToken, requireConversationAccess, async (req, res) => {
  try {
    const { messageId } = req.params;
    const { conversationId, fromType } = req.query;

    if (!conversationId || fromType !== 'doctor') {
      return res.status(400).json({ message: 'conversationId et fromType=doctor requis (query).' });
    }
    if (!mongoose.Types.ObjectId.isValid(messageId)) {
      return res.status(400).json({ message: 'messageId invalide.' });
    }

    const result = await Message.deleteOne({
      _id: messageId,
      conversation: conversationId,
      type: 'teleconsult_scheduled',
      fromType: 'doctor',
    });

    if (result.deletedCount === 0) {
      return res.status(404).json({ message: 'Créneau introuvable ou déjà supprimé.' });
    }

    emitToConversation(conversationId, 'consultation:cancelled', {
      conversationId,
      messageId: String(messageId),
    });

    return res.status(204).send();
  } catch (err) {
    console.error('Erreur DELETE /messages/:messageId', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Demande de téléconsultation (cas « Non, première consultation »)
app.post('/teleconsultations/request', verifyToken, requirePatientConversationBody, async (req, res) => {
  try {
    const { conversationId, motif, letterBody } = req.body;
    if (!conversationId) {
      return res.status(400).json({ message: 'conversationId requis.' });
    }

    const conv = await Conversation.findById(conversationId).lean();
    if (!conv) {
      return res.status(404).json({ message: 'Conversation introuvable.' });
    }

    const letterTrim =
      letterBody != null && String(letterBody).trim() ? String(letterBody).trim() : '';

    const reqDoc = await TeleconsultationRequest.create({
      conversation: conversationId,
      patient: conv.patient,
      doctor: conv.doctor,
      motif: motif || '',
      letterBody: letterTrim,
    });

    await Message.create({
      conversation: conversationId,
      fromType: 'system',
      type: 'request_teleconsult',
      content: 'Demande de téléconsultation envoyée.',
      payload: {
        requestId: reqDoc._id.toString(),
        motif: motif || '',
        letterBody: letterTrim,
      },
    });

    return res
      .status(201)
      .json({ message: 'Demande envoyée.', id: reqDoc._id.toString() });
  } catch (err) {
    console.error('Erreur /teleconsultations/request', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Formulaire de téléconsultation (cas « Oui, j’ai déjà consulté »)
app.post('/teleconsultations/form', verifyToken, requirePatientConversationBody, async (req, res) => {
  try {
    const {
      conversationId,
      motif,
      symptomes,
      dateDerniereConsultation,
      traitements,
      allergies,
      notifyChat,
    } = req.body;

    if (!conversationId) {
      return res.status(400).json({ message: 'conversationId requis.' });
    }

    const conv = await Conversation.findById(conversationId).lean();
    if (!conv) {
      return res.status(404).json({ message: 'Conversation introuvable.' });
    }

    const form = await TeleconsultationForm.create({
      doctor: conv.doctor,
      patient: conv.patient,
      conversation: conversationId,
      motif,
      symptomes,
      dateDerniereConsultation: dateDerniereConsultation
        ? new Date(dateDerniereConsultation)
        : undefined,
      traitements,
      allergies,
      attachments: [],
      status: 'pending',
      workflowStatus: 'pending',
    });

    const syncChat = notifyChat !== false && notifyChat !== 'false';
    if (syncChat) {
      await Message.create({
        conversation: conversationId,
        fromType: 'system',
        type: 'form_teleconsult',
        content: 'Formulaire de téléconsultation envoyé.',
        payload: { formId: form._id.toString(), motif, symptomes },
      });
    }

    await persistAutoHl7ForConversation({
      conversationId,
      source: 'auto-teleconsult-form',
      fromType: 'patient',
      content: 'Formulaire de téléconsultation',
      payload: { motif, symptomes, traitements, allergies },
    });

    return res.status(201).json({
      message: 'Formulaire enregistré.',
      id: form._id.toString(),
      patientId: String(conv.patient),
      doctorId: String(conv.doctor),
    });
  } catch (err) {
    console.error('Erreur /teleconsultations/form', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Statistiques téléconsultation (tableau de bord médecin)
app.get('/doctor/:doctorId/teleconsult-stats', verifyToken, requireDoctorParam, async (req, res) => {
  try {
    const { doctorId } = req.params;
    if (!mongoose.Types.ObjectId.isValid(doctorId)) {
      return res.status(400).json({ message: 'doctorId invalide.' });
    }
    const convIds = await teleconsultConversationIdsForDoctor(doctorId);
    const rScope = teleconsultRequestDoctorScope(doctorId, convIds);
    const fScope = teleconsultFormDoctorScope(doctorId, convIds);
    const [rqP, rqA, rqR, forms] = await Promise.all([
      TeleconsultationRequest.countDocuments({ $and: [rScope, { status: 'pending' }] }),
      TeleconsultationRequest.countDocuments({ $and: [rScope, { status: 'accepted' }] }),
      TeleconsultationRequest.countDocuments({ $and: [rScope, { status: 'rejected' }] }),
      TeleconsultationForm.find(fScope).select('status workflowStatus').lean(),
    ]);
    let fp = 0;
    let fa = 0;
    let fr = 0;
    let fws = 0;
    let fwr = 0;
    let awaitingDoctorAction = 0;
    for (const f of forms) {
      const st = normalizedTeleconsultFormStatus(f);
      const wf = f.workflowStatus || 'pending';
      if (st === 'pending') {
        fp += 1;
        awaitingDoctorAction += 1;
      } else if (st === 'accepted') {
        fa += 1;
        if (wf === 'pending') awaitingDoctorAction += 1;
      } else if (st === 'rejected') {
        fr += 1;
      }
      if (wf === 'scheduled') fws += 1;
      if (wf === 'replied') fwr += 1;
    }
    return res.json({
      requests: { pending: rqP, accepted: rqA, rejected: rqR },
      forms: {
        pending: fp,
        accepted: fa,
        rejected: fr,
        workflowScheduled: fws,
        workflowReplied: fwr,
        awaitingDoctorAction,
      },
    });
  } catch (err) {
    console.error('Erreur GET teleconsult-stats', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Demandes de téléconsultation (liste / décision médecin)
app.get('/doctor/:doctorId/teleconsult-requests', verifyToken, requireDoctorParam, async (req, res) => {
  try {
    const { doctorId } = req.params;
    const statusQ = String(req.query.status || '').trim().toLowerCase();
    if (!mongoose.Types.ObjectId.isValid(doctorId)) {
      return res.status(400).json({ message: 'doctorId invalide.' });
    }
    const convos = await Conversation.find({ doctor: doctorId })
      .select('_id patient')
      .populate('patient', 'fullName photoPath')
      .lean();
    const convById = new Map(convos.map((c) => [c._id.toString(), c]));
    const convIds = convos.map((c) => c._id);
    const scope = teleconsultRequestDoctorScope(doctorId, convIds);
    const query =
      statusQ === 'pending' || statusQ === 'accepted' || statusQ === 'rejected'
        ? { $and: [scope, { status: statusQ }] }
        : scope;

    const requests = await TeleconsultationRequest.find(query)
      .populate('patient', 'fullName photoPath')
      .sort({ createdAt: -1 })
      .lean();

    const items = requests.map((r) => {
      let patientId = r.patient && r.patient._id ? String(r.patient._id) : '';
      let patientName = decrypt(r.patient && r.patient.fullName) || 'Patient';
      let patientPhotoPath = patientPhotoPathFromPopulated(r.patient);
      if (!patientId && r.conversation) {
        const c = convById.get(String(r.conversation));
        const p = c && c.patient;
        if (p && p._id) patientId = String(p._id);
        if ((p && p.fullName) || patientName === 'Patient') {
          patientName = decrypt(p && p.fullName) || patientName;
        }
        if (!patientPhotoPath) patientPhotoPath = patientPhotoPathFromPopulated(p);
      }
      return {
        id: String(r._id),
        conversationId: r.conversation ? String(r.conversation) : '',
        patientId,
        patientName,
        patientPhotoPath,
        motif: r.motif || '',
        letterBody: r.letterBody || '',
        rejectionMotif: r.rejectionMotif || '',
        status: r.status,
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
      };
    });
    return res.json({ items });
  } catch (err) {
    console.error('Erreur GET /doctor/:doctorId/teleconsult-requests', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

app.get('/teleconsultations/request/:requestId/for-doctor', verifyToken, requireDoctorQuery, async (req, res) => {
  try {
    const { requestId } = req.params;
    const doctorId = String(req.query.doctorId || '').trim();
    if (!mongoose.Types.ObjectId.isValid(requestId) || !mongoose.Types.ObjectId.isValid(doctorId)) {
      return res.status(400).json({ message: 'Identifiants invalides.' });
    }
    const r = await TeleconsultationRequest.findById(requestId).populate('patient', 'fullName photoPath').lean();
    if (!r) return res.status(404).json({ message: 'Demande introuvable.' });
    let allowed = r.doctor && String(r.doctor) === String(doctorId);
    let conv = null;
    if (!allowed && r.conversation) {
      conv = await Conversation.findById(r.conversation).populate('patient', 'fullName photoPath').lean();
      allowed = conv && String(conv.doctor) === String(doctorId);
    }
    if (!allowed) return res.status(403).json({ message: 'Accès refusé.' });
    let patientId = r.patient && r.patient._id ? String(r.patient._id) : '';
    let patientName = decrypt(r.patient && r.patient.fullName) || 'Patient';
    let patientPhotoPath = patientPhotoPathFromPopulated(r.patient);
    if (!patientId && r.conversation) {
      if (!conv) {
        conv = await Conversation.findById(r.conversation).populate('patient', 'fullName photoPath').lean();
      }
      if (conv && conv.patient) {
        patientId = String(conv.patient._id || conv.patient);
        patientName = decrypt(conv.patient.fullName) || patientName;
        if (!patientPhotoPath) patientPhotoPath = patientPhotoPathFromPopulated(conv.patient);
      }
    }
    return res.json({
      id: String(r._id),
      conversationId: r.conversation ? String(r.conversation) : '',
      patientId,
      patientName,
      patientPhotoPath,
      motif: r.motif || '',
      letterBody: r.letterBody || '',
      rejectionMotif: r.rejectionMotif || '',
      status: r.status,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
    });
  } catch (err) {
    console.error('Erreur GET request for-doctor', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

/**
 * Accepte ou refuse une demande de téléconsultation (message système + socket patient + room chat).
 * @param {'accept'|'reject'} decision
 */
async function applyTeleconsultRequestDecision(requestId, doctorId, decision, rejectionMotifRaw) {
  const rid = String(requestId || '').trim();
  const did = String(doctorId || '').trim();
  if (!mongoose.Types.ObjectId.isValid(rid) || !mongoose.Types.ObjectId.isValid(did)) {
    return { error: 400, message: 'Identifiants invalides.' };
  }
  if (decision !== 'accept' && decision !== 'reject') {
    return { error: 400, message: 'decision doit être accept ou reject.' };
  }
  const reqDoc = await TeleconsultationRequest.findById(rid);
  if (!reqDoc) return { error: 404, message: 'Demande introuvable.' };
  const conv = await Conversation.findById(reqDoc.conversation);
  if (!conv || String(conv.doctor) !== String(did)) {
    return { error: 403, message: 'Accès refusé.' };
  }
  if (reqDoc.status !== 'pending') {
    return { ok: true, status: reqDoc.status, alreadyProcessed: true };
  }
  const motifTrim =
    rejectionMotifRaw != null && String(rejectionMotifRaw).trim()
      ? String(rejectionMotifRaw).trim()
      : '';
  reqDoc.status = decision === 'accept' ? 'accepted' : 'rejected';
  if (decision === 'reject') {
    reqDoc.rejectionMotif = motifTrim || undefined;
  }
  await reqDoc.save();

  const doctor = await Doctor.findById(did).select('fullName photoPath').lean();
  const doctorName = decrypt(doctor?.fullName) || 'Médecin';
  const doctorPhotoPath = doctor?.photoPath || null;
  const patientId = String(reqDoc.patient || conv.patient || '');
  const convIdStr = String(reqDoc.conversation);

  if (decision === 'accept') {
    await Message.create({
      conversation: reqDoc.conversation,
      fromType: 'system',
      type: 'accept_request',
      content: 'Votre demande de téléconsultation a été acceptée par le médecin.',
      payload: { requestId: String(reqDoc._id) },
    });
  }
  // Refus : pas de message dans le fil (notification socket + `patient:teleconsult_request_decision` uniquement).

  emitToConversation(convIdStr, 'chat:new_activity', { conversationId: convIdStr });

  const payloadPatient =
    decision === 'accept'
      ? {
          status: 'accepted',
          title: 'Demande acceptée ✅',
          body: `Dr. ${doctorName} a accepté votre demande. Ouvrez le chat pour remplir le formulaire de téléconsultation.`,
          conversationId: convIdStr,
          doctorId: did,
          doctorName,
          doctorPhotoPath,
          requestId: String(reqDoc._id),
          openChat: true,
        }
      : {
          status: 'rejected',
          title: 'Demande refusée ❌',
          body: motifTrim
            ? `Dr. ${doctorName} a refusé votre demande. Motif : ${motifTrim}`
            : `Dr. ${doctorName} a refusé votre demande.`,
          conversationId: convIdStr,
          doctorId: did,
          doctorName,
          doctorPhotoPath,
          requestId: String(reqDoc._id),
          openChat: false,
          rejectionMotif: motifTrim || null,
        };

  if (patientId) {
    emitToUserId(patientId, 'patient:teleconsult_request_decision', payloadPatient);
  }

  return { ok: true, status: reqDoc.status };
}

// 🔹 CAS 1 / CAS 2 — REST demandes (spécification produit)
app.put('/api/demandes/:id/accepter', verifyToken, requireDoctorBodyMatches, async (req, res) => {
  try {
    const { id } = req.params;
    const doctorId = String(req.body.doctorId || '').trim();
    const result = await applyTeleconsultRequestDecision(id, doctorId, 'accept', null);
    if (result.error) {
      return res.status(result.error).json({ message: result.message });
    }
    return res.json({ ok: true, status: result.status, alreadyProcessed: !!result.alreadyProcessed });
  } catch (err) {
    console.error('Erreur PUT /api/demandes/:id/accepter', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

app.put('/api/demandes/:id/refuser', verifyToken, requireDoctorBodyMatches, async (req, res) => {
  try {
    const { id } = req.params;
    const doctorId = String(req.body.doctorId || '').trim();
    const motif = req.body.motif != null ? String(req.body.motif) : '';
    const result = await applyTeleconsultRequestDecision(id, doctorId, 'reject', motif);
    if (result.error) {
      return res.status(result.error).json({ message: result.message });
    }
    return res.json({ ok: true, status: result.status, alreadyProcessed: !!result.alreadyProcessed });
  } catch (err) {
    console.error('Erreur PUT /api/demandes/:id/refuser', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

app.patch('/teleconsultations/request/:requestId/decision', verifyToken, requireDoctorBodyMatches, async (req, res) => {
  try {
    const { requestId } = req.params;
    const doctorId = String(req.body.doctorId || '').trim();
    const decision = String(req.body.decision || '').trim().toLowerCase();
    const motif = req.body.motif != null ? String(req.body.motif) : '';
    if (decision !== 'accept' && decision !== 'reject') {
      return res.status(400).json({ message: 'decision doit être accept ou reject.' });
    }
    const result = await applyTeleconsultRequestDecision(
      requestId,
      doctorId,
      decision === 'accept' ? 'accept' : 'reject',
      decision === 'reject' ? motif : null
    );
    if (result.error) {
      return res.status(result.error).json({ message: result.message });
    }
    return res.json({ ok: true, status: result.status, alreadyProcessed: !!result.alreadyProcessed });
  } catch (err) {
    console.error('Erreur PATCH request decision', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Formulaires téléconsultation (liste / suivi workflow médecin)
app.get('/doctor/:doctorId/teleconsult-forms', verifyToken, requireDoctorParam, async (req, res) => {
  try {
    const { doctorId } = req.params;
    const statusQ = String(req.query.status || '').trim().toLowerCase();
    if (!mongoose.Types.ObjectId.isValid(doctorId)) {
      return res.status(400).json({ message: 'doctorId invalide.' });
    }
    const convos = await Conversation.find({ doctor: doctorId })
      .select('_id patient')
      .populate('patient', 'fullName photoPath')
      .lean();
    const convById = new Map(convos.map((c) => [c._id.toString(), c]));
    const convIds = convos.map((c) => c._id);
    const scope = teleconsultFormDoctorScope(doctorId, convIds);
    const query =
      statusQ === 'pending' || statusQ === 'accepted' || statusQ === 'rejected'
        ? { $and: [scope, { status: statusQ }] }
        : scope;

    const forms = await TeleconsultationForm.find(query)
      .populate('patient', 'fullName photoPath')
      .sort({ createdAt: -1 })
      .lean();

    const items = forms.map((f) => {
      let patientId = f.patient && f.patient._id ? String(f.patient._id) : '';
      let patientName = decrypt(f.patient && f.patient.fullName) || 'Patient';
      let patientPhotoPath = patientPhotoPathFromPopulated(f.patient);
      if (!patientId && f.conversation) {
        const c = convById.get(String(f.conversation));
        const p = c && c.patient;
        if (p && p._id) patientId = String(p._id);
        if ((p && p.fullName) || patientName === 'Patient') {
          patientName = decrypt(p && p.fullName) || patientName;
        }
        if (!patientPhotoPath) patientPhotoPath = patientPhotoPathFromPopulated(p);
      }
      const wf = f.workflowStatus || 'pending';
      const st = normalizedTeleconsultFormStatus(f);
      return {
        id: String(f._id),
        doctorId: f.doctor ? String(f.doctor) : '',
        patientId,
        patientName,
        patientPhotoPath,
        conversationId: f.conversation ? String(f.conversation) : '',
        motif: f.motif || '',
        symptomes: f.symptomes || '',
        traitements: f.traitements || '',
        allergies: f.allergies || '',
        dateDerniereConsultation: f.dateDerniereConsultation || null,
        attachments: Array.isArray(f.attachments) ? f.attachments : [],
        status: st,
        workflowStatus: wf,
        createdAt: f.createdAt,
        updatedAt: f.updatedAt,
      };
    });
    return res.json({ items });
  } catch (err) {
    console.error('Erreur GET teleconsult-forms', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

app.get('/teleconsultations/form/:formId/for-doctor', verifyToken, requireDoctorQuery, async (req, res) => {
  try {
    const { formId } = req.params;
    const doctorId = String(req.query.doctorId || '').trim();
    if (!mongoose.Types.ObjectId.isValid(formId) || !mongoose.Types.ObjectId.isValid(doctorId)) {
      return res.status(400).json({ message: 'Identifiants invalides.' });
    }
    const f = await TeleconsultationForm.findById(formId).populate('patient', 'fullName photoPath').lean();
    if (!f) return res.status(404).json({ message: 'Formulaire introuvable.' });
    const ok = await canDoctorAccessTeleconsultForm(doctorId, f);
    if (!ok) return res.status(403).json({ message: 'Accès refusé.' });
    let patientId = f.patient && f.patient._id ? String(f.patient._id) : '';
    let patientName = decrypt(f.patient && f.patient.fullName) || 'Patient';
    let patientPhotoPath = patientPhotoPathFromPopulated(f.patient);
    let conversationId = f.conversation ? String(f.conversation) : '';
    if (!patientId && f.conversation) {
      const conv = await Conversation.findById(f.conversation).populate('patient', 'fullName photoPath').lean();
      if (conv && conv.patient) {
        patientId = String(conv.patient._id || conv.patient);
        patientName = decrypt(conv.patient.fullName) || patientName;
        if (!patientPhotoPath) patientPhotoPath = patientPhotoPathFromPopulated(conv.patient);
        if (!conversationId) conversationId = String(conv._id);
      }
    }
    return res.json({
      id: String(f._id),
      doctorId: f.doctor ? String(f.doctor) : '',
      conversationId,
      patientId,
      patientName,
      patientPhotoPath,
      motif: f.motif || '',
      symptomes: f.symptomes || '',
      traitements: f.traitements || '',
      allergies: f.allergies || '',
      dateDerniereConsultation: f.dateDerniereConsultation || null,
      attachments: Array.isArray(f.attachments) ? f.attachments : [],
      status: normalizedTeleconsultFormStatus(f),
      workflowStatus: f.workflowStatus || 'pending',
      createdAt: f.createdAt,
      updatedAt: f.updatedAt,
    });
  } catch (err) {
    console.error('Erreur GET form for-doctor', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

app.patch('/teleconsultations/form/:formId/decision', verifyToken, requireDoctorBodyMatches, async (req, res) => {
  try {
    const { formId } = req.params;
    const doctorId = String(req.body.doctorId || '').trim();
    const decision = String(req.body.decision || '').trim().toLowerCase();
    if (!mongoose.Types.ObjectId.isValid(formId) || !mongoose.Types.ObjectId.isValid(doctorId)) {
      return res.status(400).json({ message: 'Identifiants invalides.' });
    }
    if (decision !== 'accept' && decision !== 'reject') {
      return res.status(400).json({ message: 'decision doit être accept ou reject.' });
    }
    const form = await TeleconsultationForm.findById(formId);
    if (!form) return res.status(404).json({ message: 'Formulaire introuvable.' });
    const ok = await canDoctorAccessTeleconsultForm(doctorId, form);
    if (!ok) return res.status(403).json({ message: 'Accès refusé.' });
    const effectiveStatus = normalizedTeleconsultFormStatus(form);
    if (effectiveStatus !== 'pending') {
      return res.json({ ok: true, status: effectiveStatus, alreadyProcessed: true });
    }
    form.status = decision === 'accept' ? 'accepted' : 'rejected';
    if (form.status === 'accepted') {
      form.workflowStatus = 'pending';
    }
    await form.save();
    if (form.conversation) {
      if (decision === 'accept') {
        await Message.create({
          conversation: form.conversation,
          fromType: 'system',
          type: 'text',
          content: 'Votre formulaire de téléconsultation a été accepté par le médecin.',
          payload: { kind: 'form_accepted', formId: String(form._id) },
        });
      } else {
        await Message.create({
          conversation: form.conversation,
          fromType: 'system',
          type: 'text',
          content:
            'Votre formulaire de téléconsultation n’a pas été retenu par le médecin pour le moment.',
          payload: { kind: 'form_rejected', formId: String(form._id) },
        });
      }
    }
    return res.json({ ok: true, status: form.status });
  } catch (err) {
    console.error('Erreur PATCH form decision', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

app.patch('/teleconsultations/form/:formId/workflow', verifyToken, requireDoctorBodyMatches, async (req, res) => {
  try {
    const { formId } = req.params;
    const doctorId = String(req.body.doctorId || '').trim();
    const status = String(req.body.status || '').trim();
    if (!mongoose.Types.ObjectId.isValid(formId) || !mongoose.Types.ObjectId.isValid(doctorId)) {
      return res.status(400).json({ message: 'Identifiants invalides.' });
    }
    if (status !== 'scheduled' && status !== 'replied') {
      return res.status(400).json({ message: 'status doit être scheduled ou replied.' });
    }
    const form = await TeleconsultationForm.findById(formId);
    if (!form) return res.status(404).json({ message: 'Formulaire introuvable.' });
    const ok = await canDoctorAccessTeleconsultForm(doctorId, form);
    if (!ok) return res.status(403).json({ message: 'Accès refusé.' });
    if (normalizedTeleconsultFormStatus(form) !== 'accepted') {
      return res.status(409).json({ message: 'Le formulaire doit d’abord être accepté.' });
    }
    const current = form.workflowStatus || 'pending';
    if (current !== 'pending') {
      if (current === status) {
        return res.json({ ok: true, workflowStatus: status, idempotent: true });
      }
      return res.status(409).json({ message: 'Le formulaire a déjà été traité.' });
    }
    form.workflowStatus = status;
    await form.save();

    let replyConversationId = '';
    if (status === 'replied') {
      const pid = form.patient ? String(form.patient) : '';
      const did = form.doctor ? String(form.doctor) : '';
      if (pid && did) {
        let convDoc = form.conversation ? await Conversation.findById(form.conversation) : null;
        if (!convDoc) {
          let c2 = await Conversation.findOne({ patient: pid, doctor: did });
          if (!c2) {
            c2 = await Conversation.create({ patient: pid, doctor: did, sessionStatus: 'open' });
            await Message.create({
              conversation: c2._id,
              fromType: 'system',
              type: 'question_physique',
              content: 'Avez‑vous déjà eu une consultation physique avec ce médecin ?',
            });
          } else {
            c2.sessionStatus = 'open';
            await c2.save();
          }
          convDoc = c2;
        } else {
          convDoc.sessionStatus = 'open';
          await convDoc.save();
        }
        if (!form.conversation || String(form.conversation) !== String(convDoc._id)) {
          form.conversation = convDoc._id;
          await form.save();
        }
        replyConversationId = String(convDoc._id);
        await Message.create({
          conversation: convDoc._id,
          fromType: 'system',
          type: 'system',
          content: '',
          payload: { event: 'reply_by_message', formId: String(form._id) },
        });
        const doctor = await Doctor.findById(did).select('fullName photoPath').lean();
        const doctorName = decrypt(doctor?.fullName) || 'Médecin';
        emitToConversation(replyConversationId, 'chat:new_activity', {
          conversationId: replyConversationId,
        });
        emitToUserId(pid, 'patient:doctor_replied_form', {
          title: 'Réponse de votre médecin 💬',
          body: `Dr. ${doctorName} a répondu à votre formulaire. Ouvrez le chat.`,
          conversationId: replyConversationId,
          doctorId: did,
          doctorName,
          doctorPhotoPath: doctor?.photoPath || null,
          openChat: true,
        });
      }
    }

    return res.json({
      ok: true,
      workflowStatus: form.workflowStatus,
      ...(replyConversationId ? { conversationId: replyConversationId } : {}),
    });
  } catch (err) {
    console.error('Erreur PATCH form workflow', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
});

// 🔹 Pièce jointe rattachée au formulaire téléconsultation (stockage métier, pas le chat)
app.post(
  '/teleconsultations/form/:formId/attachment',
  verifyToken,
  requirePatientBodyPatientId,
  (req, res, next) => {
    uploadChat.single('file')(req, res, (err) => {
      if (err) {
        if (err instanceof multer.MulterError && err.code === 'LIMIT_FILE_SIZE') {
          return res.status(400).json({
            message: `Fichier trop volumineux (max ${Math.round(CHAT_UPLOAD_MAX_BYTES / (1024 * 1024))} Mo).`,
          });
        }
        const msg =
          typeof err.message === 'string' && err.message.length ? err.message : 'Upload refusé.';
        return res.status(400).json({ message: msg });
      }
      next();
    });
  },
  async (req, res) => {
    try {
      const { formId } = req.params;
      const patientId = String(req.body.patientId || '').trim();
      if (!mongoose.Types.ObjectId.isValid(formId) || !mongoose.Types.ObjectId.isValid(patientId)) {
        return res.status(400).json({ message: 'formId et patientId valides requis.' });
      }
      if (!req.file) {
        return res.status(400).json({ message: 'Fichier requis.' });
      }
      if (!isCloudinaryConfigured) {
        return res.status(503).json({
          message:
            'Stockage cloud non configuré. Ajoutez CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY et CLOUDINARY_API_SECRET dans .env.',
        });
      }
      const form = await TeleconsultationForm.findById(formId);
      if (!form) return res.status(404).json({ message: 'Formulaire introuvable.' });
      let formPatientId = form.patient ? String(form.patient) : '';
      if (!formPatientId && form.conversation) {
        const conv = await Conversation.findById(form.conversation).select('patient').lean();
        if (conv && conv.patient) formPatientId = String(conv.patient);
      }
      if (!formPatientId || formPatientId !== patientId) {
        return res.status(403).json({ message: 'Accès refusé.' });
      }
      const cloudUpload = await uploadChatFileToCloudinary(
        req.file.path,
        'telemedecine/attachments',
        req.file.mimetype,
        req.file.originalname
      );
      if (!cloudUpload?.url || !cloudUpload.publicId) {
        return res.status(500).json({ message: 'Échec upload vers le stockage cloud.' });
      }
      const displayName = fixUploadFilename(req.file.originalname);
      form.attachments.push({
        path: cloudUpload.url,
        publicId: cloudUpload.publicId,
        filename: displayName,
        mimetype: req.file.mimetype,
        size: req.file.size ?? cloudUpload.bytes,
        uploadedAt: new Date(),
      });
      await form.save();
      const last = form.attachments[form.attachments.length - 1];
      return res.status(201).json({
        message: 'Fichier ajouté au formulaire.',
        attachment: last,
      });
    } catch (err) {
      console.error('/teleconsultations/form/:formId/attachment', err);
      return res.status(500).json({ message: 'Erreur serveur.' });
    } finally {
      if (req.file?.path) {
        try {
          await fs.unlink(req.file.path);
        } catch (_) {}
      }
    }
  }
);

// 🔹 HL7: JSON -> HL7 (MSH/PID/OBX), puis stockage MongoDB
app.post('/hl7/from-json', requireHl7Auth, async (req, res) => {
  try {
    const body = req.body || {};
    if (!body.patient || typeof body.patient !== 'object') {
      return res.status(400).json({ message: 'patient requis.' });
    }
    const hl7Message = buildHl7FromJson(body);
    const check = validateAndNormalizeHl7(hl7Message);
    if (!check.ok) {
      return res.status(400).json({ message: 'Message HL7 invalide.', details: String(check.error?.message || '') });
    }
    const normalized = check.normalized;
    const parsed = parseHl7Message(normalized);
    const doc = await Hl7Message.create({
      direction: 'outbound',
      source: 'flutter-mobile',
      patientExternalId: String(body.patient.id || body.patient.patientId || ''),
      hl7Raw: normalized,
      jsonPayload: body,
      parsed,
      status: 'generated',
    });
    return res.status(201).json({
      id: doc._id.toString(),
      hl7: normalized,
      parsed,
    });
  } catch (err) {
    console.error('POST /hl7/from-json', err);
    return res.status(500).json({ message: 'Erreur serveur HL7.' });
  }
});

// 🔹 HL7: multipart (JSON + fichiers) -> upload Cloudinary -> HL7 -> stockage
app.post(
  '/hl7/from-json-with-files',
  requireHl7Auth,
  (req, res, next) => {
    uploadChat.array('files', 10)(req, res, (err) => {
      if (err) {
        if (err instanceof multer.MulterError && err.code === 'LIMIT_FILE_SIZE') {
          return res.status(400).json({
            message: `Fichier trop volumineux (max ${Math.round(CHAT_UPLOAD_MAX_BYTES / (1024 * 1024))} Mo).`,
          });
        }
        const msg =
          typeof err.message === 'string' && err.message.length ? err.message : 'Upload refusé.';
        return res.status(400).json({ message: msg });
      }
      return next();
    });
  },
  async (req, res) => {
    try {
      if (!isCloudinaryConfigured) {
        return res.status(503).json({
          message:
            'Stockage cloud non configuré. Ajoutez CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY et CLOUDINARY_API_SECRET dans .env.',
        });
      }
      const patient = parseMaybeJson(req.body?.patient, null);
      const measures = parseMaybeJson(req.body?.measures, []);
      const source = String(req.body?.source || 'flutter-mobile');
      if (!patient || typeof patient !== 'object') {
        return res.status(400).json({ message: 'patient requis (JSON).' });
      }

      const filesRaw = Array.isArray(req.files) ? req.files : [];
      const uploadedFiles = [];
      for (const f of filesRaw) {
        const up = await uploadChatFileToCloudinary(
          f.path,
          'telemedecine/hl7',
          f.mimetype,
          f.originalname
        );
        if (!up?.url || !up.publicId) continue;
        uploadedFiles.push({
          url: up.url,
          label: fixUploadFilename(f.originalname) || 'medical_file',
          mimetype: f.mimetype || '',
          publicId: up.publicId,
        });
      }

      const payload = {
        patient,
        measures: Array.isArray(measures) ? measures : [],
        files: uploadedFiles.map((x) => ({
          url: x.url,
          label: x.label,
          mimetype: x.mimetype,
        })),
      };
      const hl7Message = buildHl7FromJson(payload);
      const check = validateAndNormalizeHl7(hl7Message);
      if (!check.ok) {
        return res.status(400).json({ message: 'Message HL7 invalide.', details: String(check.error?.message || '') });
      }
      const normalized = check.normalized;
      const parsed = parseHl7Message(normalized);
      const doc = await Hl7Message.create({
        direction: 'outbound',
        source,
        patientExternalId: String(patient.id || patient.patientId || ''),
        hl7Raw: normalized,
        jsonPayload: payload,
        parsed,
        status: 'generated',
      });

      return res.status(201).json({
        id: doc._id.toString(),
        hl7: normalized,
        parsed,
        files: uploadedFiles,
      });
    } catch (err) {
      console.error('POST /hl7/from-json-with-files', err);
      return res.status(500).json({ message: 'Erreur serveur HL7.' });
    } finally {
      const filesRaw = Array.isArray(req.files) ? req.files : [];
      for (const f of filesRaw) {
        if (f?.path) {
          try {
            await fs.unlink(f.path);
          } catch (_) {}
        }
      }
    }
  }
);

// 🔹 HL7: parsing d'un message HL7 reçu, puis stockage MongoDB
app.post('/hl7/parse', requireHl7Auth, async (req, res) => {
  try {
    const { hl7Message, source } = req.body || {};
    if (!hl7Message || typeof hl7Message !== 'string') {
      return res.status(400).json({ message: 'hl7Message requis.' });
    }
    const check = validateAndNormalizeHl7(hl7Message);
    if (!check.ok) {
      return res.status(400).json({ message: 'Message HL7 invalide.', details: String(check.error?.message || '') });
    }
    const normalized = check.normalized;
    const parsed = parseHl7Message(normalized);
    const doc = await Hl7Message.create({
      direction: 'inbound',
      source: source || 'external-system',
      patientExternalId: parsed.pid.patientId || '',
      hl7Raw: normalized,
      parsed,
      status: 'parsed',
    });
    return res.status(201).json({
      id: doc._id.toString(),
      parsed,
    });
  } catch (err) {
    console.error('POST /hl7/parse', err);
    return res.status(500).json({ message: 'Erreur parse HL7.' });
  }
});

// 🔹 HL7: liste des messages stockés
app.get('/hl7/messages', requireHl7Auth, async (req, res) => {
  try {
    const direction = req.query.direction ? String(req.query.direction) : null;
    const patientId = req.query.patientId ? String(req.query.patientId) : null;
    const limit = Math.min(parseInt(req.query.limit || '50', 10) || 50, 200);
    const query = {};
    if (direction && (direction === 'inbound' || direction === 'outbound')) {
      query.direction = direction;
    }
    if (patientId) query.patientExternalId = patientId;
    const items = await Hl7Message.find(query).sort({ createdAt: -1 }).limit(limit).lean();
    return res.json({ messages: items });
  } catch (err) {
    console.error('GET /hl7/messages', err);
    return res.status(500).json({ message: 'Erreur lecture HL7.' });
  }
});

// 🔹 HL7: détail d'un message
app.get('/hl7/messages/:id', requireHl7Auth, async (req, res) => {
  try {
    const { id } = req.params;
    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({ message: 'id invalide.' });
    }
    const item = await Hl7Message.findById(id).lean();
    if (!item) return res.status(404).json({ message: 'Message HL7 introuvable.' });
    return res.json(item);
  } catch (err) {
    console.error('GET /hl7/messages/:id', err);
    return res.status(500).json({ message: 'Erreur lecture HL7.' });
  }
});

// 🔹 Upload de pièce jointe pour téléconsultation (multipart → Cloudinary resource_type auto → message type `file`)
app.post(
  '/teleconsultations/upload',
  verifyToken,
  (req, res, next) => {
    uploadChat.single('file')(req, res, (err) => {
      if (err) {
        if (err instanceof multer.MulterError && err.code === 'LIMIT_FILE_SIZE') {
          return res.status(400).json({
            message: `Fichier trop volumineux (max ${Math.round(CHAT_UPLOAD_MAX_BYTES / (1024 * 1024))} Mo).`,
          });
        }
        const msg =
          typeof err.message === 'string' && err.message.length ? err.message : 'Upload refusé.';
        return res.status(400).json({ message: msg });
      }
      next();
    });
  },
  requireConversationAccess,
  async (req, res) => {
    try {
      const { conversationId, fromType, senderId } = req.body;

      if (!conversationId || !req.file) {
        return res
          .status(400)
          .json({ message: 'conversationId et fichier requis.' });
      }
      if (!isCloudinaryConfigured) {
        return res.status(503).json({
          message:
            'Stockage cloud non configuré. Ajoutez CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY et CLOUDINARY_API_SECRET dans .env.',
        });
      }

      const senderType = fromType === 'doctor' ? 'doctor' : 'patient';
      const convUpload = await Conversation.findById(conversationId).select('sessionStatus').lean();
      if (convUpload && convUpload.sessionStatus === 'cloture') {
        return res.status(403).json({
          message: "Cette session est clôturée. Impossible d'envoyer un message.",
        });
      }
      const cloudUpload = await uploadChatFileToCloudinary(
        req.file.path,
        'telemedecine/attachments',
        req.file.mimetype,
        req.file.originalname
      );
      if (!cloudUpload?.url || !cloudUpload.publicId) {
        return res.status(500).json({ message: 'Échec upload vers le stockage cloud.' });
      }
      const fileUrl = cloudUpload.url;
      const displayName = fixUploadFilename(req.file.originalname);

      let fromId;
      if (senderId && mongoose.Types.ObjectId.isValid(String(senderId))) {
        const conv = await Conversation.findById(conversationId).lean();
        if (conv) {
          const sid = String(senderId);
          if (String(conv.patient) === sid || String(conv.doctor) === sid) {
            fromId = new mongoose.Types.ObjectId(senderId);
          }
        }
      }

      const uploadedMsg = await Message.create({
        conversation: conversationId,
        fromType: senderType,
        from: fromId,
        type: 'file',
        content: displayName,
        payload: {
          filename: displayName,
          publicId: cloudUpload.publicId,
          path: fileUrl,
          mimetype: req.file.mimetype,
          size: req.file.size ?? cloudUpload.bytes,
          cloudinaryResourceType: cloudUpload.resourceType,
          cloudinaryFormat: cloudUpload.format,
          width: cloudUpload.width,
          height: cloudUpload.height,
        },
      });

      emitToConversation(conversationId, 'chat:new_activity', {
        conversationId: String(conversationId),
        messageId: String(uploadedMsg._id),
        fromType: senderType,
        type: 'file',
      });
      await notifyDoctorInboxNewMessage(conversationId, senderType, 'file', uploadedMsg._id);

      await persistAutoHl7ForConversation({
        conversationId,
        source: 'auto-chat-file',
        fromType: senderType,
        content: '',
        payload: { mimetype: req.file.mimetype },
        files: [
          {
            url: fileUrl,
            label: displayName,
            mimetype: req.file.mimetype,
          },
        ],
      });

      return res.status(201).json({
        message: 'Fichier reçu.',
        filename: displayName,
        originalName: displayName,
        url: fileUrl,
        resourceType: cloudUpload.resourceType,
        format: cloudUpload.format,
      });
    } catch (err) {
      console.error('/teleconsultations/upload', err);
      return res.status(500).json({ message: 'Erreur serveur.' });
    } finally {
      if (req.file?.path) {
        try {
          await fs.unlink(req.file.path);
        } catch (_) {}
      }
    }
  }
);

app.use((err, req, res, next) => {
  console.error('Erreur middleware non gérée:', err);
  if (res.headersSent) return next(err);
  return res.status(500).json({ message: 'Erreur serveur inattendue.' });
});

// 🔹 Lancement serveur HTTP + Socket.IO
const PORT = parseInt(process.env.PORT || '3000', 10);
server.listen(PORT, () => {
  console.log(`Serveur démarré sur http://localhost:${PORT}`);
});