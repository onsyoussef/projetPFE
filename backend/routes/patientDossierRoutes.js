const express = require('express');
const router = express.Router();
const multer = require('multer');
const { uploadChat, CHAT_UPLOAD_MAX_BYTES } = require('../config/multerConfig');
const { verifyToken } = require('../middleware/authJwt');
const patientDossierController = require('../controllers/patientDossierController');

router.get('/api/patient/dossier-medical', verifyToken, patientDossierController.listPatientDossier);
router.get(
  '/api/patient/dossier-medical/:documentId/file',
  verifyToken,
  patientDossierController.streamPatientDossierFile,
);

router.post(
  '/api/patient/dossier-medical',
  verifyToken,
  (req, res, next) => {
    uploadChat.single('file')(req, res, (err) => {
      if (err) {
        if (err instanceof multer.MulterError && err.code === 'LIMIT_FILE_SIZE') {
          return res.status(400).json({
            message: `Fichier trop volumineux (max ${Math.round(CHAT_UPLOAD_MAX_BYTES / (1024 * 1024))} Mo).`,
          });
        }
        const msg =
          typeof err.message === 'string' && err.message.length ? err.message : 'Upload refusé.';
        return res.status(400).json({ message: msg });
      }
      next();
    });
  },
  patientDossierController.createPatientDossier,
);

router.delete('/api/patient/dossier-medical/:documentId', verifyToken, patientDossierController.deletePatientDossier);
router.post('/api/patient/dossier-medical/share', verifyToken, patientDossierController.sharePatientDossier);


module.exports = router;
