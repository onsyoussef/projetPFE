const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');

const { verifyToken } = require('../middleware/authJwt');
const { requireConversationParamParticipant } = require('../middleware/conversationAuthz');
const prescriptionController = require('../controllers/prescriptionController');

router.get(
  '/api/conversations/:conversationId/prescriptions/by-message/:messageId/pdf',
  verifyToken,
  requireConversationParamParticipant,
  prescriptionController.getPrescriptionPdfByMessage,
);

router.get(
  '/api/conversations/:conversationId/prescriptions/:prescriptionId/pdf',
  verifyToken,
  requireConversationParamParticipant,
  prescriptionController.getPrescriptionPdfById,
);

router.get(
  '/api/conversations/:conversationId/prescriptions',
  verifyToken,
  requireConversationParamParticipant,
  prescriptionController.listConversationPrescriptions,
);

router.get(
  '/api/conversations/:conversationId/prescriptions/latest',
  verifyToken,
  requireConversationParamParticipant,
  prescriptionController.getLatestConversationPrescription,
);
router.post(
  '/api/conversations/:conversationId/prescriptions',
  verifyToken,
  requireConversationParamParticipant,
  prescriptionController.createPrescriptionForConversation
);

router.post(
  '/api/prescriptions',
  verifyToken,
  (req, res, next) => {
    const cid = String((req.body && req.body.conversationId) || '').trim();
    if (!mongoose.Types.ObjectId.isValid(cid)) {
      return res.status(400).json({ message: 'conversationId requis ou invalide dans le corps.' });
    }
    req.params = { ...req.params, conversationId: cid };
    return requireConversationParamParticipant(req, res, next);
  },
  prescriptionController.createPrescriptionForConversation
);

router.get(
  '/api/prescriptions/conversation/:conversationId',
  verifyToken,
  requireConversationParamParticipant,
  prescriptionController.listPrescriptionsByConversation
);

router.get(
  '/api/prescriptions/:prescriptionId',
  verifyToken,
  prescriptionController.requirePrescriptionParticipant,
  prescriptionController.getPrescriptionById
);

module.exports = router;
