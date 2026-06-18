import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/emergency_symptoms_catalog.dart';
import 'espace_patient_page.dart';
import 'headsapp_theme.dart';
import 'services/api_service.dart';
import 'utils/patient_ui_utils.dart';
import 'screens/emergency_dashboard_screen.dart';
import 'services/emergency_mode_service.dart';
import 'widgets/emergency_access_granted_screen.dart';
import 'widgets/emergency_alert_screen.dart';
import 'widgets/emergency_form_widgets.dart';

class BlocUrgencePage extends StatefulWidget {
  const BlocUrgencePage({
    super.key,
    required this.patientName,
    this.patientId,
  });

  final String patientName;
  final String? patientId;

  @override
  State<BlocUrgencePage> createState() => _BlocUrgencePageState();
}

class _BlocUrgencePageState extends State<BlocUrgencePage> {
  static const String _saveErrorMessage =
      "Enregistrement du formulaire d'urgence impossible.";
  static const String _selectSymptomMessage =
      'Veuillez sélectionner au moins un symptôme.';

  final Set<String> _symptomes = {};
  final Map<String, DateTime> _symptomeHorodatages = {};
  bool _alerteUrgenceAcceptee = false;
  bool _formulaireUrgenceMasque = false;

  bool get _aUnSymptomeUrgent =>
      _symptomes.any((s) => s != EmergencySymptomsCatalog.keyAucun);
  bool get _aucunSymptome =>
      _symptomes.contains(EmergencySymptomsCatalog.keyAucun);

  void _toggleSymptome(String key) {
    setState(() {
      if (key == EmergencySymptomsCatalog.keyAucun) {
        if (_symptomes.contains(EmergencySymptomsCatalog.keyAucun)) {
          _symptomes.remove(EmergencySymptomsCatalog.keyAucun);
        } else {
          _symptomes.clear();
          _symptomeHorodatages.clear();
          _symptomes.add(EmergencySymptomsCatalog.keyAucun);
        }
      } else {
        _symptomes.remove(EmergencySymptomsCatalog.keyAucun);
        if (_symptomes.contains(key)) {
          _symptomes.remove(key);
          _symptomeHorodatages.remove(key);
        } else {
          _symptomes.add(key);
          _symptomeHorodatages[key] = DateTime.now();
        }
      }
    });
  }

  Future<void> _montrerAccesAutorise() async {
    if (!mounted) return;
    await EmergencyAccessGrantedScreen.show(
      context,
      onContinue: () async {
        Navigator.of(context).pop();
        await _enregistrerFormulaireSansUrgence();
        if (!mounted) return;
        await _naviguerVersEspace();
      },
    );
  }

  Future<void> _enregistrerFormulaireSansUrgence() async {
    if (widget.patientId == null || widget.patientId!.isEmpty || !_aucunSymptome) {
      return;
    }
    try {
      await ApiService.saveFormulaireUrgence(
        patientId: widget.patientId!,
        symptomes: _symptomes
            .map(EmergencySymptomsCatalog.labelForKey)
            .toList(),
        alerteAcceptee: false,
      );
    } catch (_) {
      if (!mounted) return;
      _showSaveErrorSnackBar();
    }
  }

  Future<void> _montrerAlerte() async {
    if (!mounted) return;
    await EmergencyAlertScreen.show(
      context,
      onAcknowledge: () async {
        Navigator.of(context).pop();
        await _enregistrerAlerteUrgence();
        if (!mounted) return;
        await _activerModeUrgence();
      },
    );
  }

  Future<void> _activerModeUrgence() async {
    final symptoms = _symptomes
        .where((key) => key != EmergencySymptomsCatalog.keyAucun)
        .map((key) {
          final at = _symptomeHorodatages[key] ?? DateTime.now();
          return {
            'label': EmergencySymptomsCatalog.labelForKey(key),
            'at': at.toIso8601String(),
          };
        })
        .toList();

    await EmergencyModeService.activate(symptoms: symptoms);
    if (!mounted) return;
    setState(() {
      _alerteUrgenceAcceptee = true;
      _formulaireUrgenceMasque = true;
    });
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => EmergencyDashboardScreen(
          patientName: widget.patientName,
          patientId: widget.patientId!,
        ),
      ),
    );
  }

  Future<void> _enregistrerAlerteUrgence() async {
    if (widget.patientId == null ||
        widget.patientId!.isEmpty ||
        !_aUnSymptomeUrgent) {
      return;
    }

    try {
      await ApiService.saveFormulaireUrgence(
        patientId: widget.patientId!,
        symptomes: _symptomes
            .map(EmergencySymptomsCatalog.labelForKey)
            .toList(),
        alerteAcceptee: true,
      );
    } catch (_) {
      if (!mounted) return;
      _showSaveErrorSnackBar();
    }
  }

  void _showSaveErrorSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(_saveErrorMessage),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSelectSymptomSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(_selectSymptomMessage),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _validerFormulaireUrgence() async {
    if (_symptomes.isEmpty) {
      _showSelectSymptomSnackBar();
      return;
    }

    if (_aucunSymptome) {
      await _montrerAccesAutorise();
      return;
    }

    if (_aUnSymptomeUrgent && !_alerteUrgenceAcceptee) {
      await _montrerAlerte();
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = readablePatientName(widget.patientName);

    return PopScope(
      canPop: !_alerteUrgenceAcceptee,
      child: Scaffold(
        backgroundColor: EmergencyFormColors.background,
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              if (!_formulaireUrgenceMasque) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: EmergencyFormHeader(
                      patientName: displayName,
                      canGoBack: !_alerteUrgenceAcceptee,
                      onBack: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                    child: const EmergencySectionTitle(),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final category =
                            EmergencySymptomsCatalog.categories[index];
                        return EmergencySymptomCategorySection(
                          category: category,
                          selectedKeys: _symptomes,
                          onToggle: _toggleSymptome,
                          onInfo: (symptom) =>
                              showEmergencySymptomInfo(context, symptom),
                        );
                      },
                      childCount: EmergencySymptomsCatalog.categories.length,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10, top: 8),
                          child: Text(
                            'Aucun symptôme',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: EmergencyFormColors.category,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        EmergencySymptomCard(
                          symptom: EmergencySymptomsCatalog.noneSymptom,
                          selected: _symptomes
                              .contains(EmergencySymptomsCatalog.keyAucun),
                          onTap: () =>
                              _toggleSymptome(EmergencySymptomsCatalog.keyAucun),
                          onInfo: () => showEmergencySymptomInfo(
                            context,
                            EmergencySymptomsCatalog.noneSymptom,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'En validant ce formulaire, vous acceptez que HeadsApp analyse ces données à des fins d\'orientation médicale non urgente.',
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: HeadsAppColors.textTertiary,
                                    height: 1.4,
                                  ),
                        ),
                        const SizedBox(height: 16),
                        EmergencyConfirmButton(
                          onPressed: _validerFormulaireUrgence,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _naviguerVersEspace() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastRoute', 'espace_patient');
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => EspacePatientPage(
          patientName: widget.patientName,
          patientId: widget.patientId ?? '',
        ),
      ),
    );
  }
}
