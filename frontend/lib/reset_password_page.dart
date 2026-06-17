import 'dart:async';

import 'package:flutter/material.dart';

import 'headsapp_theme.dart';
import 'services/api_service.dart';
import 'utils/password_validator.dart';
import 'widgets/auth_ui_widgets.dart';

/// Écran 1 : saisie de l'email pour recevoir un code.
class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final TextEditingController _emailController = TextEditingController();
  bool _sendingCode = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _onSendCode() {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez entrer une adresse email valide.'),
        ),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _sendingCode = true);
    ApiService.requestResetCode(email: email).then((data) {
      if (!mounted) return;
      setState(() => _sendingCode = false);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ResetPasswordLinkSentPage(
            email: email,
            message: data['message']?.toString(),
          ),
        ),
      );
    }).catchError((error) {
      if (!mounted) return;
      setState(() => _sendingCode = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Center(
            child: AuthBrandHeader(
              icon: Icons.lock_reset_rounded,
              iconBackgroundColor: HeadsAppColors.brandPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Mot de passe oublié',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: HeadsAppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 24),
          AuthGlowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Saisissez votre email pour recevoir un lien de réinitialisation. Nous vous accompagnerons pas à pas pour sécuriser votre compte.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: HeadsAppColors.textSecondary,
                        height: 1.5,
                      ),
                ),
                const SizedBox(height: 24),
                AuthLabeledField(
                  label: 'Email professionnel ou personnel',
                  labelUppercase: true,
                  child: TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: authInputDecoration(
                      hintText: 'votre@email.com',
                      prefixIcon: Icons.email_outlined,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                AuthGradientButton(
                  label: 'Envoyer le lien',
                  loading: _sendingCode,
                  onPressed: _sendingCode ? null : _onSendCode,
                ),
                const SizedBox(height: 20),
                const AuthInfoBox(
                  message:
                      'Si vous ne recevez pas l\'email dans les 5 minutes, vérifiez votre dossier de courriers indésirables ou contactez notre support.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Center(child: AuthBackLink()),
        ],
      ),
    );
  }
}

/// Écran intermédiaire : confirmation d'envoi du lien / code.
class ResetPasswordLinkSentPage extends StatelessWidget {
  const ResetPasswordLinkSentPage({
    super.key,
    required this.email,
    this.message,
  });

  final String email;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 40),
          const AuthSuccessIcon(),
          const SizedBox(height: 28),
          const AuthTitleBlock(
            title: 'Lien envoyé !',
            subtitle:
                'Consultez votre boîte mail pour réinitialiser votre mot de passe.',
          ),
          const SizedBox(height: 36),
          AuthGradientButton(
            label: 'Continuer',
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => ResetPasswordCodePage(email: email),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () {
              ApiService.requestResetCode(email: email).then((_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('E-mail renvoyé.')),
                );
              }).catchError((error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      error.toString().replaceFirst('Exception: ', ''),
                    ),
                  ),
                );
              });
            },
            child: const Text(
              'RENVOYER L\'E-MAIL',
              style: TextStyle(
                color: HeadsAppColors.brandPrimary,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                fontSize: 12,
              ),
            ),
          ),
          if (message != null && message!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: HeadsAppColors.textTertiary,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Écran 2 : saisie du code reçu par email.
class ResetPasswordCodePage extends StatefulWidget {
  const ResetPasswordCodePage({super.key, required this.email});

  final String email;

  @override
  State<ResetPasswordCodePage> createState() => _ResetPasswordCodePageState();
}

class _ResetPasswordCodePageState extends State<ResetPasswordCodePage> {
  final List<TextEditingController> _digitControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _validating = false;
  int _resendSeconds = 120;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    for (final c in _digitControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 120);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSeconds <= 0) {
        timer.cancel();
        setState(() {});
        return;
      }
      setState(() => _resendSeconds--);
    });
  }

  String _currentCode() => _digitControllers.map((c) => c.text).join();

  String _formatTimer() {
    final m = (_resendSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_resendSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _onResendCode() {
    if (_resendSeconds > 0) return;
    ApiService.requestResetCode(email: widget.email).then((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Un nouveau code a été envoyé.')),
      );
      _startResendTimer();
    }).catchError((error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    });
  }

  void _onValidateCode() {
    final code = _currentCode();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le code doit contenir 6 chiffres.')),
      );
      return;
    }
    setState(() => _validating = true);
    ApiService.verifyResetCode(email: widget.email, code: code).then((data) {
      if (!mounted) return;
      setState(() => _validating = false);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ResetPasswordNewPasswordPage(
            email: widget.email,
            code: code,
          ),
        ),
      );
    }).catchError((error) {
      if (!mounted) return;
      setState(() => _validating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('Exception: ', ''),
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      showBackButton: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Center(
            child: AuthBrandHeader(
              icon: Icons.mark_email_read_outlined,
              iconBackgroundColor: HeadsAppColors.brandPrimary,
            ),
          ),
          const SizedBox(height: 24),
          const AuthTitleBlock(
            title: 'Vérification',
          ),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: HeadsAppColors.textSecondary,
                  ),
              children: [
                const TextSpan(
                  text: 'Nous avons envoyé un code de confirmation à ',
                ),
                TextSpan(
                  text: widget.email,
                  style: const TextStyle(
                    color: HeadsAppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          AuthOtpBoxes(
            controllers: _digitControllers,
            focusNodes: _focusNodes,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Vous n\'avez pas reçu le code ?',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: HeadsAppColors.textSecondary,
                    ),
              ),
              TextButton(
                onPressed: _resendSeconds > 0 ? null : _onResendCode,
                child: const Text(
                  'Renvoyer le code',
                  style: TextStyle(
                    color: HeadsAppColors.brandPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_resendSeconds > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: HeadsAppColors.authInputFill,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _formatTimer(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: HeadsAppColors.textTertiary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 28),
          AuthGradientButton(
            label: 'Confirmer',
            loading: _validating,
            showArrow: false,
            onPressed: _validating ? null : _onValidateCode,
          ),
        ],
      ),
    );
  }
}

/// Écran 3 : saisie du nouveau mot de passe + confirmation.
class ResetPasswordNewPasswordPage extends StatefulWidget {
  const ResetPasswordNewPasswordPage({
    super.key,
    required this.email,
    required this.code,
  });

  final String email;
  final String code;

  @override
  State<ResetPasswordNewPasswordPage> createState() =>
      _ResetPasswordNewPasswordPageState();
}

class _ResetPasswordNewPasswordPageState
    extends State<ResetPasswordNewPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _saving = false;

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _onResetPassword() {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    ApiService.verifyAndResetPassword(
      email: widget.email,
      code: widget.code,
      newPassword: _newPasswordController.text,
    ).then((data) {
      if (!mounted) return;
      setState(() => _saving = false);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => ResetPasswordSuccessPage(
            message: data['message']?.toString(),
          ),
        ),
        (route) => route.isFirst,
      );
    }).catchError((error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      showBackButton: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const AuthBrandHeader(),
          const SizedBox(height: 24),
          const AuthTitleBlock(
            title: 'Nouveau mot de passe',
            subtitle:
                'Pour terminer, entrez votre nouveau mot de passe et confirmez-le.',
          ),
          const SizedBox(height: 28),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthLabeledField(
                  label: 'Nouveau mot de passe',
                  child: TextFormField(
                    controller: _newPasswordController,
                    obscureText: _obscureNewPassword,
                    inputFormatters: PasswordValidator.inputFormatters,
                    decoration: authInputDecoration(
                      hintText: '••••••••',
                      prefixIcon: Icons.lock_outline_rounded,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureNewPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: HeadsAppColors.textTertiary,
                          size: 20,
                        ),
                        onPressed: () => setState(
                          () => _obscureNewPassword = !_obscureNewPassword,
                        ),
                      ),
                    ),
                    validator: (value) => PasswordValidator.validate(
                      value,
                      emptyMessage:
                          'Veuillez entrer un nouveau mot de passe',
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  PasswordValidator.requirementsHint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: HeadsAppColors.textTertiary,
                        height: 1.35,
                      ),
                ),
                const SizedBox(height: 16),
                AuthLabeledField(
                  label: 'Confirmer le mot de passe',
                  child: TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirmPassword,
                    inputFormatters: PasswordValidator.inputFormatters,
                    decoration: authInputDecoration(
                      hintText: '••••••••',
                      prefixIcon: Icons.lock_reset_outlined,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: HeadsAppColors.textTertiary,
                          size: 20,
                        ),
                        onPressed: () => setState(
                          () => _obscureConfirmPassword =
                              !_obscureConfirmPassword,
                        ),
                      ),
                    ),
                    validator: (value) => PasswordValidator.validateConfirm(
                      value,
                      _newPasswordController.text,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                AuthGradientButton(
                  label: 'Changer le mot de passe',
                  loading: _saving,
                  onPressed: _saving ? null : _onResetPassword,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ResetPasswordSuccessPage extends StatelessWidget {
  const ResetPasswordSuccessPage({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 40),
          const AuthSuccessIcon(),
          const SizedBox(height: 28),
          AuthTitleBlock(
            title: 'Mot de passe modifié !',
            subtitle: message ??
                'Votre mot de passe a été mis à jour avec succès.',
          ),
          const SizedBox(height: 36),
          AuthGradientButton(
            label: 'Retour à la connexion',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
