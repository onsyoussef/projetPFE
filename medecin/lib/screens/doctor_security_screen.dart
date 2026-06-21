import 'package:flutter/material.dart';

import '../headsapp_theme.dart';
import '../services/api_service.dart';
import '../utils/password_validator.dart';

/// Sécurité du compte : changement de mot de passe.
class DoctorSecurityScreen extends StatefulWidget {
  const DoctorSecurityScreen({
    super.key,
    required this.doctorId,
  });

  final String doctorId;

  @override
  State<DoctorSecurityScreen> createState() => _DoctorSecurityScreenState();
}

class _DoctorSecurityScreenState extends State<DoctorSecurityScreen> {
  static const Color _pageBg = Color(0xFFF5F7F9);
  static const Color _titleNavy = Color(0xFF1A3B70);
  static const Color _hintGrey = Color(0xFF7E8B9E);
  static const Color _fieldBorder = Color(0xFFE2E8F0);
  static const Color _buttonBlue = Color(0xFF2B5BA9);

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
      final data = await ApiService.changeDoctorPassword(
        doctorId: widget.doctorId,
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
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _fieldBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: _buttonBlue.withValues(alpha: 0.55),
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: HeadsAppColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
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
        title: const Text(
          'Sécurité',
          style: TextStyle(
            color: _titleNavy,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Changer le mot de passe',
                  style: TextStyle(
                    color: _titleNavy,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Saisissez votre mot de passe actuel puis choisissez un nouveau mot de passe.',
                  style: TextStyle(
                    color: _hintGrey,
                    fontSize: 14,
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
                    emptyMessage: 'Veuillez confirmer le nouveau mot de passe',
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _saving ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: _buttonBlue,
                      disabledBackgroundColor:
                          _buttonBlue.withValues(alpha: 0.55),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Confirmer',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
