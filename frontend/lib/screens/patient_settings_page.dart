import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../headsapp_theme.dart';
import '../profile_page.dart';
import '../services/api_service.dart';
import 'patient_security_page.dart';

class PatientSettingsPage extends StatefulWidget {
  const PatientSettingsPage({
    super.key,
    required this.patientId,
    required this.patientName,
    this.patientPhotoPath,
    this.unreadNotificationCount = 0,
    this.onOpenNotifications,
  });

  final String patientId;
  final String patientName;
  final String? patientPhotoPath;
  final int unreadNotificationCount;
  final VoidCallback? onOpenNotifications;

  static const String languagePrefKey = 'patient_preferred_language';

  @override
  State<PatientSettingsPage> createState() => _PatientSettingsPageState();
}

class _PatientSettingsPageState extends State<PatientSettingsPage> {
  static const Color _pageBg = Color(0xFFF8FAFC);
  static const Color _titleBlack = Color(0xFF111827);
  static const Color _subtitleGrey = Color(0xFF6B7280);
  static const Color _iconBg = Color(0xFFE8F2FC);
  static const Color _iconColor = Color(0xFF265AA6);
  static const Color _selectedLangBg = Color(0xFFEEF6FF);
  static const Color _selectedLangBorder = Color(0xFF4A89DC);

  String _selectedLanguage = 'fr';
  String? _photoPath;

  @override
  void initState() {
    super.initState();
    _photoPath = widget.patientPhotoPath;
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(PatientSettingsPage.languagePrefKey);
    if (!mounted) return;
    if (saved != null && saved.isNotEmpty) {
      setState(() => _selectedLanguage = saved);
    }
  }

  Future<void> _selectLanguage(String code) async {
    setState(() => _selectedLanguage = code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PatientSettingsPage.languagePrefKey, code);
  }

  String? _photoUrl() => ApiService.resolveMediaUrlOrNull(_photoPath);

  Future<void> _openProfile() async {
    final result = await Navigator.of(context).push<Map<String, String?>>(
      MaterialPageRoute<Map<String, String?>>(
        builder: (_) => ProfilePage(
          patientId: widget.patientId,
          patientName: widget.patientName,
        ),
      ),
    );
    if (!mounted || result == null) return;
    final newPhoto = result['photoPath'];
    if (newPhoto != null) {
      setState(() => _photoPath = newPhoto);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photoUrl = _photoUrl();

    return Scaffold(
      backgroundColor: _pageBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                    color: _titleBlack,
                    tooltip: 'Retour',
                  ),
                  Text(
                    'HeadsApp',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: HeadsAppColors.brandPrimary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  if (widget.onOpenNotifications != null)
                    Badge(
                      isLabelVisible: widget.unreadNotificationCount > 0,
                      label: Text(
                        widget.unreadNotificationCount > 99
                            ? '99+'
                            : '${widget.unreadNotificationCount}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      backgroundColor: HeadsAppColors.danger,
                      child: IconButton(
                        onPressed: widget.onOpenNotifications,
                        icon: const Icon(Icons.notifications_outlined),
                        color: _titleBlack,
                      ),
                    ),
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: _iconBg,
                    backgroundImage:
                        photoUrl != null ? NetworkImage(photoUrl) : null,
                    child: photoUrl == null
                        ? const Icon(
                            Icons.person_rounded,
                            color: _iconColor,
                            size: 22,
                          )
                        : null,
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Paramètres',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: _titleBlack,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Gérez vos préférences et la sécurité de votre compte',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _subtitleGrey,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _SettingsSectionCard(
                      title: 'Mon Compte',
                      children: [
                        _SettingsNavRow(
                          icon: Icons.person_outline_rounded,
                          title: 'Profil',
                          subtitle: 'Informations personnelles et santé',
                          onTap: _openProfile,
                        ),
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        _SettingsNavRow(
                          icon: Icons.shield_outlined,
                          title: 'Sécurité',
                          subtitle: 'Mot de passe et authentification',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => PatientSecurityPage(
                                  patientId: widget.patientId,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _SettingsSectionCard(
                      title: 'Préférences',
                      children: [
                        _SettingsNavRow(
                          icon: Icons.language_rounded,
                          title: 'Langue de l\'application',
                          subtitle: null,
                          showChevron: false,
                          onTap: null,
                        ),
                        const SizedBox(height: 12),
                        _LanguageOption(
                          label: 'Français',
                          selected: _selectedLanguage == 'fr',
                          onTap: () => _selectLanguage('fr'),
                        ),
                        const SizedBox(height: 10),
                        _LanguageOption(
                          label: 'Anglais',
                          selected: _selectedLanguage == 'en',
                          onTap: () => _selectLanguage('en'),
                        ),
                        const SizedBox(height: 10),
                        _LanguageOption(
                          label: 'Arabe',
                          selected: _selectedLanguage == 'ar',
                          onTap: () => _selectLanguage('ar'),
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
    );
  }
}

class _SettingsSectionCard extends StatelessWidget {
  const _SettingsSectionCard({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF111827),
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE8EDF3)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1A2B48).withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}

class _SettingsNavRow extends StatelessWidget {
  const _SettingsNavRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.showChevron = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool showChevron;

  static const Color _iconBg = Color(0xFFE8F2FC);
  static const Color _iconColor = Color(0xFF265AA6);
  static const Color _subtitleGrey = Color(0xFF6B7280);

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: const Color(0xFF111827),
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _subtitleGrey,
                          height: 1.3,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (showChevron)
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF9CA3AF),
              size: 22,
            ),
        ],
      ),
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: content,
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEEF6FF) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? const Color(0xFF4A89DC)
                  : const Color(0xFFE8EDF3),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: const Color(0xFF111827),
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                  ),
                ),
                if (selected)
                  Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: Color(0xFF4A89DC),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 14,
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
