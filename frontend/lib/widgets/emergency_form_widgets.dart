import 'package:flutter/material.dart';

import '../data/emergency_symptoms_catalog.dart';
import '../headsapp_theme.dart';
import 'gradient_button.dart';

const _pageBackground = Color(0xFFF5F7FA);
const _navy = Color(0xFF1A3B5D);
const _cardText = Color(0xFF2D3E50);
const _categoryColor = Color(0xFF8A9AAF);
const _greetingColor = Color(0xFF9AA8BA);
const _iconIdle = Color(0xFF4A6B8A);
const _infoColor = Color(0xFF90A4BE);
const _selectedRed = Color(0xFFEF4444);
const _selectedRedBg = Color(0xFFFFF8F8);
const _selectedGreen = Color(0xFF22C55E);
const _selectedGreenBg = Color(0xFFF4FFF7);

const double _cardHeight = 76;
const double _cardRadius = 20;

class EmergencyFormColors {
  static const background = _pageBackground;
  static const cardText = _cardText;
  static const category = _categoryColor;
}

/// Bouton « Confirmer » en dégradé rose → bleu.
class EmergencyConfirmButton extends StatelessWidget {
  const EmergencyConfirmButton({
    super.key,
    required this.onPressed,
    this.loading = false,
  });

  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return HeadsAppGradientButton(
      label: 'Confirmer',
      onPressed: onPressed,
      loading: loading,
    );
  }
}

class EmergencyFormHeader extends StatelessWidget {
  const EmergencyFormHeader({
    super.key,
    required this.patientName,
    this.onBack,
    this.canGoBack = true,
  });

  final String patientName;
  final VoidCallback? onBack;
  final bool canGoBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: canGoBack ? onBack : null,
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              color: _navy,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            const Spacer(),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Bonjour $patientName',
          style: theme.textTheme.titleMedium?.copyWith(
            color: _greetingColor,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Complétez ce formulaire pour nous aider à comprendre votre situation. Vos données restent confidentielles.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: HeadsAppColors.textTertiary,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class EmergencySectionTitle extends StatelessWidget {
  const EmergencySectionTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _navy,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: _navy.withValues(alpha: 0.22),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.medical_services_outlined,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Text(
          'Symptômes d\'urgences',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: _navy,
                letterSpacing: -0.3,
              ),
        ),
      ],
    );
  }
}

class EmergencyCategoryHeader extends StatelessWidget {
  const EmergencyCategoryHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 18),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: _categoryColor,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
      ),
    );
  }
}

class EmergencySymptomCard extends StatelessWidget {
  const EmergencySymptomCard({
    super.key,
    required this.symptom,
    required this.selected,
    required this.onTap,
    required this.onInfo,
  });

  final EmergencySymptom symptom;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final isNone = symptom.isNoneOption;
    final Color backgroundColor;
    final Color iconColor;
    final Color textColor;
    final List<BoxShadow> shadows;
    final Border? border;

    if (selected) {
      if (isNone) {
        backgroundColor = _selectedGreenBg;
        iconColor = _selectedGreen;
        textColor = const Color(0xFF166534);
        border = Border.all(color: _selectedGreen.withValues(alpha: 0.55), width: 1.5);
      } else {
        backgroundColor = _selectedRedBg;
        iconColor = _selectedRed;
        textColor = const Color(0xFF991B1B);
        border = Border.all(color: _selectedRed.withValues(alpha: 0.55), width: 1.5);
      }
      shadows = [
        BoxShadow(
          color: iconColor.withValues(alpha: 0.14),
          blurRadius: 14,
          offset: const Offset(0, 5),
        ),
      ];
    } else {
      backgroundColor = Colors.white;
      iconColor = _iconIdle;
      textColor = _cardText;
      border = null;
      shadows = [
        BoxShadow(
          color: const Color(0xFF1A3B5D).withValues(alpha: 0.07),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ];
    }

    return SizedBox(
      height: _cardHeight,
      width: double.infinity,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(_cardRadius),
          border: border,
          boxShadow: shadows,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(_cardRadius),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 48, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                      Icon(symptom.icon, size: 28, color: iconColor),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          symptom.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: textColor,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                                letterSpacing: -0.1,
                              ),
                        ),
                      ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 12,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onInfo,
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.info_outline_rounded,
                      size: 20,
                      color: _infoColor,
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
}

class EmergencySymptomCategorySection extends StatelessWidget {
  const EmergencySymptomCategorySection({
    super.key,
    required this.category,
    required this.selectedKeys,
    required this.onToggle,
    required this.onInfo,
  });

  final EmergencySymptomCategory category;
  final Set<String> selectedKeys;
  final ValueChanged<String> onToggle;
  final ValueChanged<EmergencySymptom> onInfo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EmergencyCategoryHeader(title: category.title),
        ...category.symptoms.map(
          (symptom) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: EmergencySymptomCard(
              symptom: symptom,
              selected: selectedKeys.contains(symptom.key),
              onTap: () => onToggle(symptom.key),
              onInfo: () => onInfo(symptom),
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> showEmergencySymptomInfo(
  BuildContext context,
  EmergencySymptom symptom,
) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (dialogContext) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _navy.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                symptom.icon,
                color: _navy,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              symptom.label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _cardText,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              symptom.info,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: HeadsAppColors.textSecondary,
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: HeadsAppColors.brandPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Compris'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
