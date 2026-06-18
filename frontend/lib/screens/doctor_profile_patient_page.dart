import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/patient_ui_utils.dart';

class DoctorProfilePatientPage extends StatelessWidget {
  const DoctorProfilePatientPage({
    super.key,
    required this.doctor,
    required this.patientId,
  });

  final Map<String, dynamic> doctor;
  final String patientId;

  static const Color _titleNavy = Color(0xFF1A458B);
  static const Color _textGrey = Color(0xFF6B7280);
  static const Color _bioBg = Color(0xFFF2F4F7);
  static const Color _onlineGreen = Color(0xFF2ECC71);

  String _displayDoctorName(String fullName) {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return 'Dr. —';
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('dr.') || lower.startsWith('dr ')) return trimmed;
    return 'Dr. $trimmed';
  }

  String _statusBadge(String status) {
    switch (status) {
      case 'busy':
        return 'OCCUPÉ';
      case 'unavailable':
        return 'NON DISPONIBLE';
      default:
        return 'DISPONIBLE';
    }
  }

  ({String clinic, String location}) _clinicAndLocation({
    required String hospital,
    required String address,
    required String governorate,
  }) {
    final addressParts = address
        .split(RegExp(r'[\n,]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    var clinic = hospital;
    var location = '';

    if (clinic.isEmpty && addressParts.isNotEmpty) {
      clinic = addressParts.first;
    }
    if (addressParts.length > 1) {
      location = addressParts[1];
    } else if (address.isNotEmpty && clinic != address) {
      location = address;
    }
    if (location.isEmpty) {
      location = governorate;
    }
    if (clinic.isEmpty) {
      clinic = governorate;
      if (location == governorate) location = '';
    }

    return (clinic: clinic, location: location);
  }

  String _buildShortBio({
    required String specialty,
    required int yearsExperience,
  }) {
    final spec = specialty.trim().toLowerCase();
    final yearsPart = yearsExperience > 0
        ? ' avec plus de $yearsExperience ans d\'expérience'
        : '';

    if (spec.contains('cardio')) {
      return 'Spécialiste en cardiologie$yearsPart. Expert dans le traitement des pathologies coronariennes complexes et la prévention cardiovasculaire. Engagé dans une approche humaine et personnalisée du soin.';
    }
    if (yearsExperience > 0) {
      return 'Spécialiste en $specialty$yearsPart. Expert dans le traitement des pathologies liées à cette spécialité. Engagé dans une approche humaine et personnalisée du soin.';
    }
    return 'Spécialiste en $specialty. Engagé dans une approche humaine et personnalisée du soin.';
  }

  @override
  Widget build(BuildContext context) {
    final fullName = readableDoctorName(doctor['fullName'] as String?, fallback: '—');
    final specialty = readableDecryptedField(
      doctor['specialty']?.toString(),
      fallback: '—',
    );
    final governorate = readableDecryptedField(
      doctor['governorate']?.toString(),
      fallback: '—',
    );
    final address = readableDecryptedField(doctor['address']?.toString());
    final hospital = doctor['hospitalOrClinic']?.toString().trim() ?? '';
    final yearsExperience = (doctor['yearsExperience'] as num?)?.toInt() ?? 0;
    final status = doctor['status'] as String? ?? 'available';
    final photoPath = doctor['photoPath']?.toString();
    final photoUrl = ApiService.resolveMediaUrlOrNull(photoPath);
    final showOnlineDot = status == 'available';
    final lines = _clinicAndLocation(
      hospital: hospital,
      address: address,
      governorate: governorate,
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 8),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                      color: _titleNavy,
                    ),
                  ),
                  Text(
                    'Voir le profil',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: _titleNavy,
                          fontWeight: FontWeight.w700,
                          fontSize: 19,
                          letterSpacing: -0.2,
                        ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
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
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              CircleAvatar(
                                radius: 58,
                                backgroundColor: const Color(0xFFE8F0FE),
                                backgroundImage:
                                    photoUrl != null ? NetworkImage(photoUrl) : null,
                                child: photoUrl == null
                                    ? const Icon(
                                        Icons.person_rounded,
                                        color: _titleNavy,
                                        size: 58,
                                      )
                                    : null,
                              ),
                              if (showOnlineDot)
                                Positioned(
                                  right: 4,
                                  bottom: 4,
                                  child: Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      color: _onlineGreen,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 3),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F4FD),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _statusBadge(status),
                              style: const TextStyle(
                                color: _titleNavy,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _displayDoctorName(fullName),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF111827),
                                  fontSize: 22,
                                  letterSpacing: -0.3,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            specialty,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: _titleNavy,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                          ),
                          if (lines.clinic.isNotEmpty) ...[
                            const SizedBox(height: 18),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.local_hospital_outlined,
                                  size: 17,
                                  color: _textGrey,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    lines.clinic,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: _textGrey,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (lines.location.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  size: 17,
                                  color: _textGrey,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    lines.location,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: _textGrey,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                      decoration: BoxDecoration(
                        color: _bioBg,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: const BoxDecoration(
                                  color: _titleNavy,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.menu_book_outlined,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Biographie courte',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF111827),
                                      fontSize: 16,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _buildShortBio(
                              specialty: specialty,
                              yearsExperience: yearsExperience,
                            ),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: const Color(0xFF4B5563),
                                  height: 1.55,
                                  fontSize: 14.5,
                                ),
                          ),
                        ],
                      ),
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
