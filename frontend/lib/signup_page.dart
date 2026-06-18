import 'package:flutter/material.dart';

import 'headsapp_theme.dart';
import 'services/api_service.dart';
import 'utils/password_validator.dart';
import 'widgets/auth_ui_widgets.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  static const Color _fieldFill = Color(0xFFF0F4F8);

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _countryController =
      TextEditingController(text: 'Tunisie');
  final TextEditingController _addressExactController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptedTerms = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _countryController.dispose();
    _addressExactController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _onSignup() {
    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Veuillez accepter les conditions générales et la politique de confidentialité.',
          ),
        ),
      );
      return;
    }
    if (_formKey.currentState!.validate()) {
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inscription en cours...')),
      );

      ApiService.registerPatient(
        fullName: _fullNameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        country: _countryController.text.trim(),
        addressExact: _addressExactController.text.trim(),
        phone: _phoneController.text.replaceAll(' ', ''),
      ).then((data) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Compte créé avec succès.')),
        );
        Navigator.of(context).pop();
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
      showBackButton: true,
      backgroundColor: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const AuthBrandHeader(useLogoAsset: true, vertical: true),
          const SizedBox(height: 28),
          const AuthTitleBlock(title: 'Créer un compte'),
          const SizedBox(height: 28),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthLabeledField(
                  label: 'Nom complet',
                  child: TextFormField(
                    controller: _fullNameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: authInputDecoration(
                      hintText: 'Prénom et nom',
                      prefixIcon: Icons.person_outline_rounded,
                      fillColor: _fieldFill,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Veuillez entrer votre prénom et nom';
                      }
                      if (value.trim().split(' ').length < 2) {
                        return 'Entrez au moins nom et prénom';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 18),
                AuthLabeledField(
                  label: 'Ville',
                  child: TextFormField(
                    controller: _addressExactController,
                    textCapitalization: TextCapitalization.words,
                    decoration: authInputDecoration(
                      hintText: 'Tunis',
                      prefixIcon: Icons.location_on_outlined,
                      fillColor: _fieldFill,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Veuillez entrer votre ville';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 18),
                AuthLabeledField(
                  label: 'Email',
                  child: TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: authInputDecoration(
                      hintText: 'nom@exemple.com',
                      prefixIcon: Icons.email_outlined,
                      fillColor: _fieldFill,
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
                ),
                const SizedBox(height: 18),
                AuthLabeledField(
                  label: 'Téléphone',
                  child: TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: authInputDecoration(
                      hintText: '8 chiffres',
                      prefixIcon: Icons.phone_outlined,
                      fillColor: _fieldFill,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Veuillez entrer votre numéro de téléphone';
                      }
                      final cleaned = value.replaceAll(' ', '');
                      final regex = RegExp(r'^[0-9]{8}$');
                      if (!regex.hasMatch(cleaned)) {
                        return 'Numéro tunisien à 8 chiffres';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 18),
                AuthLabeledField(
                  label: 'Mot de passe',
                  child: TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    inputFormatters: PasswordValidator.inputFormatters,
                    decoration: authInputDecoration(
                      hintText: '••••••••',
                      prefixIcon: Icons.lock_outline_rounded,
                      fillColor: _fieldFill,
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
                    validator: PasswordValidator.validate,
                  ),
                ),
                const SizedBox(height: 12),
                const AuthPasswordRulesBox(),
                const SizedBox(height: 18),
                AuthLabeledField(
                  label: 'Confirmer le mot de passe',
                  child: TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirmPassword,
                    inputFormatters: PasswordValidator.inputFormatters,
                    decoration: authInputDecoration(
                      hintText: '••••••••',
                      prefixIcon: Icons.lock_reset_outlined,
                      fillColor: _fieldFill,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: HeadsAppColors.textTertiary,
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureConfirmPassword = !_obscureConfirmPassword;
                          });
                        },
                      ),
                    ),
                    validator: (value) => PasswordValidator.validateConfirm(
                      value,
                      _passwordController.text,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: Checkbox(
                        value: _acceptedTerms,
                        onChanged: (v) =>
                            setState(() => _acceptedTerms = v ?? false),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        side: const BorderSide(color: HeadsAppColors.border),
                        activeColor: HeadsAppColors.brandPrimary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: HeadsAppColors.textSecondary,
                                    height: 1.45,
                                  ),
                          children: const [
                            TextSpan(text: "J'accepte les "),
                            TextSpan(
                              text: 'conditions générales',
                              style: TextStyle(
                                color: HeadsAppColors.brandPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(text: ' et la '),
                            TextSpan(
                              text: 'politique de confidentialité',
                              style: TextStyle(
                                color: HeadsAppColors.brandPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(text: '.'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                AuthGradientButton(
                  label: 'Commencer',
                  onPressed: _onSignup,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          AuthFooterLink(
            prompt: 'Déjà inscrit ?',
            actionLabel: 'Se connecter',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
