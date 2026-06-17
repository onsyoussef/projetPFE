const express = require('express');
const router = express.Router();

const { upload } = require('../config/multerConfig');
const { verifyToken } = require('../middleware/authJwt');
const { requirePatientParam, requirePatientQuery } = require('../middleware/patientAuthz');
const patientController = require('../controllers/patientController');

router.get(
  '/patient/conversations',
  verifyToken,
  requirePatientQuery,
  patientController.getPatientConversations,
);
router.get(
  '/patient/:patientId/scheduled-teleconsults',
  verifyToken,
  requirePatientParam,
  patientController.getPatientScheduledTeleconsults,
);
router.get(
  '/patient/:patientId/teleconsult-requests',
  verifyToken,
  requirePatientParam,
  patientController.getPatientTeleconsultRequests,
);
router.get('/patient/:patientId', verifyToken, requirePatientParam, patientController.getPatientProfile);
router.patch(
  '/patient/:patientId/name',
  verifyToken,
  requirePatientParam,
  patientController.patchPatientName,
);
router.patch(
  '/patient/:patientId/profile',
  verifyToken,
  requirePatientParam,
  patientController.patchPatientProfile,
);
router.post(
  '/patient/:patientId/change-password',
  verifyToken,
  requirePatientParam,
  patientController.changePatientPassword,
);
router.post(
  '/patient/:patientId/photo',
  verifyToken,
  requirePatientParam,
  upload.single('photo'),
  patientController.uploadPatientPhoto,
);

module.exports = router;
