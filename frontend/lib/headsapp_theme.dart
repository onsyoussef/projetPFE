import 'package:flutter/material.dart';

final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier<ThemeMode>(
  ThemeMode.light,
);

class HeadsAppColors {
  static const Color brandPrimary = Color(0xFF265AA6);
  /// Boutons d’action principaux (chat : « Remplir formulaire », envoi formulaire, etc.).
  static const Color chatPrimaryButton = Color(0xFF1A3D5F);
  @Deprecated('Utiliser chatPrimaryButton pour les CTA chat / formulaire.')
  static const Color brandFormCta = Color(0xFF5DADE2);
  static const Color brandAccent = Color(0xFF00BAEE);
  static const Color brandPrimaryDark = Color(0xFF1F4A88);
  static const Color brandHighlight = Color(0xFFEEF6FF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFF4F8FD);
  static const Color surfaceSoft = Color(0xFFEFF6FF);
  static const Color surfaceMuted = Color(0xFFF8FBFF);
  static const Color textPrimary = Color(0xFF1A2740);
  static const Color textSecondary = Color(0xFF5F6F86);
  static const Color textTertiary = Color(0xFF7B8BA3);
  static const Color border = Color(0xFFD8E5F5);
  static const Color success = Color(0xFF1F9D68);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFE14D65);

  /// Écrans d'authentification (login, inscription, reset).
  static const Color authInputFill = Color(0xFFF3F4F6);
  static const Color authGradientStart = Color(0xFFE57399);
  static const Color authGradientEnd = Color(0xFF2C539E);
  static const Color authInfoBackground = Color(0xFFEEF4FB);
}

class HeadsAppMetrics {
  static const double pagePadding = 20;
  static const double sectionSpacing = 18;
  static const double cardRadius = 24;
  static const double controlRadius = 18;
  static const double compactRadius = 14;
  static const double buttonHeight = 54;
}

class HeadsAppTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: HeadsAppColors.brandPrimary,
        primary: HeadsAppColors.brandPrimary,
        secondary: HeadsAppColors.brandAccent,
        surface: HeadsAppColors.surface,
      ),
      scaffoldBackgroundColor: HeadsAppColors.surfaceAlt,
      fontFamily: 'Roboto',
    );

    final textTheme = base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        color: HeadsAppColors.textPrimary,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        color: HeadsAppColors.textPrimary,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        color: HeadsAppColors.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        color: HeadsAppColors.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        color: HeadsAppColors.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        color: HeadsAppColors.textPrimary,
        height: 1.45,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        color: HeadsAppColors.textSecondary,
        height: 1.45,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        color: HeadsAppColors.textTertiary,
        height: 1.35,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        color: HeadsAppColors.textPrimary,
        fontWeight: FontWeight.w700,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      iconTheme: const IconThemeData(color: HeadsAppColors.textPrimary),
      appBarTheme: const AppBarTheme(
        backgroundColor: HeadsAppColors.surface,
        foregroundColor: HeadsAppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: HeadsAppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HeadsAppMetrics.cardRadius),
          side: const BorderSide(color: HeadsAppColors.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: HeadsAppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HeadsAppMetrics.cardRadius),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: HeadsAppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: const DividerThemeData(
        color: HeadsAppColors.border,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: HeadsAppColors.textPrimary,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: HeadsAppColors.surfaceMuted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HeadsAppMetrics.controlRadius),
          borderSide: const BorderSide(color: HeadsAppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HeadsAppMetrics.controlRadius),
          borderSide: const BorderSide(color: HeadsAppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HeadsAppMetrics.controlRadius),
          borderSide: const BorderSide(
            color: HeadsAppColors.brandPrimary,
            width: 1.4,
          ),
        ),
        hintStyle: const TextStyle(color: HeadsAppColors.textTertiary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: HeadsAppColors.brandPrimary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(HeadsAppMetrics.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HeadsAppMetrics.controlRadius),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: HeadsAppColors.brandPrimary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(HeadsAppMetrics.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HeadsAppMetrics.controlRadius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: HeadsAppColors.brandPrimary,
          side: const BorderSide(color: HeadsAppColors.border),
          minimumSize: const Size.fromHeight(HeadsAppMetrics.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HeadsAppMetrics.controlRadius),
          ),
          backgroundColor: HeadsAppColors.surface,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: HeadsAppColors.brandPrimary,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: HeadsAppColors.surfaceSoft,
        selectedColor: HeadsAppColors.brandPrimary.withValues(alpha: 0.12),
        side: const BorderSide(color: HeadsAppColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HeadsAppMetrics.compactRadius),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: HeadsAppColors.textPrimary,
        textColor: HeadsAppColors.textPrimary,
      ),
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: HeadsAppColors.brandPrimary,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0F172A),
      fontFamily: 'Roboto',
    );
  }
}
