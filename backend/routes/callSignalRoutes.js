const express = require('express');
const { verifyToken } = require('../middleware/authJwt');
const callSignalController = require('../controllers/callSignalController');

const router = express.Router();

/**
 * Refus depuis CallKit / UI native (app en arrière-plan, socket parfois absent).
 * body: { doctorUserId, roomId? } — roomId par défaut = callId d’URL.
 */
router.post('/api/patient/calls/:callId/decline', verifyToken, callSignalController.declinePatientCall);

/**
 * Timeout côté client (CallKit). Le serveur enregistre déjà « manqué » sur son propre timer ;
 * cette route sert de secours / télémétrie.
 */
router.post('/api/patient/calls/:callId/missed', verifyToken, callSignalController.markMissedPatientCall);

module.exports = router;
