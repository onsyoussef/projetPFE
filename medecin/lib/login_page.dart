import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'espace_medecin_shell.dart';
import 'headsapp_theme.dart';
import 'reset_password_page.dart';
import 'services/api_service.dart';
import 'services/push_notification_service.dart';
import 'session_keys.dart';
import 'signup_page.dart';
import 'utils/doctor_session_utils.dart';
import 'utils/doctor_ui_utils.dart';
import 'widgets/headsapp_brand_widgets.dart';

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

      ApiService.loginUser(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      ).then((data) async {
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        final user = data['doctor'] as Map<String, dynamic>?;
        var name = readableDoctorName(user?['fullName'] as String?);
        final doctorId = (user?['id'] ?? user?['_id'])?.toString() ?? '';
        final token = data['token']?.toString();
        if (doctorId.isNotEmpty) {
          name = await resolveDoctorDisplayName(
            doctorId: doctorId,
            cached: name,
          );
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(kSessionDoctorIdKey, doctorId);
            await prefs.setString(kSessionDoctorNameKey, name);
            if (token != null && token.trim().isNotEmpty) {
              await prefs.setString(kSessionDoctorTokenKey, token.trim());
            } else {
              await prefs.remove(kSessionDoctorTokenKey);
            }
            ApiService.setJwtToken(
              token != null && token.trim().isNotEmpty ? token.trim() : null,
            );
            await PushNotificationService.instance.initializeForDoctor(doctorId: doctorId);
          } catch (_) {}
        }
        if (!mounted) return;

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => EspaceMedecinShell(
              doctorId: doctorId,
              doctorName: name,
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
    return Scaffold(
      body: HeadsAppGradientBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    // Sur certains appareils, le 1er layout peut être très petit (voire 0),
                    // ce qui rendait minHeight négatif et faisait planter l'écran.
                    minHeight: (constraints.maxHeight - 32).clamp(0, double.infinity),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: HeadsAppSurfaceCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Center(
                                child: HeadsAppHeroBadge(
                                  icon: Icons.medical_services_rounded,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'Bienvenue, Docteur',
                                textAlign: TextAlign.left,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: HeadsAppColors.textPrimary,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Connectez-vous pour accéder à votre espace médecin.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: HeadsAppColors.textSecondary,
                                    ),
                              ),
                              const SizedBox(height: 24),
                              Form(
                                key: _formKey,
                                child: Column(
                                  children: [
                                    TextFormField(
                                      controller: _emailController,
                                      keyboardType: TextInputType.emailAddress,
                                      decoration: InputDecoration(
                                        labelText: 'Adresse email',
                                        prefixIcon: Icon(
                                          Icons.email_rounded,
                                          color: HeadsAppColors.brandAccent,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Veuillez entrer votre email';
                                        }
                                        if (!value.contains('@')) {
                                          return 'Email invalide';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      controller: _passwordController,
                                      obscureText: _obscurePassword,
                                      decoration: InputDecoration(
                                        labelText: 'Mot de passe',
                                        prefixIcon: Icon(
                                          Icons.lock_rounded,
                                          color: HeadsAppColors.brandAccent,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          borderSide: BorderSide.none,
                                        ),
                                        suffixIcon: IconButton(
                                          icon: Icon(
                                            _obscurePassword
                                                ? Icons.visibility_off_rounded
                                                : Icons.visibility_rounded,
                                            color: Colors.grey,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              _obscurePassword =
                                                  !_obscurePassword;
                                            });
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
                                    const SizedBox(height: 12),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const ResetPasswordPage(),
                                            ),
                                          );
                                        },
                                        child: Text(
                                          'Mot de passe oublié ?',
                                          style: const TextStyle(
                                            color: HeadsAppColors.brandPrimary,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              HeadsAppColors.brandPrimary,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 16,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(18),
                                          ),
                                          elevation: 4,
                                          shadowColor:
                                              HeadsAppColors.brandPrimary
                                                  .withValues(alpha: 0.28),
                                        ),
                                        onPressed: _onLogin,
                                        child: const Text(
                                          'SE CONNECTER',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 4,
                                children: [
                                  const Text(
                                    "Vous n'avez pas de compte médecin ?",
                                    textAlign: TextAlign.center,
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => const SignupPage(),
                                        ),
                                      );
                                    },
                                    child: Text(
                                      "S'inscrire",
                                      style: TextStyle(
                                        color: HeadsAppColors.brandPrimary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
