const mongoose = require('mongoose');
const AppNotification = require('../models/AppNotification');

function normalizeId(value) {
  const id = String(value || '').trim();
  if (!id || !mongoose.Types.ObjectId.isValid(id)) return '';
  return id;
}

function buildPatientDedupeKey(patientId, type, payload = {}) {
  const pid = normalizeId(patientId);
  if (!pid) return '';
  const t = String(type || 'notice');
  const p = payload && typeof payload === 'object' ? payload : {};
  if (p.requestId) return `patient:${pid}:${t}:req:${p.requestId}`;
  if (p.formId) return `patient:${pid}:${t}:form:${p.formId}`;
  if (p.scheduledAt && p.conversationId) {
    return `patient:${pid}:${t}:rdv:${p.conversationId}:${p.scheduledAt}`;
  }
  if (p.messageId) return `patient:${pid}:${t}:msg:${p.messageId}`;
  if (p.conversationId && p.status) {
    return `patient:${pid}:${t}:${p.conversationId}:${p.status}`;
  }
  if (p.conversationId) return `patient:${pid}:${t}:conv:${p.conversationId}`;
  return '';
}

function buildDoctorDedupeKey(doctorId, type, payload = {}) {
  const did = normalizeId(doctorId);
  if (!did) return '';
  const t = String(type || 'notice');
  const p = payload && typeof payload === 'object' ? payload : {};
  if (p.alertId) return `doctor:${did}:${t}:alert:${p.alertId}`;
  if (p.enteredAt && p.conversationId) {
    return `doctor:${did}:${t}:wr:${p.conversationId}:${p.enteredAt}`;
  }
  if (p.formId) return `doctor:${did}:${t}:form:${p.formId}`;
  if (p.requestId) return `doctor:${did}:${t}:req:${p.requestId}`;
  if (p.messageId) return `doctor:${did}:${t}:msg:${p.messageId}`;
  if (p.conversationId) return `doctor:${did}:${t}:conv:${p.conversationId}`;
  return '';
}

async function createAppNotification({
  recipientRole,
  recipientId,
  type,
  title,
  body,
  payload = {},
  dedupeKey,
}) {
  const rid = normalizeId(recipientId);
  if (!rid || !recipientRole) return null;

  const doc = {
    recipientRole,
    recipientId: rid,
    type: String(type || 'general'),
    title: String(title || ''),
    body: String(body || ''),
    payload: payload && typeof payload === 'object' ? payload : {},
  };

  const key = String(dedupeKey || '').trim();
  if (key) {
    doc.dedupeKey = key;
    return AppNotification.findOneAndUpdate(
      { dedupeKey: key },
      {
        $set: doc,
        $setOnInsert: { readAt: null },
      },
      { upsert: true, new: true, setDefaultsOnInsert: true },
    );
  }

  return AppNotification.create({ ...doc, readAt: null });
}

async function listNotifications({ recipientRole, recipientId, limit = 50 }) {
  const rid = normalizeId(recipientId);
  if (!rid) return [];
  const cap = Math.min(Math.max(parseInt(limit, 10) || 50, 1), 100);
  return AppNotification.find({ recipientRole, recipientId: rid })
    .sort({ createdAt: -1 })
    .limit(cap)
    .lean();
}

async function countUnread({ recipientRole, recipientId }) {
  const rid = normalizeId(recipientId);
  if (!rid) return 0;
  return AppNotification.countDocuments({
    recipientRole,
    recipientId: rid,
    readAt: null,
  });
}

async function markNotificationRead({ notificationId, recipientRole, recipientId }) {
  const nid = normalizeId(notificationId);
  const rid = normalizeId(recipientId);
  if (!nid || !rid) return null;
  return AppNotification.findOneAndUpdate(
    { _id: nid, recipientRole, recipientId: rid },
    { $set: { readAt: new Date() } },
    { new: true },
  ).lean();
}

async function markAllNotificationsRead({ recipientRole, recipientId }) {
  const rid = normalizeId(recipientId);
  if (!rid) return { modifiedCount: 0 };
  const result = await AppNotification.updateMany(
    { recipientRole, recipientId: rid, readAt: null },
    { $set: { readAt: new Date() } },
  );
  return { modifiedCount: result.modifiedCount || 0 };
}

module.exports = {
  createAppNotification,
  buildPatientDedupeKey,
  buildDoctorDedupeKey,
  listNotifications,
  countUnread,
  markNotificationRead,
  markAllNotificationsRead,
};
