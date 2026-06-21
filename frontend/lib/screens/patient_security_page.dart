import 'package:flutter/material.dart';

import '../headsapp_theme.dart';
import '../services/api_service.dart';
import '../utils/password_validator.dart';
import '../widgets/gradient_button.dart';

class PatientSecurityPage extends StatefulWidget {
  const PatientSecurityPage({
    super.key,
    required this.patientId,
  });

  final String patientId;

  @override
  State<PatientSecurityPage> createState() => _PatientSecurityPageState();
}

class _PatientSecurityPageState extends State<PatientSecurityPage> {
  static const Color _pageBg = Color(0xFFF8FAFC);
  static const Color _titleNavy = Color(0xFF1A458B);
  static const Color _hintGrey = Color(0xFF6B7280);
  static const Color _fieldBorder = Color(0xFFD8E5F5);

  final _formKey = GlobalKey<FormState>();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _saving = false;

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final data = await ApiService.changePatientPassword(
        patientId: widget.patientId,
        oldPassword: _oldPasswordController.text,
        newPassword: _newPasswordController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            data['message']?.toString() ?? 'Mot de passe mis à jour.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _passwordDecoration({
    required String hint,
    required bool obscure,
    required VoidCallback onToggleVisibility,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: Color(0xFF9CA3AF),
        fontSize: 15,
        fontWeight: FontWeight.w400,
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _fieldBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: HeadsAppColors.brandPrimary.withValues(alpha: 0.55),
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: HeadsAppColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: HeadsAppColors.danger),
      ),
      suffixIcon: IconButton(
        icon: Icon(
          obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          color: const Color(0xFF9CA3AF),
          size: 22,
        ),
        onPressed: onToggleVisibility,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: _pageBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: _titleNavy,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Sécurité',
          style: theme.textTheme.titleLarge?.copyWith(
            color: _titleNavy,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Changer le mot de passe',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: _titleNavy,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Saisissez votre mot de passe actuel puis choisissez un nouveau mot de passe.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _hintGrey,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 28),
              TextFormField(
                controller: _oldPasswordController,
                obscureText: _obscureOld,
                inputFormatters: PasswordValidator.inputFormatters,
                decoration: _passwordDecoration(
                  hint: 'Ancien mot de passe',
                  obscure: _obscureOld,
                  onToggleVisibility: () =>
                      setState(() => _obscureOld = !_obscureOld),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez entrer votre ancien mot de passe';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _newPasswordController,
                obscureText: _obscureNew,
                inputFormatters: PasswordValidator.inputFormatters,
                decoration: _passwordDecoration(
                  hint: 'Nouveau mot de passe',
                  obscure: _obscureNew,
                  onToggleVisibility: () =>
                      setState(() => _obscureNew = !_obscureNew),
                ),
                validator: (value) {
                  final ruleError = PasswordValidator.validate(
                    value,
                    emptyMessage: 'Veuillez entrer un nouveau mot de passe',
                  );
                  if (ruleError != null) return ruleError;
                  if (value == _oldPasswordController.text) {
                    return 'Le nouveau mot de passe doit être différent de l\'ancien';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              Text(
                PasswordValidator.requirementsHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _hintGrey,
                  height: 1.4,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirm,
                inputFormatters: PasswordValidator.inputFormatters,
                decoration: _passwordDecoration(
                  hint: 'Confirmation du nouveau mot de passe',
                  obscure: _obscureConfirm,
                  onToggleVisibility: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
                validator: (value) => PasswordValidator.validateConfirm(
                  value,
                  _newPasswordController.text,
                  emptyMessage:
                      'Veuillez confirmer le nouveau mot de passe',
                ),
              ),
              const SizedBox(height: 32),
              HeadsAppGradientButton(
                label: 'Confirmer',
                loading: _saving,
                onPressed: _saving ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
