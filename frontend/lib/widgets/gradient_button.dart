import 'package:flutter/material.dart';

import '../headsapp_theme.dart';

/// Bouton principal pill : dégradé rose → bleu (maquette HeadsApp).
class HeadsAppGradientButton extends StatelessWidget {
  const HeadsAppGradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.showArrow = false,
    this.height = HeadsAppMetrics.buttonHeight,
    this.borderRadius = 999,
    this.fontSize = 16,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final bool showArrow;
  final double height;
  final double borderRadius;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: enabled ? HeadsAppColors.primaryButtonGradient : null,
        color: enabled ? null : HeadsAppColors.textTertiary.withValues(alpha: 0.35),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: HeadsAppColors.authGradientEnd.withValues(alpha: 0.28),
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
          borderRadius: BorderRadius.circular(borderRadius),
          child: SizedBox(
            width: double.infinity,
            height: height,
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
                        if (icon != null) ...[
                          Icon(icon, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          label,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: fontSize,
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

@Deprecated('Utiliser HeadsAppGradientButton')
typedef GradientButton = HeadsAppGradientButton;
