const multer = require('multer');
const path = require('path');

const uploadsDir = path.join(__dirname, '..', 'uploads');

// 🔹 Configuration upload fichiers (pièces jointes téléconsultation)
const upload = multer({
  dest: uploadsDir,
});

const CHAT_UPLOAD_MAX_BYTES = parseInt(
  process.env.CHAT_UPLOAD_MAX_BYTES || String(25 * 1024 * 1024),
  10
);

function chatUploadFileFilter(req, file, cb) {
  const m = String(file.mimetype || '').toLowerCase();
  const name = String(file.originalname || '').toLowerCase();
  const ok =
    m.startsWith('image/') ||
    m.startsWith('audio/') ||
    m.startsWith('video/') ||
    m === 'application/pdf' ||
    m.includes('pdf') ||
    m.includes('wordprocessingml') ||
    m.includes('msword') ||
    m.includes('spreadsheet') ||
    m.includes('presentation') ||
    m.includes('officedocument') ||
    m === 'application/zip' ||
    m === 'application/x-zip-compressed' ||
    m.startsWith('text/') ||
    m === 'application/octet-stream' ||
    name.endsWith('.m4a') ||
    name.endsWith('.webm') ||
    name.endsWith('.aac');
  if (ok) return cb(null, true);
  cb(new Error('Type de fichier non autorisé pour le chat.'));
}

const uploadChat = multer({
  dest: uploadsDir,
  limits: { fileSize: CHAT_UPLOAD_MAX_BYTES },
  fileFilter: chatUploadFileFilter,
});

module.exports = {
  upload,
  uploadChat,
  CHAT_UPLOAD_MAX_BYTES,
};
