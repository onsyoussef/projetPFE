import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../chat_medecin_page.dart';
import '../headsapp_theme.dart';
import '../services/api_service.dart';
import '../utils/doctor_ui_utils.dart';
import 'doctor_teleconsult_agenda_screen.dart';

const Color _sky = HeadsAppColors.brandPrimary;

String _formReviewStatusLabel(String api) {
  switch (api) {
    case 'accepted':
      return 'Accepté';
    case 'rejected':
      return 'Rejeté';
    default:
      return 'En attente de décision';
  }
}

String _formWorkflowLabel(String api) {
  switch (api) {
    case 'scheduled':
      return 'Téléconsultation planifiée';
    case 'replied':
      return 'Répondu';
    default:
      return 'En attente';
  }
}

String _fullFormText(Map<String, dynamic> m) {
  final parts = <String>[];
  void add(String label, dynamic v) {
    final s = v?.toString().trim() ?? '';
    if (s.isNotEmpty) parts.add('$label\n$s');
  }

  add('Motif', m['motif']);
  add('Symptômes', m['symptomes']);
  add('Traitements', m['traitements']);
  add('Allergies', m['allergies']);
  final d = m['dateDerniereConsultation'];
  if (d != null && d.toString().isNotEmpty) {
    final dt = DateTime.tryParse(d.toString());
    if (dt != null) {
      parts.add(
        'Date dernière consultation\n${DateFormat('dd/MM/yyyy').format(dt.toLocal())}',
      );
    }
  }
  return parts.isEmpty ? '—' : parts.join('\n\n');
}

String _formPreviewFromMap(Map<String, dynamic> m) {
  return doctorFormBodyPreview(_fullFormText(m));
}

/// Liste des formulaires de téléconsultation.
class DoctorTeleconsultFormsScreen extends StatefulWidget {
  const DoctorTeleconsultFormsScreen({
    super.key,
    required this.doctorId,
    this.onRefreshHome,
    this.onListConsulted,
  });

  final String doctorId;
  final Future<void> Function()? onRefreshHome;
  final VoidCallback? onListConsulted;

  @override
  State<DoctorTeleconsultFormsScreen> createState() =>
      _DoctorTeleconsultFormsScreenState();
}

class _DoctorTeleconsultFormsScreenState
    extends State<DoctorTeleconsultFormsScreen> {
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
      final list = await ApiService.getDoctorTeleconsultForms(widget.doctorId);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
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
      appBar: AppBar(
        title: const Text('Formulaires'),
        backgroundColor: _sky,
        foregroundColor: Colors.white,
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
                              'Aucun formulaire de téléconsultation reçu.',
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
                          final preview = _formPreviewFromMap(it);
                          final st = it['status']?.toString() ?? 'pending';
                          final wf =
                              it['workflowStatus']?.toString() ?? 'pending';
                          final at = it['createdAt'];
                          final nAtt = (it['attachments'] is List)
                              ? (it['attachments'] as List).length
                              : 0;
                          DateTime? dt;
                          if (at != null) {
                            dt = DateTime.tryParse(at.toString());
                          }

                          return Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () async {
                                final id = it['id']?.toString() ?? '';
                                if (id.isEmpty) return;
                                final changed = await Navigator.of(context)
                                    .push<bool>(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        DoctorTeleconsultFormDetailScreen(
                                      doctorId: widget.doctorId,
                                      formId: id,
                                    ),
                                  ),
                                );
                                if (changed == true && mounted) await _load();
                              },
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
                                          backgroundColor:
                                              _sky.withValues(alpha: 0.15),
                                          accentColor: _sky,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            '👤 $name',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (preview.isNotEmpty &&
                                        preview != '—') ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        '📄 $preview',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.grey.shade800,
                                          fontSize: 13,
                                          height: 1.25,
                                        ),
                                      ),
                                    ],
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
                                    const SizedBox(height: 8),
                                    Text(
                                      'Dossier : ${_formReviewStatusLabel(st)} · Suivi : ${_formWorkflowLabel(wf)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (nAtt > 0)
                                      Text(
                                        '📎 $nAtt pièce(s) jointe(s)',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
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
    );
  }
}

class DoctorTeleconsultFormDetailScreen extends StatefulWidget {
  const DoctorTeleconsultFormDetailScreen({
    super.key,
    required this.doctorId,
    required this.formId,
  });

  final String doctorId;
  final String formId;

  @override
  State<DoctorTeleconsultFormDetailScreen> createState() =>
      _DoctorTeleconsultFormDetailScreenState();
}

class _DoctorTeleconsultFormDetailScreenState
    extends State<DoctorTeleconsultFormDetailScreen> {
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _scheduledSlot;
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ApiService.getTeleconsultFormForDoctor(
        formId: widget.formId,
        doctorId: widget.doctorId,
      );
      if (!mounted) return;
      final scheduled = await _findScheduledSlot(d);
      if (!mounted) return;
      setState(() {
        _data = d;
        _scheduledSlot = scheduled;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _scheduledSlot = null;
        _loading = false;
      });
    }
  }

  DateTime? _slotLocal(Map<String, dynamic> slot) {
    final iso = slot['dateHeure'] ??
        slot['scheduledAt'] ??
        slot['startAt'] ??
        slot['startAtUtc'];
    if (iso is String && iso.isNotEmpty) {
      return DateTime.tryParse(iso)?.toLocal();
    }
    final date = slot['date']?.toString() ?? '';
    final heure = slot['heure']?.toString() ?? '';
    if (date.isNotEmpty && heure.isNotEmpty) {
      return DateTime.tryParse('${date}T$heure:00')?.toLocal();
    }
    return null;
  }

  String _slotId(Map<String, dynamic> slot) =>
      (slot['id'] ??
              slot['_id'] ??
              slot['rendezvousId'] ??
              slot['rendezVousId'] ??
              '')
          .toString()
          .trim();

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _fmtLocal(DateTime d) => DateFormat('dd/MM/yyyy à HH:mm').format(d);

  Future<Map<String, dynamic>?> _findScheduledSlot(
    Map<String, dynamic> formData,
  ) async {
    final patientId = formData['patientId']?.toString() ?? '';
    if (patientId.isEmpty) return null;
    try {
      final rows = await ApiService.getDoctorAgendaRendezVous(
        doctorId: widget.doctorId,
      );
      final formId = widget.formId;
      final filtered = rows.where((raw) {
        final e = Map<String, dynamic>.from(raw);
        final statut = (e['statut'] ?? '').toString().toLowerCase();
        if (statut == 'annule') return false;
        if ((e['patientId']?.toString() ?? '') != patientId) return false;
        final fId = e['formulaireId']?.toString() ?? '';
        if (fId.isNotEmpty) return fId == formId;
        return true;
      }).map((e) => Map<String, dynamic>.from(e)).toList();
      if (filtered.isEmpty) return null;
      final withId = filtered.where((e) => _slotId(e).isNotEmpty).toList();
      if (withId.isEmpty) return null;

      // Priorité 1: RDV lié explicitement au formulaire (formulaireId == formId).
      final exact = withId.where(
        (e) => (e['formulaireId']?.toString() ?? '') == formId,
      );
      if (exact.isNotEmpty) {
        final exactList = exact.toList();
        exactList.sort((a, b) {
          final da = _slotLocal(a);
          final db = _slotLocal(b);
          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;
          return da.compareTo(db);
        });
        return exactList.first;
      }

      // Priorité 2: prochain RDV actif du patient (non terminé/annulé) le plus proche.
      final now = DateTime.now();
      final active = withId.where((e) {
        final s = (e['statutEffectif'] ?? e['statut'] ?? '').toString().toLowerCase();
        return s != 'termine' && s != 'annule';
      }).toList();
      final upcoming = active.where((e) {
        final dt = _slotLocal(e);
        return dt != null && !dt.isBefore(now);
      }).toList();
      if (upcoming.isNotEmpty) {
        upcoming.sort((a, b) => _slotLocal(a)!.compareTo(_slotLocal(b)!));
        return upcoming.first;
      }

      // Priorité 3: fallback sur le dernier RDV connu du patient.
      withId.sort((a, b) {
        final da = _slotLocal(a);
        final db = _slotLocal(b);
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });
      return withId.first;
    } catch (_) {
      return null;
    }
  }

  Future<void> _openAttachmentUrl(String rawUrl) async {
    final url = ApiService.resolveMediaUrl(rawUrl);
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _decideForm(bool accept) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ApiService.decideTeleconsultForm(
        formId: widget.formId,
        doctorId: widget.doctorId,
        accept: accept,
      );
      if (!mounted) return;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              accept
                  ? 'Formulaire accepté.'
                  : 'Formulaire rejeté. Le patient est informé.',
            ),
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scheduleTeleconsult() async {
    if (_busy || _data == null) return;
    final patientId = _data!['patientId']?.toString() ?? '';
    if (patientId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Patient introuvable pour ce dossier.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final patientName = readablePatientName(_data!['patientName']?.toString());
    final photo = _data!['patientPhotoPath']?.toString();

    if (!mounted) return;
    await DoctorTeleconsultAgendaScreen.showAsDialog(
      context,
      doctorId: widget.doctorId,
      patientId: patientId,
      patientName: patientName,
      patientPhotoPath: photo,
      formulaireId: widget.formId,
    );
    if (mounted) await _load();
  }

  Future<Set<String>> _occupiedHoursForDate(
    DateTime day, {
    String? excludeRdvId,
  }) async {
    final out = <String>{};
    try {
      final data = await ApiService.getRendezVousForDate(
        medecinId: widget.doctorId,
        dateYYYYMMDD: _ymd(day),
      );
      final raw = data['rendezvous'];
      if (raw is List) {
        for (final e in raw) {
          if (e is! Map) continue;
          final row = Map<String, dynamic>.from(e);
          final id = (row['id'] ?? row['_id'] ?? '').toString().trim();
          if (excludeRdvId != null && id == excludeRdvId) continue;
          final h = row['heure']?.toString().trim() ?? '';
          if (h.isNotEmpty) out.add(h);
        }
      }
    } catch (_) {}
    return out;
  }

  Future<void> _editScheduledSlot() async {
    final slot = _scheduledSlot;
    if (slot == null || _busy) return;
    final rdvId = _slotId(slot);
    final current = _slotLocal(slot);
    if (rdvId.isEmpty || current == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rendez-vous introuvable.')),
      );
      return;
    }

    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: current.isBefore(now) ? now : current,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2, 12, 31),
      helpText: 'Nouvelle date du rendez-vous',
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      confirmText: 'Enregistrer',
    );
    if (pickedTime == null || !mounted) return;

    final local = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    if (!local.isAfter(DateTime.now().subtract(const Duration(minutes: 1)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choisissez un horaire dans le futur.')),
      );
      return;
    }

    final date = _ymd(local);
    final heure = _hhmm(local);
    final occupied = await _occupiedHoursForDate(local, excludeRdvId: rdvId);
    if (!mounted) return;
    if (occupied.contains(heure)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Le créneau $date à $heure est déjà pris.')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await ApiService.putRendezVous(
        rendezvousId: rdvId,
        medecinId: widget.doctorId,
        dateYYYYMMDD: date,
        heureHHmm: heure,
        startAtIsoUtc: local.toUtc().toIso8601String(),
      );
      if (!mounted) return;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rendez-vous modifié: $date à $heure')),
        );
      }
    } on RendezVousConflictException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Créneau déjà pris: ${e.date ?? date} à ${e.heure ?? heure}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteScheduledSlot() async {
    final slot = _scheduledSlot;
    if (slot == null || _busy) return;
    final rdvId = _slotId(slot);
    if (rdvId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rendez-vous introuvable.')),
      );
      return;
    }
    final motifCtrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Supprimer ce rendez-vous ?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_slotLocal(slot) != null)
                Text('Téléconsultation du ${_fmtLocal(_slotLocal(slot)!)}'),
              const SizedBox(height: 12),
              TextField(
                controller: motifCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Motif (optionnel)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      setState(() => _busy = true);
      await ApiService.deleteRendezVous(
        rendezvousId: rdvId,
        medecinId: widget.doctorId,
        motif: motifCtrl.text.trim(),
      );
      if (!mounted) return;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rendez-vous supprimé')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      motifCtrl.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _replyByMessage() async {
    if (_busy || _data == null) return;
    final patientId = _data!['patientId']?.toString() ?? '';
    final name = _data!['patientName']?.toString() ?? 'Patient';
    if (patientId.isEmpty) return;

    setState(() => _busy = true);
    try {
      await ApiService.patchTeleconsultFormWorkflow(
        formId: widget.formId,
        doctorId: widget.doctorId,
        status: 'replied',
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      final convId = _data!['conversationId']?.toString() ?? '';
      if (convId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Conversation introuvable après enregistrement. Réessayez.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ChatMedecinPage(
            conversationId: convId,
            patientId: patientId,
            patientName: name,
            doctorId: widget.doctorId,
            patientPhotoPath:
                _data!['patientPhotoPath']?.toString(),
          ),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Vous pouvez répondre au patient dans le chat.',
            ),
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
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final review = _data?['status']?.toString() ?? 'pending';
    final wf = _data?['workflowStatus']?.toString() ?? 'pending';
    final slot = _scheduledSlot;
    final slotDt = slot == null ? null : _slotLocal(slot);
    final slotStatus = (slot?['statutEffectif'] ?? slot?['statut'] ?? '')
        .toString()
        .toLowerCase();
    final canManageScheduled =
        slot != null && slotStatus != 'annule' && slotStatus != 'termine';
    final needsDecision = review == 'pending';
    final canWorkflow = review == 'accepted' && wf == 'pending';
    final attachments = _data?['attachments'];
    final attList = attachments is List ? attachments : const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Formulaire — détail'),
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
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          patientAvatarForDoctor(
                            name: _data?['patientName']?.toString() ??
                                'Patient',
                            patientPhotoPath:
                                _data?['patientPhotoPath']?.toString(),
                            radius: 28,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              _data?['patientName']?.toString() ?? 'Patient',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ID dossier : ${widget.formId}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_data?['createdAt'] != null)
                        Text(
                          'Créé le ${DateFormat('dd/MM/yyyy à HH:mm').format(DateTime.parse(_data!['createdAt'].toString()).toLocal())}',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 14,
                          ),
                        ),
                      if (_data?['updatedAt'] != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Mis à jour le ${DateFormat('dd/MM/yyyy à HH:mm').format(DateTime.parse(_data!['updatedAt'].toString()).toLocal())}',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        'Décision dossier : ${_formReviewStatusLabel(review)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: review == 'accepted'
                              ? const Color(0xFF16A34A)
                              : review == 'rejected'
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFFCA8A04),
                        ),
                      ),
                      Text(
                        'Suivi : ${_formWorkflowLabel(wf)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Contenu du formulaire',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _fullFormText(_data!),
                        style: const TextStyle(fontSize: 15, height: 1.35),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Pièces jointes (dossier téléconsultation)',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (attList.isEmpty)
                        Text(
                          'Aucune pièce jointe sur ce dossier.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        )
                      else
                        ...attList.map<Widget>((raw) {
                          final m = Map<String, dynamic>.from(raw as Map);
                          final name =
                              m['filename']?.toString() ?? 'Fichier';
                          final path = m['path']?.toString() ?? '';
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.attach_file_rounded),
                            title: Text(name,
                                style: const TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF2563EB),
                                    decoration: TextDecoration.underline)),
                            onTap: path.isEmpty ? null : () => _openAttachmentUrl(path),
                          );
                        }),
                      const SizedBox(height: 24),
                      if (needsDecision) ...[
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF16A34A),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                                onPressed: _busy ? null : () => _decideForm(true),
                                icon: const Icon(Icons.check_rounded),
                                label: const Text('Accepter le dossier'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFDC2626),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                                onPressed: _busy ? null : () => _decideForm(false),
                                icon: const Icon(Icons.close_rounded),
                                label: const Text('Rejeter'),
                              ),
                            ),
                          ],
                        ),
                      ] else if (review == 'rejected')
                        const Text(
                          'Ce dossier a été rejeté. Aucune autre action sur ce formulaire.',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFDC2626),
                          ),
                        )
                      else if (canWorkflow) ...[
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: _busy ? null : _scheduleTeleconsult,
                            icon: const Icon(Icons.videocam_rounded),
                            label: const Text('Téléconsultation'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF16A34A),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: _busy ? null : _replyByMessage,
                            icon: const Icon(Icons.chat_rounded),
                            label: const Text('Répondre par message'),
                          ),
                        ),
                      ] else if (wf == 'scheduled') ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Rendez-vous planifié',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1D4ED8),
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (slotDt != null)
                                Text(
                                  'Date/heure : ${_fmtLocal(slotDt)}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              else
                                const Text(
                                  'Rendez-vous existant mais date indisponible.',
                                  style: TextStyle(fontSize: 14),
                                ),
                              if (slot == null) ...[
                                const SizedBox(height: 8),
                                const Text(
                                  'Impossible de retrouver le rendez-vous dans l’agenda.',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ],
                              if (slot != null) ...[
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: (_busy || !canManageScheduled)
                                            ? null
                                            : _editScheduledSlot,
                                        icon: const Icon(Icons.edit_rounded),
                                        label: const Text('Modifier'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: const Color(0xFFDC2626),
                                          foregroundColor: Colors.white,
                                        ),
                                        onPressed: (_busy || !canManageScheduled)
                                            ? null
                                            : _deleteScheduledSlot,
                                        icon: const Icon(Icons.delete_outline_rounded),
                                        label: const Text('Supprimer'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ] else
                        Text(
                          'Suivi final : ${_formWorkflowLabel(wf)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: wf == 'scheduled'
                                ? const Color(0xFF2563EB)
                                : const Color(0xFF16A34A),
                          ),
                        ),
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
}
