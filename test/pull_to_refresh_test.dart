// Verifica el hallazgo "pull-to-refresh faltante": confirma que las 3
// pantallas corregidas (Catálogo, Perfil>Historial, Perfil>Direcciones)
// tienen un RefreshIndicator real y que dispararlo vuelve a llamar al
// endpoint de carga -- no solo que el widget esté en el árbol.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chocoadmin/core/services/api_service.dart';
import 'package:chocoadmin/features/auth/providers/auth_provider.dart';
import 'package:chocoadmin/features/cliente/providers/carrito_provider.dart';
import 'package:chocoadmin/features/cliente/providers/catalogo_provider.dart';
import 'package:chocoadmin/features/cliente/screens/catalogo_screen.dart';
import 'package:chocoadmin/features/cliente/screens/perfil_screen.dart';

http.Response _vacio() => http.Response(jsonEncode({'data': []}), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

// El RefreshIndicator anima su entrada/salida (~1s) -- .show() no se espera
// directamente (necesitaría pumps concurrentes, no antes), así que se
// dispara y luego se bombean varios frames para que la animación y el
// onRefresh mockeado terminen de resolver.
Future<void> _dispararRefresh(WidgetTester tester, Finder refreshFinder) async {
  tester.state<RefreshIndicatorState>(refreshFinder).show();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('es_CO', null);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'token': 'un-token-cualquiera'});
  });

  tearDown(() {
    ApiService.client = MockClient((_) async => http.Response('No mockeado', 400));
  });

  testWidgets('Catálogo: RefreshIndicator existe y dispararlo vuelve a pedir el catálogo', (tester) async {
    var llamadasProductos = 0;
    ApiService.client = MockClient((req) async {
      if (req.url.path.contains('/api/catalogo/productos')) llamadasProductos++;
      if (req.url.path.startsWith('/api/catalogo/')) return _vacio();
      return http.Response('No mockeado', 404);
    });

    await tester.pumpWidget(MaterialApp(
      home: MultiProvider(providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CatalogoProvider()),
        ChangeNotifierProvider(create: (_) => CarritoProvider()),
      ], child: const CatalogoScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final refreshFinder = find.byType(RefreshIndicator);
    expect(refreshFinder, findsOneWidget);
    expect(llamadasProductos, 1, reason: 'carga inicial al entrar a Catálogo');

    await _dispararRefresh(tester, refreshFinder);

    expect(llamadasProductos, 2, reason: 'disparar el RefreshIndicator debe volver a pedir el catálogo');
  });

  testWidgets('Perfil > Historial: RefreshIndicator existe y dispararlo vuelve a pedir el historial', (tester) async {
    var llamadasHistorial = 0;
    ApiService.client = MockClient((req) async {
      if (req.url.path.contains('/api/ventas/mis-pedidos')) {
        llamadasHistorial++;
        // El RefreshIndicator de Historial solo se renderiza cuando hay
        // pedidos (con la lista vacía se muestra el estado vacío en su
        // lugar) -- se necesita al menos 1 pedido para poder encontrarlo.
        return http.Response(jsonEncode({'data': [
          {'id_venta': 1, 'estado': 'entregado', 'total': 15000, 'fecha': '2026-08-01T10:00:00.000Z'},
        ]}), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response(jsonEncode({'data': {}}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

    await tester.pumpWidget(MaterialApp(
      home: MultiProvider(providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CarritoProvider()),
      ], child: const PerfilScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // PerfilScreen arranca en la pestaña "Datos" -- hay que tocar el pill
    // "Historial" y dejar que la animación de cambio de tab se asiente
    // (sin CachedNetworkImage en este árbol, pumpAndSettle es seguro acá).
    await tester.tap(find.text('Historial'));
    await tester.pumpAndSettle();

    final refreshFinder = find.byType(RefreshIndicator);
    expect(refreshFinder, findsOneWidget);
    expect(llamadasHistorial, 1, reason: 'carga inicial al construir el tab Historial');

    await _dispararRefresh(tester, refreshFinder);

    expect(llamadasHistorial, 2, reason: 'disparar el RefreshIndicator debe volver a pedir el historial');
  });

  testWidgets('Perfil > Direcciones: RefreshIndicator existe y dispararlo vuelve a pedir las direcciones', (tester) async {
    var llamadasDirecciones = 0;
    ApiService.client = MockClient((req) async {
      if (req.url.path.contains('/api/auth/mis-direcciones')) {
        llamadasDirecciones++;
        return _vacio();
      }
      return http.Response(jsonEncode({'data': {}}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

    await tester.pumpWidget(MaterialApp(
      home: MultiProvider(providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CarritoProvider()),
      ], child: const PerfilScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Direcciones'));
    await tester.pumpAndSettle();

    final refreshFinder = find.byType(RefreshIndicator);
    expect(refreshFinder, findsOneWidget);
    expect(llamadasDirecciones, 1, reason: 'carga inicial al construir el tab Direcciones');

    await _dispararRefresh(tester, refreshFinder);

    expect(llamadasDirecciones, 2, reason: 'disparar el RefreshIndicator debe volver a pedir las direcciones');
  });
}
