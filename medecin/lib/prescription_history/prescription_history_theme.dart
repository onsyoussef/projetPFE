import 'package:flutter/material.dart';

import '../headsapp_theme.dart';

/// Styles d’historique d’ordonnances alignés sur la charte [HeadsAppColors] / [HeadsAppMetrics].
abstract final class PrescriptionHistoryTheme {
  static Color get accent => HeadsAppColors.brandPrimary;
  static Color get background => HeadsAppColors.surfaceAlt;
  static Color get cardSurface => HeadsAppColors.surface;
  static Color get textPrimary => HeadsAppColors.textPrimary;
  static Color get textSecondary => HeadsAppColors.textSecondary;
  static Color get border => HeadsAppColors.border;

  static Color get badgeActiveBg => HeadsAppColors.brandHighlight;
  static Color get badgeActiveFg => HeadsAppColors.success;

  static Color get badgeInactiveBg => HeadsAppColors.surfaceMuted;
  static Color get badgeInactiveFg => HeadsAppColors.textTertiary;

  static double get sheetCornerRadius => HeadsAppMetrics.cardRadius;
  static double get cardCornerRadius => HeadsAppMetrics.cardRadius;
  static double get chipCornerRadius => HeadsAppMetrics.compactRadius;
}
