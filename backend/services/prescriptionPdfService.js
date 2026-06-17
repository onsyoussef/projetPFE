'use strict';

const PDFDocument = require('pdfkit');

function sanitizeLine(s, max = 500) {
  const t = String(s || '')
    .replace(/\s+/g, ' ')
    .trim();
  if (t.length <= max) return t;
  return `${t.slice(0, Math.max(0, max - 1))}…`;
}

/** Évite « 3 fois par jours » (usage courant mais incorrect). */
function fixFrenchFrequencyPhrasing(s) {
  let t = String(s || '');
  t = t.replace(/\bfois\s+par\s+jours\b/gi, 'fois par jour');
  return t;
}

/** Première lettre en majuscule, reste cohérent (ex. panadol → Panadol). */
function prettifyMedicationName(raw) {
  const s = sanitizeLine(raw, 140);
  if (!s) return s;
  const lower = s.toLocaleLowerCase('fr-FR');
  return lower.charAt(0).toLocaleUpperCase('fr-FR') + lower.slice(1);
}

/**
 * @param {object} data
 * @param {string} data.doctorName
 * @param {string} data.specialty
 * @param {string} data.city
 * @param {string} data.dateLabel
 * @param {string} data.patientName
 * @param {Array<{name:string,posologie?:string,duree?:string,instructions?:string}>} data.medications
 * @param {string} [data.notes]
 * @returns {Promise<Buffer>}
 */
async function buildPrescriptionPdfBuffer(data) {
  const doc = new PDFDocument({ margin: 42, size: 'A4' });
  const chunks = [];
  doc.on('data', (c) => chunks.push(c));
  const done = new Promise((resolve, reject) => {
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);
  });

  const {
    doctorName,
    specialty,
    city,
    dateLabel,
    patientName,
    medications,
    notes,
  } = data;

  const pageLeft = doc.page.margins.left;
  const pageRight = doc.page.width - doc.page.margins.right;
  const fullWidth = pageRight - pageLeft;

  /** Aligné charte Flutter `HeadsAppColors` (bleu institutionnel + surfaces). */
  const primary = '#265AA6';
  const highlight = '#EEF6FF';
  const border = '#D8E5F5';
  const textDark = '#1A2740';
  const textMuted = '#5F6F86';

  // Bandeau titre
  doc
    .roundedRect(pageLeft, 36, fullWidth, 74, 12)
    .fillAndStroke(highlight, border);
  doc
    .fillColor(textDark)
    .font('Helvetica-Bold')
    .fontSize(22)
    .text('Ordonnance médicale', pageLeft + 16, 52, { width: fullWidth - 32 });
  doc
    .fillColor(textMuted)
    .font('Helvetica')
    .fontSize(11)
    .text('Document médical professionnel', pageLeft + 16, 80, { width: fullWidth - 32 });
  doc
    .fillColor(primary)
    .font('Helvetica-Bold')
    .fontSize(11)
    .text(`${city || '—'} · ${dateLabel || ''}`, pageLeft + 16, 96, {
      width: fullWidth - 32,
      align: 'right',
    });

  let y = 128;
  const sectionGap = 12;

  function sectionTitle(title) {
    doc.fillColor(primary).font('Helvetica-Bold').fontSize(12).text(title, pageLeft + 2, y);
    y += 18;
  }

  function boxed(draw, boxHeight) {
    doc.roundedRect(pageLeft, y, fullWidth, boxHeight, 10).fillAndStroke('#FFFFFF', border);
    draw(y + 12);
    y += boxHeight + sectionGap;
  }

  // Bloc medecin
  sectionTitle('Informations du médecin');
  boxed((contentY) => {
    doc.fillColor(textDark).font('Helvetica-Bold').fontSize(13).text(doctorName || 'Médecin', pageLeft + 12, contentY);
    doc.fillColor(textMuted).font('Helvetica').fontSize(10).text(specialty || 'Spécialité non renseignée', pageLeft + 12, contentY + 18);
    doc.text(`Ville: ${city || '—'}`, pageLeft + 12, contentY + 35);
  }, 64);

  // Bloc patient
  sectionTitle('Informations du patient');
  boxed((contentY) => {
    doc.fillColor(textMuted).font('Helvetica').fontSize(9).text('Patient', pageLeft + 12, contentY);
    doc.fillColor(textDark).font('Helvetica-Bold').fontSize(12).text(patientName || '—', pageLeft + 12, contentY + 14);
  }, 48);

  // Prescription (table)
  sectionTitle('Prescription');
  const tableTop = y;
  const innerLeft = pageLeft + 12;
  const innerWidth = fullWidth - 24;
  const wMed = innerWidth * 0.34;
  const wPosologie = innerWidth * 0.18;
  const wInstructions = innerWidth * 0.33;
  const wDuree = innerWidth * 0.15;
  const colMed = innerLeft;
  const colPosologie = colMed + wMed;
  const colInstructions = colPosologie + wPosologie;
  const colDuree = colInstructions + wInstructions;
  const headerBandH = 32;
  doc.roundedRect(pageLeft, tableTop, fullWidth, headerBandH, 8).fillAndStroke('#EFF6FF', border);
  doc.fillColor(primary).font('Helvetica-Bold').fontSize(9);
  const headPad = 6;
  doc.text('Médicament', colMed, tableTop + 10, { width: wMed - headPad });
  doc.text('Posologie', colPosologie, tableTop + 10, { width: wPosologie - headPad });
  doc.text('Instructions', colInstructions, tableTop + 10, { width: wInstructions - headPad });
  doc.text('Durée', colDuree, tableTop + 10, { width: wDuree - headPad });

  y = tableTop + headerBandH + 4;

  let idx = 1;
  for (const med of medications || []) {
    const name = prettifyMedicationName(med.name);
    if (!name) continue;
    const posologie = fixFrenchFrequencyPhrasing(sanitizeLine(med.posologie, 220));
    const duree = sanitizeLine(med.duree, 140);
    const instructions = fixFrenchFrequencyPhrasing(sanitizeLine(med.instructions, 480));

    const rowHeight = 44;
    if (y + rowHeight > doc.page.height - 120) {
      doc.addPage();
      y = doc.page.margins.top;
    }
    doc.roundedRect(pageLeft, y, fullWidth, rowHeight, 6).stroke(border);
    doc.fillColor(textDark).font('Helvetica-Bold').fontSize(10).text(`${idx}. ${name}`, colMed, y + 8, {
      width: wMed - 10,
      ellipsis: true,
    });
    doc.fillColor('#334155').font('Helvetica').fontSize(9).text(posologie || '—', colPosologie, y + 8, {
      width: wPosologie - 10,
      ellipsis: true,
    });
    doc.fillColor('#334155').font('Helvetica').fontSize(8.5).text(instructions || '—', colInstructions, y + 8, {
      width: wInstructions - 10,
      height: 28,
      ellipsis: true,
    });
    doc.fillColor('#334155').font('Helvetica').fontSize(9).text(duree || '—', colDuree, y + 8, {
      width: wDuree - 8,
      ellipsis: true,
    });
    y += rowHeight + 8;
    idx += 1;
  }
  if (idx === 1) {
    doc.roundedRect(pageLeft, y, fullWidth, 38, 6).stroke(border);
    doc.fillColor('#64748B').font('Helvetica').fontSize(10).text('Aucun médicament renseigné.', pageLeft + 12, y + 12);
    y += 46;
  }

  const n = sanitizeLine(notes, 2000);
  if (n) {
    sectionTitle('Notes et recommandations');
    const notesHeight = Math.min(120, Math.max(54, Math.ceil(n.length / 90) * 14 + 20));
    boxed((contentY) => {
      doc.fillColor('#334155').font('Helvetica').fontSize(10).text(n, pageLeft + 12, contentY, {
        width: fullWidth - 24,
      });
    }, notesHeight);
  }

  const footerY = doc.page.height - doc.page.margins.bottom - 28;
  doc
    .fontSize(8.5)
    .fillColor('#7B8BA3')
    .font('Helvetica')
    .text('Document généré électroniquement — sans signature ni tampon.', pageLeft, footerY, {
      align: 'center',
      width: fullWidth,
    });

  doc.end();
  return done;
}

module.exports = { buildPrescriptionPdfBuffer };
