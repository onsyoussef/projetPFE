import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../headsapp_theme.dart';
import '../services/api_service.dart';
import '../utils/doctor_ui_utils.dart';

/// Source d’envoi : même endpoint, traçabilité en base.
enum PrescriptionSendSource {
  chat,
  teleconsult,
}

String prescriptionSourceApiValue(PrescriptionSendSource s) =>
    s == PrescriptionSendSource.teleconsult ? 'teleconsult' : 'chat';

/// Ouvre le formulaire d’ordonnance (bottom sheet scrollable).
Future<void> showDoctorPrescriptionFormBottomSheet(
  BuildContext context, {
  required String conversationId,
  required String doctorId,
  required String patientName,
  required PrescriptionSendSource source,
  String? consultationCallRoomId,
  Future<void> Function()? onSent,
  List<Map<String, String>>? initialMedicationRows,
  String? initialNotes,
  String? initialCity,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: HeadsAppColors.surfaceAlt,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: PrescriptionFormSheet(
          conversationId: conversationId,
          doctorId: doctorId,
          patientName: patientName,
          source: source,
          consultationCallRoomId: consultationCallRoomId,
          onSent: onSent,
          initialMedicationRows: initialMedicationRows,
          initialNotes: initialNotes,
          initialCity: initialCity,
        ),
      );
    },
  );
}

class PrescriptionMedicationLine {
  PrescriptionMedicationLine({
    required this.nameController,
    required this.posologieController,
    required this.dureeController,
    required this.instructionsController,
  });

  final TextEditingController nameController;
  final TextEditingController posologieController;
  final TextEditingController dureeController;
  final TextEditingController instructionsController;

  void dispose() {
    nameController.dispose();
    posologieController.dispose();
    dureeController.dispose();
    instructionsController.dispose();
  }
}

class PrescriptionFormSheet extends StatefulWidget {
  const PrescriptionFormSheet({
    super.key,
    required this.conversationId,
    required this.doctorId,
    required this.patientName,
    required this.source,
    this.consultationCallRoomId,
    this.onSent,
    this.initialMedicationRows,
    this.initialNotes,
    this.initialCity,
  });

  final String conversationId;
  final String doctorId;
  final String patientName;
  final PrescriptionSendSource source;
  final String? consultationCallRoomId;
  final Future<void> Function()? onSent;
  final List<Map<String, String>>? initialMedicationRows;
  final String? initialNotes;
  final String? initialCity;

  @override
  State<PrescriptionFormSheet> createState() => _PrescriptionFormSheetState();
}

class _PrescriptionFormSheetState extends State<PrescriptionFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _cityController = TextEditingController();
  final _notesController = TextEditingController();

  final List<PrescriptionMedicationLine> _lines = [];

  bool _loadingProfile = true;
  String? _profileError;
  String _doctorName = '';
  String _doctorSpecialty = '';
  String _doctorEmail = '';
  String _doctorPhone = '';
  String _doctorGovernorate = '';
  String _doctorAddress = '';

  bool _submitting = false;

  late final String _draftOrdRef;

  @override
  void initState() {
    super.initState();
    final y = DateTime.now().year;
    final seed =
        '${widget.conversationId}_${widget.doctorId}'.hashCode.abs() % 90000;
    _draftOrdRef = '#ORD-$y-${(10000 + seed).toString()}';
    final initial = widget.initialMedicationRows;
    if (initial != null && initial.isNotEmpty) {
      for (final row in initial) {
        final line = _newLine();
        line.nameController.text = (row['name'] ?? '').trim();
        line.posologieController.text =
            (row['posologie'] ?? row['dosage'] ?? '').trim();
        line.dureeController.text = (row['duree'] ?? row['duration'] ?? '').trim();
        line.instructionsController.text =
            (row['instructions'] ?? '').trim();
        _lines.add(line);
      }
    } else {
      _lines.add(_newLine());
    }
    final cityInit = widget.initialCity?.trim();
    if (cityInit != null && cityInit.isNotEmpty) {
      _cityController.text = cityInit;
    }
    final notesInit = widget.initialNotes?.trim();
    if (notesInit != null && notesInit.isNotEmpty) {
      _notesController.text = notesInit;
    }
    unawaited(_loadDoctorProfile());
  }

  PrescriptionMedicationLine _newLine() {
    return PrescriptionMedicationLine(
      nameController: TextEditingController(),
      posologieController: TextEditingController(),
      dureeController: TextEditingController(),
      instructionsController: TextEditingController(),
    );
  }

  Future<void> _loadDoctorProfile() async {
    try {
      final data = await ApiService.getDoctorProfile(widget.doctorId);
      if (!mounted) return;
      setState(() {
        _doctorName = readableDoctorName(data['fullName']?.toString(), fallback: '');
        _doctorSpecialty = readableDecryptedField(data['specialty']?.toString());
        _doctorEmail = readableDecryptedField(data['email']?.toString());
        _doctorPhone = readableDecryptedField(data['phone']?.toString());
        _doctorGovernorate = readableDecryptedField(data['governorate']?.toString());
        _doctorAddress = readableDecryptedField(data['address']?.toString());
        _loadingProfile = false;
        _profileError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingProfile = false;
        _profileError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  void dispose() {
    _cityController.dispose();
    _notesController.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  String _subtitleSource() {
    switch (widget.source) {
      case PrescriptionSendSource.teleconsult:
        return 'Téléconsultation';
      case PrescriptionSendSource.chat:
        return 'Messagerie sécurisée';
    }
  }

  String _dateHeaderLabel() {
    return DateFormat('d MMMM yyyy', 'fr_FR').format(DateTime.now());
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final meds = <Map<String, String>>[];
    for (final l in _lines) {
      final name = l.nameController.text.trim();
      if (name.isEmpty) continue;
      meds.add({
        'name': name,
        'posologie': l.posologieController.text.trim(),
        'duree': l.dureeController.text.trim(),
        'instructions': l.instructionsController.text.trim(),
      });
    }
    if (meds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ajoutez au moins un médicament avec un nom.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await ApiService.createPrescription(
        conversationId: widget.conversationId,
        city: _cityController.text.trim(),
        medications: meds,
        notes: _notesController.text.trim(),
        source: prescriptionSourceApiValue(widget.source),
        consultationCallRoomId: widget.consultationCallRoomId?.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ordonnance générée et envoyée au patient.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await widget.onSent?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InputDecoration _fieldDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(HeadsAppMetrics.compactRadius),
        borderSide: const BorderSide(color: HeadsAppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(HeadsAppMetrics.compactRadius),
        borderSide: const BorderSide(color: HeadsAppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(HeadsAppMetrics.compactRadius),
        borderSide: const BorderSide(color: HeadsAppColors.brandPrimary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height * 0.92;

    return SizedBox(
      height: h,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Fermer',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
                color: HeadsAppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, viewportConstraints) {
                const horizontalPadding = 16.0 * 2;
                final innerWidth = (viewportConstraints.maxWidth -
                        horizontalPadding)
                    .clamp(240.0, viewportConstraints.maxWidth);
                return _loadingProfile
                    ? const Center(
                        child: CircularProgressIndicator(color: HeadsAppColors.brandPrimary),
                      )
                    : _profileError != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _profileError!,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton(
                                    onPressed: () {
                                      setState(() {
                                        _loadingProfile = true;
                                        _profileError = null;
                                      });
                                      unawaited(_loadDoctorProfile());
                                    },
                                    child: const Text('Réessayer'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : SingleChildScrollView(
                            padding:
                                const EdgeInsets.fromLTRB(16, 0, 16, 28),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: innerWidth,
                                maxWidth: innerWidth,
                              ),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildHeroHeader(context),
                                    const SizedBox(height: 16),
                                    _buildDoctorSection(context),
                                    const SizedBox(height: 14),
                                    _buildPatientSection(context),
                                    const SizedBox(height: 14),
                                    _buildPrescriptionSection(context),
                                    const SizedBox(height: 14),
                                    _buildRecommendationsSection(context),
                                    const SizedBox(height: 16),
                                    _buildDisclaimer(context),
                                    const SizedBox(height: 24),
                                    FilledButton.icon(
                                      onPressed:
                                          _submitting ? null : _submit,
                                      icon: _submitting
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child:
                                                  CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(Icons.send_rounded,
                                              size: 20),
                                      label: Text(
                                        _submitting
                                            ? 'Envoi…'
                                            : 'Générer et envoyer',
                                      ),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: HeadsAppColors.brandPrimary,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(
                                            HeadsAppMetrics.compactRadius,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Ordonnance médicale',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: HeadsAppColors.textPrimary,
                letterSpacing: -0.5,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          _subtitleSource(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: HeadsAppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(HeadsAppMetrics.compactRadius),
            border: Border.all(color: HeadsAppColors.border),
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_today_outlined,
                  size: 18, color: HeadsAppColors.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _dateHeaderLabel(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                _draftOrdRef,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: HeadsAppColors.brandPrimary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDoctorSection(BuildContext context) {
    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            icon: Icons.badge_outlined,
            label: 'Informations du médecin',
          ),
          const SizedBox(height: 12),
          Text(
            _doctorName.isEmpty ? '—' : _doctorName,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: HeadsAppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _doctorSpecialty.isEmpty ? '—' : _doctorSpecialty,
            style: TextStyle(
              color: HeadsAppColors.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          if (_doctorPhone.isNotEmpty)
            _ContactRow(icon: Icons.phone_outlined, text: _doctorPhone),
          if (_doctorEmail.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ContactRow(icon: Icons.mail_outline_rounded, text: _doctorEmail),
          ],
          if (_doctorGovernorate.isNotEmpty || _doctorAddress.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ContactRow(
              icon: Icons.place_outlined,
              text: [
                if (_doctorAddress.isNotEmpty) _doctorAddress,
                if (_doctorGovernorate.isNotEmpty) _doctorGovernorate,
              ].join(' · '),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPatientSection(BuildContext context) {
    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            icon: Icons.person_outline_rounded,
            label: 'Informations du patient',
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final gap = 12.0;
              final half = (w - gap) / 2;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      SizedBox(
                        width: half,
                        child: _PatientKv(
                          label: 'Nom et prénom',
                          value: widget.patientName,
                        ),
                      ),
                      SizedBox(
                        width: half,
                        child: _PatientKv(
                          label: 'Ville (ordonnance)',
                          value: _cityController.text.trim().isEmpty
                              ? '—'
                              : _cityController.text.trim(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _cityController,
                    textCapitalization: TextCapitalization.words,
                    decoration: _fieldDecoration(
                      'Ville',
                      hint: 'Ex. Tunis',
                    ),
                    validator: (v) {
                      if ((v ?? '').trim().isEmpty) {
                        return 'La ville est obligatoire.';
                      }
                      return null;
                    },
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPrescriptionSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 370;
              final title = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.medication_outlined, color: HeadsAppColors.brandPrimary, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Prescription',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: HeadsAppColors.brandPrimary,
                        ),
                  ),
                ],
              );
              final addButton = Material(
                color: HeadsAppColors.brandPrimary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(HeadsAppMetrics.compactRadius),
                child: InkWell(
                  borderRadius: BorderRadius.circular(HeadsAppMetrics.compactRadius),
                  onTap: () => setState(() => _lines.add(_newLine())),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, size: 20, color: HeadsAppColors.brandPrimary),
                        SizedBox(width: 6),
                        Text(
                          'Ajouter',
                          style: TextStyle(
                            color: HeadsAppColors.brandPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: addButton),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 8),
                  addButton,
                ],
              );
            },
          ),
        ),
        ...List.generate(_lines.length, (i) {
          final line = _lines[i];
          return _MedicationEditorCard(
            index: i + 1,
            line: line,
            canRemove: _lines.length > 1,
            fieldDecoration: _fieldDecoration,
            onRemove: () {
              setState(() {
                line.dispose();
                _lines.removeAt(i);
              });
            },
          );
        }),
      ],
    );
  }

  Widget _buildRecommendationsSection(BuildContext context) {
    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            icon: Icons.content_paste_outlined,
            label: 'Recommandations',
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _notesController,
            maxLines: 5,
            decoration: _fieldDecoration(
              'Conseils au patient (facultatif)',
              hint:
                  'Ex. Hydratation, repos, surveillance des symptômes…',
            ).copyWith(
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisclaimer(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HeadsAppColors.brandHighlight,
        borderRadius: BorderRadius.circular(HeadsAppMetrics.compactRadius),
        border: Border.all(color: HeadsAppColors.brandPrimary.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: HeadsAppColors.brandPrimary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Cette ordonnance est valable dans le cadre de la téléconsultation '
              'documentée. Respectez strictement posologie et durée ; en cas de '
              'doute, consultez votre médecin.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: HeadsAppColors.textPrimary,
                    height: 1.4,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WhiteCard extends StatelessWidget {
  const _WhiteCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(HeadsAppMetrics.compactRadius),
        border: Border.all(color: HeadsAppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: HeadsAppColors.brandPrimary, size: 22),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: HeadsAppColors.brandPrimary,
              ),
        ),
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: HeadsAppColors.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: HeadsAppColors.textPrimary,
                  height: 1.35,
                ),
          ),
        ),
      ],
    );
  }
}

class _PatientKv extends StatelessWidget {
  const _PatientKv({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: HeadsAppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: HeadsAppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: HeadsAppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: HeadsAppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MedicationEditorCard extends StatelessWidget {
  const _MedicationEditorCard({
    required this.index,
    required this.line,
    required this.canRemove,
    required this.onRemove,
    required this.fieldDecoration,
  });

  final int index;
  final PrescriptionMedicationLine line;
  final bool canRemove;
  final VoidCallback onRemove;
  final InputDecoration Function(String label, {String? hint}) fieldDecoration;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(HeadsAppMetrics.compactRadius),
          border: Border.all(color: HeadsAppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: HeadsAppColors.brandPrimary.withValues(alpha: 0.12),
                    child: Text(
                      '$index',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: HeadsAppColors.brandPrimary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: line.nameController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: fieldDecoration('Médicament'),
                      validator: (v) => null,
                    ),
                  ),
                  if (canRemove)
                    IconButton(
                      tooltip: 'Supprimer',
                      onPressed: onRemove,
                      icon: Icon(Icons.delete_outline_rounded,
                          color: Colors.red.shade700),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final gap = 10.0;
                  final narrow = w < 420;
                  final half = narrow ? w : (w - gap) / 2;
                  final dosageDurRow = narrow
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: line.posologieController,
                              decoration: fieldDecoration(
                                'Dosage',
                                hint: 'ex. 1000 mg',
                              ),
                            ),
                            SizedBox(height: gap),
                            TextFormField(
                              controller: line.dureeController,
                              decoration: fieldDecoration(
                                'Durée',
                                hint: 'ex. 7 jours',
                              ),
                            ),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: half,
                              child: TextFormField(
                                controller: line.posologieController,
                                decoration: fieldDecoration(
                                  'Dosage',
                                  hint: 'ex. 1000 mg',
                                ),
                              ),
                            ),
                            SizedBox(width: gap),
                            SizedBox(
                              width: half,
                              child: TextFormField(
                                controller: line.dureeController,
                                decoration: fieldDecoration(
                                  'Durée',
                                  hint: 'ex. 7 jours',
                                ),
                              ),
                            ),
                          ],
                        );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      dosageDurRow,
                      SizedBox(height: gap),
                      TextFormField(
                        controller: line.instructionsController,
                        maxLines: 3,
                        decoration: fieldDecoration(
                          'Instructions / fréquence',
                          hint: 'ex. 3 fois par jour après les repas',
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
