import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'headsapp_theme.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'services/push_notification_service.dart';
import 'login_page.dart';
import 'bloc_urgence_page.dart';
import 'chat_page.dart';
import 'choix_medecin_page.dart';
import 'dossier_medical_page.dart';
import 'discussions_patient_page.dart';
import 'espace_patient_page.dart';
import 'rendezvous_patient_page.dart';
import 'screens/blood_pressure_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'widgets/patient_incoming_call_host.dart';
import 'services/call_navigation_bridge.dart';
import 'utils/patient_session_utils.dart';
import 'utils/patient_ui_utils.dart';

final GlobalKey<NavigatorState> patientNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PushNotificationService.navigatorKey = patientNavigatorKey;
  CallNavigationBridge.navigatorKey = patientNavigatorKey;
  // Requis pour les notifications en arrière-plan / app fermée (Android/iOS). Inopérant sur Web.
  if (!kIsWeb) {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      NotificationService.registerBackgroundHandler();
    } catch (e) {
      debugPrint('[FCM] initialisation au démarrage: $e');
    }
  }
  runApp(MyApp(navigatorKey: patientNavigatorKey));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (context, themeMode, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'Télémedecine',
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [
            Locale('fr'),
            Locale('en'),
          ],
          theme: HeadsAppTheme.light(),
          darkTheme: HeadsAppTheme.dark(),
          themeMode: themeMode,
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            final vi = mq.viewInsets;
            final safeInsets = EdgeInsets.fromLTRB(
              vi.left.clamp(0.0, double.infinity),
              vi.top.clamp(0.0, double.infinity),
              vi.right.clamp(0.0, double.infinity),
              vi.bottom.clamp(0.0, double.infinity),
            );
            return MediaQuery(
              data: mq.copyWith(viewInsets: safeInsets),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const _RootRouter(),
          routes: {
            '/login': (_) => const LoginPage(),
          },
        );
      },
    );
  }
}

/// Gère le routage initial : si une session patient existe, on va directement
/// sur le bloc d'urgence, sinon on affiche l'écran de login.
class _RootRouter extends StatefulWidget {
  const _RootRouter();

  @override
  State<_RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<_RootRouter> {
  Future<({Map<String, String>? session, bool onboardingCompleted})> _loadAppState() async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingCompleted = prefs.getBool('onboarding_completed') ?? false;
    final patientId = prefs.getString('patientId');
    final patientName = prefs.getString('patientName');
    final patientJwt = prefs.getString('patient_jwt');
    ApiService.setJwtToken(patientJwt);
    final lastRoute = prefs.getString('lastRoute');
    final chatDoctorId = prefs.getString('chatDoctorId');
    final chatDoctorName = prefs.getString('chatDoctorName');
    final chatDoctorPhotoPath = prefs.getString('chatDoctorPhotoPath');
    if (patientId != null && patientId.isNotEmpty) {
      await PushNotificationService.instance.initializeForPatient(patientId: patientId);
      final displayName = await resolvePatientDisplayName(
        patientId: patientId,
        cached: patientName,
      );
      final map = <String, String>{
        'id': patientId,
        'name': displayName,
      };
      if (lastRoute != null) map['lastRoute'] = lastRoute;
      if (chatDoctorId != null) map['chatDoctorId'] = chatDoctorId;
      if (chatDoctorName != null) map['chatDoctorName'] = chatDoctorName;
      if (chatDoctorPhotoPath != null && chatDoctorPhotoPath.isNotEmpty) {
        map['chatDoctorPhotoPath'] = chatDoctorPhotoPath;
      }
      return (session: map, onboardingCompleted: onboardingCompleted);
    }
    return (session: null, onboardingCompleted: onboardingCompleted);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({Map<String, String>? session, bool onboardingCompleted})>(
      future: _loadAppState(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final appState = snapshot.data;
        final session = appState?.session;
        if (session != null) {
          late final Widget home;
          final lastRoute = session['lastRoute'];
          if (lastRoute == 'chat' &&
              session['chatDoctorId'] != null &&
              (session['chatDoctorId'] ?? '').isNotEmpty) {
            home = ChatPage(
              patientId: session['id']!,
              doctorId: session['chatDoctorId']!,
              doctorName: readableDoctorName(session['chatDoctorName']),
              doctorPhotoPath: session['chatDoctorPhotoPath'],
            );
          } else if (lastRoute == 'espace_patient') {
            home = EspacePatientPage(
              patientName: session['name'] ?? 'Patient',
              patientId: session['id']!,
            );
          } else if (lastRoute == 'choix_medecin') {
            home = ChoixMedecinPage(
              patientName: session['name'] ?? 'Patient',
              patientId: session['id']!,
            );
          } else if (lastRoute == 'discussions') {
            home = DiscussionsPatientPage(
              patientId: session['id']!,
              patientName: session['name'] ?? 'Patient',
            );
          } else if (lastRoute == 'rendezvous') {
            home = RendezVousPatientPage(
              patientName: session['name'] ?? 'Patient',
              patientId: session['id']!,
            );
          } else if (lastRoute == 'dossier_medical') {
            home = DossierMedicalPage(
              patientId: session['id']!,
            );
          } else if (lastRoute == 'tensiometre') {
            home = BloodPressureScreen(
              patientId: session['id']!,
              patientName: session['name'] ?? 'Patient',
            );
          } else {
            home = BlocUrgencePage(
              patientName: session['name'] ?? 'Patient',
              patientId: session['id'],
            );
          }

          return PatientIncomingCallHost(
            patientId: session['id']!,
            child: home,
          );
        }

        if (!(appState?.onboardingCompleted ?? false)) {
          return const OnboardingScreen();
        }

        return const LoginPage();
      },
    );
  }
}
