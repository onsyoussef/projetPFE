const express = require('express');
const router = express.Router();
const { verifyToken } = require('../middleware/authJwt');
const pushController = require('../controllers/pushController');

router.post('/push/register-device', verifyToken, pushController.registerDevice);
router.post('/push/unregister-device', verifyToken, pushController.unregisterDevice);

module.exports = router;
