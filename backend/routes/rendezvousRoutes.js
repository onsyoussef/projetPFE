const express = require('express');
const router = express.Router();

const { verifyToken } = require('../middleware/authJwt');
const {
  requireRdvPostDoctor,
  requireRdvPatientGet,
  requireRdvDoctorGetQuery,
  requireRdvMutateDoctor,
} = require('../middleware/rendezvousAuthz');
const rendezvousController = require('../controllers/rendezvousController');


router.get('/api/medecin/rendez-vous', verifyToken, requireRdvDoctorGetQuery, rendezvousController.getMedecinRendezVous);

router.get('/api/rendezvous/patient', verifyToken, requireRdvPatientGet, rendezvousController.getPatientRendezVous);

router.get('/api/rendezvous', verifyToken, requireRdvDoctorGetQuery, rendezvousController.getRendezVousMois);

router.get('/api/rendezvous/date/:date', verifyToken, requireRdvDoctorGetQuery, rendezvousController.getRendezVousDate);

router.post('/api/rendezvous', verifyToken, requireRdvPostDoctor, rendezvousController.createRendezVous);

router.put('/api/rendezvous/:id', verifyToken, requireRdvMutateDoctor, rendezvousController.updateRendezVous);

router.delete('/api/rendezvous/:id', verifyToken, requireRdvMutateDoctor, rendezvousController.deleteRendezVous);


module.exports = router;
