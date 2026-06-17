import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:medecin/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Affiche la page de connexion après le chargement', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MedecinApp());
    await tester.pumpAndSettle();
    expect(find.text('Bienvenue, Docteur'), findsOneWidget);
  });
}
