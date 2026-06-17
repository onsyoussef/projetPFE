import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../headsapp_theme.dart';
import '../services/api_service.dart';
import '../utils/doctor_category_badge_storage.dart';
import '../utils/doctor_ui_utils.dart';

const Color _sky = HeadsAppColors.brandPrimary;

/// Liste des formulaires d’urgence (onglet tableau de bord).
class DoctorUrgenceListScreen extends StatefulWidget {
  const DoctorUrgenceListScreen({
    super.key,
    required this.doctorId,
    this.onRefreshHome,
    this.onListConsulted,
  });

  final String doctorId;
  final Future<void> Function()? onRefreshHome;
  final VoidCallback? onListConsulted;

  @override
  State<DoctorUrgenceListScreen> createState() => _DoctorUrgenceListScreenState();
}

class _DoctorUrgenceListScreenState extends State<DoctorUrgenceListScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.doctorId.isEmpty) {
      setState(() {
        _loading = false;
        _items = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list =
          await ApiService.getDoctorUrgenceFormulaires(widget.doctorId);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
      await DoctorCategoryBadgeStorage.markConsultedNow(
        widget.doctorId,
        DoctorDashboardCategory.urgence,
      );
      if (mounted) widget.onListConsulted?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HeadsAppColors.surfaceAlt,
      appBar: AppBar(
        title: const Text('Formulaire d’urgence'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _load();
          await widget.onRefreshHome?.call();
        },
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _sky))
            : _error != null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 48),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
                    ],
                  )
                : _items.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 80),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              'Aucun formulaire d’urgence. Les patients avec alerte acceptée apparaissent ici.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final it = _items[i];
                          final name =
                              readablePatientName(it['patientName']?.toString());
                          final consulted = it['consulted'] == true;
                          final at = it['createdAt'];
                          DateTime? dt;
                          if (at != null) {
                            dt = DateTime.tryParse(at.toString());
                          }
                          final symptomes = it['symptomes'];
                          final preview = symptomes is List
                              ? symptomes
                                  .map((e) => e.toString())
                                  .where((s) => s.isNotEmpty)
                                  .join(' · ')
                              : '';

                          Future<void> openDetail() async {
                            final id = it['id']?.toString() ?? '';
                            if (id.isEmpty) return;
                            final changed = await Navigator.of(context)
                                .push<bool>(
                              MaterialPageRoute(
                                builder: (_) => DoctorUrgenceDetailScreen(
                                  doctorId: widget.doctorId,
                                  formId: id,
                                ),
                              ),
                            );
                            if (changed == true && mounted) await _load();
                          }

                          return Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                HeadsAppMetrics.compactRadius,
                              ),
                            ),
                            color: HeadsAppColors.surface,
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                    Row(
                                      children: [
                                        patientAvatarForDoctor(
                                          name: name,
                                          patientPhotoPath: it['patientPhotoPath']
                                              ?.toString(),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: InkWell(
                                            onTap: openDetail,
                                            child: Text(
                                              name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 16,
                                                color: HeadsAppColors.brandPrimary,
                                                decoration:
                                                    TextDecoration.underline,
                                                decorationColor:
                                                    HeadsAppColors.brandPrimary,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: HeadsAppColors.danger,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: const Text(
                                            'URGENT',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (dt != null) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        '🕐 ${DateFormat('dd/MM/yyyy HH:mm').format(dt.toLocal())}',
                                        style: TextStyle(
                                          color: Colors.grey.shade700,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                    if (preview.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        preview,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.grey.shade800,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Text(
                                      consulted
                                          ? 'Statut : Consulté'
                                          : 'Statut : Non consulté',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: consulted
                                            ? const Color(0xFF16A34A)
                                            : const Color(0xFFCA8A04),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}

/// Détail d’un formulaire d’urgence — marque « Consulté » à l’ouverture.
class DoctorUrgenceDetailScreen extends StatefulWidget {
  const DoctorUrgenceDetailScreen({
    super.key,
    required this.doctorId,
    required this.formId,
  });

  final String doctorId;
  final String formId;

  @override
  State<DoctorUrgenceDetailScreen> createState() =>
      _DoctorUrgenceDetailScreenState();
}

class _DoctorUrgenceDetailScreenState extends State<DoctorUrgenceDetailScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  bool _marked = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ApiService.getUrgenceFormulaireForDoctor(
        formId: widget.formId,
        doctorId: widget.doctorId,
      );
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
      await ApiService.markUrgenceFormulaireConsulted(
        formId: widget.formId,
        doctorId: widget.doctorId,
      );
      if (!mounted) return;
      setState(() => _marked = true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Urgence — détail'),
        backgroundColor: _sky,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context, true),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _sky))
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center),
                ))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          patientAvatarForDoctor(
                            name: readablePatientName(_data?['patientName']?.toString()),
                            patientPhotoPath:
                                _data?['patientPhotoPath']?.toString(),
                            radius: 28,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              readablePatientName(_data?['patientName']?.toString()),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_data?['createdAt'] != null) ...[
                        Text(
                          'Soumis le ${DateFormat('dd/MM/yyyy à HH:mm').format(DateTime.parse(_data!['createdAt'].toString()).toLocal())}',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE1395F),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'URGENT',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _marked
                            ? 'Statut : Consulté'
                            : 'Statut : Non consulté',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _marked
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFCA8A04),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Symptômes',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._symptomLines(),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context, true),
                          icon: const Icon(Icons.arrow_back_rounded),
                          label: const Text('Retour à la liste'),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  List<Widget> _symptomLines() {
    final s = _data?['symptomes'];
    if (s is! List || s.isEmpty) {
      return [
        Text(
          '—',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      ];
    }
    return s.map<Widget>((e) {
      final t = e.toString();
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• ', style: TextStyle(color: Colors.grey.shade800)),
            Expanded(child: Text(t)),
          ],
        ),
      );
    }).toList();
  }
}
