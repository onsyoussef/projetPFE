const {
  listNotifications,
  countUnread,
  markNotificationRead,
  markAllNotificationsRead,
} = require('../services/appNotificationService');

function serializeNotification(doc) {
  if (!doc) return null;
  return {
    id: String(doc._id),
    type: doc.type || '',
    title: doc.title || '',
    body: doc.body || '',
    read: !!doc.readAt,
    createdAt: doc.createdAt,
    payload: doc.payload && typeof doc.payload === 'object' ? doc.payload : {},
  };
}

async function getPatientNotifications(req, res) {
  try {
    const { patientId } = req.params;
    const limit = Math.min(parseInt(req.query.limit, 10) || 50, 100);
    const [items, unreadCount] = await Promise.all([
      listNotifications({ recipientRole: 'patient', recipientId: patientId, limit }),
      countUnread({ recipientRole: 'patient', recipientId: patientId }),
    ]);
    return res.json({
      notifications: items.map(serializeNotification),
      unreadCount,
    });
  } catch (err) {
    console.error('GET /patient/:patientId/notifications', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function markPatientNotificationRead(req, res) {
  try {
    const { patientId, notificationId } = req.params;
    const updated = await markNotificationRead({
      notificationId,
      recipientRole: 'patient',
      recipientId: patientId,
    });
    if (!updated) return res.status(404).json({ message: 'Notification introuvable.' });
    return res.json({ ok: true, notification: serializeNotification(updated) });
  } catch (err) {
    console.error('PATCH patient notification read', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function markAllPatientNotificationsRead(req, res) {
  try {
    const { patientId } = req.params;
    const result = await markAllNotificationsRead({
      recipientRole: 'patient',
      recipientId: patientId,
    });
    return res.json({ ok: true, ...result });
  } catch (err) {
    console.error('PATCH patient notifications read-all', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getDoctorNotifications(req, res) {
  try {
    const { doctorId } = req.params;
    const limit = Math.min(parseInt(req.query.limit, 10) || 50, 100);
    const [items, unreadCount] = await Promise.all([
      listNotifications({ recipientRole: 'doctor', recipientId: doctorId, limit }),
      countUnread({ recipientRole: 'doctor', recipientId: doctorId }),
    ]);
    return res.json({
      notifications: items.map(serializeNotification),
      unreadCount,
    });
  } catch (err) {
    console.error('GET /doctor/:doctorId/notifications', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function markDoctorNotificationRead(req, res) {
  try {
    const { doctorId, notificationId } = req.params;
    const updated = await markNotificationRead({
      notificationId,
      recipientRole: 'doctor',
      recipientId: doctorId,
    });
    if (!updated) return res.status(404).json({ message: 'Notification introuvable.' });
    return res.json({ ok: true, notification: serializeNotification(updated) });
  } catch (err) {
    console.error('PATCH doctor notification read', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function markAllDoctorNotificationsRead(req, res) {
  try {
    const { doctorId } = req.params;
    const result = await markAllNotificationsRead({
      recipientRole: 'doctor',
      recipientId: doctorId,
    });
    return res.json({ ok: true, ...result });
  } catch (err) {
    console.error('PATCH doctor notifications read-all', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

module.exports = {
  getPatientNotifications,
  markPatientNotificationRead,
  markAllPatientNotificationsRead,
  getDoctorNotifications,
  markDoctorNotificationRead,
  markAllDoctorNotificationsRead,
};
