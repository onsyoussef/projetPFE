import 'package:flutter/material.dart';

/// Logo texte « HeadsApp » : « Heads » navy + « App » cyan (maquette dashboard).
class HeadsAppLogoText extends StatelessWidget {
  const HeadsAppLogoText({
    super.key,
    this.fontSize,
    this.fontWeight = FontWeight.w800,
    this.letterSpacing = -0.3,
    this.textAlign,
  });

  static const Color headsNavy = Color(0xFF1A3B5D);
  static const Color appCyan = Color(0xFF2BB8E4);

  final double? fontSize;
  final FontWeight fontWeight;
  final double letterSpacing;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      fontWeight: fontWeight,
      fontSize: fontSize ?? Theme.of(context).textTheme.titleLarge?.fontSize,
      letterSpacing: letterSpacing,
      height: 1.1,
    );

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'Heads',
            style: baseStyle.copyWith(color: headsNavy),
          ),
          TextSpan(
            text: 'App',
            style: baseStyle.copyWith(color: appCyan),
          ),
        ],
      ),
      textAlign: textAlign,
    );
  }
}
