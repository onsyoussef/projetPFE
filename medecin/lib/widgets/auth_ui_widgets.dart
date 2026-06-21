import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../headsapp_theme.dart';
import 'headsapp_logo_text.dart';

const _authInputRadius = 14.0;
const _authMaxWidth = 420.0;
const _logoAsset = 'assets/images/headsapp_logo.png';

/// Fond blanc centré pour les écrans d'authentification.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.child,
    this.showBackButton = false,
    this.onBack,
    this.backgroundColor = Colors.white,
  });

  final Widget child;
  final bool showBackButton;
  final VoidCallback? onBack;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 40),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _authMaxWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showBackButton) ...[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: AuthBackLink(onPressed: onBack),
                          ),
                          const SizedBox(height: 8),
                        ],
                        child,
                      ],
                    ),
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

/// Logo HeadsApp (carré arrondi + nom de marque).
class AuthBrandHeader extends StatelessWidget {
  const AuthBrandHeader({
    super.key,
    this.icon = Icons.face_rounded,
    this.iconBackgroundColor,
    this.centered = true,
    this.useLogoAsset = false,
    this.vertical = false,
  });

  final IconData icon;
  final Color? iconBackgroundColor;
  final bool centered;
  final bool useLogoAsset;
  final bool vertical;

  Widget _logoBox() {
    if (useLogoAsset) {
      return Container(
        height: 72,
        width: 72,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: HeadsAppColors.brandPrimary.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Image.asset(_logoAsset, fit: BoxFit.contain),
      );
    }

    return Container(
      height: 44,
      width: 44,
      decoration: BoxDecoration(
        color: iconBackgroundColor ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: iconBackgroundColor == null
            ? Border.all(
                color: HeadsAppColors.brandPrimary.withValues(alpha: 0.2),
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: HeadsAppColors.brandPrimary.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(
        icon,
        color: iconBackgroundColor != null ? Colors.white : HeadsAppColors.brandPrimary,
        size: 26,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = const HeadsAppLogoText();

    if (vertical) {
      final column = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _logoBox(),
          const SizedBox(height: 12),
          title,
        ],
      );
      return centered ? Center(child: column) : column;
    }

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _logoBox(),
        const SizedBox(width: 10),
        title,
      ],
    );

    if (centered) {
      return Center(child: row);
    }
    return row;
  }
}

class AuthTitleBlock extends StatelessWidget {
  const AuthTitleBlock({
    super.key,
    required this.title,
    this.subtitle,
    this.centered = false,
  });

  final String title;
  final String? subtitle;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final align = centered ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          title,
          textAlign: align,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: HeadsAppColors.textPrimary,
                letterSpacing: -0.4,
              ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            textAlign: align,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: HeadsAppColors.textSecondary,
                  height: 1.45,
                ),
          ),
        ],
      ],
    );
  }
}

class AuthLabeledField extends StatelessWidget {
  const AuthLabeledField({
    super.key,
    required this.label,
    required this.child,
    this.labelUppercase = false,
    this.labelColor,
  });

  final String label;
  final Widget child;
  final bool labelUppercase;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final displayLabel = labelUppercase ? label.toUpperCase() : label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          displayLabel,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: labelColor ??
                    (labelUppercase
                        ? HeadsAppColors.textTertiary
                        : const Color(0xFF374151)),
                fontWeight: FontWeight.w700,
                letterSpacing: labelUppercase ? 0.6 : 0,
                fontSize: labelUppercase ? 11 : 14,
              ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

InputDecoration authInputDecoration({
  required String hintText,
  required IconData prefixIcon,
  Widget? suffixIcon,
  Color? fillColor,
}) {
  return InputDecoration(
    hintText: hintText,
    prefixIcon: Icon(
      prefixIcon,
      color: HeadsAppColors.textTertiary,
      size: 20,
    ),
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: fillColor ?? HeadsAppColors.authInputFill,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_authInputRadius),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_authInputRadius),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_authInputRadius),
      borderSide: const BorderSide(
        color: HeadsAppColors.authGradientEnd,
        width: 1.4,
      ),
    ),
    hintStyle: const TextStyle(color: HeadsAppColors.textTertiary),
  );
}

/// Bouton principal en dégradé cyan → bleu (écran de connexion).
class AuthSolidButton extends StatelessWidget {
  const AuthSolidButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: enabled
            ? const LinearGradient(
                colors: [
                  HeadsAppColors.authGradientStart,
                  HeadsAppColors.authGradientEnd,
                ],
              )
            : null,
        color: enabled ? null : HeadsAppColors.textTertiary.withValues(alpha: 0.35),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: HeadsAppColors.authGradientEnd.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: double.infinity,
            height: HeadsAppMetrics.buttonHeight,
            child: Center(
              child: loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthFooterLink extends StatelessWidget {
  const AuthFooterLink({
    super.key,
    required this.prompt,
    required this.actionLabel,
    required this.onPressed,
  });

  final String prompt;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          prompt,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: HeadsAppColors.textSecondary,
              ),
        ),
        TextButton(
          onPressed: onPressed,
          child: Text(
            actionLabel,
            style: const TextStyle(
              color: HeadsAppColors.brandPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class AuthBackLink extends StatelessWidget {
  const AuthBackLink({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
      icon: const Icon(
        Icons.arrow_back_rounded,
        size: 18,
        color: HeadsAppColors.brandPrimary,
      ),
      label: const Text(
        'Retour',
        style: TextStyle(
          color: HeadsAppColors.brandPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }
}

/// Barre de progression multi-étapes (inscription).
class AuthSignupProgressBar extends StatelessWidget {
  const AuthSignupProgressBar({
    super.key,
    required this.currentStep,
    this.totalSteps = 4,
  });

  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    final progress = ((currentStep + 1) / totalSteps).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: progress,
        minHeight: 5,
        backgroundColor: const Color(0xFFE5E7EB),
        valueColor: const AlwaysStoppedAnimation<Color>(HeadsAppColors.brandPrimary),
      ),
    );
  }
}

/// Carte blanche flottante pour les formulaires d'inscription.
class AuthFormCard extends StatelessWidget {
  const AuthFormCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 24, 20, 24),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Lien texte centré (Précédent / Retour).
class AuthTextLink extends StatelessWidget {
  const AuthTextLink({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: onPressed,
        child: Text(
          label,
          style: const TextStyle(
            color: HeadsAppColors.brandPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

InputDecoration authDropdownDecoration({
  required String hintText,
  IconData? prefixIcon,
}) {
  return InputDecoration(
    hintText: hintText,
    prefixIcon: prefixIcon != null
        ? Icon(prefixIcon, color: HeadsAppColors.textTertiary, size: 20)
        : null,
    suffixIcon: const Icon(
      Icons.keyboard_arrow_down_rounded,
      color: HeadsAppColors.textTertiary,
    ),
    filled: true,
    fillColor: HeadsAppColors.authInputFill,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_authInputRadius),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_authInputRadius),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_authInputRadius),
      borderSide: const BorderSide(
        color: HeadsAppColors.authGradientEnd,
        width: 1.4,
      ),
    ),
    hintStyle: const TextStyle(color: HeadsAppColors.textTertiary),
  );
}

/// Encadré d'information (conseils validation document).
class AuthInfoBox extends StatelessWidget {
  const AuthInfoBox({
    super.key,
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HeadsAppColors.authInfoBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: HeadsAppColors.brandPrimary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: HeadsAppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: HeadsAppColors.textSecondary,
                        height: 1.4,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Icône centrée dans un carré bleu clair (écrans reset / OTP).
class AuthIconHeader extends StatelessWidget {
  const AuthIconHeader({
    super.key,
    required this.icon,
    this.size = 60,
    this.iconSize = 28,
  });

  final IconData icon;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        height: size,
        width: size,
        decoration: BoxDecoration(
          color: HeadsAppColors.brandHighlight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          icon,
          color: HeadsAppColors.brandPrimary,
          size: iconSize,
        ),
      ),
    );
  }
}

class AuthSuccessIcon extends StatelessWidget {
  const AuthSuccessIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 100,
        height: 100,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: HeadsAppColors.success.withValues(alpha: 0.12),
              ),
            ),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: HeadsAppColors.success.withValues(alpha: 0.22),
              ),
            ),
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: HeadsAppColors.success,
              ),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 30),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthOtpBoxes extends StatelessWidget {
  const AuthOtpBoxes({
    super.key,
    required this.controllers,
    required this.focusNodes,
    this.length = 6,
    this.onChanged,
  });

  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final int length;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(length, (index) {
        return SizedBox(
          width: length > 4 ? 46 : 56,
          child: TextField(
            controller: controllers[index],
            focusNode: focusNodes[index],
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 1,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: HeadsAppColors.textPrimary,
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              counterText: '',
              filled: true,
              fillColor: HeadsAppColors.authInputFill,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(
                  color: HeadsAppColors.authGradientEnd,
                  width: 2,
                ),
              ),
            ),
            onChanged: (val) {
              if (val.isNotEmpty && index < length - 1) {
                focusNodes[index + 1].requestFocus();
              } else if (val.isEmpty && index > 0) {
                focusNodes[index - 1].requestFocus();
              }
              onChanged?.call();
            },
          ),
        );
      }),
    );
  }
}

/// Icône de sécurité (étape mot de passe).
class AuthSecurityHeader extends StatelessWidget {
  const AuthSecurityHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 64,
          width: 64,
          decoration: BoxDecoration(
            color: HeadsAppColors.brandHighlight,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.lock_outline_rounded,
            color: HeadsAppColors.brandPrimary,
            size: 32,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Sécurisez votre compte',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: HeadsAppColors.textPrimary,
                letterSpacing: -0.4,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Dernière étape pour finaliser votre inscription sur HeadsApp.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: HeadsAppColors.textSecondary,
                height: 1.45,
              ),
        ),
      ],
    );
  }
}
