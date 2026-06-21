import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../espace_patient_page.dart';
import '../headsapp_theme.dart';
import '../services/api_service.dart';
import '../services/emergency_liaison_pdf_service.dart';
import '../widgets/gradient_button.dart';
import '../services/emergency_mode_service.dart';
import '../utils/patient_ui_utils.dart';

/// Dashboard affiché après acceptation de l'alerte d'urgence.
class EmergencyDashboardScreen extends StatefulWidget {
  const EmergencyDashboardScreen({
    super.key,
    required this.patientName,
    required this.patientId,
  });

  final String patientName;
  final String patientId;

  @override
  State<EmergencyDashboardScreen> createState() =>
      _EmergencyDashboardScreenState();
}

class _EmergencyDashboardScreenState extends State<EmergencyDashboardScreen> {
  static const Color _navy = Color(0xFF1A3B5D);
  static const Color _pageBg = Color(0xFFF5F7FA);

  String _addressLabel = 'Adresse indisponible';
  bool _locationLoading = true;
  double? _lat;
  double? _lon;
  Duration _remaining = EmergencyModeService.lockDuration;
  bool _canAccessEspace = false;
  bool _generatingPdf = false;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _initDashboard();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _initDashboard() async {
    await _refreshLockState();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshLockState();
    });
    await _detectLocation();
  }

  Future<void> _refreshLockState() async {
    final remaining = await EmergencyModeService.remainingLockTime();
    final canAccess = await EmergencyModeService.canAccessEspace();
    if (!mounted) return;
    setState(() {
      _remaining = remaining;
      _canAccessEspace = canAccess;
    });
  }

  Future<void> _detectLocation() async {
    setState(() => _locationLoading = true);
    try {
      if (!kIsWeb) {
        final status = await Permission.locationWhenInUse.request();
        if (!status.isGranted) {
          if (mounted) {
            setState(() {
              _locationLoading = false;
              _addressLabel = 'Autorisation de localisation refusée';
            });
          }
          return;
        }
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          if (mounted) {
            setState(() {
              _locationLoading = false;
              _addressLabel = 'Localisation désactivée';
            });
          }
          return;
        }
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      _lat = position.latitude;
      _lon = position.longitude;
      final address = await _reverseGeocode(_lat!, _lon!);
      if (mounted) {
        setState(() {
          _addressLabel = address ?? 'Adresse indisponible';
          _locationLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _locationLoading = false;
          _addressLabel = 'Adresse indisponible';
        });
      }
    }
  }

  Future<String?> _reverseGeocode(double lat, double lon) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=$lat&lon=$lon&format=json&accept-language=fr',
      );
      final response = await http.get(
        uri,
        headers: const {'User-Agent': 'HeadsApp/1.0'},
      );
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (data['display_name'] as String?)?.trim();
    } catch (_) {
      return null;
    }
  }

  Future<void> _openNearbyEmergencies() async {
    if (_lat == null || _lon == null) {
      await _detectLocation();
    }
    if (_lat == null || _lon == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible de déterminer votre position.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final uri = Uri.parse(
      'https://www.google.com/maps/search/urgences+hôpital/@$_lat,$_lon,14z',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _generateFiche() async {
    if (_generatingPdf) return;
    setState(() => _generatingPdf = true);
    try {
      final profile = await ApiService.getPatientProfile(
        patientId: widget.patientId,
      );
      final symptoms = await EmergencyModeService.symptomsWithTimes();
      final startedAt =
          await EmergencyModeService.startedAtTime() ?? DateTime.now();
      final path = await EmergencyLiaisonPdfService.generateAndSave(
        patientProfile: profile,
        symptomsWithTimes: symptoms,
        emergencyStartedAt: startedAt,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kIsWeb
                ? 'Fiche telechargee dans vos telechargements.'
                : 'Fiche telechargee : $path',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  Future<void> _goToEspace() async {
    if (!_canAccessEspace) return;
    await EmergencyModeService.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastRoute', 'espace_patient');
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => EspacePatientPage(
          patientName: widget.patientName,
          patientId: widget.patientId,
        ),
      ),
    );
  }

  String _formatRemaining(Duration d) {
    final totalMinutes = d.inMinutes;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final displayName = readablePatientName(widget.patientName);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: _pageBg,
        body: SafeArea(
          child: Stack(
            children: [
              CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                      child: Text(
                        "DASHBOARD D'URGENCE",
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: _navy,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _DashboardCard(
                          accentColor: const Color(0xFFEF4444),
                          icon: Icons.location_on_rounded,
                          iconColor: const Color(0xFFEF4444),
                          title: 'Ma Position',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: _locationLoading
                                    ? const Row(
                                        children: [
                                          SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                          SizedBox(width: 12),
                                          Text('Localisation en cours…'),
                                        ],
                                      )
                                    : Text(
                                        _addressLabel,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: _addressLabel ==
                                                      'Adresse indisponible'
                                                  ? const Color(0xFF94A3B8)
                                                  : const Color(0xFF334155),
                                            ),
                                      ),
                              ),
                              const SizedBox(height: 14),
                              HeadsAppGradientButton(
                                label: 'Voir les urgences proches',
                                borderRadius: 12,
                                height: 48,
                                fontSize: 15,
                                onPressed: _openNearbyEmergencies,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _DashboardCard(
                          accentColor: HeadsAppColors.brandPrimary,
                          icon: Icons.description_rounded,
                          iconColor: HeadsAppColors.brandPrimary,
                          title: 'Ma Fiche de Liaison',
                          child: HeadsAppGradientButton(
                            label: _generatingPdf
                                ? 'Génération…'
                                : 'Générer ma fiche',
                            borderRadius: 12,
                            height: 48,
                            fontSize: 15,
                            loading: _generatingPdf,
                            onPressed: _generatingPdf ? null : _generateFiche,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _DashboardCard(
                          accentColor: const Color(0xFFFBBF24),
                          icon: Icons.warning_amber_rounded,
                          iconColor: const Color(0xFFF59E0B),
                          title: 'Consignes importantes',
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                _ConsigneLine(
                                  text: 'Appelez immédiatement le 190 (SAMU)',
                                ),
                                _ConsigneLine(
                                  text: 'Restez au repos absolu',
                                ),
                                _ConsigneLine(
                                  text: 'Ne conduisez pas vous-même',
                                ),
                                _ConsigneLine(
                                  text: 'Gardez votre téléphone libre',
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (displayName.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Text(
                            'Patient : $displayName',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: HeadsAppColors.textTertiary),
                          ),
                        ],
                      ]),
                    ),
                  ),
                ],
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF64748B),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.schedule_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _formatRemaining(_remaining),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _MonEspaceButton(
                      enabled: _canAccessEspace,
                      onPressed: _canAccessEspace ? _goToEspace : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({
    required this.accentColor,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
  });

  final Color accentColor;
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: accentColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(icon, color: iconColor, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            title,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: const Color(0xFF1A3B5D),
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      child,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
class _ConsigneLine extends StatelessWidget {
  const _ConsigneLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 7, right: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF97316),
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF1A3B5D),
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonEspaceButton extends StatelessWidget {
  const _MonEspaceButton({
    required this.enabled,
    this.onPressed,
  });

  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? HeadsAppColors.brandPrimary : const Color(0xFF94A3B8),
      borderRadius: BorderRadius.circular(24),
      elevation: enabled ? 2 : 0,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                enabled ? Icons.person_rounded : Icons.lock_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Mon Espace',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: enabled ? 1 : 0.9),
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
