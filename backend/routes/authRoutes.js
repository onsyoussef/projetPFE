const express = require('express');
const router = express.Router();

const { authLoginLimiter } = require('../middleware/authJwt');
const { upload } = require('../config/multerConfig');
const authController = require('../controllers/authController');

router.post('/auth/register', authLoginLimiter, authController.registerPatient);
router.post('/auth/login', authLoginLimiter, authController.loginPatient);
router.post(
  '/auth/doctor/register',
  authLoginLimiter,
  upload.single('diploma'),
  authController.registerDoctor,
);
router.post('/auth/doctor/login', authLoginLimiter, authController.loginDoctor);
router.post('/auth/request-reset-code', authLoginLimiter, authController.requestResetCode);
router.post('/auth/verify-reset-code', authController.verifyResetCode);
router.post('/auth/verify-reset-password', authController.verifyResetPassword);


module.exports = router;
