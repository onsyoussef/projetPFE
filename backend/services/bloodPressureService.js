function computePam(systolic, diastolic, meanArterialPressure) {
  const pam = Number(meanArterialPressure);
  if (Number.isFinite(pam) && pam > 0) return Math.round(pam);
  const pas = Number(systolic);
  const pad = Number(diastolic);
  if (!Number.isFinite(pas) || !Number.isFinite(pad)) return null;
  return Math.round((pas + 2 * pad) / 3);
}

function evaluateBloodPressureAlert(systolic, diastolic) {
  const pas = Number(systolic);
  const pad = Number(diastolic);
  if (!Number.isFinite(pas) || !Number.isFinite(pad)) return null;

  if (pas < 90 || pad < 60) {
    return {
      type: 'hypotension',
      severity: 'high',
      message: `Hypotension détectée (${pas}/${pad} mmHg).`,
    };
  }
  if (pas >= 140 || pad >= 90) {
    return {
      type: 'hypertension',
      severity: 'high',
      message: `Hypertension détectée (${pas}/${pad} mmHg).`,
    };
  }
  return null;
}

function toMeasurementDto(doc) {
  if (!doc) return null;
  const pas = Number(doc.systolic);
  const pad = Number(doc.diastolic);
  return {
    id: String(doc._id),
    patientId: String(doc.patient),
    systolic: pas,
    diastolic: pad,
    meanArterialPressure: computePam(pas, pad, doc.meanArterialPressure),
    pam: computePam(pas, pad, doc.meanArterialPressure),
    heartRate: doc.heartRate == null ? null : Number(doc.heartRate),
    measuredAt: doc.measuredAt,
    source: doc.source || 'ble_esp32',
    deviceName: doc.deviceName || null,
  };
}

function toAlertDto(doc) {
  if (!doc) return null;
  return {
    id: String(doc._id),
    patientId: String(doc.patient),
    type: doc.type,
    severity: doc.severity || 'high',
    message: doc.message,
    systolic: doc.systolic == null ? null : Number(doc.systolic),
    diastolic: doc.diastolic == null ? null : Number(doc.diastolic),
    createdAt: doc.createdAt,
  };
}

module.exports = {
  computePam,
  evaluateBloodPressureAlert,
  toMeasurementDto,
  toAlertDto,
};
