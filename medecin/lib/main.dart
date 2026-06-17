import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'espace_medecin_shell.dart';
import 'headsapp_theme.dart';
import 'login_page.dart';
import 'screens/onboarding/onboarding_flow.dart';
import 'services/api_service.dart';
import 'services/onboarding_service.dart';
import 'services/push_notification_service.dart';
import 'session_keys.dart';
import 'utils/doctor_session_utils.dart';
import 'utils/doctor_ui_utils.dart';
import 'widgets/doctor_waiting_room_global_banner.dart';

/// Clé de navigation pour ouvrir le chat depuis la bannière salle d’attente.
final GlobalKey<NavigatorState> kMedecinNavigatorKey =
    GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  final hasSeenOnboarding = await OnboardingService.hasSeenOnboarding();
  runApp(MedecinApp(initialRoute: hasSeenOnboarding ? '/home' : '/onboarding'));
}

class MedecinApp extends StatelessWidget {
  const MedecinApp({super.key, required this.initialRoute});

  final String initialRoute;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: kMedecinNavigatorKey,
      title: 'Médecin',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [
        Locale('fr', 'FR'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: HeadsAppTheme.light(),
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
          child: Stack(
            fit: StackFit.expand,
            children: [
              child ?? const SizedBox.expand(),
              DoctorWaitingRoomGlobalBanner(navigatorKey: kMedecinNavigatorKey),
            ],
          ),
        );
      },
      initialRoute: initialRoute,
      routes: {
        '/onboarding': (_) => const OnboardingFlow(),
        '/home': (_) => const _SessionBootstrap(),
      },
    );
  }
}

class _SessionBootstrap extends StatefulWidget {
  const _SessionBootstrap();

  @override
  State<_SessionBootstrap> createState() => _SessionBootstrapState();
}

class _SessionBootstrapState extends State<_SessionBootstrap> {
  late final Future<Widget> _homeFuture;

  @override
  void initState() {
    super.initState();
    _homeFuture = _resolveInitialHome();
  }

  Future<Widget> _resolveInitialHome() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(kSessionDoctorIdKey) ?? '';
      final cachedName = prefs.getString(kSessionDoctorNameKey);
      final tok = prefs.getString(kSessionDoctorTokenKey)?.trim() ?? '';
      ApiService.setJwtToken(tok.isEmpty ? null : tok);
      // Sans JWT, les routes protégées renvoient 401 « Authentification requise. »
      if (id.isNotEmpty && tok.isNotEmpty) {
        await PushNotificationService.instance.initializeForDoctor(
          doctorId: id,
        );
        final name = await resolveDoctorDisplayName(
          doctorId: id,
          cached: cachedName,
        );
        return EspaceMedecinShell(doctorId: id, doctorName: name);
      }
    } catch (_) {}
    return const LoginPage();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _homeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snapshot.data ?? const LoginPage();
      },
    );
  }
}
