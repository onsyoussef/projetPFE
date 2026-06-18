import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'headsapp_theme.dart';
import 'widgets/auth_ui_widgets.dart';
import 'signup_page.dart';
import 'reset_password_page.dart';
import 'bloc_urgence_page.dart';
import 'services/api_service.dart';
import 'services/push_notification_service.dart';
import 'utils/patient_session_utils.dart';
import 'utils/patient_ui_utils.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onLogin() {
    if (_formKey.currentState!.validate()) {
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connexion en cours...')),
      );

      ApiService.loginPatient(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      ).then((data) async {
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        final patient = data['patient'] as Map<String, dynamic>?;
        var name = readablePatientName(patient?['fullName'] as String?);
        final patientId = patient?['id'] as String? ?? '';
        if (patientId.isNotEmpty) {
          name = await resolvePatientDisplayName(
            patientId: patientId,
            cached: name,
          );
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('patientId', patientId);
        await prefs.setString('patientName', name);
        final token = data['token']?.toString();
        if (token != null && token.trim().isNotEmpty) {
          await prefs.setString('patient_jwt', token.trim());
        } else {
          await prefs.remove('patient_jwt');
        }
        ApiService.setJwtToken(
          token != null && token.trim().isNotEmpty ? token.trim() : null,
        );
        await PushNotificationService.instance.initializeForPatient(patientId: patientId);
        await prefs.remove('lastRoute');
        await prefs.remove('chatDoctorId');
        await prefs.remove('chatDoctorName');
        await prefs.remove('chatDoctorPhotoPath');
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => BlocUrgencePage(
              patientName: name,
              patientId: patientId,
            ),
          ),
        );
      }).catchError((error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.toString().replaceFirst('Exception: ', ''),
            ),
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          const AuthBrandHeader(useLogoAsset: true, vertical: true),
          const SizedBox(height: 32),
          const AuthTitleBlock(
            title: 'Bon retour parmi nous',
            subtitle: 'Veuillez entrer vos identifiants pour continuer.',
          ),
          const SizedBox(height: 32),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthLabeledField(
                  label: 'Adresse e-mail',
                  child: TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: authInputDecoration(
                      hintText: 'nom@exemple.com',
                      prefixIcon: Icons.email_outlined,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Veuillez entrer votre adresse e-mail';
                      }
                      if (!value.contains('@')) {
                        return 'Adresse e-mail invalide';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Mot de passe',
                        style: TextStyle(
                          color: Color(0xFF374151),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ResetPasswordPage(),
                          ),
                        );
                      },
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Mot de passe oublié ?',
                        style: TextStyle(
                          color: HeadsAppColors.brandPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: authInputDecoration(
                    hintText: '••••••••',
                    prefixIcon: Icons.lock_outline_rounded,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: HeadsAppColors.textTertiary,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Veuillez entrer votre mot de passe';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 28),
                AuthSolidButton(
                  label: 'Se connecter',
                  onPressed: _onLogin,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          AuthFooterLink(
            prompt: 'Vous n\'avez pas de compte ?',
            actionLabel: 'S\'inscrire',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SignupPage()),
              );
            },
          ),
        ],
      ),
    );
  }
}
