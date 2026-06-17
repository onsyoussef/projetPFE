const express = require('express');
const router = express.Router();
const { verifyToken } = require('../middleware/authJwt');
const webrtcController = require('../controllers/webrtcController');


router.get('/webrtc/ice-config', verifyToken, webrtcController.getIceConfig);


module.exports = router;
