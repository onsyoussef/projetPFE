import 'package:flutter/material.dart';

import '../headsapp_theme.dart';
import '../services/api_service.dart';
import '../utils/doctor_ui_utils.dart';
import '../widgets/headsapp_logo_text.dart';
import 'doctor_availability_settings_screen.dart';
import 'doctor_profile_screen.dart';
import 'doctor_security_screen.dart';

/// Hub Paramètres : navigation vers profil, sécurité et disponibilité.
class DoctorSettingsScreen extends StatefulWidget {
  const DoctorSettingsScreen({
    super.key,
    required this.doctorId,
    this.doctorName = '',
  });

  final String doctorId;
  final String doctorName;

  @override
  State<DoctorSettingsScreen> createState() => _DoctorSettingsScreenState();
}

class _DoctorSettingsScreenState extends State<DoctorSettingsScreen> {
  static const Color _background = Color(0xFFF5F9FC);
  static const Color _textPrimary = HeadsAppColors.textPrimary;
  static const Color _textSecondary = HeadsAppColors.textSecondary;
  static const Color _brandBlue = Color(0xFF2459A8);

  String _displayName = '';
  String? _photoPath;

  @override
  void initState() {
    super.initState();
    _displayName = widget.doctorName;
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await ApiService.getDoctorProfile(widget.doctorId);
      if (!mounted) return;
      setState(() {
        _displayName = readableDoctorName(
          profile['fullName']?.toString(),
          fallback: widget.doctorName,
        );
        _photoPath = profile['photoPath']?.toString();
      });
    } catch (_) {}
  }

  String? _avatarUrl() {
    if (_photoPath == null || _photoPath!.trim().isEmpty) return null;
    return ApiService.resolveMediaUrl(_photoPath);
  }

  void _openProfile() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DoctorProfileScreen(doctorId: widget.doctorId),
      ),
    ).then((_) => _loadProfile());
  }

  void _openSecurity() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DoctorSecurityScreen(doctorId: widget.doctorId),
      ),
    );
  }

  void _openAvailability() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DoctorAvailabilitySettingsScreen(
          doctorId: widget.doctorId,
          doctorName: _displayName.isEmpty ? widget.doctorName : _displayName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                    color: _textPrimary,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: HeadsAppColors.border),
                    ),
                  ),
                  Expanded(
                    child: HeadsAppLogoText(
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(
                      Icons.notifications_outlined,
                      size: 20,
                      color: _textPrimary,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: HeadsAppColors.border),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: HeadsAppColors.border),
                    ),
                    child: ClipOval(
                      child: _avatarUrl() != null
                          ? Image.network(_avatarUrl()!, fit: BoxFit.cover)
                          : Center(
                              child: Text(
                                doctorInitials(_displayName),
                                style: const TextStyle(
                                  color: _textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Paramètres',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: _textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Gérez vos préférences et la sécurité de votre compte',
                      style: TextStyle(
                        fontSize: 14,
                        color: _textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _SettingsSectionCard(
                      title: 'Mon Compte',
                      children: [
                        _SettingsMenuTile(
                          icon: Icons.person_outline_rounded,
                          title: 'Profil',
                          subtitle: 'Informations personnelles et professionnelles',
                          onTap: _openProfile,
                        ),
                        const Divider(height: 1, color: HeadsAppColors.border),
                        _SettingsMenuTile(
                          icon: Icons.shield_outlined,
                          title: 'Sécurité',
                          subtitle: 'Mot de passe et authentification',
                          onTap: _openSecurity,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _SettingsSectionCard(
                      title: 'Disponibilité',
                      children: [
                        _SettingsMenuTile(
                          icon: Icons.event_available_outlined,
                          title: 'Disponibilité',
                          subtitle:
                              'Statut, jours ouvrés, horaires et mode absence',
                          onTap: _openAvailability,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'HEADSAPP — 2026',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _textSecondary,
                  letterSpacing: 1.2,
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: HeadsAppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: HeadsAppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }
}

class _SettingsMenuTile extends StatelessWidget {
  const _SettingsMenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: HeadsAppColors.brandHighlight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: HeadsAppColors.brandPrimary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: HeadsAppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: HeadsAppColors.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: HeadsAppColors.textSecondary,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
