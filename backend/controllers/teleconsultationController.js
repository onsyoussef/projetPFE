const fs = require('fs/promises');
const mongoose = require('mongoose');

const { uploadChatFileToCloudinary, isConfigured: isCloudinaryConfigured } = require('../config/cloudinaryConfig');
const Conversation = require('../models/Conversation');
const Doctor = require('../models/Doctor');
const Message = require('../models/Message');
const TeleconsultationRequest = require('../models/TeleconsultationRequest');
const TeleconsultationForm = require('../models/TeleconsultationForm');
const { persistAutoHl7ForConversation } = require('../services/hl7Service');
const {
  fixUploadFilename,
  patientPhotoPathFromPopulated,
  normalizedTeleconsultFormStatus,
  canDoctorAccessTeleconsultForm,
  notifyDoctorInboxNewMessage,
  notifyPatientInboxNewMessage,
} = require('../services/utilsService');
const { emitToConversation, emitToUserId } = require('../services/realtimeGateway');
const { decrypt } = require('../services/cryptoService');
const {
  notifyDoctorTeleconsultRequest,
  notifyDoctorTeleconsultForm,
} = require('../services/doctorNotifyService');
const { notifyPatientPushAndSocket } = require('../services/patientNotifyService');
const { assertFreeMessagingAllowed } = require('../services/messagingGateService');

async function syncFormAttachmentsToChatMessage(formId) {
  const fid = String(formId || '').trim();
  if (!mongoose.Types.ObjectId.isValid(fid)) return;
  const form = await TeleconsultationForm.findById(fid)
    .select('conversation attachments motif symptomes')
    .lean();
  if (!form || !form.conversation) return;
  const attachments = Array.isArray(form.attachments) ? form.attachments : [];
  const convId = String(form.conversation);
  const updated = await Message.findOneAndUpdate(
    {
      conversation: form.conversation,
      type: 'form_teleconsult',
      'payload.formId': fid,
    },
    {
      $set: {
        'payload.attachments': attachments,
        'payload.motif': form.motif || '',
        'payload.symptomes': form.symptomes || '',
      },
    },
    { returnDocument: 'after' },
  ).lean();
  if (updated) {
    emitToConversation(convId, 'chat:new_activity', {
      conversationId: convId,
      messageId: String(updated._id),
      type: 'form_teleconsult',
    });
  }
}

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
  if (!conv || String(conv.doctor) !== String(did)) return { error: 403, message: 'Accès refusé.' };
  if (reqDoc.status !== 'pending') return { ok: true, status: reqDoc.status, alreadyProcessed: true };

  const motifTrim = rejectionMotifRaw != null && String(rejectionMotifRaw).trim() ? String(rejectionMotifRaw).trim() : '';
  reqDoc.status = decision === 'accept' ? 'accepted' : 'rejected';
  if (decision === 'reject') reqDoc.rejectionMotif = motifTrim || undefined;
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
    await notifyPatientPushAndSocket({
      patientId,
      socketEvent: 'patient:teleconsult_request_decision',
      title: payloadPatient.title,
      body: payloadPatient.body,
      pushType: 'teleconsult_request_decision',
      payload: payloadPatient,
    });
  }
  return { ok: true, status: reqDoc.status };
}

async function createRequest(req, res) {
  try {
    const { conversationId, motif, letterBody } = req.body;
    if (!conversationId) return res.status(400).json({ message: 'conversationId requis.' });
    const conv = await Conversation.findById(conversationId).lean();
    if (!conv) return res.status(404).json({ message: 'Conversation introuvable.' });
    const letterTrim = letterBody != null && String(letterBody).trim() ? String(letterBody).trim() : '';
    const reqDoc = await TeleconsultationRequest.create({
      conversation: conversationId,
      patient: conv.patient,
      doctor: conv.doctor,
      motif: motif || '',
      letterBody: letterTrim,
    });
    const msg = await Message.create({
      conversation: conversationId,
      fromType: 'system',
      type: 'request_teleconsult',
      content: motif ? String(motif).trim() : 'Demande de téléconsultation envoyée.',
      payload: { requestId: reqDoc._id.toString(), motif: motif || '', letterBody: letterTrim },
    });
    try {
      await notifyDoctorTeleconsultRequest({
        conversationId,
        requestId: reqDoc._id,
        messageId: msg._id,
        motif: motif || '',
      });
    } catch (notifyErr) {
      console.error('[NOTIFY] teleconsult request', notifyErr);
    }
    return res.status(201).json({ message: 'Demande envoyée.', id: reqDoc._id.toString() });
  } catch (err) {
    console.error('Erreur /teleconsultations/request', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function createForm(req, res) {
  try {
    const { conversationId, motif, symptomes, dateDerniereConsultation, traitements, allergies, notifyChat } = req.body;
    if (!conversationId) return res.status(400).json({ message: 'conversationId requis.' });
    const conv = await Conversation.findById(conversationId).lean();
    if (!conv) return res.status(404).json({ message: 'Conversation introuvable.' });
    const form = await TeleconsultationForm.create({
      doctor: conv.doctor,
      patient: conv.patient,
      conversation: conversationId,
      motif,
      symptomes,
      dateDerniereConsultation: dateDerniereConsultation ? new Date(dateDerniereConsultation) : undefined,
      traitements,
      allergies,
      attachments: [],
      status: 'pending',
      workflowStatus: 'pending',
    });
    const syncChat = notifyChat !== false && notifyChat !== 'false';
    let formMsg = null;
    if (syncChat) {
      formMsg = await Message.create({
        conversation: conversationId,
        fromType: 'system',
        type: 'form_teleconsult',
        content: 'Formulaire de téléconsultation envoyé.',
        payload: { formId: form._id.toString(), motif, symptomes, attachments: [] },
      });
    }
    try {
      await notifyDoctorTeleconsultForm({
        conversationId,
        formId: form._id,
        messageId: formMsg?._id,
        motif,
        symptomes,
      });
    } catch (notifyErr) {
      console.error('[NOTIFY] teleconsult form', notifyErr);
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
}

async function getRequestForDoctor(req, res) {
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
      if (!conv) conv = await Conversation.findById(r.conversation).populate('patient', 'fullName photoPath').lean();
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
}

async function acceptDemande(req, res) {
  try {
    const { id } = req.params;
    const doctorId = String(req.body.doctorId || '').trim();
    const result = await applyTeleconsultRequestDecision(id, doctorId, 'accept', null);
    if (result.error) return res.status(result.error).json({ message: result.message });
    return res.json({ ok: true, status: result.status, alreadyProcessed: !!result.alreadyProcessed });
  } catch (err) {
    console.error('Erreur PUT demandes/:id/accepter', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function rejectDemande(req, res) {
  try {
    const { id } = req.params;
    const doctorId = String(req.body.doctorId || '').trim();
    const motif = req.body.motif != null ? String(req.body.motif) : '';
    const result = await applyTeleconsultRequestDecision(id, doctorId, 'reject', motif);
    if (result.error) return res.status(result.error).json({ message: result.message });
    return res.json({ ok: true, status: result.status, alreadyProcessed: !!result.alreadyProcessed });
  } catch (err) {
    console.error('Erreur PUT demandes/:id/refuser', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function patchRequestDecision(req, res) {
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
      decision === 'reject' ? motif : null,
    );
    if (result.error) return res.status(result.error).json({ message: result.message });
    return res.json({ ok: true, status: result.status, alreadyProcessed: !!result.alreadyProcessed });
  } catch (err) {
    console.error('Erreur PATCH request decision', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getFormForDoctor(req, res) {
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
}

async function patchFormDecision(req, res) {
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
    if (effectiveStatus !== 'pending') return res.json({ ok: true, status: effectiveStatus, alreadyProcessed: true });
    form.status = decision === 'accept' ? 'accepted' : 'rejected';
    if (form.status === 'accepted') form.workflowStatus = 'pending';
    await form.save();
    const doctor = await Doctor.findById(doctorId).select('fullName photoPath').lean();
    const doctorName = decrypt(doctor?.fullName) || 'Médecin';
    const doctorPhotoPath = doctor?.photoPath || null;
    const patientId = form.patient ? String(form.patient) : '';
    const convIdStr = form.conversation ? String(form.conversation) : '';

    if (form.conversation) {
      await Message.create({
        conversation: form.conversation,
        fromType: 'system',
        type: 'text',
        content:
          decision === 'accept'
            ? 'Votre formulaire de téléconsultation a été accepté par le médecin.'
            : 'Votre formulaire de téléconsultation n’a pas été retenu par le médecin pour le moment.',
        payload: { kind: decision === 'accept' ? 'form_accepted' : 'form_rejected', formId: String(form._id) },
      });
      emitToConversation(convIdStr, 'chat:new_activity', { conversationId: convIdStr });
    }

    if (patientId) {
      const payloadPatient = {
        status: decision === 'accept' ? 'accepted' : 'rejected',
        title: decision === 'accept' ? 'Formulaire accepté ✅' : 'Formulaire refusé',
        body:
          decision === 'accept'
            ? `Dr. ${doctorName} a accepté votre formulaire de téléconsultation.`
            : `Dr. ${doctorName} n'a pas retenu votre formulaire pour le moment.`,
        conversationId: convIdStr,
        doctorId,
        doctorName,
        doctorPhotoPath,
        formId: String(form._id),
        openChat: decision === 'accept',
      };
      await notifyPatientPushAndSocket({
        patientId,
        socketEvent: 'patient:teleconsult_form_decision',
        title: payloadPatient.title,
        body: payloadPatient.body,
        pushType: 'teleconsult_form_decision',
        payload: payloadPatient,
      });
    }
    return res.json({ ok: true, status: form.status });
  } catch (err) {
    console.error('Erreur PATCH form decision', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function patchFormWorkflow(req, res) {
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
      if (current === status) return res.json({ ok: true, workflowStatus: status, idempotent: true });
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
        emitToConversation(replyConversationId, 'chat:new_activity', { conversationId: replyConversationId });
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
    return res.json({ ok: true, workflowStatus: form.workflowStatus, ...(replyConversationId ? { conversationId: replyConversationId } : {}) });
  } catch (err) {
    console.error('Erreur PATCH form workflow', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function addFormAttachment(req, res) {
  try {
    const { formId } = req.params;
    const patientId = String(req.body.patientId || '').trim();
    if (!mongoose.Types.ObjectId.isValid(formId) || !mongoose.Types.ObjectId.isValid(patientId)) {
      return res.status(400).json({ message: 'formId et patientId valides requis.' });
    }
    if (!req.file) return res.status(400).json({ message: 'Fichier requis.' });
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
    if (!formPatientId || formPatientId !== patientId) return res.status(403).json({ message: 'Accès refusé.' });
    const cloudUpload = await uploadChatFileToCloudinary(req.file.path, 'telemedecine/attachments', req.file.mimetype, req.file.originalname);
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
    await syncFormAttachmentsToChatMessage(formId);
    const last = form.attachments[form.attachments.length - 1];
    return res.status(201).json({ message: 'Fichier ajouté au formulaire.', attachment: last });
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

async function uploadTeleconsultFile(req, res) {
  try {
    const { conversationId, fromType, senderId } = req.body;
    if (!conversationId || !req.file) {
      return res.status(400).json({ message: 'conversationId et fichier requis.' });
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
      return res.status(403).json({ message: "Cette session est clôturée. Impossible d'envoyer un message." });
    }
    try {
      await assertFreeMessagingAllowed(conversationId, 'file');
    } catch (gateErr) {
      return res.status(gateErr.statusCode || 403).json({ message: gateErr.message });
    }
    const cloudUpload = await uploadChatFileToCloudinary(
      req.file.path,
      'telemedecine/attachments',
      req.file.mimetype,
      req.file.originalname,
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
    await notifyPatientInboxNewMessage(conversationId, senderType, 'file', uploadedMsg._id);
    await persistAutoHl7ForConversation({
      conversationId,
      source: 'auto-chat-file',
      fromType: senderType,
      content: '',
      payload: { mimetype: req.file.mimetype },
      files: [{ url: fileUrl, label: displayName, mimetype: req.file.mimetype }],
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

module.exports = {
  createRequest,
  createForm,
  getRequestForDoctor,
  acceptDemande,
  rejectDemande,
  patchRequestDecision,
  getFormForDoctor,
  patchFormDecision,
  patchFormWorkflow,
  addFormAttachment,
  uploadTeleconsultFile,
};
