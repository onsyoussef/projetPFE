const mongoose = require('mongoose');

const Doctor = require('../models/Doctor');
const Conversation = require('../models/Conversation');
const RendezVous = require('../models/RendezVous');

const {
  notifyPatientRdv,
  notifyAndMessagePatientRdvProgramme,
  notifyAndMessagePatientRdvAnnule,
  buildDoctorAgendaListFromRendezVous,
  doctorMinuteOccupied,
  effectiveRdvStatut,
  formatRdvJson,
  phraseRdvTeleconsultReprogramme,
} = require('../services/rendezvousService');
const { decrypt } = require('../services/cryptoService');

async function getMedecinRendezVous(req, res) {
  try {
    const medecinId = String(req.query.medecinId || '').trim();
    const dateFilter = String(req.query.date || '').trim();
    if (!mongoose.Types.ObjectId.isValid(medecinId)) {
      return res.status(400).json({ message: 'medecinId invalide.' });
    }
    const list = await buildDoctorAgendaListFromRendezVous(medecinId, { dateFilter });
    return res.json({ rendezVous: list });
  } catch (err) {
    console.error('Erreur GET /api/medecin/rendez-vous', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getPatientRendezVous(req, res) {
  try {
    const patientId = String(req.query.patientId || '').trim();
    if (!mongoose.Types.ObjectId.isValid(patientId)) {
      return res.status(400).json({ message: 'patientId invalide.' });
    }
    const now = Date.now();
    const list = await RendezVous.find({ patientId })
      .populate('medecinId', 'fullName photoPath')
      .populate('patientId', 'fullName photoPath')
      .sort({ startAt: -1 })
      .lean();
    const aVenir = [];
    const historique = [];
    for (const r of list) {
      const json = formatRdvJson(r, r.patientId, r.medecinId);
      if (r.statut === 'annule') {
        json.statutEffectif = 'annule';
        historique.push(json);
        continue;
      }
      const eff = effectiveRdvStatut(r);
      json.statutEffectif = eff;
      const end = new Date(r.startAt).getTime() + 30 * 60000;
      if (eff === 'termine' || end < now) historique.push(json);
      else aVenir.push(json);
    }
    aVenir.sort((a, b) => new Date(a.startAt) - new Date(b.startAt));
    historique.sort((a, b) => new Date(b.startAt) - new Date(a.startAt));
    return res.json({ aVenir, historique });
  } catch (err) {
    console.error('Erreur GET /api/rendezvous/patient', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getRendezVousMois(req, res) {
  try {
    const medecinId = String(req.query.medecinId || '').trim();
    const mois = String(req.query.mois || '').trim();
    if (!mongoose.Types.ObjectId.isValid(medecinId)) {
      return res.status(400).json({ message: 'medecinId invalide.' });
    }
    if (!/^\d{4}-\d{2}$/.test(mois)) {
      return res.status(400).json({ message: 'mois requis (YYYY-MM).' });
    }
    const docs = await RendezVous.find({
      medecinId,
      statut: { $ne: 'annule' },
      date: new RegExp(`^${mois}-`),
    })
      .populate('patientId', 'fullName photoPath')
      .sort({ date: 1, heure: 1 })
      .lean();
    const rendezvous = docs.map((d) => formatRdvJson(d, d.patientId, null));
    const dateSet = new Set();
    for (const d of docs) if (d.date) dateSet.add(d.date);
    return res.json({ rendezvous, datesOccupees: [...dateSet].sort() });
  } catch (err) {
    console.error('Erreur GET /api/rendezvous', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function getRendezVousDate(req, res) {
  try {
    const date = String(req.params.date || '').trim();
    const medecinId = String(req.query.medecinId || '').trim();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      return res.status(400).json({ message: 'date invalide (YYYY-MM-DD).' });
    }
    if (!mongoose.Types.ObjectId.isValid(medecinId)) {
      return res.status(400).json({ message: 'medecinId invalide.' });
    }
    const docs = await RendezVous.find({
      medecinId,
      date,
      statut: { $ne: 'annule' },
    })
      .populate('patientId', 'fullName photoPath')
      .sort({ heure: 1 })
      .lean();
    const rendezvous = docs.map((d) => formatRdvJson(d, d.patientId, null));
    const creneauxOccupes = rendezvous.map((r) => r.heure).filter(Boolean);
    return res.json({ rendezvous, creneauxOccupes });
  } catch (err) {
    console.error('Erreur GET /api/rendezvous/date', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function createRendezVous(req, res) {
  try {
    const medecinId = String(req.body.medecinId || '').trim();
    const patientId = String(req.body.patientId || '').trim();
    const formulaireId = req.body.formulaireId ? String(req.body.formulaireId).trim() : '';
    const date = String(req.body.date || '').trim();
    const heure = String(req.body.heure || '').trim();
    const type = String(req.body.type || 'teleconsultation').trim();
    const startAtRaw = req.body.startAt;

    if (!mongoose.Types.ObjectId.isValid(medecinId) || !mongoose.Types.ObjectId.isValid(patientId)) {
      return res.status(400).json({ message: 'medecinId ou patientId invalide.' });
    }
    if (!date || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      return res.status(400).json({ message: 'date requise (YYYY-MM-DD).' });
    }
    if (!heure || !/^\d{1,2}:\d{2}$/.test(heure)) {
      return res.status(400).json({ message: 'heure requise (HH:mm).' });
    }
    const conv = await Conversation.findOne({ doctor: medecinId, patient: patientId }).lean();
    if (!conv) return res.status(400).json({ message: 'Aucune conversation avec ce patient.' });

    if (!startAtRaw || typeof startAtRaw !== 'string') {
      return res.status(400).json({ message: 'startAt (ISO UTC) requis.' });
    }
    const start = new Date(startAtRaw);
    if (Number.isNaN(start.getTime())) return res.status(400).json({ message: 'startAt invalide.' });

    const hit = await doctorMinuteOccupied(medecinId, start.toISOString(), {});
    if (hit) {
      return res.status(409).json({
        message: 'Ce créneau est déjà réservé.',
        conflictWith: { patientNom: hit.patientNom, date: hit.date || date, heure: hit.heure || heure },
      });
    }

    const parts = String(heure).split(':');
    const heureNorm = parts.length === 2 ? `${parts[0].padStart(2, '0')}:${parts[1].padStart(2, '0')}` : heure;
    const rv = await RendezVous.create({
      medecinId,
      patientId,
      formulaireId: formulaireId && mongoose.Types.ObjectId.isValid(formulaireId) ? formulaireId : undefined,
      date,
      heure: heureNorm,
      startAt: start,
      type,
      statut: 'confirme',
    });

    const pop = await RendezVous.findById(rv._id)
      .populate('patientId', 'fullName photoPath')
      .populate('medecinId', 'fullName')
      .lean();
    await notifyAndMessagePatientRdvProgramme({
      conversationId: String(conv._id),
      patientId,
      rendezvousId: String(rv._id),
      dateYmd: date,
      heureHHmm: heureNorm,
      kind: 'programme',
    });
    return res.status(201).json({
      success: true,
      rendezvousId: String(rv._id),
      rendezvous: formatRdvJson(pop, pop.patientId, pop.medecinId),
    });
  } catch (err) {
    console.error('Erreur POST /api/rendezvous', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function updateRendezVous(req, res) {
  try {
    const id = String(req.params.id || '').trim();
    const medecinId = String(req.body.medecinId || '').trim();
    const date = String(req.body.date || '').trim();
    const heure = String(req.body.heure || '').trim();
    const startAtRaw = req.body.startAt;

    if (!mongoose.Types.ObjectId.isValid(id) || !mongoose.Types.ObjectId.isValid(medecinId)) {
      return res.status(400).json({ message: 'id ou medecinId invalide.' });
    }
    const existing = await RendezVous.findOne({ _id: id, medecinId }).lean();
    if (!existing || existing.statut === 'annule') {
      return res.status(404).json({ message: 'Rendez-vous introuvable.' });
    }
    if (!startAtRaw || typeof startAtRaw !== 'string') {
      return res.status(400).json({ message: 'startAt (ISO UTC) requis.' });
    }
    const start = new Date(startAtRaw);
    if (Number.isNaN(start.getTime())) return res.status(400).json({ message: 'startAt invalide.' });

    const hit = await doctorMinuteOccupied(medecinId, start.toISOString(), { excludeRdvId: id });
    if (hit) {
      return res.status(409).json({
        message: 'Ce créneau est déjà réservé.',
        conflictWith: { patientNom: hit.patientNom, date: hit.date || date, heure: hit.heure || heure },
      });
    }
    const d = date || existing.date;
    const h = heure || existing.heure;
    const updated = await RendezVous.findByIdAndUpdate(
      id,
      { $set: { startAt: start, date: d, heure: h } },
      { returnDocument: 'after' },
    )
      .populate('patientId', 'fullName photoPath')
      .populate('medecinId', 'fullName')
      .lean();

    const convPut = await Conversation.findOne({ doctor: medecinId, patient: existing.patientId }).select('_id').lean();
    if (convPut && convPut._id) {
      await notifyAndMessagePatientRdvProgramme({
        conversationId: String(convPut._id),
        patientId: String(existing.patientId),
        rendezvousId: String(id),
        dateYmd: d,
        heureHHmm: h,
        kind: 'reprogramme',
      });
    } else {
      await notifyPatientRdv(String(existing.patientId), 'Rendez-vous modifié', phraseRdvTeleconsultReprogramme(d, h), {
        rendezvousId: String(id),
        kind: 'reprogramme',
      });
    }
    return res.json({ success: true, rendezvous: formatRdvJson(updated, updated.patientId, updated.medecinId) });
  } catch (err) {
    console.error('Erreur PUT /api/rendezvous/:id', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

async function deleteRendezVous(req, res) {
  try {
    const id = String(req.params.id || '').trim();
    const medecinId = String(req.body.medecinId || req.query.medecinId || '').trim();
    const motif = String(req.body.motif || req.query.motif || '').trim();
    if (!mongoose.Types.ObjectId.isValid(id) || !mongoose.Types.ObjectId.isValid(medecinId)) {
      return res.status(400).json({ message: 'id ou medecinId invalide.' });
    }
    const existing = await RendezVous.findOne({ _id: id, medecinId }).lean();
    if (!existing || existing.statut === 'annule') {
      return res.status(404).json({ message: 'Rendez-vous introuvable.' });
    }

    await RendezVous.updateOne({ _id: id }, { $set: { statut: 'annule', motifAnnulation: motif } });
    const pop = await Doctor.findById(medecinId).lean();
    const drName = pop && pop.fullName ? `Dr. ${decrypt(pop.fullName)}` : 'Votre médecin';
    let body = `${drName} a annulé votre RDV du ${existing.date} à ${existing.heure}.`;
    if (motif) body += ` Motif : ${motif}`;

    const convDel = await Conversation.findOne({ doctor: medecinId, patient: existing.patientId }).select('_id').lean();
    if (convDel && convDel._id) {
      await notifyAndMessagePatientRdvAnnule({
        conversationId: String(convDel._id),
        patientId: String(existing.patientId),
        rendezvousId: String(id),
        dateYmd: existing.date,
        heureHHmm: existing.heure,
        motif,
        content: body,
      });
    } else {
      await notifyPatientRdv(String(existing.patientId), 'Rendez-vous annulé', body, {
        rendezvousId: String(id),
        kind: 'annule',
      });
    }
    return res.json({ success: true });
  } catch (err) {
    console.error('Erreur DELETE /api/rendezvous/:id', err);
    return res.status(500).json({ message: 'Erreur serveur.' });
  }
}

module.exports = {
  getMedecinRendezVous,
  getPatientRendezVous,
  getRendezVousMois,
  getRendezVousDate,
  createRendezVous,
  updateRendezVous,
  deleteRendezVous,
};
