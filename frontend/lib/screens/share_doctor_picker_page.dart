import 'package:flutter/material.dart';

import '../headsapp_theme.dart';
import '../services/api_service.dart';
import '../utils/patient_ui_utils.dart';
import '../widgets/share_success_dialog.dart';

class ShareDoctorPickerPage extends StatefulWidget {
  const ShareDoctorPickerPage({
    super.key,
    required this.patientId,
    required this.selectedItemIds,
  });

  final String patientId;
  final List<String> selectedItemIds;

  @override
  State<ShareDoctorPickerPage> createState() => _ShareDoctorPickerPageState();
}

class _ShareDoctorPickerPageState extends State<ShareDoctorPickerPage> {
  static const Color _titleNavy = Color(0xFF1A458B);
  static const Color _pageBg = Color(0xFFF8FAFC);
  static const Color _fieldBg = Color(0xFFF0F4F8);
  static const Color _labelGrey = Color(0xFF9CA3AF);
  static const Color _textGrey = Color(0xFF6B7280);
  static const Color _specialtyTeal = Color(0xFF0D9488);
  static const Color _cardBorder = Color(0xFFDCE7F5);

  final TextEditingController _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _doctors = [];
  bool _loading = true;
  bool _sharing = false;
  String? _error;
  String? _selectedDoctorId;

  @override
  void initState() {
    super.initState();
    _loadDoctors();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDoctors() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiService.getDoctors(),
        ApiService.getPatientConversations(patientId: widget.patientId),
      ]);
      final allDoctors = List<Map<String, dynamic>>.from(results[0] as List);
      final conversations = List<Map<String, dynamic>>.from(results[1] as List);

      final myDoctorIds = <String>{
        for (final c in conversations)
          if ((c['doctorId']?.toString() ?? '').isNotEmpty) c['doctorId'].toString(),
      };

      final byId = <String, Map<String, dynamic>>{
        for (final d in allDoctors)
          if ((d['id']?.toString() ?? '').isNotEmpty) d['id'].toString(): d,
      };

      final myDoctors = <Map<String, dynamic>>[];
      for (final id in myDoctorIds) {
        final doctor = byId[id];
        if (doctor != null) myDoctors.add(doctor);
      }

      if (!mounted) return;
      setState(() {
        _doctors = myDoctors.isNotEmpty ? myDoctors : allDoctors;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  String _displayDoctorName(String? fullName) {
    final name = readableDoctorName(fullName, fallback: '—');
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == '—') return 'Dr. —';
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('dr.') || lower.startsWith('dr ')) return trimmed;
    return 'Dr. $trimmed';
  }

  List<Map<String, dynamic>> get _visibleDoctors {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _doctors;
    return _doctors.where((d) {
      final name = readableDoctorName(d['fullName']?.toString(), fallback: '').toLowerCase();
      final specialty = readableDecryptedField(
        d['specialty']?.toString(),
        fallback: '',
      ).toLowerCase();
      final city = readableDecryptedField(
        d['governorate']?.toString(),
        fallback: '',
      ).toLowerCase();
      return name.contains(q) || specialty.contains(q) || city.contains(q);
    }).toList();
  }

  void _toggleDoctorSelection(String doctorId) {
    if (doctorId.isEmpty || _sharing) return;
    setState(() {
      if (_selectedDoctorId == doctorId) {
        _selectedDoctorId = null;
      } else {
        _selectedDoctorId = doctorId;
      }
    });
  }

  Future<void> _confirmShare() async {
    final doctorId = _selectedDoctorId;
    if (doctorId == null || doctorId.isEmpty || _sharing) return;
    setState(() => _sharing = true);
    try {
      final result = await ApiService.sharePatientMedicalDossier(
        patientId: widget.patientId,
        doctorId: doctorId,
        itemIds: widget.selectedItemIds,
      );
      if (!mounted) return;
      final doctorName = _displayDoctorName(result['doctorName']?.toString());
      await showShareSuccessDialog(context, doctorName: doctorName);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sharing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            color: _titleNavy,
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'Retour',
          ),
          const Expanded(
            child: Text(
              'Choisir un médecin',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _titleNavy,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildDoctorCard(Map<String, dynamic> doctor) {
    final id = doctor['id']?.toString() ?? '';
    final selected = _selectedDoctorId == id;
    final fullName = _displayDoctorName(doctor['fullName']?.toString());
    final specialty = readableDecryptedField(
      doctor['specialty']?.toString(),
      fallback: '—',
    );
    final city = readableDecryptedField(
      doctor['governorate']?.toString(),
      fallback: '—',
    );
    final status = doctor['status']?.toString() ?? 'available';
    final isOnline = status == 'available';
    final photoUrl = ApiService.resolveMediaUrlOrNull(doctor['photoPath']?.toString());

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _cardBorder, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          child: Row(
            children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: const Color(0xFFE8F0FE),
                      backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                      child: photoUrl == null
                          ? const Icon(Icons.person_rounded, color: _titleNavy, size: 30)
                          : null,
                    ),
                    if (isOnline)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        specialty,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: _specialtyTeal,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 15, color: _textGrey),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              city,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: _textGrey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Material(
                  color: selected ? const Color(0xFF2563EB) : _fieldBg,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _sharing ? null : () => _toggleDoctorSelection(id),
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(
                        Icons.add_rounded,
                        color: selected ? Colors.white : _textGrey,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }

  Widget _buildConfirmButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: HeadsAppColors.primaryButtonGradient,
            boxShadow: [
              BoxShadow(
                color: HeadsAppColors.authGradientEnd.withValues(alpha: 0.28),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: _sharing ? null : _confirmShare,
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: _sharing
                    ? const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check_rounded,
                              color: HeadsAppColors.authGradientEnd,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Confirmer (1)',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleDoctors;

    return Scaffold(
      backgroundColor: _pageBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: _titleNavy))
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_error!, textAlign: TextAlign.center),
                                const SizedBox(height: 16),
                                FilledButton(
                                  onPressed: _loadDoctors,
                                  child: const Text('Réessayer'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Padding(
                              padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
                              child: Text(
                                'Partage sécurisé',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF111827),
                                  height: 1.1,
                                ),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
                              child: Text(
                                'Sélectionnez un médecin de santé avec qui vous souhaitez partager vos documents médicaux.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _textGrey,
                                  height: 1.45,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: TextField(
                                controller: _searchCtrl,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  hintText: 'Rechercher par nom, spécialité ou ville...',
                                  hintStyle: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 14,
                                  ),
                                  prefixIcon: Icon(Icons.search_rounded, color: Colors.grey.shade500),
                                  filled: true,
                                  fillColor: _fieldBg,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(999),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 22),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 20),
                              child: Text(
                                'MES MÉDECINS',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.1,
                                  color: _labelGrey,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: visible.isEmpty
                                  ? ListView(
                                      physics: const AlwaysScrollableScrollPhysics(),
                                      padding: const EdgeInsets.all(24),
                                      children: [
                                        Icon(Icons.person_search_rounded, size: 56, color: Colors.grey.shade400),
                                        const SizedBox(height: 12),
                                        Text(
                                          'Aucun médecin trouvé.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    )
                                  : ListView.builder(
                                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                                      itemCount: visible.length,
                                      itemBuilder: (_, i) => _buildDoctorCard(visible[i]),
                                    ),
                            ),
                          ],
                        ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return SizeTransition(
                  sizeFactor: animation,
                  axisAlignment: -1,
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
              child: (!_loading && _error == null && _selectedDoctorId != null)
                  ? KeyedSubtree(
                      key: const ValueKey('confirm-visible'),
                      child: _buildConfirmButton(),
                    )
                  : const SizedBox.shrink(key: ValueKey('confirm-hidden')),
            ),
          ],
        ),
      ),
    );
  }
}
