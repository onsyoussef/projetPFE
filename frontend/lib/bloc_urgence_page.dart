import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/emergency_symptoms_catalog.dart';
import 'espace_patient_page.dart';
import 'headsapp_theme.dart';
import 'services/api_service.dart';
import 'services/push_notification_service.dart';
import 'utils/patient_ui_utils.dart';
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
  static const String _accessDisabledMessage =
      "L'accès à cet espace est actuellement suspendu en raison d'une alerte active. Veuillez réessayer une fois l'alerte levée.";
  static const String _accessDisabledTitle = 'Accès temporairement désactivé';
  static const String _selectSymptomMessage =
      'Veuillez sélectionner au moins un symptôme.';

  final Set<String> _symptomes = {};
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
          _symptomes.add(EmergencySymptomsCatalog.keyAucun);
        }
      } else {
        _symptomes.remove(EmergencySymptomsCatalog.keyAucun);
        if (_symptomes.contains(key)) {
          _symptomes.remove(key);
        } else {
          _symptomes.add(key);
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
      onRetour: () async {
        Navigator.of(context).pop();
        await _enregistrerAlerteUrgence();
        if (!mounted) return;
        setState(() {
          _alerteUrgenceAcceptee = true;
          _formulaireUrgenceMasque = true;
        });
      },
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
              if (_formulaireUrgenceMasque && _alerteUrgenceAcceptee)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 320),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            final slide = Tween<Offset>(
                              begin: const Offset(0, 0.05),
                              end: Offset.zero,
                            ).animate(animation);
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: slide,
                                child: child,
                              ),
                            );
                          },
                          child: _ResultCard(
                            key: const ValueKey('blocked-access-card'),
                            icon: Icons.info_outline_rounded,
                            iconColor: const Color(0xFFEA580C),
                            backgroundColor: const Color(0xFFFFF7ED),
                            title: _accessDisabledTitle,
                            message: _accessDisabledMessage,
                            buttonLabel: 'Se déconnecter',
                            onPressed: _deconnecterDepuisBlocage,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
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

  Future<void> _deconnecterDepuisBlocage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('patientId');
    await prefs.remove('patientName');
    await PushNotificationService.instance.unregisterCurrentDevice();
    await prefs.remove('patient_jwt');
    ApiService.setJwtToken(null);
    await prefs.remove('lastRoute');
    await prefs.remove('chatDoctorId');
    await prefs.remove('chatDoctorName');
    await prefs.remove('chatDoctorPhotoPath');
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    this.title,
    required this.message,
    this.buttonLabel,
    this.onPressed,
  });

  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final String? title;
  final String message;
  final String? buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: iconColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: iconColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null) ...[
                      Text(
                        title!,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: const Color(0xFF9A3412),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      message,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF334155),
                            height: 1.45,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (buttonLabel != null && onPressed != null) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onPressed,
                style: FilledButton.styleFrom(
                  backgroundColor: HeadsAppColors.brandPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(buttonLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
