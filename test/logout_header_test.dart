// Verifica el ícono de cerrar sesión agregado a los headers de Catálogo y
// Landing (ClientLogoutAction): debe aparecer con sesión activa y no
// aparecer sin sesión, en ambas pantallas.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chocoadmin/core/services/api_service.dart';
import 'package:chocoadmin/features/auth/providers/auth_provider.dart';
import 'package:chocoadmin/features/cliente/providers/carrito_provider.dart';
import 'package:chocoadmin/features/cliente/providers/catalogo_provider.dart';
import 'package:chocoadmin/features/cliente/screens/catalogo_screen.dart';
import 'package:chocoadmin/shared/layouts/client_layout.dart';

Widget _harness(Widget child) => MaterialApp(
      home: MultiProvider(providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CatalogoProvider()),
        ChangeNotifierProvider(create: (_) => CarritoProvider()),
      ], child: child),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    ApiService.client = MockClient((_) async => http.Response('No mockeado', 400));
  });

  testWidgets('Catálogo: con sesión activa muestra el ícono de cerrar sesión', (tester) async {
    SharedPreferences.setMockInitialValues({
      'token': 'un-token', 'user_id': 1, 'user_name': 'Ana',
      'user_email': 'ana@test.com', 'user_role': 'cliente',
    });
    ApiService.client = MockClient((_) async => http.Response('{"data":[]}', 200,
        headers: {'content-type': 'application/json; charset=utf-8'}));

    await tester.pumpWidget(_harness(const CatalogoScreen()));
    // Autentica de verdad vía checkSession (lee SharedPreferences, no red).
    final ctx = tester.element(find.byType(CatalogoScreen));
    await ctx.read<AuthProvider>().checkSession();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byIcon(Icons.logout_rounded), findsOneWidget);
  });

  testWidgets('Catálogo: sin sesión NO muestra el ícono de cerrar sesión', (tester) async {
    SharedPreferences.setMockInitialValues({});
    ApiService.client = MockClient((_) async => http.Response('{"data":[]}', 200,
        headers: {'content-type': 'application/json; charset=utf-8'}));

    await tester.pumpWidget(_harness(const CatalogoScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byIcon(Icons.logout_rounded), findsNothing);
  });

  testWidgets('Landing (ClientLayout): con sesión activa muestra el ícono de cerrar sesión', (tester) async {
    SharedPreferences.setMockInitialValues({
      'token': 'un-token', 'user_id': 1, 'user_name': 'Ana',
      'user_email': 'ana@test.com', 'user_role': 'cliente',
    });

    await tester.pumpWidget(_harness(const ClientLayout(child: SizedBox())));
    final ctx = tester.element(find.byType(ClientLayout));
    await ctx.read<AuthProvider>().checkSession();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byIcon(Icons.logout_rounded), findsOneWidget);
  });
}
