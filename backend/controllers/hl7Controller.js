const fs = require('fs/promises');
const mongoose = require('mongoose');

const Hl7Message = require('../models/Hl7Message');
const {
  uploadChatFileToCloudinary,
  isConfigured: isCloudinaryConfigured,
} = require('../config/cloudinaryConfig');
const { parseHl7Message, validateAndNormalizeHl7, buildHl7FromJson } = require('../services/hl7Service');
const { fixUploadFilename, parseMaybeJson } = require('../services/utilsService');

async function fromJson(req, res) {
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
}

async function fromJsonWithFiles(req, res) {
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
      const up = await uploadChatFileToCloudinary(f.path, 'telemedecine/hl7', f.mimetype, f.originalname);
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

async function parseIncoming(req, res) {
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
}

async function listMessages(req, res) {
  try {
    const direction = req.query.direction ? String(req.query.direction) : null;
    const patientId = req.query.patientId ? String(req.query.patientId) : null;
    const limit = Math.min(parseInt(req.query.limit || '50', 10) || 50, 200);
    const query = {};
    if (direction && (direction === 'inbound' || direction === 'outbound')) query.direction = direction;
    if (patientId) query.patientExternalId = patientId;
    const items = await Hl7Message.find(query).sort({ createdAt: -1 }).limit(limit).lean();
    return res.json({ messages: items });
  } catch (err) {
    console.error('GET /hl7/messages', err);
    return res.status(500).json({ message: 'Erreur lecture HL7.' });
  }
}

async function getMessageById(req, res) {
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
}

module.exports = {
  fromJson,
  fromJsonWithFiles,
  parseIncoming,
  listMessages,
  getMessageById,
};
