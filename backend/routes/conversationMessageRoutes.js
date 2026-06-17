const express = require('express');
const router = express.Router();

const { verifyToken } = require('../middleware/authJwt');
const { requireConversationAccess, requireConversationCreate } = require('../middleware/conversationAuthz');
const { requireDoctorBodyMatches } = require('../middleware/doctorAuthz');
const conversationMessageController = require('../controllers/conversationMessageController');

router.post('/conversations', verifyToken, requireConversationCreate, conversationMessageController.createConversation);

router.get('/messages', verifyToken, requireConversationAccess, conversationMessageController.getMessages);

router.get('/messages/after', verifyToken, requireConversationAccess, conversationMessageController.getMessagesAfter);

router.get('/messages/:messageId/file', verifyToken, requireConversationAccess, conversationMessageController.getMessageFile);

router.post('/messages', verifyToken, requireConversationAccess, conversationMessageController.postMessage);

router.post('/messages/mark-read', verifyToken, requireConversationAccess, conversationMessageController.markMessagesRead);

router.put('/api/conversations/:conversationId/cloturer', verifyToken, requireDoctorBodyMatches, conversationMessageController.closeConversation);

router.put('/api/conversations/:conversationId/rouvrir', verifyToken, requireDoctorBodyMatches, conversationMessageController.reopenConversation);

router.patch('/messages/:messageId', verifyToken, requireConversationAccess, conversationMessageController.patchMessage);

router.delete('/messages/:messageId', verifyToken, requireConversationAccess, conversationMessageController.deleteMessage);


module.exports = router;
