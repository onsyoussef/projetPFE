const express = require('express');
const router = express.Router();

const { verifyToken } = require('../middleware/authJwt');
const { requireFormulaireUrgenceWrite } = require('../middleware/miscAuthz');
const surveillanceController = require('../controllers/surveillanceController');
const formulaireUrgenceController = require('../controllers/formulaireUrgenceController');

router.post(
  '/api/surveillance/activer',
  verifyToken,
  requireFormulaireUrgenceWrite,
  surveillanceController.activerSurveillance,
);

router.post(
  '/formulaire-urgence',
  verifyToken,
  requireFormulaireUrgenceWrite,
  formulaireUrgenceController.createFormulaireUrgence,
);

module.exports = router;
