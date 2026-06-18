import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../headsapp_theme.dart';

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
    final title = Text(
      'HeadsApp',
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: const Color(0xFF2459A8),
            fontWeight: FontWeight.w800,
            fontSize: vertical ? 22 : null,
            letterSpacing: -0.3,
          ),
    );

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
    this.centered = true,
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
  });

  final String label;
  final Widget child;
  final bool labelUppercase;

  @override
  Widget build(BuildContext context) {
    final displayLabel = labelUppercase ? label.toUpperCase() : label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          displayLabel,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: labelUppercase
                    ? HeadsAppColors.textTertiary
                    : const Color(0xFF374151),
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

/// Encadré des règles de mot de passe (inscription).
class AuthPasswordRulesBox extends StatelessWidget {
  const AuthPasswordRulesBox({super.key});

  static const _rules = [
    'Minimum 8 caractères',
    'Au moins 1 majuscule (A-Z)',
    'Au moins 1 minuscule (a-z)',
    'Au moins 1 chiffre (0-9)',
    'Au moins 1 caractère spécial (!@#...)',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6F8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Règles du mot de passe :',
            style: TextStyle(
              color: Color(0xFF374151),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          for (final rule in _rules)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '- $rule',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bouton principal bleu plein, forme pilule (écran de connexion).
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
        borderRadius: BorderRadius.circular(999),
        color: enabled ? const Color(0xFF2459A8) : HeadsAppColors.textTertiary.withValues(alpha: 0.35),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: const Color(0xFF2459A8).withValues(alpha: 0.28),
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
          borderRadius: BorderRadius.circular(999),
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

/// Bouton principal en dégradé lavande → bleu, forme pilule.
class AuthGradientButton extends StatelessWidget {
  const AuthGradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.showArrow = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
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
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(999),
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
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (showArrow) ...[
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ],
                      ],
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

class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Divider(color: HeadsAppColors.border, height: 1),
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

/// Carte blanche avec halo rose en haut à droite (écran reset).
class AuthGlowCard extends StatelessWidget {
  const AuthGlowCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(24, 28, 24, 24),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: -20,
          right: -10,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFFE8B4C8).withValues(alpha: 0.35),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: HeadsAppColors.border.withValues(alpha: 0.6)),
            boxShadow: [
              BoxShadow(
                color: HeadsAppColors.brandPrimary.withValues(alpha: 0.08),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ],
    );
  }
}

class AuthInfoBox extends StatelessWidget {
  const AuthInfoBox({super.key, required this.message});

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
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: HeadsAppColors.textSecondary,
                    height: 1.4,
                  ),
            ),
          ),
        ],
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
