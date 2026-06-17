const cloudinary = require('cloudinary').v2;

/** Logs détaillés Cloudinary : désactivés en production sauf si `CLOUDINARY_DEBUG=1|true|yes`. */
function isCloudinaryVerboseLoggingEnabled() {
  const v = String(process.env.CLOUDINARY_DEBUG || '').trim().toLowerCase();
  if (v === '1' || v === 'true' || v === 'yes') return true;
  return process.env.NODE_ENV !== 'production';
}

function cloudinaryVerboseLog(...args) {
  if (!isCloudinaryVerboseLoggingEnabled()) return;
  console.log(...args);
}

const isConfigured =
  !!process.env.CLOUDINARY_CLOUD_NAME &&
  !!process.env.CLOUDINARY_API_KEY &&
  !!process.env.CLOUDINARY_API_SECRET;

if (isConfigured) {
  cloudinary.config({
    cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
    api_key: process.env.CLOUDINARY_API_KEY,
    api_secret: process.env.CLOUDINARY_API_SECRET,
  });
}

cloudinaryVerboseLog(
  '[CLOUDINARY] config loaded:',
  JSON.stringify({
    cloudName: !!String(process.env.CLOUDINARY_CLOUD_NAME || '').trim(),
    apiKey: !!String(process.env.CLOUDINARY_API_KEY || '').trim(),
    apiSecret: !!String(process.env.CLOUDINARY_API_SECRET || '').trim(),
    isConfigured,
  })
);

/**
 * Choisit le resource_type Cloudinary selon le MIME (images, PDF, audio, vidéo).
 * L’audio est envoyé en `video` (convention Cloudinary pour fichiers audio).
 * @param {string} [mimetype]
 * @returns {'image'|'video'|'raw'|'auto'}
 */
function resourceTypeFromMimetype(mimetype = '') {
  const m = String(mimetype).toLowerCase();
  if (m.startsWith('image/')) return 'image';
  if (m.startsWith('audio/')) return 'video';
  if (m.startsWith('video/')) return 'video';
  if (m === 'application/pdf' || m.includes('pdf')) return 'raw';
  if (
    m.startsWith('text/') ||
    m.startsWith('application/msword') ||
    m.includes('wordprocessingml') ||
    m.includes('spreadsheet') ||
    m.includes('presentation')
  ) {
    return 'raw';
  }
  return 'auto';
}

function resourceTypeFromFilename(filename = '') {
  const f = String(filename || '').toLowerCase().trim();
  if (!f) return 'auto';
  const imageExt = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic', '.heif'];
  const videoExt = ['.mp4', '.mov', '.m4v', '.avi', '.mkv', '.webm'];
  const audioExt = ['.mp3', '.wav', '.m4a', '.aac', '.ogg'];
  const rawExt = ['.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.zip', '.rar', '.7z', '.txt', '.csv'];
  if (imageExt.some((ext) => f.endsWith(ext))) return 'image';
  if (videoExt.some((ext) => f.endsWith(ext))) return 'video';
  if (audioExt.some((ext) => f.endsWith(ext))) return 'video';
  if (rawExt.some((ext) => f.endsWith(ext))) return 'raw';
  return 'auto';
}

/**
 * @param {string} localFilePath
 * @param {string} folder dossier Cloudinary (ex. telemedecine/patients)
 * @param {'image'|'video'|'raw'|'auto'} resourceType
 * @returns {Promise<{ url: string, publicId: string } | null>}
 */
async function uploadFileToCloudinary(localFilePath, folder, resourceType = 'image') {
  if (!isConfigured) return null;
  const result = await cloudinary.uploader.upload(localFilePath, {
    folder,
    resource_type: resourceType,
  });
  return {
    url: result.secure_url,
    publicId: result.public_id,
  };
}

/**
 * Ajoute fl_inline à l’URL de livraison (PDF, Office, audio/vidéo) pour Content-Disposition: inline
 * et un meilleur affichage dans l’onglet du navigateur (évite le téléchargement forcé quand c’est possible).
 * @param {string} secureUrl
 */
function cloudinaryInlineDeliveryUrl(secureUrl) {
  if (!secureUrl || typeof secureUrl !== 'string') return secureUrl;
  const u = secureUrl.split('?')[0];
  if (!u.includes('res.cloudinary.com') || u.includes('fl_inline')) return secureUrl;
  /** Les livraisons `resource_type: raw` ne supportent pas `fl_inline` dans le chemin
   * (erreur Cloudinary : « Invalid flag in transformation: inline », HTTP 400).
   * Vidéo / image : inchangé.
   */
  if (u.includes('/raw/')) {
    return secureUrl;
  }
  if (u.includes('/video/upload/')) {
    return secureUrl.replace('/video/upload/', '/video/upload/fl_inline/');
  }
  return secureUrl;
}

function _basePublicIdAndFormat(publicId = '', fallbackFormat = 'pdf') {
  const raw = String(publicId || '').trim();
  if (!raw) return { basePublicId: '', format: fallbackFormat };
  const dotIndex = raw.lastIndexOf('.');
  if (dotIndex <= 0 || dotIndex === raw.length - 1) {
    return { basePublicId: raw, format: fallbackFormat };
  }
  return {
    basePublicId: raw.slice(0, dotIndex),
    format: raw.slice(dotIndex + 1),
  };
}

/** `upload` (défaut) vs `authenticated` — doit correspondre au type d’upload Cloudinary. */
function _rawDeliveryType(options = {}) {
  if (options.type === 'authenticated' || options.type === 'upload') return options.type;
  const e = String(process.env.CLOUDINARY_RAW_DELIVERY_TYPE || 'upload').trim().toLowerCase();
  return e === 'authenticated' ? 'authenticated' : 'upload';
}

function extractCloudinaryVersionFromUrl(url = '') {
  const raw = String(url || '').trim();
  if (!raw) return '';
  const match = raw.match(/\/v(\d+)\/.+$/);
  return match?.[1] || '';
}

/**
 * Extrait le segment public_id depuis une URL de livraison raw Cloudinary.
 * @param {string} secureUrl
 * @returns {string}
 */
function extractRawPublicIdFromSecureUrl(secureUrl = '') {
  const u = String(secureUrl || '').trim().split('?')[0];
  if (!u.includes('res.cloudinary.com') || !u.includes('/raw/')) return '';
  const normalized = u.replace(/\/raw\/upload\/fl_inline\//, '/raw/upload/');
  const m = normalized.match(/\/raw\/(?:upload|authenticated)\/(?:v\d+\/)?(.+)$/);
  if (!m || !m[1]) return '';
  try {
    return decodeURIComponent(m[1]);
  } catch {
    return m[1];
  }
}

/**
 * Résout public_id + version canoniques via l’API Admin (évite 404 si le public_id
 * en base ne correspond pas exactement à l’asset ou si la version URL est fausse).
 * @param {string} publicIdFromDb
 * @param {string} [secureUrlHint] secure_url / path HTTP enregistré
 * @returns {Promise<{ publicId: string, version: number } | null>}
 */
async function resolveRawAssetForSigning(publicIdFromDb, secureUrlHint = '') {
  if (!isConfigured) return null;
  /** @type {string[]} */
  const candidates = [];
  const push = (v) => {
    const s = String(v || '').trim();
    if (s && !candidates.includes(s)) candidates.push(s);
  };

  push(publicIdFromDb);
  push(String(publicIdFromDb || '').replace(/\.pdf$/i, ''));

  const hint = extractRawPublicIdFromSecureUrl(String(secureUrlHint || '').trim());
  push(hint);
  push(hint.replace(/\.pdf$/i, ''));

  for (const id of candidates) {
    if (!id) continue;
    try {
      const r = await cloudinary.api.resource(id, { resource_type: 'raw' });
      if (r?.public_id) {
        const ver = Number.parseInt(String(r.version ?? ''), 10);
        cloudinaryVerboseLog(
          '[CLOUDINARY] resolveRawAssetForSigning OK',
          JSON.stringify({
            tried: id,
            resolvedPublicId: r.public_id,
            version: Number.isFinite(ver) && ver > 0 ? ver : null,
          })
        );
        return {
          publicId: r.public_id,
          version: Number.isFinite(ver) && ver > 0 ? ver : 0,
        };
      }
    } catch (e) {
      const http = e?.http_code ?? e?.error?.http_code;
      cloudinaryVerboseLog(
        '[CLOUDINARY] resolveRawAssetForSigning miss',
        JSON.stringify({ id, http: http ?? null, message: String(e?.message || e).slice(0, 160) })
      );
    }
  }
  console.error('[CLOUDINARY] resolveRawAssetForSigning failed', JSON.stringify({ candidates }));
  return null;
}

/**
 * URL de téléchargement signée via l’API Cloudinary (`/v1_1/.../raw/download?...`).
 * La signature inclut `timestamp`, `expires_at`, `public_id`, etc. — adaptée aux comptes
 * « Restricted / signed URLs » ; le SDK **n’applique pas** `expires_at` sur les URL CDN (`res.cloudinary.com`).
 *
 * @param {string} basePublicId — public_id sans double extension (cf. `_basePublicIdAndFormat`)
 * @param {string} format — ex. `pdf`
 * @param {number} expiresAtUnix — expiration (secondes depuis epoch)
 * @param {object} [extra]
 * @param {'upload'|'authenticated'} [extra.type]
 */
function buildPrivateRawDownloadUrl(basePublicId, format, expiresAtUnix, extra = {}) {
  const deliveryType =
    extra.type === 'authenticated' || extra.type === 'upload'
      ? extra.type
      : _rawDeliveryType(extra);
  const fmt = String(format || '').trim();
  return cloudinary.utils.private_download_url(basePublicId, fmt || undefined, {
    resource_type: 'raw',
    type: deliveryType,
    expires_at: expiresAtUnix,
    attachment: !!extra.attachment,
  });
}

/**
 * Mode de livraison signé des assets raw (PDF).
 * Par défaut on privilégie `api_download` pour réduire les erreurs
 * `401 deny or ACL failure` observées sur certains comptes Cloudinary en CDN signé.
 */
function rawDeliveryModeFromEnv() {
  const mode = String(process.env.CLOUDINARY_RAW_DELIVERY_MODE || 'api_download')
    .trim()
    .toLowerCase();
  return mode === 'cdn' ? 'cdn' : 'api_download';
}

/**
 * URL signée pour fichiers raw (PDF).
 *
 * Modes (`options.deliveryMode` ou env `CLOUDINARY_RAW_DELIVERY_MODE`) :
 * - `cdn` (défaut) : URL CDN `res.cloudinary.com` avec segment `s--…--` dans le chemin.
 *   Important : désactive les analytics SDK (`_a=`) qui peuvent perturber certaines politiques CDN,
 *   et utilise une signature longue (SHA256). **`expires_at` n’est pas pris en charge par `cloudinary.url()` en v2.x**
 *   (paramètre ignoré par le SDK) ; l’« expiration » côté CDN repose sur la rotation des liens côté serveur.
 * - `api_download` : URL `api.cloudinary.com/.../raw/download?...` avec `expires_at` réel dans la signature API
 *   (recommandé si vous avez des 401 sur les URL CDN malgré une config valide).
 *
 * Type d’asset : `upload` par défaut (`uploader.upload`). Utilisez `authenticated` seulement si l’upload
 * a été fait avec `type: "authenticated"` (URL de type `/raw/authenticated/`).
 *
 * @param {'cdn'|'api_download'} [options.deliveryMode]
 * @param {'upload'|'authenticated'} [options.type]
 */
function buildSignedRawUrl(publicId, expiresInSeconds = 3600, options = {}) {
  if (!isConfigured || !publicId) return '';
  const nowSec = Math.floor(Date.now() / 1000);
  const expiresAt = nowSec + Math.max(60, Number(expiresInSeconds) || 3600);
  const rawPublicId = String(publicId || '').trim();
  const { basePublicId, format } = _basePublicIdAndFormat(rawPublicId, 'pdf');
  if (!basePublicId) return '';
  const versionRaw = String(options.version || '').trim();
  const versionNum = Number.parseInt(versionRaw, 10);
  const hasVersion = Number.isFinite(versionNum) && versionNum > 0;

  const modeRaw = options.deliveryMode || rawDeliveryModeFromEnv();
  const mode = modeRaw === 'api_download' ? 'api_download' : 'cdn';

  const deliveryType = _rawDeliveryType(options);
  const rawName = rawPublicId.split('/').pop() || '';
  const rawLooksWithExt = /\.[A-Za-z0-9]{2,8}$/.test(rawName);

  let signed;
  if (mode === 'api_download') {
    // Sur certains assets raw, le public_id réel inclut déjà `.pdf`.
    // Si on le retire, Cloudinary répond 404 "Resource not found".
    const publicIdForApiDownload = rawLooksWithExt ? rawPublicId : basePublicId;
    const formatForApiDownload = rawLooksWithExt ? '' : format;
    signed = buildPrivateRawDownloadUrl(publicIdForApiDownload, formatForApiDownload, expiresAt, {
      type: deliveryType,
      attachment: options.attachment,
    });
  } else {
    signed = cloudinary.url(basePublicId, {
      resource_type: 'raw',
      type: deliveryType,
      secure: true,
      sign_url: true,
      format,
      analytics: false,
      urlAnalytics: false,
      long_url_signature: true,
      ...(hasVersion ? { version: versionNum, force_version: true } : { force_version: false }),
    });
  }

  cloudinaryVerboseLog(
    '[CLOUDINARY] buildSignedRawUrl',
    JSON.stringify({
      publicId,
      basePublicId,
      format,
      deliveryMode: mode,
      assetType: deliveryType,
      version: hasVersion ? versionNum : null,
      expiresAtUnix: expiresAt,
      signedPreview: signed.slice(0, 180),
    })
  );
  return signed;
}

/**
 * URL miniature de la 1ère page d'un PDF Cloudinary.
 */
function buildPdfFirstPageThumbnailUrl(publicId) {
  if (!isConfigured || !publicId) return '';
  const { basePublicId } = _basePublicIdAndFormat(publicId, 'pdf');
  if (!basePublicId) return '';
  return cloudinary.url(basePublicId, {
    resource_type: 'image',
    type: 'upload',
    secure: true,
    sign_url: false,
    format: 'jpg',
    transformation: [
      { page: 1 },
      { width: 420, crop: 'fit', quality: 'auto', fetch_format: 'auto' },
    ],
  });
}

/**
 * Livraison image optimisée (compression / format auto / largeur max chat).
 * @param {string} secureUrl
 */
function chatImageDeliveryUrl(secureUrl) {
  if (!secureUrl || typeof secureUrl !== 'string') return secureUrl;
  const u = secureUrl.split('?')[0];
  if (!u.includes('res.cloudinary.com') || !u.includes('/image/upload/')) return secureUrl;
  if (u.includes('q_auto') || u.includes('f_auto')) return secureUrl;
  return secureUrl.replace('/image/upload/', '/image/upload/q_auto,f_auto,w_1200,c_limit/');
}

/**
 * Upload chat : `resource_type: "auto"` (détection Cloudinary), URL HTTPS optimisée selon le type.
 * @returns {Promise<null | { url: string, publicId: string, resourceType: string, format?: string, bytes?: number, width?: number, height?: number }>}
 */
async function uploadChatFileToCloudinary(localFilePath, folder, mimetype = '', originalName = '') {
  if (!isConfigured) return null;
  let chosenType = resourceTypeFromMimetype(mimetype);
  if (chosenType === 'auto') {
    chosenType = resourceTypeFromFilename(originalName);
  }
  const result = await cloudinary.uploader.upload(localFilePath, {
    folder,
    resource_type: chosenType === 'auto' ? 'auto' : chosenType,
  });
  let deliveryUrl = result.secure_url;
  const rt = result.resource_type;
  if (rt === 'image') {
    deliveryUrl = chatImageDeliveryUrl(result.secure_url);
  } else if (rt === 'raw' || rt === 'video') {
    deliveryUrl = cloudinaryInlineDeliveryUrl(result.secure_url);
  }
  return {
    url: deliveryUrl,
    publicId: result.public_id,
    resourceType: rt,
    format: result.format,
    bytes: result.bytes,
    width: result.width,
    height: result.height,
  };
}

/**
 * Tente d’extraire le public_id d’une URL secure Cloudinary (image), pour les anciens enregistrements sans publicId en base.
 * @param {string} secureUrl
 * @returns {string | null}
 */
function tryParseCloudinaryImagePublicId(secureUrl) {
  if (!secureUrl || typeof secureUrl !== 'string') return null;
  const u = secureUrl.split('?')[0];
  if (!u.includes('res.cloudinary.com')) return null;
  const m = u.match(/\/image\/upload\/(?:v\d+\/)?(.+)$/);
  if (!m) return null;
  let rest = m[1];
  const lastDot = rest.lastIndexOf('.');
  if (lastDot > 0) rest = rest.slice(0, lastDot);
  return rest || null;
}

/**
 * Upload PDF depuis un Buffer (ordonnances).
 * @param {Buffer} buffer
 * @param {string} [folder]
 * @returns {Promise<{ url: string, publicId: string } | null>}
 */
async function uploadPdfBufferToCloudinary(buffer, folder = 'telemedecine/prescriptions') {
  if (!isConfigured || !buffer || !Buffer.isBuffer(buffer)) return null;
  const { Readable } = require('stream');
  const result = await new Promise((resolve, reject) => {
    const uploadStream = cloudinary.uploader.upload_stream(
      {
        folder,
        resource_type: 'raw',
        format: 'pdf',
      },
      (error, uploadResult) => {
        if (error) reject(error);
        else resolve(uploadResult);
      }
    );
    Readable.from(buffer).pipe(uploadStream);
  });
  if (!result || !result.secure_url) return null;
  return {
    url: cloudinaryInlineDeliveryUrl(result.secure_url),
    publicId: result.public_id || '',
  };
}

/**
 * Supprime une ressource Cloudinary (ne fait pas échouer l’appel parent si l’asset est déjà absent).
 * @param {string} publicId
 * @param {'image'|'video'|'raw'} resourceType
 */
async function destroyByPublicId(publicId, resourceType = 'image') {
  if (!isConfigured || !publicId) return;
  const id = String(publicId).trim();
  if (!id) return;
  try {
    await cloudinary.uploader.destroy(id, { resource_type: resourceType });
  } catch (e) {
    if (isCloudinaryVerboseLoggingEnabled()) {
      console.warn('Cloudinary destroy (non bloquant):', e.message);
    }
  }
}

module.exports = {
  cloudinary,
  isConfigured,
  resourceTypeFromMimetype,
  uploadPdfBufferToCloudinary,
  uploadFileToCloudinary,
  uploadChatFileToCloudinary,
  chatImageDeliveryUrl,
  cloudinaryInlineDeliveryUrl,
  buildSignedRawUrl,
  rawDeliveryModeFromEnv,
  buildPrivateRawDownloadUrl,
  extractCloudinaryVersionFromUrl,
  extractRawPublicIdFromSecureUrl,
  resolveRawAssetForSigning,
  buildPdfFirstPageThumbnailUrl,
  tryParseCloudinaryImagePublicId,
  destroyByPublicId,
};
