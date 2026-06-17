import 'package:flutter/material.dart';

import '../espace_medecin_shell.dart';
import '../headsapp_theme.dart';
import '../services/api_service.dart';

/// Paramètres : disponibilités, statut, message d'absence (thème blanc + bleu ciel).
class DoctorSettingsScreen extends StatefulWidget {
  const DoctorSettingsScreen({
    super.key,
    required this.doctorId,
    this.doctorName = '',
    this.embeddedInShell = false,
  });

  final String doctorId;
  final String doctorName;
  final bool embeddedInShell;

  @override
  State<DoctorSettingsScreen> createState() => _DoctorSettingsScreenState();
}

class _DoctorSettingsScreenState extends State<DoctorSettingsScreen> {
  static const Color _skyBlue = HeadsAppColors.brandAccent;
  static const Color _white = Colors.white;
  static const Color _background = HeadsAppColors.surfaceAlt;
  static const Color _textPrimary = HeadsAppColors.textPrimary;
  static const Color _textSecondary = HeadsAppColors.textSecondary;
  static const Color _borderLight = HeadsAppColors.border;
  static const int _maxAbsenceChars = 500;

  static const List<({int index, String label})> _dayChips = [
    (index: 1, label: 'Lun'),
    (index: 2, label: 'Mar'),
    (index: 3, label: 'Mer'),
    (index: 4, label: 'Jeu'),
    (index: 5, label: 'Ven'),
    (index: 6, label: 'Sam'),
    (index: 0, label: 'Dim'),
  ];

  static const List<int> _timeSlotHours = [
    8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
  ];

  bool _loading = true;
  String? _error;

  TimeOfDay _startHour = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endHour = const TimeOfDay(hour: 18, minute: 0);
  final Set<int> _availableDays = {1, 2, 3, 4, 5};
  final TextEditingController _absenceController = TextEditingController();
  bool _autoReplyEnabled = false;

  String _status = 'available';
  DateTime? _statusUpdatedAt;
  bool _updatingStatus = false;

  @override
  void initState() {
    super.initState();
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
    _startHour = _parseTime(data['workingHoursStart']?.toString()) ?? _startHour;
    _endHour = _parseTime(data['workingHoursEnd']?.toString()) ?? _endHour;
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
    _absenceController.text = (data['absenceMessage'] as String?) ?? '';
    _autoReplyEnabled = data['autoReplyEnabled'] == true;
    _status = (data['status'] as String?) ?? 'available';
    final updated = data['statusUpdatedAt'];
    if (updated is String) {
      _statusUpdatedAt = DateTime.tryParse(updated);
    }
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

  String _toBackendTime(TimeOfDay t) {
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

  void _setStartHourFromSlot(int hour) {
    setState(() => _startHour = TimeOfDay(hour: hour, minute: 0));
  }

  void _setEndHourFromSlot(int hour) {
    setState(() => _endHour = TimeOfDay(hour: hour, minute: 0));
  }

  int get _timeCategoryIndex {
    final start = _startHour.hour;
    final end = _endHour.hour;
    if (start >= 8 && end <= 12) return 0;
    if (start >= 12 && end <= 18) return 1;
    if (start >= 18 && end <= 21) return 2;
    return -1;
  }

  void _applyTimeCategory(int index) {
    setState(() {
      switch (index) {
        case 0:
          _startHour = const TimeOfDay(hour: 8, minute: 0);
          _endHour = const TimeOfDay(hour: 12, minute: 0);
          break;
        case 1:
          _startHour = const TimeOfDay(hour: 12, minute: 0);
          _endHour = const TimeOfDay(hour: 18, minute: 0);
          break;
        case 2:
          _startHour = const TimeOfDay(hour: 18, minute: 0);
          _endHour = const TimeOfDay(hour: 21, minute: 0);
          break;
      }
    });
  }

  Future<void> _saveAvailability() async {
    try {
      await ApiService.updateDoctorSettings(
        doctorId: widget.doctorId,
        workingHoursStart: _toBackendTime(_startHour),
        workingHoursEnd: _toBackendTime(_endHour),
        availableDays: List<int>.from(_availableDays)..sort(),
        absenceMessage: _absenceController.text,
        autoReplyEnabled: _autoReplyEnabled,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Réglages enregistrés'),
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
    }
  }

  Future<void> _updateStatus({bool showSuccessSnack = true}) async {
    if (_updatingStatus) return;
    setState(() => _updatingStatus = true);
    try {
      final data = await ApiService.updateDoctorStatus(
        doctorId: widget.doctorId,
        status: _status,
      );
      if (mounted) {
        final updated = data['statusUpdatedAt'];
        if (updated is String) {
          _statusUpdatedAt = DateTime.tryParse(updated);
        }
        setState(() => _updatingStatus = false);
        if (showSuccessSnack) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Statut mis à jour'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _updatingStatus = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      rethrow;
    }
  }

  Future<void> _selectStatus(String value) async {
    if (_updatingStatus || _status == value) return;
    final previousStatus = _status;
    setState(() => _status = value);
    try {
      await _updateStatus(showSuccessSnack: false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = previousStatus);
    }
  }

  PreferredSizeWidget? _appBar() {
    if (widget.embeddedInShell) return null;
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 22),
        color: _textPrimary,
        onPressed: () async {
          final didPop = await Navigator.of(context).maybePop();
          if (didPop || !mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => EspaceMedecinShell(
                doctorId: widget.doctorId,
                doctorName: widget.doctorName.isEmpty ? 'Médecin' : widget.doctorName,
              ),
            ),
          );
        },
      ),
      title: const Text(
        'Paramètres',
        style: TextStyle(
          color: _textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      centerTitle: true,
      backgroundColor: _white,
      foregroundColor: _textPrimary,
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
          child: Center(
            child: CircularProgressIndicator(color: _skyBlue),
          ),
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
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.error_outline_rounded,
                      size: 48,
                      color: _skyBlue,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _textSecondary,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    label: const Text('Réessayer'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE1395F),
                      foregroundColor: _white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            widget.embeddedInShell ? 8 : 8,
            16,
            24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.embeddedInShell)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Paramètres',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: _skyBlue,
                        ),
                  ),
                ),
              _buildAvailabilitySection(),
              const SizedBox(height: 20),
              _buildStatusSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvailabilitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDateCard(),
        const SizedBox(height: 16),
        _buildTimeCard(),
        const SizedBox(height: 16),
        _buildAbsenceCard(),
      ],
    );
  }

  Widget _buildDateCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(HeadsAppMetrics.cardRadius),
        border: Border.all(color: _borderLight),
        boxShadow: [
          BoxShadow(
            color: HeadsAppColors.brandPrimary.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Choisir les jours',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: _dayChips
                .map(
                  (d) => SizedBox(
                    width: 36,
                    child: Text(
                      d.label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: _textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: _dayChips.map((d) {
              final selected = _availableDays.contains(d.index);
              return GestureDetector(
                onTap: () => _toggleDay(d.index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? _skyBlue : Colors.transparent,
                    border: Border.all(
                      color: selected ? _skyBlue : _borderLight,
                      width: 1.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    d.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? _white : _textPrimary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeCard() {
    const timeCategories = <(String, IconData, int)>[
      ('Matin', Icons.wb_sunny_outlined, 0),
      ('Après-midi', Icons.wb_cloudy_outlined, 1),
      ('Soir', Icons.nightlight_round, 2),
    ];
    final categoryIndex = _timeCategoryIndex;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(HeadsAppMetrics.cardRadius),
        border: Border.all(color: _borderLight),
        boxShadow: [
          BoxShadow(
            color: HeadsAppColors.brandPrimary.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Choisir les horaires',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: timeCategories.map((cat) {
              final label = cat.$1;
              final icon = cat.$2;
              final index = cat.$3;
              final selected = categoryIndex == index;
              return GestureDetector(
                onTap: () => _applyTimeCategory(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? _skyBlue : _white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? _skyBlue : _borderLight,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 18,
                        color: selected ? _white : _textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: selected ? _white : _textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          const Text(
            'Heure de début',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _timeSlotHours.map((h) {
              final selected = _startHour.hour == h;
              return GestureDetector(
                onTap: () => _setStartHourFromSlot(h),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? _skyBlue : _white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? _skyBlue : _borderLight,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    '${h.toString().padLeft(2, '0')}:00',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: selected ? _white : _textPrimary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          const Text(
            'Heure de fin',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _timeSlotHours.map((h) {
              final selected = _endHour.hour == h;
              return GestureDetector(
                onTap: () => _setEndHourFromSlot(h),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? _skyBlue : _white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? _skyBlue : _borderLight,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    '${h.toString().padLeft(2, '0')}:00',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: selected ? _white : _textPrimary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAbsenceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(HeadsAppMetrics.cardRadius),
        border: Border.all(color: _borderLight),
        boxShadow: [
          BoxShadow(
            color: HeadsAppColors.brandPrimary.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Message d\'absence',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Réponses automatiques',
                  style: TextStyle(
                    fontSize: 15,
                    color: _textPrimary,
                  ),
                ),
              ),
              Switch(
                value: _autoReplyEnabled,
                onChanged: (v) => setState(() => _autoReplyEnabled = v),
                activeTrackColor: _skyBlue.withValues(alpha: 0.5),
                thumbColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? _skyBlue
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Texte du message',
            style: TextStyle(fontSize: 13, color: _textSecondary),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _absenceController,
            maxLines: 3,
            maxLength: _maxAbsenceChars,
            decoration: InputDecoration(
              hintText:
                  'Je suis actuellement absent. Je vous répondrai dès mon retour.',
              hintStyle: const TextStyle(color: _textSecondary),
              filled: true,
              fillColor: _white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _borderLight),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _borderLight),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _skyBlue, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saveAvailability,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE1395F),
                foregroundColor: _white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Enregistrer les réglages',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _load,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _skyBlue),
                foregroundColor: _skyBlue,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Annuler'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSection() {
    const statusOptions = <(String, String)>[
      ('available', 'Disponible'),
      ('busy', 'Occupé'),
      ('unavailable', 'Non disponible'),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Statut',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Sélectionnez votre statut actuel',
            style: TextStyle(fontSize: 14, color: _textSecondary),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: statusOptions.map((opt) {
              final value = opt.$1;
              final label = opt.$2;
              final selected = _status == value;
              return GestureDetector(
                onTap: _updatingStatus ? null : () => _selectStatus(value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? _skyBlue : _white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? _skyBlue : _skyBlue.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: selected ? _white : _skyBlue,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          if (_updatingStatus)
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text(
                  'Mise à jour du statut...',
                  style: TextStyle(fontSize: 13, color: _textSecondary),
                ),
              ],
            )
          else
            const Text(
              'Le statut est sauvegardé automatiquement.',
              style: TextStyle(fontSize: 13, color: _textSecondary),
            ),
          if (_statusUpdatedAt != null) ...[
            const SizedBox(height: 12),
            Text(
              'Dernière mise à jour : ${_formatStatusTime(_statusUpdatedAt!)}',
              style: const TextStyle(fontSize: 13, color: _textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  String _formatStatusTime(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
