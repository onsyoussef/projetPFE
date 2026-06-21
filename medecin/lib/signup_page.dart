import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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
  static const _totalSteps = 4;

  /// TEMP — scan diplôme désactivé pour les tests. Remettre à `true` en prod.
  static const _kDiplomaScanEnabled = false;

  int get _progressTotal => _kDiplomaScanEnabled ? _totalSteps : _totalSteps - 1;

  int get _progressStep {
    if (!_kDiplomaScanEnabled && _step >= 2) return _step - 1;
    return _step;
  }

  int _step = 0;
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  final _step1Key = GlobalKey<FormState>();
  final _step2Key = GlobalKey<FormState>();
  final _step4Key = GlobalKey<FormState>();

  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _orderNumberController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  String? _specialty;
  String? _governorate;
  XFile? _documentFile;
  Uint8List? _documentPreview;
  final String _country = 'Tunisie';

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _orderNumberController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String get _fullName =>
      '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
          .trim();

  int get _passwordStrength {
    final pwd = _passwordController.text;
    if (pwd.isEmpty) return 0;
    var score = 0;
    if (pwd.length >= 8) score++;
    if (RegExp(r'[A-Z]').hasMatch(pwd)) score++;
    if (RegExp(r'[a-z]').hasMatch(pwd)) score++;
    if (RegExp(r'[0-9]').hasMatch(pwd)) score++;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\;/`~]').hasMatch(pwd)) {
      score++;
    }
    return score.clamp(0, 4);
  }

  String get _passwordStrengthLabel {
    switch (_passwordStrength) {
      case 0:
      case 1:
        return 'FAIBLE';
      case 2:
        return 'MOYEN';
      case 3:
        return 'BON';
      default:
        return 'FORT';
    }
  }

  bool _validateCurrentStep() {
    switch (_step) {
      case 0:
        return _step1Key.currentState?.validate() ?? false;
      case 1:
        return _step2Key.currentState?.validate() ?? false;
      case 2:
        // Étape scan diplôme — désactivée pour tests (_kDiplomaScanEnabled).
        if (!_kDiplomaScanEnabled) return true;
        if (_documentFile == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Veuillez scanner votre document professionnel.'),
            ),
          );
          return false;
        }
        return true;
      case 3:
        return _step4Key.currentState?.validate() ?? false;
      default:
        return false;
    }
  }

  void _nextStep() {
    if (!_validateCurrentStep()) return;
    if (_step < _totalSteps - 1) {
      setState(() {
        var next = _step + 1;
        if (!_kDiplomaScanEnabled && next == 2) next = 3;
        _step = next;
      });
      return;
    }
    _onSignup();
  }

  void _previousStep() {
    if (_step > 0) {
      setState(() {
        var prev = _step - 1;
        if (!_kDiplomaScanEnabled && prev == 2) prev = 1;
        _step = prev;
      });
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _pickDocument() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Appareil photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galerie'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 85);
    if (file == null) return;
    await _setDocument(file);
  }

  Future<void> _setDocument(XFile file) async {
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _documentFile = file;
      _documentPreview = bytes;
    });
  }

  void _removeDocument() {
    setState(() {
      _documentFile = null;
      _documentPreview = null;
    });
  }

  void _onSignup() {
    if (!_validateCurrentStep()) return;

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Inscription en cours...')),
    );

    final governorate = _governorate!.trim();
    ApiService.registerDoctor(
      fullName: _fullName,
      email: _emailController.text.trim(),
      password: _passwordController.text,
      specialty: _specialty!,
      governorate: governorate,
      address: governorate,
      phone: _phoneController.text.replaceAll(' ', ''),
      orderNumber: _orderNumberController.text.trim().isEmpty
          ? null
          : _orderNumberController.text.trim(),
      country: _country,
      // diploma: _documentFile, // scan diplôme (réactiver avec _kDiplomaScanEnabled)
      diploma: _kDiplomaScanEnabled ? _documentFile : null,
    ).then((_) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Demande enregistrée. Un administrateur validera votre compte.',
          ),
        ),
      );
      Navigator.of(context).pop();
    }).catchError((error) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
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

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_step < 3) ...[
            const SizedBox(height: 8),
            const AuthBrandHeader(useLogoAsset: true, vertical: true),
            const SizedBox(height: 20),
            AuthSignupProgressBar(
              currentStep: _progressStep,
              totalSteps: _progressTotal,
            ),
            const SizedBox(height: 24),
          ] else ...[
            const SizedBox(height: 16),
            const AuthSecurityHeader(),
            const SizedBox(height: 16),
            AuthSignupProgressBar(
              currentStep: _progressStep,
              totalSteps: _progressTotal,
            ),
            const SizedBox(height: 24),
          ],
          if (_step == 0) _buildStep1(),
          if (_step == 1) _buildStep2(),
          // Étape scan diplôme (désactivée pour tests)
          if (_step == 2 && _kDiplomaScanEnabled) _buildStep3(),
          if (_step == 3) _buildStep4(),
        ],
      ),
    );
  }

  Widget _buildStep1() {
    return AuthFormCard(
      child: Form(
        key: _step1Key,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AuthTitleBlock(
              title: 'Créez votre profil',
              subtitle: 'Bienvenue. Commençons par faire connaissance.',
            ),
            const SizedBox(height: 24),
            AuthLabeledField(
              label: 'Prénom',
              labelUppercase: true,
              child: TextFormField(
                controller: _firstNameController,
                textCapitalization: TextCapitalization.words,
                decoration: authInputDecoration(
                  hintText: 'Ex: Abid',
                  prefixIcon: Icons.person_outline_rounded,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Veuillez entrer votre prénom';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 16),
            AuthLabeledField(
              label: 'Nom',
              labelUppercase: true,
              child: TextFormField(
                controller: _lastNameController,
                textCapitalization: TextCapitalization.words,
                decoration: authInputDecoration(
                  hintText: 'Ex: Tarek',
                  prefixIcon: Icons.badge_outlined,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Veuillez entrer votre nom';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 16),
            AuthLabeledField(
              label: 'Email professionnel',
              labelUppercase: true,
              child: TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: authInputDecoration(
                  hintText: 'exemple@clinique.tn',
                  prefixIcon: Icons.email_outlined,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez entrer votre e-mail';
                  }
                  if (!value.contains('@')) {
                    return 'E-mail invalide';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 16),
            AuthLabeledField(
              label: 'Téléphone',
              labelUppercase: true,
              child: TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: authInputDecoration(
                  hintText: '+216 54 879 256',
                  prefixIcon: Icons.phone_outlined,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez entrer votre téléphone';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 28),
            AuthSolidButton(label: 'Suivant', onPressed: _nextStep),
          ],
        ),
      ),
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AuthTitleBlock(
          title: 'Vos informations médicales',
          centered: true,
        ),
        const SizedBox(height: 20),
        AuthFormCard(
          child: Form(
            key: _step2Key,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthLabeledField(
                  label: 'Spécialité médicale',
                  child: DropdownButtonFormField<String>(
                    initialValue: _specialty,
                    decoration: authDropdownDecoration(
                      hintText: 'Sélectionnez votre spécialité',
                      prefixIcon: Icons.medical_services_outlined,
                    ),
                    items: kSpecialties
                        .map(
                          (s) => DropdownMenuItem(value: s, child: Text(s)),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _specialty = v),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Choisissez une spécialité';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 16),
                AuthLabeledField(
                  label: 'Numéro RPPS',
                  child: TextFormField(
                    controller: _orderNumberController,
                    keyboardType: TextInputType.number,
                    decoration: authInputDecoration(
                      hintText: 'Ex: 12345',
                      prefixIcon: Icons.numbers_rounded,
                    ),
                    validator: (value) {
                      final v = value?.trim() ?? '';
                      if (v.isEmpty) return null;
                      if (!RegExp(r'^\d{1,5}$').hasMatch(v)) {
                        return 'Maximum 5 chiffres';
                      }
                      return null;
                    },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Ce numéro sera vérifié auprès du conseil de l\'ordre.',
                    style: TextStyle(
                      color: HeadsAppColors.textTertiary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                AuthLabeledField(
                  label: 'Ville d\'exercice principale',
                  child: Autocomplete<String>(
                    optionsBuilder: (textEditingValue) {
                      if (textEditingValue.text.isEmpty) {
                        return kGovernorates;
                      }
                      return kGovernorates.where(
                        (g) => g.toLowerCase().contains(
                              textEditingValue.text.toLowerCase(),
                            ),
                      );
                    },
                    onSelected: (selection) {
                      setState(() => _governorate = selection);
                    },
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      if (_governorate != null && controller.text.isEmpty) {
                        controller.text = _governorate!;
                      }
                      return TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: authInputDecoration(
                          hintText: 'Rechercher une ville...',
                          prefixIcon: Icons.location_city_outlined,
                        ),
                        onChanged: (v) {
                          if (kGovernorates.contains(v)) {
                            _governorate = v;
                          } else {
                            _governorate = null;
                          }
                        },
                        validator: (_) {
                          final city = controller.text.trim();
                          if (city.isEmpty) {
                            return 'Veuillez sélectionner une ville';
                          }
                          if (!kGovernorates.contains(city)) {
                            return 'Choisissez une ville de la liste';
                          }
                          _governorate = city;
                          return null;
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 28),
                AuthSolidButton(label: 'Suivant', onPressed: _nextStep),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        AuthTextLink(label: 'Précédent', onPressed: _previousStep),
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AuthTitleBlock(
          title: 'Validation Documents',
          subtitle:
              'Veuillez scanner votre carte de médecin ou justificatif pour finaliser votre accréditation professionnelle sur la plateforme.',
          centered: true,
        ),
        const SizedBox(height: 20),
        AuthFormCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Container(
                      height: 56,
                      width: 56,
                      decoration: BoxDecoration(
                        color: HeadsAppColors.brandHighlight,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.photo_camera_outlined,
                        color: HeadsAppColors.brandPrimary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Scanner le document',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: HeadsAppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Utilisez votre appareil photo pour une capture nette et lisible.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: HeadsAppColors.textSecondary,
                            height: 1.4,
                          ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _pickDocument,
                      icon: const Icon(Icons.camera_alt_outlined, size: 18),
                      label: const Text('Lancer le scan'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: HeadsAppColors.brandPrimary,
                        side: const BorderSide(color: HeadsAppColors.brandPrimary),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_documentPreview != null) ...[
                const SizedBox(height: 16),
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(
                        _documentPreview!,
                        width: double.infinity,
                        height: 180,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: HeadsAppColors.success,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_rounded, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'CAPTURE VALIDÉE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      right: 10,
                      child: Material(
                        color: const Color(0xFFFEE2E2),
                        shape: const CircleBorder(),
                        child: InkWell(
                          onTap: _removeDocument,
                          customBorder: const CircleBorder(),
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(
                              Icons.delete_outline_rounded,
                              color: HeadsAppColors.danger,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              const AuthInfoBox(
                title: 'Conseils pour la validation',
                message:
                    'Assurez-vous que les quatre coins du document sont visibles et que les textes sont parfaitement nets. Évitez les reflets directs de lumière.',
              ),
              const SizedBox(height: 24),
              AuthSolidButton(label: 'Suivant', onPressed: _nextStep),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AuthTextLink(label: 'Retour', onPressed: _previousStep),
      ],
    );
  }

  Widget _buildStep4() {
    return AuthFormCard(
      child: Form(
        key: _step4Key,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthLabeledField(
              label: 'Mot de passe',
              child: TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                inputFormatters: PasswordValidator.inputFormatters,
                onChanged: (_) => setState(() {}),
                decoration: authInputDecoration(
                  hintText: '••••••••',
                  prefixIcon: Icons.vpn_key_outlined,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: HeadsAppColors.textTertiary,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (value) => PasswordValidator.validate(
                  value,
                  emptyMessage: 'Veuillez entrer un mot de passe',
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: List.generate(4, (index) {
                      final filled = index < _passwordStrength;
                      return Expanded(
                        child: Container(
                          margin: EdgeInsets.only(right: index < 3 ? 6 : 0),
                          height: 4,
                          decoration: BoxDecoration(
                            color: filled
                                ? HeadsAppColors.brandPrimary
                                : const Color(0xFFE5E7EB),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _passwordStrengthLabel,
                  style: const TextStyle(
                    color: HeadsAppColors.brandPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            AuthLabeledField(
              label: 'Confirmez le mot de passe',
              child: TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                inputFormatters: PasswordValidator.inputFormatters,
                decoration: authInputDecoration(
                  hintText: '••••••••',
                  prefixIcon: Icons.verified_user_outlined,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: HeadsAppColors.textTertiary,
                      size: 20,
                    ),
                    onPressed: () => setState(
                      () => _obscureConfirmPassword = !_obscureConfirmPassword,
                    ),
                  ),
                ),
                validator: (value) => PasswordValidator.validateConfirm(
                  value,
                  _passwordController.text,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _PasswordRequirement(
              met: _passwordController.text.length >= 8,
              label: '8 caractères minimum',
            ),
            const SizedBox(height: 8),
            _PasswordRequirement(
              met: RegExp(r'[0-9]').hasMatch(_passwordController.text) &&
                  RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\;/`~]')
                      .hasMatch(_passwordController.text),
              label: '1 chiffre et 1 symbole',
            ),
            const SizedBox(height: 28),
            AuthSolidButton(
              label: 'Terminer l\'inscription',
              onPressed: _isSubmitting ? null : _nextStep,
              loading: _isSubmitting,
            ),
            const SizedBox(height: 8),
            AuthTextLink(label: 'Précédent', onPressed: _previousStep),
          ],
        ),
      ),
    );
  }
}

class _PasswordRequirement extends StatelessWidget {
  const _PasswordRequirement({required this.met, required this.label});

  final bool met;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          height: 18,
          width: 18,
          decoration: BoxDecoration(
            color: met ? HeadsAppColors.brandPrimary : const Color(0xFFE5E7EB),
            shape: BoxShape.circle,
          ),
          child: met
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 12)
              : null,
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: met ? HeadsAppColors.textSecondary : HeadsAppColors.textTertiary,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
