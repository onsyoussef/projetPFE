const express = require('express');
const router = express.Router();

const { verifyToken } = require('../middleware/authJwt');
const { requirePatientParam } = require('../middleware/patientAuthz');
const { requireDoctorParam } = require('../middleware/doctorAuthz');
const notificationController = require('../controllers/notificationController');

router.get(
  '/patient/:patientId/notifications',
  verifyToken,
  requirePatientParam,
  notificationController.getPatientNotifications,
);
router.patch(
  '/patient/:patientId/notifications/read-all',
  verifyToken,
  requirePatientParam,
  notificationController.markAllPatientNotificationsRead,
);
router.patch(
  '/patient/:patientId/notifications/:notificationId/read',
  verifyToken,
  requirePatientParam,
  notificationController.markPatientNotificationRead,
);

router.get(
  '/doctor/:doctorId/notifications',
  verifyToken,
  requireDoctorParam,
  notificationController.getDoctorNotifications,
);
router.patch(
  '/doctor/:doctorId/notifications/read-all',
  verifyToken,
  requireDoctorParam,
  notificationController.markAllDoctorNotificationsRead,
);
router.patch(
  '/doctor/:doctorId/notifications/:notificationId/read',
  verifyToken,
  requireDoctorParam,
  notificationController.markDoctorNotificationRead,
);

module.exports = router;
