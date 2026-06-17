const express = require('express');

const { verifyToken } = require('../middleware/authJwt');
const { requirePatientQuery, requirePatientBodyPatientId } = require('../middleware/patientAuthz');
const { requireDoctorQuery } = require('../middleware/doctorAuthz');
const bloodPressureController = require('../controllers/bloodPressureController');

const router = express.Router();

router.get(
  '/patient/blood-pressure/latest',
  verifyToken,
  requirePatientQuery,
  bloodPressureController.getLatestMeasurement,
);
router.get(
  '/patient/blood-pressure/history',
  verifyToken,
  requirePatientQuery,
  bloodPressureController.getHistory,
);
router.get(
  '/patient/blood-pressure/alerts',
  verifyToken,
  requirePatientQuery,
  bloodPressureController.getPatientAlerts,
);
router.post(
  '/patient/blood-pressure/measurements',
  verifyToken,
  requirePatientBodyPatientId,
  bloodPressureController.postMeasurement,
);

router.get(
  '/api/doctor/blood-pressure/patient-data',
  verifyToken,
  requireDoctorQuery,
  bloodPressureController.getPatientDataForDoctor,
);
router.get(
  '/api/doctor/blood-pressure/patients',
  verifyToken,
  requireDoctorQuery,
  bloodPressureController.getDoctorPatients,
);
router.get(
  '/api/doctor/blood-pressure/measurements',
  verifyToken,
  requireDoctorQuery,
  bloodPressureController.getDoctorMeasurements,
);
router.get(
  '/api/doctor/blood-pressure/alerts',
  verifyToken,
  requireDoctorQuery,
  bloodPressureController.getDoctorAlerts,
);

module.exports = router;
