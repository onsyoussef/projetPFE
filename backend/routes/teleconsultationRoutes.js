const express = require('express');
const router = express.Router();
const multer = require('multer');
const { uploadChat, CHAT_UPLOAD_MAX_BYTES } = require('../config/multerConfig');
const { verifyToken } = require('../middleware/authJwt');
const { requirePatientBodyPatientId, requirePatientConversationBody } = require('../middleware/patientAuthz');
const { requireDoctorQuery, requireDoctorBodyMatches } = require('../middleware/doctorAuthz');
const { requireConversationAccess } = require('../middleware/conversationAuthz');
const teleconsultationController = require('../controllers/teleconsultationController');

router.post('/teleconsultations/request', verifyToken, requirePatientConversationBody, teleconsultationController.createRequest);

router.post('/teleconsultations/form', verifyToken, requirePatientConversationBody, teleconsultationController.createForm);

router.get('/teleconsultations/request/:requestId/for-doctor', verifyToken, requireDoctorQuery, teleconsultationController.getRequestForDoctor);

// Deux chemins : `/demandes/...` (canonique) et `/api/demandes/...` (anciens clients Flutter).
router.put(
  ['/demandes/:id/accepter', '/api/demandes/:id/accepter'],
  verifyToken,
  requireDoctorBodyMatches,
  teleconsultationController.acceptDemande,
);

router.put(
  ['/demandes/:id/refuser', '/api/demandes/:id/refuser'],
  verifyToken,
  requireDoctorBodyMatches,
  teleconsultationController.rejectDemande,
);

router.patch('/teleconsultations/request/:requestId/decision', verifyToken, requireDoctorBodyMatches, teleconsultationController.patchRequestDecision);

router.get('/teleconsultations/form/:formId/for-doctor', verifyToken, requireDoctorQuery, teleconsultationController.getFormForDoctor);

router.patch('/teleconsultations/form/:formId/decision', verifyToken, requireDoctorBodyMatches, teleconsultationController.patchFormDecision);

router.patch('/teleconsultations/form/:formId/workflow', verifyToken, requireDoctorBodyMatches, teleconsultationController.patchFormWorkflow);

router.post(
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
  teleconsultationController.addFormAttachment,
);

router.post(
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
  teleconsultationController.uploadTeleconsultFile,
);


module.exports = router;
