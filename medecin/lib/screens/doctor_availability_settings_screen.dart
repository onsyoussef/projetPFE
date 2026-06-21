import 'package:flutter/material.dart';

import '../headsapp_theme.dart';
import '../services/api_service.dart';

class _WorkingTimeSlot {
  _WorkingTimeSlot({required this.start, required this.end});

  TimeOfDay start;
  TimeOfDay end;

  String get sessionLabel {
    final h = start.hour;
    if (h < 12) return 'Session du matin';
    if (h < 18) return 'Session de l\'après-midi';
    return 'Session du soir';
  }

  Map<String, String> toJson() => {
        'start': _formatTime(start),
        'end': _formatTime(end),
      };

  static String _formatTime(TimeOfDay t) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}

/// Paramètres de disponibilité : jours, horaires, mode absence.
class DoctorAvailabilitySettingsScreen extends StatefulWidget {
  const DoctorAvailabilitySettingsScreen({
    super.key,
    required this.doctorId,
    this.doctorName = '',
  });

  final String doctorId;
  final String doctorName;

  @override
  State<DoctorAvailabilitySettingsScreen> createState() =>
      _DoctorAvailabilitySettingsScreenState();
}

class _DoctorAvailabilitySettingsScreenState
    extends State<DoctorAvailabilitySettingsScreen> {
  static const Color _cyan = HeadsAppColors.brandAccent;
  static const Color _primaryBlue = HeadsAppColors.brandPrimary;
  static const Color _white = Colors.white;
  static const Color _background = Color(0xFFF5F9FC);
  static const Color _textPrimary = HeadsAppColors.textPrimary;
  static const Color _textSecondary = HeadsAppColors.textSecondary;
  static const Color _borderLight = HeadsAppColors.border;
  static const int _maxAbsenceChars = 500;

  // Couleurs maquette disponibilité
  static const Color _statusAvailableBg = Color(0xFFE8F5E9);
  static const Color _statusAvailableFg = Color(0xFF4CAF50);
  static const Color _statusBusyBg = Color(0xFFFFF7ED);
  static const Color _statusBusyFg = Color(0xFFEA580C);
  static const Color _statusUnavailableBg = Color(0xFFF3F4F6);
  static const Color _statusUnavailableFg = Color(0xFF64748B);
  static const Color _cardBorderGrey = Color(0xFFE0E0E0);
  static const Color _daySelectedBg = Color(0xFFE3F2FD);
  static const Color _daySelectedFg = Color(0xFF1976D2);
  static const Color _labelGrey = Color(0xFF757575);

  static const Set<String> _validStatuses = {'available', 'busy', 'unavailable'};

  static const List<({int index, String label})> _dayChips = [
    (index: 1, label: 'Lun'),
    (index: 2, label: 'Mar'),
    (index: 3, label: 'Mer'),
    (index: 4, label: 'Jeu'),
    (index: 5, label: 'Ven'),
    (index: 6, label: 'Sam'),
    (index: 0, label: 'Dim'),
  ];

  bool _loading = true;
  bool _saving = false;
  String? _error;

  final Set<int> _availableDays = {1, 2, 3, 4, 5};
  final List<_WorkingTimeSlot> _timeSlots = [];
  final TextEditingController _absenceController = TextEditingController();
  bool _absenceModeEnabled = false;
  bool _emergencyOnly = false;
  String _doctorStatus = 'available';

  @override
  void initState() {
    super.initState();
    _timeSlots.add(
      _WorkingTimeSlot(
        start: const TimeOfDay(hour: 9, minute: 0),
        end: const TimeOfDay(hour: 12, minute: 0),
      ),
    );
    _load();
  }

  @override
  void dispose() {
    _absenceController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getDoctorSettings(widget.doctorId);
      if (!mounted) return;
      setState(() {
        _applySettings(data);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  void _applySettings(Map<String, dynamic> data) {
    final days = data['availableDays'];
    if (days is List) {
      _availableDays.clear();
      for (final d in days) {
        final v = int.tryParse(d.toString());
        if (v != null && v >= 0 && v <= 6) _availableDays.add(v);
      }
      if (_availableDays.isEmpty) {
        _availableDays.addAll({1, 2, 3, 4, 5});
      }
    }

    _timeSlots.clear();
    final slots = data['workingTimeSlots'];
    if (slots is List && slots.isNotEmpty) {
      for (final slot in slots) {
        if (slot is! Map) continue;
        final start = _parseTime(slot['start']?.toString());
        final end = _parseTime(slot['end']?.toString());
        if (start != null && end != null) {
          _timeSlots.add(_WorkingTimeSlot(start: start, end: end));
        }
      }
    }
    if (_timeSlots.isEmpty) {
      final start = _parseTime(data['workingHoursStart']?.toString()) ??
          const TimeOfDay(hour: 9, minute: 0);
      final end = _parseTime(data['workingHoursEnd']?.toString()) ??
          const TimeOfDay(hour: 18, minute: 0);
      _timeSlots.add(_WorkingTimeSlot(start: start, end: end));
    }

    _absenceController.text = (data['absenceMessage'] as String?) ?? '';
    _absenceModeEnabled = data['autoReplyEnabled'] == true;
    _emergencyOnly = data['absenceEmergencyOnly'] == true;
    final rawStatus = data['status']?.toString() ?? 'available';
    _doctorStatus =
        _validStatuses.contains(rawStatus) ? rawStatus : 'available';
  }

  TimeOfDay? _parseTime(String? s) {
    if (s == null || s.isEmpty) return null;
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1].replaceAll(RegExp(r'[^0-9]'), ''));
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    return TimeOfDay(hour: h, minute: m);
  }

  String _formatTime(TimeOfDay t) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  void _toggleDay(int day) {
    setState(() {
      if (_availableDays.contains(day)) {
        _availableDays.remove(day);
      } else {
        _availableDays.add(day);
      }
    });
  }

  void _addShift() {
    setState(() {
      _timeSlots.add(
        _WorkingTimeSlot(
          start: const TimeOfDay(hour: 14, minute: 0),
          end: const TimeOfDay(hour: 18, minute: 0),
        ),
      );
    });
  }

  void _removeShift(int index) {
    if (_timeSlots.length <= 1) return;
    setState(() => _timeSlots.removeAt(index));
  }

  Future<void> _pickTime({
    required int slotIndex,
    required bool isStart,
  }) async {
    final slot = _timeSlots[slotIndex];
    final initial = isStart ? slot.start : slot.end;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: _primaryBlue,
                ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        slot.start = picked;
      } else {
        slot.end = picked;
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final slots = _timeSlots.map((s) => s.toJson()).toList();
      await ApiService.updateDoctorSettings(
        doctorId: widget.doctorId,
        workingTimeSlots: slots,
        workingHoursStart: slots.first['start'],
        workingHoursEnd: slots.last['end'],
        availableDays: List<int>.from(_availableDays)..sort(),
        absenceMessage: _absenceController.text,
        autoReplyEnabled: _absenceModeEnabled,
        absenceEmergencyOnly: _emergencyOnly,
      );
      await ApiService.updateDoctorStatus(
        doctorId: widget.doctorId,
        status: _doctorStatus,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Modifications enregistrées'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  PreferredSizeWidget _appBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        color: _primaryBlue,
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: const Text(
        'Paramètres de disponibilité',
        style: TextStyle(
          color: _primaryBlue,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      centerTitle: false,
      titleSpacing: 0,
      backgroundColor: _background,
      foregroundColor: _primaryBlue,
      elevation: 0,
      scrolledUnderElevation: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: _background,
        appBar: _appBar(),
        body: const SafeArea(
          child: Center(child: CircularProgressIndicator(color: _cyan)),
        ),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: _background,
        appBar: _appBar(),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 48,
                    color: _cyan,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _textSecondary, fontSize: 15),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    label: const Text('Réessayer'),
                    style: FilledButton.styleFrom(
                      backgroundColor: HeadsAppColors.danger,
                      foregroundColor: _white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _background,
      appBar: _appBar(),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Disponibilité',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: _textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Gérez vos horaires et vos absences pour maintenir une communication fluide avec vos patients.',
                      style: TextStyle(
                        fontSize: 14,
                        color: _textSecondary,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _sectionLabel('STATUT'),
                    const SizedBox(height: 12),
                    _buildStatusRow(),
                    const SizedBox(height: 28),
                    _sectionLabel('JOURS OUVRÉS'),
                    const SizedBox(height: 12),
                    _buildDaysRow(),
                    const SizedBox(height: 28),
                    _buildHoursHeader(),
                    const SizedBox(height: 12),
                    ...List.generate(
                      _timeSlots.length,
                      (i) => Padding(
                        padding: EdgeInsets.only(
                          bottom: i < _timeSlots.length - 1 ? 12 : 0,
                        ),
                        child: _buildShiftCard(i),
                      ),
                    ),
                    const SizedBox(height: 28),
                    _buildAbsenceCard(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: _primaryBlue,
                    foregroundColor: _white,
                    disabledBackgroundColor:
                        _primaryBlue.withValues(alpha: 0.6),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _white,
                          ),
                        )
                      : const Text(
                          'Enregistrer les modifications',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: _labelGrey,
      ),
    );
  }

  Widget _buildStatusRow() {
    return Row(
      children: [
        Expanded(
          child: _statusCard(
            value: 'available',
            icon: Icons.check_circle_outline_rounded,
            label: 'Disponible',
            selectedBg: _statusAvailableBg,
            selectedFg: _statusAvailableFg,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _statusCard(
            value: 'busy',
            icon: Icons.schedule_rounded,
            label: 'Occupé',
            selectedBg: _statusBusyBg,
            selectedFg: _statusBusyFg,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _statusCard(
            value: 'unavailable',
            icon: Icons.remove_circle_outline_rounded,
            label: 'Non disponible',
            selectedBg: _statusUnavailableBg,
            selectedFg: _statusUnavailableFg,
          ),
        ),
      ],
    );
  }

  Widget _statusCard({
    required String value,
    required IconData icon,
    required String label,
    required Color selectedBg,
    required Color selectedFg,
  }) {
    final selected = _doctorStatus == value;
    return GestureDetector(
      onTap: () => setState(() => _doctorStatus = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? selectedBg : _white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? selectedFg : _cardBorderGrey,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: selected ? selectedFg : _labelGrey,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? selectedFg : _textPrimary,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDaysRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: _dayChips.map((d) {
        final selected = _availableDays.contains(d.index);
        return GestureDetector(
          onTap: () => _toggleDay(d.index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 44,
            height: 58,
            decoration: BoxDecoration(
              color: selected ? _daySelectedBg : _white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? _daySelectedFg : _cardBorderGrey,
                width: selected ? 1.5 : 1,
              ),
              boxShadow: selected
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  d.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected ? _daySelectedFg : _textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  size: 14,
                  color: selected
                      ? _daySelectedFg
                      : _labelGrey.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildHoursHeader() {
    return Row(
      children: [
        _sectionLabel('HEURES QUOTIDIENNES'),
        const Spacer(),
        TextButton.icon(
          onPressed: _addShift,
          icon: const Icon(Icons.add_rounded, size: 18, color: _daySelectedFg),
          label: const Text(
            'Ajouter un décalage',
            style: TextStyle(
              color: _daySelectedFg,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }

  Widget _buildShiftCard(int index) {
    final slot = _timeSlots[index];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _timeField(
                  label: 'Heure de début',
                  time: slot.start,
                  onTap: () => _pickTime(slotIndex: index, isStart: true),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: _textSecondary.withValues(alpha: 0.6),
                ),
              ),
              Expanded(
                child: _timeField(
                  label: 'Heure de fin',
                  time: slot.end,
                  onTap: () => _pickTime(slotIndex: index, isStart: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                slot.sessionLabel,
                style: const TextStyle(
                  fontSize: 13,
                  color: _textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (_timeSlots.length > 1)
                TextButton(
                  onPressed: () => _removeShift(index),
                  style: TextButton.styleFrom(
                    foregroundColor: HeadsAppColors.danger,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Supprimer',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timeField({
    required String label,
    required TimeOfDay time,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: _textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Material(
          color: _white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _borderLight),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 18,
                    color: _textSecondary.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatTime(time),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAbsenceCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: HeadsAppColors.brandHighlight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.beach_access_rounded,
                  color: _primaryBlue,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Mode Absence',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                      ),
                    ),
                    Text(
                      'Désactiver les rendez-vous temporairement',
                      style: TextStyle(
                        fontSize: 13,
                        color: _textSecondary.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _absenceModeEnabled,
                onChanged: (v) {
                  setState(() {
                    _absenceModeEnabled = v;
                    if (v) {
                      _doctorStatus = 'unavailable';
                    } else if (_doctorStatus == 'unavailable') {
                      _doctorStatus = 'available';
                    }
                  });
                },
                activeTrackColor: _primaryBlue.withValues(alpha: 0.45),
                activeThumbColor: _primaryBlue,
              ),
            ],
          ),
          if (_absenceModeEnabled) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: HeadsAppColors.brandHighlight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _emergencyOnly,
                      onChanged: (v) =>
                          setState(() => _emergencyOnly = v ?? false),
                      activeColor: _primaryBlue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Accepter uniquement les cas d\'urgence',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Les patients pourront toujours vous contacter pour des motifs critiques définis dans vos protocoles.',
                          style: TextStyle(
                            fontSize: 12,
                            color: _textSecondary.withValues(alpha: 0.95),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Message automatique',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _absenceController,
              maxLines: 3,
              maxLength: _maxAbsenceChars,
              decoration: InputDecoration(
                hintText:
                    'Je suis actuellement indisponible, je reviens le...',
                hintStyle: TextStyle(
                  color: _textSecondary.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
                filled: true,
                fillColor: const Color(0xFFF0F4F8),
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Ce message sera envoyé en réponse à toute nouvelle demande de consultation non-urgente.',
              style: TextStyle(
                fontSize: 12,
                color: _textSecondary.withValues(alpha: 0.85),
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
