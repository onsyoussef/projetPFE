const mongoose = require('mongoose');
const path = require('path');
const fs = require('fs/promises');
const fsSync = require('fs');
const crypto = require('crypto');

const Conversation = require('../models/Conversation');
const Doctor = require('../models/Doctor');
const Patient = require('../models/Patient');
const Message = require('../models/Message');
const Prescription = require('../models/Prescription');
const { assertDoctorVerifiedForRequest } = require('../services/doctorVerificationService');
const { buildPrescriptionPdfBuffer } = require('../services/prescriptionPdfService');
const {
  isConfigured: isCloudinaryConfigured,
  uploadPdfBufferToCloudinary,
  cloudinaryInlineDeliveryUrl,
  buildSignedRawUrl,
  rawDeliveryModeFromEnv,
  resolveRawAssetForSigning,
  extractRawPublicIdFromSecureUrl,
} = require('../config/cloudinaryConfig');
const { emitToConversation } = require('../services/realtimeGateway');
const { notifyPatientInboxNewMessage } = require('../services/utilsService');
const { persistAutoHl7ForConversation } = require('../services/hl7Service');
const { streamHttpsUrlToClient } = require('../services/streamHttpsFile');
const { decrypt } = require('../services/cryptoService');

const uploadsRootDir = path.join(__dirname, '..', 'uploads');

function stripInvalidRawFlInline(url) {
  if (!url || typeof url !== 'string') return url;
  return url.replace(/\/raw\/upload\/fl_inline\//g, '/raw/upload/').replace(/\/video\/upload\/fl_inline\//g, '/video/upload/');
}
function withAttachmentFlag(url) {
  if (!url || typeof url !== 'string') return '';
  try {
    const u = new URL(url);
    if (!u.searchParams.has('fl_attachment')) u.searchParams.set('fl_attachment', 'ordonnance.pdf');
    return u.toString();
  } catch {
    return url;
  }
}
function isCloudinaryRawUrl(url) {
  return !!(url && typeof url === 'string' && url.includes('res.cloudinary.com') && url.includes('/raw/'));
}
function logPrescriptionPdf(event, details = {}) {
  try { console.log('[PRESCRIPTION PDF]', event, JSON.stringify(details)); } catch { console.log('[PRESCRIPTION PDF]', event); }
}

async function buildCloudinaryPdfCandidates(pres) {
  const rawPath = String(pres?.pdfUrl || '').trim();
  if (!isCloudinaryConfigured || !isCloudinaryRawUrl(rawPath)) return [stripInvalidRawFlInline(rawPath)].filter(Boolean);
  const candidates = [];
  const push = (url) => { const u = String(url || '').trim(); if (u && !candidates.includes(u)) candidates.push(u); };
  const normalizedOriginal = stripInvalidRawFlInline(rawPath);
  push(normalizedOriginal); push(withAttachmentFlag(normalizedOriginal));
  const publicIdHint = (typeof pres.pdfPublicId === 'string' && pres.pdfPublicId.trim()) || extractRawPublicIdFromSecureUrl(rawPath);
  if (!publicIdHint) return candidates;
  try {
    const resolved = await resolveRawAssetForSigning(publicIdHint.trim(), rawPath);
    if (!resolved?.publicId) return candidates;
    const version = resolved.version > 0 ? resolved.version : undefined;
    const signedApiDownload = buildSignedRawUrl(resolved.publicId, 3600, { deliveryMode: 'api_download', version });
    const signedCdn = buildSignedRawUrl(resolved.publicId, 3600, { deliveryMode: 'cdn', version });
    if (rawDeliveryModeFromEnv() === 'api_download') { push(signedApiDownload); push(signedCdn); } else { push(signedCdn); push(signedApiDownload); }
    push(withAttachmentFlag(signedApiDownload)); push(withAttachmentFlag(signedCdn));
  } catch (e) {
    logPrescriptionPdf('signed-candidates-error', { prescriptionId: String(pres?._id || ''), error: e?.message || String(e) });
  }
  return candidates;
}

async function sendPrescriptionLeanPdf(pres, res) {
  const rawPath = pres.pdfUrl;
  const filename = 'ordonnance.pdf';
  if (typeof rawPath === 'string' && rawPath.startsWith('http')) {
    const streamCandidates = await buildCloudinaryPdfCandidates(pres);
    for (const streamUrl of streamCandidates) {
      if (res.headersSent) return;
      await new Promise((resolve) => {
        streamHttpsUrlToClient(streamUrl, res, {
          filename,
          mimetype: 'application/pdf',
          disposition: 'inline',
          skipUpstreamTrustCheck: true,
          onFinished: resolve,
        });
      });
      if (res.headersSent) return;
    }
    if (!res.headersSent) return res.status(502).json({ message: 'PDF Cloudinary inaccessible (échec des liens signés/fallback).' });
    return;
  }
  if (typeof rawPath === 'string' && rawPath.startsWith('/uploads/')) {
    const rel = rawPath.replace(/^\/uploads\/?/, '');
    const segments = rel.split('/').filter((s) => s && s !== '..' && s !== '.');
    const fp = path.join(uploadsRootDir, ...segments);
    const resolvedBase = path.resolve(uploadsRootDir);
    const resolvedFile = path.resolve(fp);
    const relSafe = path.relative(resolvedBase, resolvedFile);
    if (relSafe.startsWith('..') || path.isAbsolute(relSafe)) { if (!res.headersSent) res.status(400).json({ message: 'Chemin invalide.' }); return; }
    try { await fs.access(resolvedFile); } catch { if (!res.headersSent) res.status(404).json({ message: 'Fichier introuvable.' }); return; }
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `inline; filename*=UTF-8''${encodeURIComponent(filename)}`);
    res.setHeader('Cache-Control', 'private, max-age=300');
    fsSync.createReadStream(resolvedFile).pipe(res);
    return;
  }
  if (!res.headersSent) res.status(404).json({ message: 'Fichier introuvable.' });
}

function normalizeMedications(raw) {
  if (!Array.isArray(raw)) return [];
  const out = [];
  for (const item of raw) {
    if (!item || typeof item !== 'object') continue;
    const name = String(item.name || '').trim();
    if (!name) continue;
    out.push({
      name,
      posologie: String(item.posologie || '').trim(),
      duree: String(item.duree || '').trim(),
      instructions: String(item.instructions || '').trim(),
    });
  }
  return out;
}
function prescriptionHistoryDto(p) {
  const meds = Array.isArray(p.medications) ? p.medications : [];
  return {
    id: String(p._id),
    prescriptionMessageId: p.message ? String(p.message) : '',
    patientId: String(p.patient),
    doctorId: String(p.doctor),
    conversationId: String(p.conversation),
    medications: meds.map((m) => ({ name: m.name, dosage: m.posologie || '', duration: m.duree || '', instructions: m.instructions || '' })),
    note: p.notes || '',
    createdAt: p.createdAt ? new Date(p.createdAt).toISOString() : null,
    updatedAt: p.updatedAt ? new Date(p.updatedAt).toISOString() : null,
    doctorName: p.doctorDisplayName || '',
    doctorSpecialty: p.doctorSpecialty || '',
    city: p.city || '',
    pdfUrl: cloudinaryInlineDeliveryUrl(p.pdfUrl) || p.pdfUrl,
    statusBadge: 'delivered',
    statusLabelKey: 'delivered',
  };
}

async function requirePrescriptionParticipant(req, res, next) {
  try {
    const prescriptionId = String(req.params.prescriptionId || '').trim();
    if (!mongoose.Types.ObjectId.isValid(prescriptionId)) return res.status(400).json({ message: 'Identifiant ordonnance invalide.' });
    const pres = await Prescription.findById(prescriptionId).select('conversation').lean();
    if (!pres) return res.status(404).json({ message: 'Ordonnance introuvable.' });
    const conv = await Conversation.findById(pres.conversation).select('patient doctor').lean();
    if (!conv) return res.status(404).json({ message: 'Conversation introuvable.' });
    const uid = req.auth && req.auth.sub;
    const role = req.auth && req.auth.role;
    if (role === 'patient' && String(conv.patient) !== String(uid)) return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
    if (role === 'doctor') {
      if (String(conv.doctor) !== String(uid)) {
        return res.status(403).json({ message: 'Accès non autorisé à cette ressource.' });
      }
      if (!(await assertDoctorVerifiedForRequest(req, res))) return;
    }
    if (role !== 'patient' && role !== 'doctor') return res.status(403).json({ message: 'Accès non autorisé.' });
    req.prescriptionAccessId = prescriptionId;
    next();
  } catch (e) {
    console.error('requirePrescriptionParticipant', e);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getPrescriptionPdfByMessage(req, res) {
  try {
    const conversationId = String(req.params.conversationId || '').trim();
    const messageId = String(req.params.messageId || '').trim();
    if (!mongoose.Types.ObjectId.isValid(conversationId) || !mongoose.Types.ObjectId.isValid(messageId)) {
      return res.status(400).json({ message: 'Identifiants invalides.' });
    }
    const pres = await Prescription.findOne({ conversation: conversationId, message: messageId }).lean();
    if (!pres) return res.status(404).json({ message: 'Ordonnance introuvable.' });
    await sendPrescriptionLeanPdf(pres, res);
  } catch (err) {
    console.error('GET .../prescriptions/by-message/:messageId/pdf', err);
    if (!res.headersSent) res.status(500).json({ message: 'Erreur serveur.' });
  }
}
async function getPrescriptionPdfById(req, res) {
  try {
    const conversationId = String(req.params.conversationId || '').trim();
    const prescriptionId = String(req.params.prescriptionId || '').trim();
    if (!mongoose.Types.ObjectId.isValid(conversationId) || !mongoose.Types.ObjectId.isValid(prescriptionId)) {
      return res.status(400).json({ message: 'Identifiants invalides.' });
    }
    const pres = await Prescription.findOne({ _id: prescriptionId, conversation: conversationId }).lean();
    if (!pres) return res.status(404).json({ message: 'Ordonnance introuvable.' });
    await sendPrescriptionLeanPdf(pres, res);
  } catch (err) {
    console.error('GET .../prescriptions/:prescriptionId/pdf', err);
    if (!res.headersSent) res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function listConversationPrescriptions(req, res) {
  try {
    const conversationId = String(req.params.conversationId || '').trim();
    if (!mongoose.Types.ObjectId.isValid(conversationId)) return res.status(400).json({ message: 'conversationId invalide.' });
    const fromRaw = String(req.query.from || '').trim();
    const toRaw = String(req.query.to || '').trim();
    const limitRaw = Number.parseInt(String(req.query.limit || '50'), 10);
    const limit = Number.isFinite(limitRaw) ? Math.max(1, Math.min(200, limitRaw)) : 50;
    const createdAt = {};
    if (fromRaw) { const d = new Date(fromRaw); if (Number.isNaN(d.getTime())) return res.status(400).json({ message: 'Paramètre from invalide (ISO attendu).' }); createdAt.$gte = d; }
    if (toRaw) { const d = new Date(toRaw); if (Number.isNaN(d.getTime())) return res.status(400).json({ message: 'Paramètre to invalide (ISO attendu).' }); createdAt.$lte = d; }
    const query = { conversation: conversationId };
    if (Object.keys(createdAt).length > 0) query.createdAt = createdAt;
    const list = await Prescription.find(query).sort({ createdAt: -1 }).limit(limit).lean();
    return res.json({ items: list.map((p) => ({
      prescriptionId: String(p._id), pdfUrl: cloudinaryInlineDeliveryUrl(p.pdfUrl) || p.pdfUrl, doctorName: p.doctorDisplayName || '',
      patientName: p.patientDisplayName || '', city: p.city || '', sentAt: p.createdAt ? new Date(p.createdAt).toISOString() : null,
    })) });
  } catch (err) {
    console.error('GET .../prescriptions', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getLatestConversationPrescription(req, res) {
  try {
    const conversationId = String(req.params.conversationId || '').trim();
    if (!mongoose.Types.ObjectId.isValid(conversationId)) return res.status(400).json({ message: 'conversationId invalide.' });
    const msg = await Message.findOne({ conversation: conversationId, type: 'prescription', fromType: 'doctor' }).sort({ createdAt: -1 }).lean();
    const pdfUrl = msg && msg.payload && typeof msg.payload.pdfUrl === 'string' && msg.payload.pdfUrl.trim() ? msg.payload.pdfUrl.trim() : '';
    if (!pdfUrl) return res.status(404).json({ message: 'Aucune ordonnance.' });
    const payload = msg.payload && typeof msg.payload === 'object' ? msg.payload : {};
    let prescriptionId = typeof payload.prescriptionId === 'string' ? payload.prescriptionId.trim() : '';
    if (!prescriptionId && msg._id) { const linked = await Prescription.findOne({ message: msg._id }).lean(); if (linked) prescriptionId = linked._id.toString(); }
    if (!prescriptionId && pdfUrl) { const linked = await Prescription.findOne({ conversation: conversationId, pdfUrl }).lean(); if (linked) prescriptionId = linked._id.toString(); }
    return res.json({ pdfUrl: cloudinaryInlineDeliveryUrl(pdfUrl) || pdfUrl, prescriptionId: prescriptionId || undefined, sentAt: msg.createdAt ? msg.createdAt.toISOString() : null });
  } catch (err) {
    console.error('GET .../prescriptions/latest', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function createPrescriptionForConversation(req, res) {
  try {
    if (!req.auth || req.auth.role !== 'doctor') return res.status(403).json({ message: 'Réservé au médecin.' });
    if (!(await assertDoctorVerifiedForRequest(req, res))) return;
    const doctorId = String(req.auth.sub || '').trim();
    const conversationId = String(req.params.conversationId || '').trim();
    const city = String(req.body.city || '').trim();
    const notes = req.body.notes != null ? String(req.body.notes).trim() : '';
    const sourceRaw = String(req.body.source || 'chat').trim().toLowerCase();
    const source = sourceRaw === 'teleconsult' ? 'teleconsult' : 'chat';
    const consultationCallRoomId = req.body.consultationCallRoomId != null ? String(req.body.consultationCallRoomId).trim() : '';
    if (!mongoose.Types.ObjectId.isValid(conversationId)) return res.status(400).json({ message: 'conversationId invalide.' });
    if (!city) return res.status(400).json({ message: 'La ville est obligatoire.' });
    const medications = normalizeMedications(req.body.medications);
    if (medications.length === 0) return res.status(400).json({ message: 'Ajoutez au moins un médicament avec un nom renseigné.' });
    const conv = await Conversation.findById(conversationId).lean();
    if (!conv) return res.status(404).json({ message: 'Conversation introuvable.' });
    if (String(conv.doctor) !== doctorId) return res.status(403).json({ message: 'Accès refusé.' });
    if (conv.sessionStatus === 'cloture') return res.status(403).json({ message: "Cette session est clôturée. Impossible d'envoyer une ordonnance." });
    const [doctor, patient] = await Promise.all([
      Doctor.findById(doctorId).select('fullName specialty').lean(),
      Patient.findById(conv.patient).select('fullName').lean(),
    ]);
    if (!doctor || !patient) return res.status(404).json({ message: 'Médecin ou patient introuvable.' });
    const doctorName = decrypt(doctor.fullName) || 'Médecin';
    const specialty = decrypt(doctor.specialty) || '—';
    const patientName = decrypt(patient.fullName) || 'Patient';
    const prescriptionDate = new Date();
    const dateLabel = prescriptionDate.toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
    const pdfBuffer = await buildPrescriptionPdfBuffer({ doctorName, specialty, city, dateLabel, patientName, medications, notes });
    let pdfUrl = ''; let pdfPublicId = '';
    if (isCloudinaryConfigured) {
      const up = await uploadPdfBufferToCloudinary(pdfBuffer);
      if (!up || !up.url) return res.status(500).json({ message: 'Échec du stockage du PDF.' });
      pdfUrl = up.url; pdfPublicId = up.publicId || '';
    } else {
      const uploadsRoot = path.join(__dirname, '..', 'uploads', 'prescriptions');
      await fs.mkdir(uploadsRoot, { recursive: true });
      const fname = `ordonnance_${crypto.randomBytes(12).toString('hex')}.pdf`;
      await fs.writeFile(path.join(uploadsRoot, fname), pdfBuffer);
      pdfUrl = `/uploads/prescriptions/${fname}`;
    }
    const prescriptionDoc = await Prescription.create({
      conversation: conversationId, patient: conv.patient, doctor: doctorId, pdfUrl, pdfPublicId: pdfPublicId || undefined, city,
      medications, notes, patientDisplayName: patientName, doctorDisplayName: doctorName, doctorSpecialty: specialty, prescriptionDate,
      source, consultationCallRoomId: consultationCallRoomId || undefined, status: 'sent',
    });
    const payload = { prescriptionId: prescriptionDoc._id.toString(), pdfUrl, pdfFilename: 'ordonnance.pdf', patientName, doctorName, specialty, city, source, sentAt: prescriptionDate.toISOString() };
    const msg = await Message.create({ conversation: conversationId, fromType: 'doctor', from: doctorId, type: 'prescription', content: 'Ordonnance médicale', payload });
    await Prescription.updateOne({ _id: prescriptionDoc._id }, { $set: { message: msg._id } });
    const prescriptionJson = prescriptionDoc.toObject(); prescriptionJson.message = msg._id;
    emitToConversation(conversationId, 'chat:new_activity', { conversationId: String(conversationId), messageId: String(msg._id), fromType: 'doctor', type: 'prescription' });
    await notifyPatientInboxNewMessage(conversationId, 'doctor', 'prescription', msg._id);
    await persistAutoHl7ForConversation({ conversationId, source: 'auto-prescription', fromType: 'doctor', content: 'Ordonnance médicale', payload });
    return res.status(201).json({ prescription: prescriptionJson, message: msg.toObject(), pdfUrl: cloudinaryInlineDeliveryUrl(pdfUrl) || pdfUrl });
  } catch (err) {
    console.error('POST /api/conversations/:conversationId/prescriptions', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function listPrescriptionsByConversation(req, res) {
  try {
    const conversationId = String(req.params.conversationId || '').trim();
    const pageRaw = Number.parseInt(String(req.query.page || '1'), 10);
    const limitRaw = Number.parseInt(String(req.query.limit || '20'), 10);
    const page = Number.isFinite(pageRaw) && pageRaw > 0 ? pageRaw : 1;
    const limit = Number.isFinite(limitRaw) ? Math.max(1, Math.min(100, limitRaw)) : 20;
    const skip = (page - 1) * limit;
    const query = { conversation: conversationId };
    const [total, list] = await Promise.all([
      Prescription.countDocuments(query),
      Prescription.find(query).sort({ createdAt: -1 }).skip(skip).limit(limit).lean(),
    ]);
    return res.json({ data: list.map((p) => prescriptionHistoryDto(p)), total, page, limit });
  } catch (err) {
    console.error('GET /api/prescriptions/conversation/:conversationId', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getPrescriptionById(req, res) {
  try {
    const id = String(req.prescriptionAccessId || '').trim();
    const pres = await Prescription.findById(id).lean();
    if (!pres) return res.status(404).json({ message: 'Ordonnance introuvable.' });
    return res.json({ data: prescriptionHistoryDto(pres) });
  } catch (err) {
    console.error('GET /api/prescriptions/:prescriptionId', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

module.exports = {
  requirePrescriptionParticipant,
  getPrescriptionPdfByMessage,
  getPrescriptionPdfById,
  listConversationPrescriptions,
  getLatestConversationPrescription,
  createPrescriptionForConversation,
  listPrescriptionsByConversation,
  getPrescriptionById,
};
