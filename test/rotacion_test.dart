// Parte 2 (adversarial): la app todavía no tiene bloqueo de orientación
// (confirmado -- no hay screenOrientation en AndroidManifest.xml ni
// setPreferredOrientations en main.dart), así que rotar a mitad de un
// formulario es un caso real a considerar, no hipotético. Este test
// confirma qué pasa exactamente: ¿se pierde el texto ya escrito? ¿aparece
// un RenderFlex overflow?
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:chocoadmin/core/services/api_service.dart';
import 'package:chocoadmin/features/auth/providers/auth_provider.dart';
import 'package:chocoadmin/features/cliente/providers/carrito_provider.dart';
import 'package:chocoadmin/features/cliente/providers/catalogo_provider.dart';
import 'package:chocoadmin/features/cliente/screens/catalogo_screen.dart';
import 'package:chocoadmin/features/cliente/screens/perfil_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'token': 'tok', 'user_id': 1, 'user_name': 'Nombre Original',
      'user_email': 'a@a.com', 'user_role': 'cliente', 'user_permisos': <String>[],
    });
  });

  testWidgets('Perfil > Datos: rotar a landscape a mitad de edición no pierde el texto ni genera overflow', (tester) async {
    final auth = AuthProvider();
    await auth.checkSession();

    await tester.pumpWidget(MaterialApp(
      home: MultiProvider(providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider(create: (_) => CarritoProvider()),
      ], child: const PerfilScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Editar datos'));
    await tester.pump();
    final campoNombre = find.byWidgetPredicate((w) => w is TextField && w.controller?.text == 'Nombre Original');
    await tester.enterText(campoNombre, 'A medio escribir');
    await tester.pump();

    // Portrait típico (ej. Pixel 6) -> landscape (mismas dimensiones invertidas).
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pump();

    tester.view.physicalSize = const Size(2400, 1080); // landscape
    await tester.pump();

    expect(tester.takeException(), isNull,
        reason: 'rotar no debe producir un RenderFlex overflow ni ninguna excepción');
    expect(find.text('A medio escribir'), findsOneWidget,
        reason: 'el texto a medio escribir no debe perderse solo por el cambio de tamaño/orientación');
  });

  testWidgets('Catálogo: el grid de 2 columnas (childAspectRatio fijo) no genera overflow en landscape', (tester) async {
    ApiService.client = MockClient((req) async {
      if (req.url.path == '/api/catalogo/productos') {
        return http.Response(jsonEncode({'data': [
          {'id_producto': 1, 'nombre': 'Producto Uno', 'precio': 12000, 'permite_toppings': false},
          {'id_producto': 2, 'nombre': 'Producto Dos', 'precio': 15000, 'permite_toppings': false},
        ]}), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response(jsonEncode({'data': []}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    addTearDown(() => ApiService.client = MockClient((_) async => http.Response('No mockeado', 400)));

    await tester.pumpWidget(MaterialApp(
      home: MultiProvider(providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CatalogoProvider()),
        ChangeNotifierProvider(create: (_) => CarritoProvider()),
      ], child: const CatalogoScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Producto Uno'), findsOneWidget);

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pump();

    tester.view.physicalSize = const Size(2400, 1080); // landscape, mucho más angosto en alto
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull,
        reason: 'el grid de productos (childAspectRatio fijo 0.62) no debe overflow-ear en landscape');
  });
}
