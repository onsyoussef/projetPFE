import 'package:flutter/material.dart';

import '../headsapp_theme.dart';

/// Bouton CTA formulaire / chat ([HeadsAppColors.chatPrimaryButton]).
///
/// - **[compact]** : pillule centrée (~235×40, rayon 22) — cartes « Remplir formulaire ».
/// - sinon : bandeau pleine largeur (min 52 px, rayon 12) — envoi demande / formulaire.
class HeadsFormCtaButton extends StatelessWidget {
  const HeadsFormCtaButton({
    super.key,
    required this.onPressed,
    this.icon,
    required this.label,
    this.isLoading = false,
    this.expand = true,
    this.compact = false,
  });

  final VoidCallback? onPressed;
  final IconData? icon;
  final String label;
  final bool isLoading;
  final bool expand;
  /// Style carte « Demande acceptée » : centré, largeur fixe, pillule.
  final bool compact;

  static const double _fullMinH = 52;
  static const double _compactRadius = 22;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _buildCompact(context);
    }
    return _buildFullWidth(context);
  }

  Widget _buildCompact(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    final bg = HeadsAppColors.chatPrimaryButton;
    final ic = icon ?? Icons.edit_note_rounded;

    final child = Material(
      color: enabled ? bg : bg.withValues(alpha: 0.45),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      borderRadius: BorderRadius.circular(_compactRadius),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(_compactRadius),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: 235,
            maxWidth: 235,
            minHeight: 40,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(ic, size: 18, color: Colors.white),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _compactLabelStyle,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );

    return Align(alignment: Alignment.center, child: child);
  }

  static const TextStyle _compactLabelStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    letterSpacing: 0.4,
  );

  Widget _buildFullWidth(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    final bg = HeadsAppColors.chatPrimaryButton;

    Widget inner;
    if (isLoading) {
      inner = const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: Colors.white,
        ),
      );
    } else if (icon != null) {
      inner = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: Colors.white),
          const SizedBox(width: 8),
          if (expand)
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: _fullLabelStyle,
              ),
            )
          else
            Text(label, style: _fullLabelStyle),
        ],
      );
    } else {
      inner = Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: _fullLabelStyle,
      );
    }

    final content = Material(
      color: enabled ? bg : bg.withValues(alpha: 0.45),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _fullMinH),
            child: Center(child: inner),
          ),
        ),
      ),
    );

    if (expand) {
      return SizedBox(
        width: double.infinity,
        child: content,
      );
    }
    return Align(alignment: Alignment.center, child: content);
  }

  static const TextStyle _fullLabelStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    letterSpacing: 0.1,
  );
}
