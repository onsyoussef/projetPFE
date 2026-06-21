const mongoose = require('mongoose');

const Patient = require('../models/Patient');
const Conversation = require('../models/Conversation');
const { emitToUserId, emitToConversation } = require('../services/realtimeGateway');
const BloodPressureMeasurement = require('../models/BloodPressureMeasurement');
const BloodPressureAlert = require('../models/BloodPressureAlert');
const {
  computePam,
  evaluateBloodPressureAlert,
  toMeasurementDto,
  toAlertDto,
} = require('../services/bloodPressureService');
const { notifyDoctorBloodPressureAlert } = require('../services/doctorNotifyService');
const { decrypt } = require('../services/cryptoService');

function parsePositiveInt(value) {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return null;
  return Math.round(n);
}

function parseMeasuredAt(value) {
  if (!value) return new Date();
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? new Date() : d;
}

async function getPatientIdsForDoctor(doctorId) {
  const rows = await Conversation.find({ doctor: doctorId }).select('patient').lean();
  return [...new Set(rows.map((r) => String(r.patient)).filter(Boolean))];
}

async function assertDoctorPatientAccess(doctorId, patientId) {
  if (!mongoose.Types.ObjectId.isValid(doctorId) || !mongoose.Types.ObjectId.isValid(patientId)) {
    return null;
  }
  return Conversation.findOne({ doctor: doctorId, patient: patientId }).select('_id doctor patient').lean();
}

async function notifyDoctorsBloodPressure(patientId, measurementDto, alertDto) {
  try {
    const convs = await Conversation.find({ patient: patientId })
      .select('doctor _id')
      .lean();
    const payload = {
      patientId: String(patientId),
      measurement: measurementDto,
      alert: alertDto || null,
    };
    let patientName = 'Patient';
    const patient = await Patient.findById(patientId).select('fullName').lean();
    if (patient?.fullName) {
      try {
        patientName = decrypt(patient.fullName) || patientName;
      } catch (_) {
        // ignore
      }
    }
    const notifiedDoctors = new Set();
    for (const conv of convs) {
      const doctorId = String(conv.doctor);
      if (!notifiedDoctors.has(doctorId)) {
        emitToUserId(doctorId, 'patient:blood_pressure', payload);
        if (alertDto) {
          try {
            await notifyDoctorBloodPressureAlert({
              doctorId,
              patientId,
              patientName,
              conversationId: conv._id,
              alert: alertDto,
            });
          } catch (notifyErr) {
            console.error('[NOTIFY] blood pressure alert', notifyErr);
          }
        }
        notifiedDoctors.add(doctorId);
      }
      emitToConversation(String(conv._id), 'patient:blood_pressure', payload);
    }
  } catch (err) {
    console.error('notifyDoctorsBloodPressure', err);
  }
}

async function getLatestMeasurement(req, res) {
  try {
    const patientId = String(req.query.patientId || '').trim();
    const doc = await BloodPressureMeasurement.findOne({ patient: patientId })
      .sort({ measuredAt: -1, createdAt: -1 })
      .lean();
    if (!doc) {
      return res.status(404).json({ message: 'Aucune mesure enregistrée.' });
    }
    return res.json({ measurement: toMeasurementDto(doc) });
  } catch (err) {
    console.error('GET /patient/blood-pressure/latest', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getHistory(req, res) {
  try {
    const patientId = String(req.query.patientId || '').trim();
    const docs = await BloodPressureMeasurement.find({ patient: patientId })
      .sort({ measuredAt: -1, createdAt: -1 })
      .limit(500)
      .lean();
    return res.json({
      measurements: docs.map(toMeasurementDto),
    });
  } catch (err) {
    console.error('GET /patient/blood-pressure/history', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getPatientAlerts(req, res) {
  try {
    const patientId = String(req.query.patientId || '').trim();
    const docs = await BloodPressureAlert.find({ patient: patientId })
      .sort({ createdAt: -1 })
      .limit(200)
      .lean();
    return res.json({
      alerts: docs.map(toAlertDto),
    });
  } catch (err) {
    console.error('GET /patient/blood-pressure/alerts', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function postMeasurement(req, res) {
  try {
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const patientId = String(body.patientId || '').trim();
    const systolic = parsePositiveInt(body.systolic);
    const diastolic = parsePositiveInt(body.diastolic);

    if (!mongoose.Types.ObjectId.isValid(patientId)) {
      return res.status(400).json({ message: 'patientId invalide.' });
    }
    if (systolic == null || diastolic == null) {
      return res.status(400).json({ message: 'systolic et diastolic requis.' });
    }

    const patient = await Patient.findById(patientId).select('_id').lean();
    if (!patient) {
      return res.status(404).json({ message: 'Patient introuvable.' });
    }

    const measuredAt = parseMeasuredAt(body.measuredAt);
    const heartRate = body.heartRate == null ? null : parsePositiveInt(body.heartRate);
    const pam = computePam(
      systolic,
      diastolic,
      body.meanArterialPressure ?? body.pam ?? body.map,
    );

    const recentDuplicate = await BloodPressureMeasurement.findOne({
      patient: patientId,
      systolic,
      diastolic,
      measuredAt: { $gte: new Date(measuredAt.getTime() - 4000) },
    })
      .sort({ measuredAt: -1 })
      .lean();

    if (recentDuplicate) {
      const existingAlert = await BloodPressureAlert.findOne({
        measurement: recentDuplicate._id,
      }).lean();
      return res.status(200).json({
        measurement: toMeasurementDto(recentDuplicate),
        alert: existingAlert ? toAlertDto(existingAlert) : null,
        duplicate: true,
      });
    }

    const measurement = await BloodPressureMeasurement.create({
      patient: patientId,
      systolic,
      diastolic,
      meanArterialPressure: pam,
      heartRate,
      measuredAt,
      source: String(body.source || 'manual'),
      deviceName: String(body.deviceName || '').trim() || undefined,
    });

    const alertInfo = evaluateBloodPressureAlert(systolic, diastolic);
    let alert = null;
    if (alertInfo) {
      alert = await BloodPressureAlert.create({
        patient: patientId,
        measurement: measurement._id,
        type: alertInfo.type,
        severity: alertInfo.severity,
        message: alertInfo.message,
        systolic,
        diastolic,
      });
    }

    const measurementDto = toMeasurementDto(measurement);
    const alertDto = alert ? toAlertDto(alert) : null;
    await notifyDoctorsBloodPressure(patientId, measurementDto, alertDto);

    return res.status(201).json({
      measurement: measurementDto,
      alert: alertDto,
    });
  } catch (err) {
    console.error('POST /patient/blood-pressure/measurements', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getPatientDataForDoctor(req, res) {
  try {
    const doctorId = String(req.query.doctorId || '').trim();
    const patientId = String(req.query.patientId || '').trim();
    const access = await assertDoctorPatientAccess(doctorId, patientId);
    if (!access) {
      return res.status(403).json({ message: 'Accès non autorisé à ce patient.' });
    }

    const latest = await BloodPressureMeasurement.findOne({ patient: patientId })
      .sort({ measuredAt: -1, createdAt: -1 })
      .lean();
    const history = await BloodPressureMeasurement.find({ patient: patientId })
      .sort({ measuredAt: -1, createdAt: -1 })
      .limit(80)
      .lean();

    return res.json({
      measurement: latest ? toMeasurementDto(latest) : null,
      measurements: history.map(toMeasurementDto),
    });
  } catch (err) {
    console.error('GET /api/doctor/blood-pressure/patient-data', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getDoctorPatients(req, res) {
  try {
    const doctorId = String(req.query.doctorId || '').trim();
    const patientIds = await getPatientIdsForDoctor(doctorId);
    if (patientIds.length === 0) {
      return res.json({ patients: [] });
    }

    const measuredPatientIds = await BloodPressureMeasurement.distinct('patient', {
      patient: { $in: patientIds },
    });
    if (measuredPatientIds.length === 0) {
      return res.json({ patients: [] });
    }

    const patients = await Patient.find({ _id: { $in: measuredPatientIds } })
      .select('fullName')
      .lean();

    return res.json({
      patients: patients.map((p) => ({
        id: String(p._id),
        _id: String(p._id),
        name: p.fullName,
        fullName: p.fullName,
      })),
    });
  } catch (err) {
    console.error('GET /api/doctor/blood-pressure/patients', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getDoctorMeasurements(req, res) {
  try {
    const doctorId = String(req.query.doctorId || '').trim();
    const patientIds = await getPatientIdsForDoctor(doctorId);
    if (patientIds.length === 0) {
      return res.json({ measurements: [] });
    }

    const docs = await BloodPressureMeasurement.find({ patient: { $in: patientIds } })
      .sort({ measuredAt: -1, createdAt: -1 })
      .limit(1000)
      .lean();

    const patients = await Patient.find({ _id: { $in: patientIds } })
      .select('fullName')
      .lean();
    const nameById = new Map(patients.map((p) => [String(p._id), p.fullName]));

    return res.json({
      measurements: docs.map((doc) => ({
        ...toMeasurementDto(doc),
        patientName: nameById.get(String(doc.patient)) || 'Patient',
      })),
    });
  } catch (err) {
    console.error('GET /api/doctor/blood-pressure/measurements', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getDoctorAlerts(req, res) {
  try {
    const doctorId = String(req.query.doctorId || '').trim();
    const patientIds = await getPatientIdsForDoctor(doctorId);
    if (patientIds.length === 0) {
      return res.json({ alerts: [] });
    }

    const docs = await BloodPressureAlert.find({ patient: { $in: patientIds } })
      .sort({ createdAt: -1 })
      .limit(500)
      .lean();

    const patients = await Patient.find({ _id: { $in: patientIds } })
      .select('fullName')
      .lean();
    const nameById = new Map(patients.map((p) => [String(p._id), p.fullName]));

    return res.json({
      alerts: docs.map((doc) => ({
        ...toAlertDto(doc),
        patientName: nameById.get(String(doc.patient)) || 'Patient',
      })),
    });
  } catch (err) {
    console.error('GET /api/doctor/blood-pressure/alerts', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

module.exports = {
  getLatestMeasurement,
  getHistory,
  getPatientAlerts,
  postMeasurement,
  getPatientDataForDoctor,
  getDoctorPatients,
  getDoctorMeasurements,
  getDoctorAlerts,
};
