import 'package:flutter/material.dart';

import 'screens/doctor_home_screen.dart';

/// Point d’entrée après connexion : accueil personnalisé (AppBar, drawer, onglets).
class EspaceMedecinShell extends StatelessWidget {
  const EspaceMedecinShell({
    super.key,
    required this.doctorId,
    required this.doctorName,
  });

  final String doctorId;
  final String doctorName;

  @override
  Widget build(BuildContext context) {
    return DoctorHomeScreen(
      doctorId: doctorId,
      initialDoctorName: doctorName,
    );
  }
}
