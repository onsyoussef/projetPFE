const express = require('express');
const router = express.Router();

const { uploadChat } = require('../config/multerConfig');
const { requireHl7Auth } = require('../middleware/miscAuthz');
const hl7Controller = require('../controllers/hl7Controller');


router.post('/hl7/from-json', requireHl7Auth, hl7Controller.fromJson);

router.post('/hl7/from-json-with-files', requireHl7Auth, uploadChat.array('files', 10), hl7Controller.fromJsonWithFiles);

router.post('/hl7/parse', requireHl7Auth, hl7Controller.parseIncoming);

router.get('/hl7/messages', requireHl7Auth, hl7Controller.listMessages);

router.get('/hl7/messages/:id', requireHl7Auth, hl7Controller.getMessageById);


module.exports = router;
