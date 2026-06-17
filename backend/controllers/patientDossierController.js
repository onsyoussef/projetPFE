const crypto = require('crypto');
const fs = require('fs/promises');
const fsSync = require('fs');
const mongoose = require('mongoose');
const path = require('path');

const {
  uploadChatFileToCloudinary,
  isConfigured: isCloudinaryConfigured,
  cloudinaryInlineDeliveryUrl,
  destroyByPublicId,
} = require(path.join(__dirname, '..', 'config', 'cloudinaryConfig'));
const Doctor = require('../models/Doctor');
const Conversation = require('../models/Conversation');
const Message = require('../models/Message');
const Patient = require('../models/Patient');
const PatientMedicalDocument = require('../models/PatientMedicalDocument');
const { fixUploadFilename, validatePatientDossierUpload, dossierCloudinaryDestroyType } = require('../services/utilsService');
const { streamHttpsUrlToClient, guessContentTypeFromFilename } = require('../services/streamHttpsFile');
const { emitToConversation } = require('../services/realtimeGateway');
const { decrypt } = require('../services/cryptoService');

const uploadsDir = path.join(__dirname, '..', 'uploads');
const API_BASE = String(process.env.API_BASE_URL || 'http://localhost:3000').replace(/\/$/, '');

function dossierMedicalFileStreamPath(documentId, patientId) {
  return `/api/patient/dossier-medical/${encodeURIComponent(documentId)}/file?patientId=${encodeURIComponent(patientId)}`;
}

function dossierBrowserPublicUrl(pathStr) {
  if (pathStr == null || typeof pathStr !== 'string') return null;
  const p = pathStr.trim();
  if (p.startsWith('http://') || p.startsWith('https://')) return cloudinaryInlineDeliveryUrl(p);
  if (p.startsWith('/uploads/')) return `${API_BASE}${p}`;
  return null;
}

function resolveAuthenticatedPatientId(req, inputPatientId) {
  if (!req.auth || req.auth.role !== 'patient') return { error: 'forbidden' };
  const authPatientId = String(req.auth.sub || '').trim();
  if (!mongoose.Types.ObjectId.isValid(authPatientId)) return { error: 'invalid_auth_sub' };
  const raw = String(inputPatientId || '').trim();
  if (!raw) return { patientId: authPatientId };
  if (!mongoose.Types.ObjectId.isValid(raw)) return { patientId: authPatientId };
  if (raw !== authPatientId) return { error: 'forbidden' };
  return { patientId: authPatientId };
}

async function listPatientDossier(req, res) {
  try {
    const resolved = resolveAuthenticatedPatientId(req, req.query.patientId);
    if (resolved.error === 'forbidden') return res.status(403).json({ message: 'Accès réservé aux patients.' });
    if (resolved.error) return res.status(401).json({ message: 'Authentification requise.' });
    const patientId = resolved.patientId;

    const docs = await PatientMedicalDocument.find({ patient: patientId }).sort({ createdAt: -1 }).lean();
    const items = docs.map((d) => {
      const mimetype = String(d.mimetype || '');
      const fn = String(d.filename || '').toLowerCase();
      const isImage =
        mimetype.startsWith('image/') || fn.endsWith('.jpg') || fn.endsWith('.jpeg') || fn.endsWith('.png');
      return {
        id: String(d._id),
        category: d.category,
        title: d.title || '',
        documentDate: d.documentDate ? new Date(d.documentDate).toISOString() : null,
        filename: d.filename,
        mimetype,
        size: Number(d.size || 0),
        url: dossierMedicalFileStreamPath(String(d._id), patientId),
        browserUrl: dossierBrowserPublicUrl(d.path),
        type: isImage ? 'image' : 'file',
        createdAt: d.createdAt,
      };
    });
    return res.json({ items });
  } catch (err) {
    console.error('Erreur GET /api/patient/dossier-medical', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function streamPatientDossierFile(req, res) {
  try {
    const resolved = resolveAuthenticatedPatientId(req, req.query.patientId);
    if (resolved.error === 'forbidden') return res.status(403).json({ message: 'Accès réservé aux patients.' });
    if (resolved.error) return res.status(401).json({ message: 'Authentification requise.' });
    const patientId = resolved.patientId;
    const { documentId } = req.params;
    if (!mongoose.Types.ObjectId.isValid(documentId)) return res.status(400).json({ message: 'Paramètres invalides.' });

    const doc = await PatientMedicalDocument.findOne({ _id: documentId, patient: patientId }).lean();
    if (!doc) return res.status(404).json({ message: 'Document introuvable.' });

    const rawPath = doc.path;
    const filename = doc.filename || 'fichier';
    let mimetype = String(doc.mimetype || '').trim() || null;

    if (typeof rawPath === 'string' && rawPath.startsWith('http')) {
      streamHttpsUrlToClient(rawPath, res, { filename, mimetype: mimetype || undefined, disposition: 'inline' });
      return;
    }
    if (typeof rawPath === 'string' && rawPath.startsWith('/uploads/')) {
      const fp = path.join(uploadsDir, path.basename(rawPath));
      if (!mimetype) mimetype = guessContentTypeFromFilename(filename) || 'application/octet-stream';
      res.setHeader('Content-Type', mimetype);
      const dispName = String(filename).replace(/[\r\n"]/g, '_');
      res.setHeader('Content-Disposition', `inline; filename*=UTF-8''${encodeURIComponent(dispName)}`);
      res.setHeader('Cache-Control', 'private, max-age=300');
      const stream = fsSync.createReadStream(fp);
      stream.on('error', () => {
        if (!res.headersSent) res.status(404).json({ message: 'Fichier introuvable.' });
      });
      stream.pipe(res);
      return;
    }
    return res.status(404).json({ message: 'Fichier introuvable.' });
  } catch (err) {
    console.error('GET /api/patient/dossier-medical/:documentId/file', err);
    if (!res.headersSent) res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function createPatientDossier(req, res) {
  try {
    const resolved = resolveAuthenticatedPatientId(req, req.body && req.body.patientId);
    if (resolved.error === 'forbidden') return res.status(403).json({ message: 'Accès réservé aux patients.' });
    if (resolved.error) return res.status(401).json({ message: 'Authentification requise.' });
    const patientId = resolved.patientId;

    const category = String(req.body.category || '').trim().toLowerCase();
    const titleRaw = req.body.title != null ? String(req.body.title).trim() : '';
    const documentDateRaw = req.body.documentDate != null ? String(req.body.documentDate).trim() : '';
    if (!['analyses', 'ordonnances', 'fichiers', 'images'].includes(category)) {
      return res.status(400).json({ message: 'Catégorie invalide.' });
    }
    if (!req.file) return res.status(400).json({ message: 'Fichier requis.' });

    const patient = await Patient.findById(patientId).select('_id').lean();
    if (!patient) return res.status(404).json({ message: 'Patient introuvable.' });

    const check = validatePatientDossierUpload(category, req.file.mimetype, req.file.originalname);
    if (!check.ok) return res.status(400).json({ message: check.message || 'Fichier non accepté pour cette catégorie.' });

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
        req.file.originalname,
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
        url: dossierMedicalFileStreamPath(String(doc._id), patientId),
        browserUrl: dossierBrowserPublicUrl(doc.path),
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

async function deletePatientDossier(req, res) {
  try {
    const resolved = resolveAuthenticatedPatientId(req, req.query.patientId);
    if (resolved.error === 'forbidden') return res.status(403).json({ message: 'Accès réservé aux patients.' });
    if (resolved.error) return res.status(401).json({ message: 'Authentification requise.' });
    const patientId = resolved.patientId;
    const { documentId } = req.params;
    if (!mongoose.Types.ObjectId.isValid(documentId)) return res.status(400).json({ message: 'Paramètres invalides.' });

    const doc = await PatientMedicalDocument.findOne({ _id: documentId, patient: patientId }).lean();
    if (!doc) return res.status(404).json({ message: 'Document introuvable.' });

    const rtRaw = doc.cloudinaryResourceType && String(doc.cloudinaryResourceType).trim();
    const rt = rtRaw || dossierCloudinaryDestroyType(doc.mimetype);
    const destroyType = rt === 'image' ? 'image' : rt === 'video' ? 'video' : 'raw';
    if (doc.path && typeof doc.path === 'string' && doc.path.startsWith('/uploads/')) {
      const fp = path.join(uploadsDir, path.basename(doc.path));
      try {
        await fs.unlink(fp);
      } catch (_) {}
    } else if (doc.publicId) {
      await destroyByPublicId(doc.publicId, destroyType);
    }
    await PatientMedicalDocument.deleteOne({ _id: documentId });
    return res.status(204).send();
  } catch (err) {
    console.error('Erreur DELETE /api/patient/dossier-medical/:documentId', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function sharePatientDossier(req, res) {
  try {
    const resolved = resolveAuthenticatedPatientId(req, req.body && req.body.patientId);
    if (resolved.error === 'forbidden') return res.status(403).json({ message: 'Accès réservé aux patients.' });
    if (resolved.error) return res.status(401).json({ message: 'Authentification requise.' });
    const patientId = resolved.patientId;
    const doctorId = String(req.body.doctorId || '').trim();
    const itemIds = Array.isArray(req.body.itemIds) ? req.body.itemIds.map((x) => String(x)) : [];
    if (!mongoose.Types.ObjectId.isValid(doctorId) || itemIds.length === 0) {
      return res.status(400).json({ message: 'patientId, doctorId et itemIds sont requis.' });
    }

    const oids = itemIds.filter((id) => mongoose.Types.ObjectId.isValid(id));
    if (oids.length === 0) return res.status(400).json({ message: 'Aucun identifiant de document valide fourni.' });

    let conv = await Conversation.findOne({ patient: patientId, doctor: doctorId }).lean();
    if (!conv) {
      const created = await Conversation.create({ patient: patientId, doctor: doctorId });
      conv = created.toObject();
    }
    if (conv.sessionStatus === 'cloture') {
      return res.status(403).json({ message: 'La session de chat est clôturée. Impossible de partager des documents.' });
    }

    const docs = await PatientMedicalDocument.find({ _id: { $in: oids }, patient: patientId }).lean();
    if (!docs.length) return res.status(404).json({ message: 'Aucun document valide à partager.' });

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
}

module.exports = {
  listPatientDossier,
  streamPatientDossierFile,
  createPatientDossier,
  deletePatientDossier,
  sharePatientDossier,
};
