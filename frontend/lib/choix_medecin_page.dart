import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'headsapp_theme.dart';
import 'services/api_service.dart';
import 'utils/patient_ui_utils.dart';
import 'widgets/doctor_interaction_dialog.dart';

enum _FilterMode { nameOnly, nameAndSpecialty, governorateAndSpecialty, all }

enum _DoctorSort { relevance, distance, name }

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
  static const Color _titleNavy = Color(0xFF1A458B);
  static const Color _pageBg = Color(0xFFF1F5F9);
  static const Color _fieldBg = Color(0xFFF0F4F8);
  static const Color _labelGrey = Color(0xFF9CA3AF);
  static const Color _textGrey = Color(0xFF6B7280);

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
  bool _loading = false;
  bool _hasSearched = false;
  String? _searchError;
  List<Map<String, dynamic>> _doctors = [];
  _DoctorSort _sortBy = _DoctorSort.relevance;

  double? _userLat;
  double? _userLon;
  bool _locationLoading = false;
  String? _locationError;

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
    super.dispose();
  }

  Future<void> _search() async {
    final currentRequestId = ++_searchRequestId;
    setState(() {
      _loading = true;
      _searchError = null;
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
          _hasSearched = true;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted && currentRequestId == _searchRequestId) {
        setState(() {
          _loading = false;
          _hasSearched = true;
          _searchError = e.toString().replaceFirst('Exception: ', '');
          _doctors = [];
        });
      }
    }
  }

  List<Map<String, dynamic>> get _sortedDoctors {
    final copy = List<Map<String, dynamic>>.from(_doctors);
    switch (_sortBy) {
      case _DoctorSort.distance:
        copy.sort((a, b) {
          final da = (a['distanceKm'] as num?)?.toDouble() ?? double.infinity;
          final db = (b['distanceKm'] as num?)?.toDouble() ?? double.infinity;
          return da.compareTo(db);
        });
      case _DoctorSort.name:
        copy.sort((a, b) {
          final na = readableDoctorName(a['fullName'] as String?, fallback: '');
          final nb = readableDoctorName(b['fullName'] as String?, fallback: '');
          return na.toLowerCase().compareTo(nb.toLowerCase());
        });
      case _DoctorSort.relevance:
        break;
    }
    return copy;
  }

  String? _locationLabel() {
    if (_userLat != null && _userLon != null) {
      return 'Position actuelle';
    }
    if (_governorate != null && _governorate!.trim().isNotEmpty) {
      return _governorate;
    }
    return null;
  }

  InputDecoration _fieldDecoration({
    required IconData icon,
    String? hintText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      prefixIcon: Icon(icon, color: _titleNavy, size: 22),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: _fieldBg,
      hintStyle: const TextStyle(color: _labelGrey, fontWeight: FontWeight.w500),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: _labelGrey,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      body: Stack(
        children: [
          Positioned(
            top: -40,
            right: -30,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFCE4EC).withValues(alpha: 0.55),
              ),
            ),
          ),
          Positioned(
            bottom: 120,
            left: -50,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFCE4EC).withValues(alpha: 0.4),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 20, 0),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          onPressed: () async {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString('lastRoute', 'espace_patient');
                            if (!context.mounted) return;
                            Navigator.of(context).pop();
                          },
                          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                          color: _titleNavy,
                        ),
                      ),
                      Text(
                        'Rechercher un médecin',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: _titleNavy,
                              fontSize: 19,
                              letterSpacing: -0.2,
                            ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                  child: Text(
                    'Bonjour ${readablePatientName(widget.patientName)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: _textGrey,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildFilters(),
                          const SizedBox(height: 20),
                          _GradientSearchButton(
                            loading: _loading,
                            onPressed: _loading ? null : _search,
                          ),
                          if (_hasSearched) ...[
                            const SizedBox(height: 24),
                            _buildResultsSection(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool get _usePosition => _userLat != null && _userLon != null;

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
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
          Row(
            children: [
              const Icon(Icons.search_rounded, color: _titleNavy, size: 22),
              const SizedBox(width: 8),
              Text(
                'Recherche rapide',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: _titleNavy,
                      fontSize: 16,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _nameController,
            style: const TextStyle(
              color: _titleNavy,
              fontWeight: FontWeight.w600,
            ),
            decoration: _fieldDecoration(
              icon: Icons.person_search_rounded,
              hintText: 'Rechercher par nom',
            ),
            enabled: _allowName,
            onFieldSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 18),
          if (_allowSpecialty) ...[
            _sectionLabel('SPÉCIALITÉ'),
            DropdownButtonFormField<String>(
              initialValue: _specialty,
              isExpanded: true,
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: _titleNavy,
              ),
              style: const TextStyle(
                color: _titleNavy,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
              decoration: _fieldDecoration(icon: Icons.medical_services_outlined),
              disabledHint: Text(
                'Spécialité indisponible (mode sélectionné)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _textGrey),
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Toutes les spécialités'),
                ),
                ...kSpecialties.map((s) => DropdownMenuItem(value: s, child: Text(s))),
              ],
              onChanged: _allowSpecialty
                  ? (v) => setState(() => _specialty = v)
                  : null,
            ),
            const SizedBox(height: 18),
          ],
          if (!_usePosition && _allowGovernorate) ...[
            _sectionLabel('VILLE'),
            DropdownButtonFormField<String>(
              initialValue: _governorate,
              isExpanded: true,
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: _titleNavy,
              ),
              style: const TextStyle(
                color: _titleNavy,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
              decoration: _fieldDecoration(icon: Icons.location_city_outlined),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Toutes les villes'),
                ),
                ...kGovernorates.map(
                  (g) => DropdownMenuItem(value: g, child: Text(g)),
                ),
              ],
              onChanged: (v) => setState(() => _governorate = v),
            ),
            const SizedBox(height: 22),
          ],
          Text(
            'Proximité',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: _titleNavy,
                  fontSize: 16,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Trouvez les praticiens les plus proches de votre position actuelle.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _textGrey,
                  height: 1.4,
                ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: _fieldBg,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 10),
                  child: Icon(Icons.place_outlined, color: _titleNavy, size: 22),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    child: Text(
                      _locationLabel() ?? 'Localisation',
                      style: TextStyle(
                        color: _locationLabel() == null ? _labelGrey : _titleNavy,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Utiliser la localisation',
                  onPressed: _locationLoading ? null : _useMyLocation,
                  icon: _locationLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _titleNavy,
                          ),
                        )
                      : const Icon(Icons.my_location_rounded, color: _titleNavy),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _locationLoading ? null : _useMyLocation,
              icon: const Icon(Icons.navigation_rounded, size: 18, color: _titleNavy),
              label: const Text(
                'Utiliser ma localisation',
                style: TextStyle(
                  color: _titleNavy,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: OutlinedButton.styleFrom(
                backgroundColor: _fieldBg,
                side: BorderSide.none,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          if (_locationError != null) ...[
            const SizedBox(height: 12),
            Text(
              _locationError!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.red.shade700,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultsSection() {
    if (_searchError != null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          _searchError!,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.red.shade700,
                fontWeight: FontWeight.w500,
              ),
        ),
      );
    }

    final doctors = _sortedDoctors;
    final count = doctors.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$count résultat${count > 1 ? 's' : ''} trouvé${count > 1 ? 's' : ''}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: _titleNavy,
                      fontSize: 15,
                    ),
              ),
            ),
            Text(
              'Trier par:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _textGrey,
                    fontWeight: FontWeight.w500,
                  ),
            ),
            const SizedBox(width: 4),
            DropdownButton<_DoctorSort>(
              value: _sortBy,
              underline: const SizedBox.shrink(),
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: _titleNavy,
                size: 20,
              ),
              style: const TextStyle(
                color: _titleNavy,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
              items: const [
                DropdownMenuItem(
                  value: _DoctorSort.relevance,
                  child: Text('Pertinence'),
                ),
                DropdownMenuItem(
                  value: _DoctorSort.distance,
                  child: Text('Distance'),
                ),
                DropdownMenuItem(
                  value: _DoctorSort.name,
                  child: Text('Nom'),
                ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _sortBy = v);
              },
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (doctors.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Icon(Icons.search_off_rounded, size: 48, color: _textGrey.withValues(alpha: 0.6)),
                const SizedBox(height: 12),
                Text(
                  'Aucun médecin trouvé',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: _titleNavy,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Essayez d’élargir vos critères de recherche.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _textGrey),
                ),
              ],
            ),
          )
        else
          ...doctors.map(
            (d) => _DoctorCard(
              doctor: d,
              skyBlue: _titleNavy,
              patientId: widget.patientId,
              patientName: widget.patientName,
            ),
          ),
      ],
    );
  }
}

class _GradientSearchButton extends StatelessWidget {
  const _GradientSearchButton({
    required this.onPressed,
    this.loading = false,
  });

  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: onPressed == null
            ? null
            : const LinearGradient(
                colors: [
                  Color(0xFFE8719A),
                  Color(0xFF3B5998),
                ],
              ),
        color: onPressed == null ? const Color(0xFFE5E7EB) : null,
        boxShadow: onPressed == null
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF3B5998).withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            width: double.infinity,
            height: HeadsAppMetrics.buttonHeight,
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Rechercher',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
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

  String _displayDoctorName(String fullName) {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return 'Dr. —';
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('dr.') || lower.startsWith('dr ')) return trimmed;
    return 'Dr. $trimmed';
  }

  String _availabilityLabel(String status) {
    switch (status) {
      case 'available':
        return 'Disponible maintenant';
      case 'busy':
        return 'Occupé pour le moment';
      case 'unavailable':
        return 'Non disponible';
      default:
        return 'Disponible maintenant';
    }
  }

  @override
  Widget build(BuildContext context) {
    final fullName = readableDoctorName(doctor['fullName'] as String?, fallback: '—');
    final specialty = readableDecryptedField(
      doctor['specialty']?.toString(),
      fallback: '—',
    );
    final governorate = readableDecryptedField(doctor['governorate'] as String?, fallback: '—');
    final address = readableDecryptedField(doctor['address']?.toString());
    final clinicLabel = address.isNotEmpty
        ? address.split(RegExp(r'[\n,]')).first.trim()
        : governorate;
    final distanceKm = doctor['distanceKm'] as num?;
    final status = doctor['status'] as String? ?? 'available';
    final doctorId = doctor['id']?.toString() ?? '';
    final photoPath = doctor['photoPath']?.toString();
    final photoUrl = ApiService.resolveMediaUrlOrNull(photoPath);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 4,
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFE8719A),
                    Color(0xFF3B5998),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: 72,
                          height: 72,
                          color: const Color(0xFFE8F0FE),
                          child: photoUrl != null
                              ? Image.network(
                                  photoUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Icon(
                                    Icons.person_rounded,
                                    color: skyBlue,
                                    size: 36,
                                  ),
                                )
                              : Icon(Icons.person_rounded, color: skyBlue, size: 36),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F4FD),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                specialty.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF1A458B),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 10.5,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _displayDoctorName(fullName),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF111827),
                                    height: 1.15,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(
                                  Icons.local_hospital_outlined,
                                  size: 15,
                                  color: Color(0xFF6B7280),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    clinicLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF6B7280),
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F4F8),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              size: 16,
                              color: Color(0xFF1A458B),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                distanceKm != null
                                    ? '$governorate · ${distanceKm == distanceKm.truncate() ? distanceKm.toInt() : distanceKm.toStringAsFixed(1)} km'
                                    : governorate,
                                style: const TextStyle(
                                  color: Color(0xFF374151),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_today_outlined,
                              size: 16,
                              color: Color(0xFF1A458B),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _availabilityLabel(status),
                                style: const TextStyle(
                                  color: Color(0xFF374151),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFE8719A),
                          Color(0xFF3B5998),
                        ],
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          showDoctorInteractionDialog(
                            context,
                            doctor: doctor,
                            patientId: patientId,
                          );
                        },
                        borderRadius: BorderRadius.circular(999),
                        child: const SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: Center(
                            child: Text(
                              'Voir plus',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
