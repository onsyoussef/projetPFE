const express = require('express');
const router = express.Router();

const { upload } = require('../config/multerConfig');
const { verifyToken } = require('../middleware/authJwt');
const {
  requireDoctorParam,
  requireDoctorQuery,
  requireDoctorBodyMatches,
  requireDoctorPublicRead,
} = require('../middleware/doctorAuthz');
const doctorController = require('../controllers/doctorController');


router.get('/doctors', doctorController.listDoctors);

router.get('/doctor/conversations', verifyToken, requireDoctorQuery, doctorController.getDoctorConversations);

router.get(
  '/doctor/:doctorId/scheduled-teleconsults',
  verifyToken,
  requireDoctorParam,
  doctorController.getDoctorScheduledTeleconsults,
);

router.get('/doctor/:doctorId/profile', verifyToken, requireDoctorParam, doctorController.getDoctorProfile);

router.patch('/doctor/:doctorId/name', verifyToken, requireDoctorParam, doctorController.patchDoctorName);

router.patch('/doctor/:doctorId/profile', verifyToken, requireDoctorParam, doctorController.patchDoctorProfile);

router.post(
  '/doctor/:doctorId/photo',
  verifyToken,
  requireDoctorParam,
  upload.single('photo'),
  doctorController.uploadDoctorPhoto,
);

router.post(
  '/doctor/:doctorId/change-password',
  verifyToken,
  requireDoctorParam,
  doctorController.changeDoctorPassword,
);

router.get('/doctor/:doctorId', verifyToken, requireDoctorPublicRead, doctorController.getDoctorPublic);

router.get('/doctor/:doctorId/settings', verifyToken, requireDoctorParam, doctorController.getDoctorSettings);

router.patch('/doctor/:doctorId/settings', verifyToken, requireDoctorParam, doctorController.patchDoctorSettings);

router.patch('/doctor/:doctorId/status', verifyToken, requireDoctorParam, doctorController.patchDoctorStatus);

router.get('/doctor/:doctorId/waiting-rooms', verifyToken, requireDoctorParam, doctorController.getDoctorWaitingRooms);

router.get('/doctor/:doctorId/teleconsult-stats', verifyToken, requireDoctorParam, doctorController.getDoctorTeleconsultStats);

router.get('/doctor/:doctorId/teleconsult-requests', verifyToken, requireDoctorParam, doctorController.getDoctorTeleconsultRequests);

router.get('/doctor/:doctorId/teleconsult-forms', verifyToken, requireDoctorParam, doctorController.getDoctorTeleconsultForms);


module.exports = router;
