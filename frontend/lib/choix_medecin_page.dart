import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'headsapp_theme.dart';
import 'services/api_service.dart';
import 'chat_page.dart';
import 'utils/patient_ui_utils.dart';

enum _FilterMode { nameOnly, nameAndSpecialty, governorateAndSpecialty, all }

class ChoixMedecinPage extends StatefulWidget {
  const ChoixMedecinPage({
    super.key,
    required this.patientName,
    required this.patientId,
  });

  final String patientName;
  final String patientId;

  @override
  State<ChoixMedecinPage> createState() => _ChoixMedecinPageState();
}

class _ChoixMedecinPageState extends State<ChoixMedecinPage> {
  _FilterMode _filterMode = _FilterMode.all;

  bool get _allowName =>
      _filterMode == _FilterMode.nameOnly ||
      _filterMode == _FilterMode.nameAndSpecialty ||
      _filterMode == _FilterMode.all;

  bool get _allowSpecialty =>
      _filterMode == _FilterMode.nameAndSpecialty ||
      _filterMode == _FilterMode.governorateAndSpecialty ||
      _filterMode == _FilterMode.all;

  bool get _allowGovernorate =>
      _filterMode == _FilterMode.governorateAndSpecialty ||
      _filterMode == _FilterMode.all;

  String? _specialty;
  String? _governorate;
  final TextEditingController _nameController = TextEditingController();
  List<Map<String, dynamic>> _doctors = [];
  bool _loading = false;
  bool _hasSearched = false;
  String? _error;
  final _skyBlue = HeadsAppColors.brandAccent;

  double? _userLat;
  double? _userLon;
  bool _locationLoading = false;
  String? _locationError;

  Timer? _searchDebounceTimer;
  int _searchRequestId = 0;

  Future<void> _useMyLocation() async {
    setState(() {
      _locationLoading = true;
      _locationError = null;
    });
    try {
      if (!kIsWeb) {
        final status = await Permission.locationWhenInUse.request();
        if (!status.isGranted) {
          if (mounted) {
            setState(() {
              _locationLoading = false;
              _locationError = 'Autorisation de localisation refusée. Vous pouvez autoriser dans les paramètres.';
            });
          }
          return;
        }
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          if (mounted) {
            setState(() {
              _locationLoading = false;
              _locationError = 'Activez la localisation dans les paramètres de votre téléphone.';
            });
          }
          return;
        }
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      if (mounted) {
        setState(() {
          _userLat = position.latitude;
          _userLon = position.longitude;
          _governorate = null;
          _locationLoading = false;
          _locationError = null;
        });
        await _search();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _locationLoading = false;
          _locationError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchDebounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _search() async {
    final currentRequestId = ++_searchRequestId;
    setState(() {
      _loading = true;
      _error = null;
      _hasSearched = true;
    });
    final usePosition = _userLat != null && _userLon != null;

    final nameQuery = _allowName
        ? (_nameController.text.trim().isEmpty ? null : _nameController.text.trim())
        : null;
    final specialtyQuery = _allowSpecialty ? _specialty : null;
    final governorateQuery = (!_usePosition && _allowGovernorate) ? _governorate : null;
    try {
      final list = await ApiService.getDoctors(
        specialty: specialtyQuery,
        name: nameQuery,
        governorate: usePosition ? null : governorateQuery,
        latitude: usePosition ? _userLat : null,
        longitude: usePosition ? _userLon : null,
      );
      if (mounted && currentRequestId == _searchRequestId) {
        setState(() {
          _doctors = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted && currentRequestId == _searchRequestId) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _doctors = [];
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              HeadsAppColors.brandHighlight,
              HeadsAppColors.surfaceAlt,
              HeadsAppColors.surfaceAlt,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('lastRoute', 'espace_patient');
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.arrow_back_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: HeadsAppColors.surface,
                        foregroundColor: HeadsAppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Choisir un médecin',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: HeadsAppColors.textPrimary,
                                ),
                          ),
                          Text(
                            'Bonjour ${readablePatientName(widget.patientName)}',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: HeadsAppColors.textSecondary,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFilters(),
                        const SizedBox(height: 24),
                        if (_loading && _doctors.isEmpty)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: CircularProgressIndicator(color: HeadsAppColors.brandPrimary),
                            ),
                          )
                        else if (_error != null)
                          _buildError()
                        else if (_hasSearched)
                          _buildDoctorList()
                        else
                          const SizedBox.shrink(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _usePosition => _userLat != null && _userLon != null;

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Médecin',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _nameController,
            decoration: InputDecoration(
              hintText: 'Nom du professionnel de santé',
              prefixIcon: Icon(Icons.person_search_rounded, color: _skyBlue),
              filled: true,
              fillColor: HeadsAppColors.surfaceMuted,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
            enabled: _allowName,
            onChanged: (value) {
              if (!_allowName) return;
              _searchDebounceTimer?.cancel();
              _searchDebounceTimer = Timer(const Duration(milliseconds: 500), () {
                _search();
              });
            },
            onFieldSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _specialty,
            decoration: InputDecoration(
              labelText: 'Spécialité',
              prefixIcon: Icon(Icons.medical_services_rounded, color: _skyBlue),
              filled: true,
              fillColor: HeadsAppColors.surfaceMuted,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
            disabledHint: Text(
              'Spécialité indisponible (mode sélectionné)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black45),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('Toutes')),
              ...kSpecialties.map((s) => DropdownMenuItem(value: s, child: Text(s))),
            ],
            onChanged: _allowSpecialty
                ? (v) {
                    setState(() => _specialty = v);
                    _search();
                  }
                : null,
          ),
          const SizedBox(height: 12),
          if (_usePosition)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(Icons.near_me_rounded, size: 18, color: _skyBlue),
                  const SizedBox(width: 8),
                  Text(
                    'Résultats triés par distance',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _skyBlue,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),

          if (!_usePosition && _allowGovernorate) ...[
            DropdownButtonFormField<String>(
              initialValue: _governorate,
              decoration: InputDecoration(
                labelText: 'Ville',
                prefixIcon: Icon(Icons.location_city_rounded, color: _skyBlue),
                suffixIcon: IconButton(
                  tooltip: 'Utiliser la localisation',
                  onPressed: _locationLoading
                      ? null
                      : () async {
                          await _useMyLocation();
                        },
                  icon: _locationLoading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: _skyBlue),
                        )
                      : Icon(Icons.my_location_rounded, color: _skyBlue),
                ),
                filled: true,
                fillColor: HeadsAppColors.surfaceMuted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Tous')),
                ...kGovernorates.map(
                  (g) => DropdownMenuItem(value: g, child: Text(g)),
                ),
              ],
              onChanged: (v) {
                setState(() => _governorate = v);
                _search();
              },
            ),
          ],

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loading ? null : _search,
              icon: const Icon(Icons.search_rounded, size: 20),
              label: const Text('RECHERCHER'),
              style: FilledButton.styleFrom(
                backgroundColor: HeadsAppColors.brandPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          if (_locationError != null) ...[
            const SizedBox(height: 12),
            Text(
              _locationError!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.red.shade700),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.red.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(color: Colors.red.shade900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoctorList() {
    if (_doctors.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.medical_services_outlined, size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                'Aucun médecin trouvé pour ces critères.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.black54),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_usePosition) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _skyBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _skyBlue.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                Icon(Icons.near_me_rounded, size: 20, color: _skyBlue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Médecins les plus proches (triés par distance)',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Text(
              '${_doctors.length} médecin${_doctors.length > 1 ? 's' : ''} trouvé${_doctors.length > 1 ? 's' : ''}',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
            ),
            if (_userLat != null && _userLon != null) ...[
              const SizedBox(width: 10),
              Icon(Icons.near_me_rounded, size: 18, color: _skyBlue),
              const SizedBox(width: 4),
              Text(
                'par distance',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _skyBlue,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        ..._doctors.map(
          (d) => _DoctorCard(
            doctor: d,
            skyBlue: _skyBlue,
            patientId: widget.patientId,
            patientName: widget.patientName,
          ),
        ),
      ],
    );
  }
}

class _DoctorCard extends StatelessWidget {
  const _DoctorCard({
    required this.doctor,
    required this.skyBlue,
    required this.patientId,
    required this.patientName,
  });

  final Map<String, dynamic> doctor;
  final Color skyBlue;
  final String patientId;
  final String patientName;

  @override
  Widget build(BuildContext context) {
    final fullName = readableDoctorName(doctor['fullName'] as String?, fallback: '—');
    final nameParts =
        fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final lastName = nameParts.length >= 2 ? nameParts.last : fullName;
    final firstName = nameParts.length >= 2 ? nameParts.sublist(0, nameParts.length - 1).join(' ') : '';

    final specialty = readableDecryptedField(
      doctor['specialty']?.toString(),
      fallback: '—',
    );
    final governorate = readableDecryptedField(doctor['governorate'] as String?, fallback: '—');
    final distanceKm = doctor['distanceKm'] as num?;
    final status = doctor['status'] as String? ?? 'available';
    final doctorId = doctor['id']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  doctorAvatarForPatient(
                    name: fullName,
                    doctorPhotoPath: doctor['photoPath']?.toString(),
                    radius: 26,
                    backgroundColor: skyBlue.withValues(alpha: 0.12),
                    accentColor: skyBlue,
                    fallbackChild: Icon(Icons.person_rounded, color: skyBlue, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullName,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          specialty,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.black54,
                                  ),
                        ),
                        Text(
                          governorate,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.black45,
                                  ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _statusColor(status).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _statusLabel(status),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _statusColor(status),
                              ),
                            ),
                          ),
                        ),
                        if (distanceKm != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Icon(Icons.location_on_rounded,
                                    size: 14, color: skyBlue),
                                const SizedBox(width: 4),
                                Text(
                                  'À ${distanceKm == distanceKm.truncate() ? distanceKm.toInt() : distanceKm.toStringAsFixed(1)} km',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: skyBlue,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      final address = readableDecryptedField(doctor['address']?.toString());
                      showModalBottomSheet<void>(
                        context: context,
                        backgroundColor: Colors.transparent,
                        isScrollControlled: true,
                        isDismissible: false,
                        enableDrag: false,
                        builder: (ctx) {
                          final statusColor = _statusColor(status);
                          final addressExact =
                              address.isEmpty ? null : address;

                          const ratingOptions = [
                            {
                              'key': 'very_satisfied',
                              'label': 'Très satisfait',
                            },
                            {
                              'key': 'satisfied',
                              'label': 'Satisfait',
                            },
                            {
                              'key': 'somewhat_satisfied',
                              'label': 'Assez satisfait',
                            },
                          ];

                          String? selectedRating;
                          bool loadedExistingRating = false;
                          bool saving = false;
                          bool saved = false;

                          return StatefulBuilder(
                            builder: (ctx, setState) {
                              if (!loadedExistingRating) {
                                loadedExistingRating = true;
                                ApiService
                                    .getDoctorEvaluation(
                                  doctorId: doctorId,
                                  patientId: patientId,
                                )
                                    .then((data) {
                                  final evaluation = data['evaluation'];
                                  if (evaluation is Map) {
                                    final s =
                                        evaluation['satisfaction']?.toString();
                                    if (s != null) {
                                      setState(() {
                                        selectedRating = s;
                                        saved = true;
                                      });
                                    }
                                  }
                                }).catchError((_) {});
                              }
                              return Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.12),
                                        blurRadius: 30,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  padding: const EdgeInsets.all(18),
                                  child: SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            Container(
                                              height: 108,
                                              width: double.infinity,
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    statusColor.withValues(alpha: 0.25),
                                                    const Color(0xFF4FA8D5)
                                                        .withValues(alpha: 0.12),
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(18),
                                              ),
                                            ),
                                            Positioned(
                                              top: -10,
                                              left: 0,
                                              right: 0,
                                              child: Center(
                                                child: doctorAvatarForPatient(
                                                  name: fullName,
                                                  doctorPhotoPath: doctor['photoPath']
                                                      ?.toString(),
                                                  radius: 44,
                                                  backgroundColor: statusColor
                                                      .withValues(alpha: 0.12),
                                                  accentColor: statusColor,
                                                  fallbackChild: Icon(
                                                    Icons
                                                        .medical_services_rounded,
                                                    color: statusColor,
                                                    size: 44,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Positioned(
                                              right: -6,
                                              top: 0,
                                              child: IconButton(
                                                tooltip: 'Fermer',
                                                icon: const Icon(
                                                  Icons.close_rounded,
                                                color: Colors.black87,
                                                  size: 20,
                                                ),
                                                onPressed: () =>
                                                    Navigator.of(ctx).pop(),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 64),

                                        Center(
                                          child: Text(
                                            (lastName.isNotEmpty &&
                                                    firstName.isNotEmpty)
                                                ? '$firstName $lastName'
                                                : fullName,
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(ctx)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),

                                        const SizedBox(height: 14),

                                        // Spécialité (encadré)
                                        SizedBox(
                                          height: 84,
                                          width: double.infinity,
                                          child: Container(
                                            padding:
                                                const EdgeInsets.all(14),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              border: Border.all(
                                                color: Colors.grey.shade300,
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Spécialité',
                                                  style: Theme.of(ctx)
                                                      .textTheme
                                                      .labelLarge
                                                      ?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  specialty,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(ctx)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                    fontWeight: FontWeight.w500,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),

                                        const SizedBox(height: 12),

                                        // Adresse exacte (encadré)
                                        SizedBox(
                                          height: 84,
                                          width: double.infinity,
                                          child: Container(
                                            padding:
                                                const EdgeInsets.all(14),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              border: Border.all(
                                                color: Colors.grey.shade300,
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Adresse exacte',
                                                  style: Theme.of(ctx)
                                                      .textTheme
                                                      .labelLarge
                                                      ?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  addressExact ?? '—',
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(ctx)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                    color: Colors.black54,
                                                    height: 1.25,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),

                                        const SizedBox(height: 16),

                                        // Évaluation (encadré)
                                        Container(
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade50,
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            border: Border.all(
                                              color: Colors.grey.shade200,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Évaluer ce médecin',
                                                style: Theme.of(ctx)
                                                    .textTheme
                                                    .labelLarge
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: Colors.black87,
                                                    ),
                                              ),
                                              const SizedBox(height: 10),
                                              DropdownButtonFormField<String>(
                                                initialValue: selectedRating,
                                                decoration: InputDecoration(
                                                  prefixIcon:
                                                      Icon(Icons.star_rounded,
                                                          color: skyBlue),
                                                  filled: true,
                                                  fillColor:
                                                      const Color(0xFFF5FBFF),
                                                  border: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(14),
                                                    borderSide: BorderSide.none,
                                                  ),
                                                ),
                                                items: ratingOptions
                                                    .map((o) =>
                                                        DropdownMenuItem(
                                                          value: o['key'] as String,
                                                          child: Text(
                                                            o['label'] as String,
                                                          ),
                                                        ))
                                                    .toList(),
                                                onChanged: saving
                                                    ? null
                                                    : (v) {
                                                        setState(() {
                                                          selectedRating = v;
                                                          saved = false;
                                                        });
                                                      },
                                              ),
                                              const SizedBox(height: 12),
                                              SizedBox(
                                                width: double.infinity,
                                                child: FilledButton.icon(
                                                  onPressed:
                                                      (saving || selectedRating == null)
                                                          ? null
                                                          : () async {
                                                      try {
                                                        setState(() {
                                                          saving = true;
                                                        });
                                                        await ApiService
                                                            .evaluateDoctor(
                                                          doctorId: doctorId,
                                                          patientId: patientId,
                                                          satisfaction:
                                                              selectedRating!,
                                                        );
                                                        setState(() {
                                                          saving = false;
                                                          saved = true;
                                                        });
                                                        if (ctx.mounted) {
                                                          Navigator.of(ctx).pop();
                                                        }
                                                      } catch (e) {
                                                        setState(() {
                                                          saving = false;
                                                        });
                                                        if (!context.mounted) return;
                                                        ScaffoldMessenger.of(context)
                                                            .showSnackBar(
                                                          SnackBar(
                                                            content: Text(
                                                              e.toString().replaceFirst(
                                                                      'Exception: ',
                                                                      ''),
                                                            ),
                                                            duration:
                                                                const Duration(
                                                                    seconds: 3),
                                                          ),
                                                        );
                                                      }
                                                    },
                                                  icon: saving
                                                      ? const SizedBox(
                                                          width: 18,
                                                          height: 18,
                                                          child:
                                                              CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color: Colors.white,
                                                          ),
                                                        )
                                                      : const Icon(Icons.check_rounded),
                                                  label: Text(saved
                                                      ? 'Enregistré'
                                                      : 'Enregistrer'),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      foregroundColor: Colors.grey.shade700,
                      side: BorderSide(color: Colors.grey.shade300),
                      backgroundColor: Colors.grey.shade100,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Profil'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      if (doctorId.isEmpty) return;
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('lastRoute', 'chat');
                      await prefs.setString('chatDoctorId', doctorId);
                      await prefs.setString('chatDoctorName', fullName);
                      if (!context.mounted) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ChatPage(
                            patientId: patientId,
                            doctorId: doctorId,
                            doctorName: fullName,
                            doctorPhotoPath: doctor['photoPath']?.toString(),
                          ),
                        ),
                      );
                      if (!context.mounted) return;
                      await prefs.remove('lastRoute');
                      await prefs.remove('chatDoctorId');
                      await prefs.remove('chatDoctorName');
                      await prefs.remove('chatDoctorPhotoPath');
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE1395F),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Contacter'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'available':
      return 'En ligne';
    case 'busy':
      return 'Occupé';
    case 'unavailable':
      return 'Non disponible';
    default:
      return 'En ligne';
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'available':
      return const Color(0xFF4FA8D5);
    case 'busy':
      return Colors.orange;
    case 'unavailable':
      return Colors.grey;
    default:
      return const Color(0xFF4FA8D5);
  }
}
