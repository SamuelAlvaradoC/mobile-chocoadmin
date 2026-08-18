// Verifica el reporte "ingreso una contraseña incorrecta y no me inicia
// sesión pero igual me manda a la landing": monta la pantalla real de Login
// con un backend mockeado que responde 401 (credenciales incorrectas) y
// confirma que efectivamente NO navega a ningún lado y sí muestra un error
// visible -- esto ya se había corregido en una sesión anterior (commit
// a43f2f4: login_screen.dart ignoraba el bool de AuthProvider.login() y
// navegaba igual), este test deja el comportamiento correcto bajo
// regresión permanente.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chocoadmin/core/services/api_service.dart';
import 'package:chocoadmin/features/auth/providers/auth_provider.dart';
import 'package:chocoadmin/features/auth/screens/login_screen.dart';

Widget _harness() => MaterialApp(
      home: MultiProvider(providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ], child: const LoginScreen()),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Viewport ancho de celular real -- LoginScreen tiene un layout
    // responsive (MediaQuery.width > 700 muestra una variante de escritorio
    // con panel lateral) que desborda en el surface angosto por defecto de
    // flutter_test si cae en ese punto de quiebre.
  });

  tearDown(() {
    ApiService.client = MockClient((_) async => http.Response('No mockeado', 400));
  });

  testWidgets('contraseña incorrecta: NO navega a ningún lado y muestra el error', (tester) async {
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    ApiService.client = MockClient((req) async {
      if (req.url.path.contains('/api/auth/login')) {
        return http.Response(
          '{"message":"Correo o contraseña incorrectos"}',
          401,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('No mockeado', 404);
    });

    await tester.pumpWidget(_harness());
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, 'alguien@test.com');
    // El segundo TextField es la contraseña.
    await tester.enterText(find.byType(TextField).at(1), 'contrasena-que-no-es');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pump(); // dispara el loading
    await tester.pumpAndSettle();

    // Sigue en Login -- si hubiera navegado a /landing (el bug reportado),
    // este texto (exclusivo de LoginScreen) ya no estaría en el árbol.
    expect(find.text('Bienvenido de nuevo'), findsOneWidget,
        reason: 'con credenciales incorrectas NO debe navegar a ningún lado');
    expect(find.textContaining('incorrect'), findsOneWidget,
        reason: 'debe mostrar visiblemente el error del backend');
  });
}
