import 'package:flutter/services.dart';

/// Règles de complexité des mots de passe HeadsApp (inscription & réinitialisation).
class PasswordValidator {
  PasswordValidator._();

  static const int minLength = 8;

  static const String requirementsHint =
      '8 caractères minimum, une majuscule (A-Z), une minuscule (a-z), '
      'un chiffre (0-9), un caractère spécial (@, #, \$, %, &, !, ?…), sans espaces.';

  static final RegExp _uppercase = RegExp(r'[A-Z]');
  static final RegExp _lowercase = RegExp(r'[a-z]');
  static final RegExp _digit = RegExp(r'[0-9]');
  static final RegExp _special =
      RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\;/`~]');
  static final RegExp _spaces = RegExp(r'\s');

  /// Bloque la saisie d'espaces dans les champs mot de passe.
  static final List<TextInputFormatter> inputFormatters = [
    FilteringTextInputFormatter.deny(_spaces),
  ];

  /// Retourne `null` si le mot de passe est valide, sinon un message d'erreur.
  static String? validate(
    String? value, {
    String emptyMessage = 'Veuillez entrer un mot de passe',
  }) {
    if (value == null || value.isEmpty) {
      return emptyMessage;
    }
    if (_spaces.hasMatch(value)) {
      return 'Le mot de passe ne doit pas contenir d\'espaces';
    }
    if (value.length < minLength) {
      return 'Au moins $minLength caractères';
    }
    if (!_uppercase.hasMatch(value)) {
      return 'Au moins une lettre majuscule (A-Z)';
    }
    if (!_lowercase.hasMatch(value)) {
      return 'Au moins une lettre minuscule (a-z)';
    }
    if (!_digit.hasMatch(value)) {
      return 'Au moins un chiffre (0-9)';
    }
    if (!_special.hasMatch(value)) {
      return 'Au moins un caractère spécial (@, #, \$, %, &, !, ?…)';
    }
    return null;
  }

  /// Validation du champ de confirmation (règles + correspondance).
  static String? validateConfirm(
    String? value,
    String password, {
    String emptyMessage = 'Veuillez confirmer le mot de passe',
    String mismatchMessage = 'Les mots de passe ne correspondent pas',
  }) {
    final ruleError = validate(value, emptyMessage: emptyMessage);
    if (ruleError != null) return ruleError;
    if (value != password) return mismatchMessage;
    return null;
  }
}
