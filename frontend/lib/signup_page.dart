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
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _countryController = TextEditingController();
  final TextEditingController _addressExactController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptedTerms = false;

  static const List<String> kCountries = [
    'Tunisie',
    'France',
    'Belgique',
    'Suisse',
    'Algérie',
    'Maroc',
    'Italie',
    'Canada',
    'Royaume-Uni',
  ];

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const AuthBrandHeader(),
          const SizedBox(height: 24),
          const AuthTitleBlock(
            title: 'Créer un compte',
            centered: true,
          ),
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
                      hintText: 'Jean Dupont',
                      prefixIcon: Icons.person_outline_rounded,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Veuillez entrer votre nom complet';
                      }
                      if (value.trim().split(' ').length < 2) {
                        return 'Entrez au moins nom et prénom';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 16),
                AuthLabeledField(
                  label: 'Ville / Adresse',
                  child: TextFormField(
                    controller: _addressExactController,
                    decoration: authInputDecoration(
                      hintText: 'Votre ville ou adresse',
                      prefixIcon: Icons.location_on_outlined,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Veuillez entrer votre adresse';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 16),
                AuthLabeledField(
                  label: 'Pays',
                  child: Autocomplete<String>(
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      final query =
                          textEditingValue.text.trim().toLowerCase();
                      if (query.isEmpty) return kCountries;
                      return kCountries
                          .where((c) => c.toLowerCase().contains(query));
                    },
                    onSelected: (selection) {
                      _countryController.text = selection;
                    },
                    fieldViewBuilder:
                        (context, controller, focusNode, onFieldSubmitted) {
                      return TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        textCapitalization: TextCapitalization.words,
                        decoration: authInputDecoration(
                          hintText: 'Tunisie',
                          prefixIcon: Icons.public_outlined,
                        ),
                        validator: (value) {
                          final v = value?.trim() ?? '';
                          if (v.isEmpty) {
                            return 'Veuillez entrer votre pays';
                          }
                          return null;
                        },
                        onChanged: (v) => _countryController.text = v,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                AuthLabeledField(
                  label: 'Téléphone',
                  child: TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: authInputDecoration(
                      hintText: '12345678',
                      prefixIcon: Icons.phone_outlined,
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
                const SizedBox(height: 16),
                AuthLabeledField(
                  label: 'Email',
                  child: TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: authInputDecoration(
                      hintText: 'nom@exemple.com',
                      prefixIcon: Icons.email_outlined,
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
                const SizedBox(height: 16),
                AuthLabeledField(
                  label: 'Mot de passe',
                  child: TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    inputFormatters: PasswordValidator.inputFormatters,
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
                    validator: PasswordValidator.validate,
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
                const SizedBox(height: 18),
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
                        shape: const CircleBorder(),
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
                const SizedBox(height: 24),
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
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
