const express = require('express');
const adminDoctorController = require('../controllers/adminDoctorController');
const adminAuthController = require('../controllers/adminAuthController');
const { requireAdminAuth } = require('../middleware/adminAuthz');
const { authLoginLimiter } = require('../middleware/authJwt');

const router = express.Router();

router.post('/admin/auth/login', authLoginLimiter, adminAuthController.loginAdmin);

router.get('/admin/dashboard/stats', requireAdminAuth, adminDoctorController.getDashboardStats);
router.get('/admin/doctors', requireAdminAuth, adminDoctorController.listDoctors);
router.get('/admin/doctors/:doctorId', requireAdminAuth, adminDoctorController.getDoctorById);
router.patch(
  '/admin/doctors/:doctorId/verification',
  requireAdminAuth,
  adminDoctorController.patchDoctorVerification,
);

module.exports = router;
