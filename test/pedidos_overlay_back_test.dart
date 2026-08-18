// Verifica el hallazgo de la Parte 2 (adversarial): el detalle y el modal
// de confirmar entrega de PedidosScreen eran widgets condicionales en un
// Stack, no rutas reales -- el back del sistema no los cerraba primero,
// saltaba directo a la lógica de raíz de tab. Se corrigieron a diálogos
// reales (showDialog en el Navigator del branch); estos tests confirman
// que ahora el back SÍ los cierra primero (usando el mismo
// ShellAwareBackButtonDispatcher real de la app, no una simulación
// distinta), y que el modal de Confirmar Entrega sigue bloqueando el back
// mientras la petición está en curso (ahora vía PopScope, ya que al ser
// una ruta real el back también podría saltarse el guard existente en
// "Cancelar"/el fondo si no se agregaba explícitamente).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chocoadmin/core/services/api_service.dart';
import 'package:chocoadmin/features/auth/providers/auth_provider.dart';
import 'package:chocoadmin/features/domiciliario/screens/pedidos_screen.dart';
import 'package:chocoadmin/shared/layouts/root_shell_scaffold.dart';
import 'package:chocoadmin/shared/widgets/double_back_to_exit.dart';

http.Response _json(dynamic body, [int status = 200]) => http.Response(
      jsonEncode(body), status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Widget _harness() {
  final router = GoRouter(
    initialLocation: '/domiciliario/pedidos',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (c, s, shell) => RootShellScaffold(
          navigationShell: shell,
          bottomNavBuilder: (_) => const SizedBox.shrink(),
        ),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/domiciliario/pedidos', builder: (_, __) => const PedidosScreen()),
          ]),
        ],
      ),
    ],
  );
  return MultiProvider(
    providers: [ChangeNotifierProvider(create: (_) => AuthProvider())],
    child: MaterialApp.router(
      routeInformationProvider: router.routeInformationProvider,
      routeInformationParser: router.routeInformationParser,
      routerDelegate: router.routerDelegate,
      backButtonDispatcher: ShellAwareBackButtonDispatcher(router, nonHomeToHome: const {}),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('es_CO', null);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'token': 'tok'});
  });

  tearDown(() {
    ApiService.client = MockClient((_) async => http.Response('No mockeado', 400));
  });

  testWidgets('el back del sistema cierra el detalle de un pedido, no salta a la lógica de tab', (tester) async {
    ApiService.client = MockClient((req) async {
      if (req.method == 'GET' && req.url.path == '/api/ventas') return _json({'data': []});
      if (req.method == 'GET' && req.url.path == '/api/ventas/mis-despachos') {
        if (req.url.queryParameters['estado'] == 'despachado') {
          return _json({'data': [
            {'id_venta': 1, 'estado': 'despachado', 'total': 9000, 'cliente': {'usuario': {'nombre': 'Cliente Uno'}}},
          ]});
        }
        return _json({'data': []});
      }
      return _json({'data': []});
    });

    await tester.pumpWidget(_harness());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byTooltip('Ver detalle'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Pedido #1'), findsOneWidget, reason: 'el detalle debe estar abierto');

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Pedido #1'), findsNothing,
        reason: 'el back debió cerrar el detalle, no saltar a la lógica de raíz de tab');
    expect(find.text('Presiona atrás de nuevo para salir'), findsNothing,
        reason: 'con el detalle abierto, el back NO debe activar el doble-back-para-salir de la pantalla de fondo');
  });

  testWidgets('el back del sistema cierra el modal Confirmar Entrega cuando NO está procesando', (tester) async {
    ApiService.client = MockClient((req) async {
      if (req.method == 'GET' && req.url.path == '/api/ventas') return _json({'data': []});
      if (req.method == 'GET' && req.url.path == '/api/ventas/mis-despachos') {
        if (req.url.queryParameters['estado'] == 'despachado') {
          return _json({'data': [
            {'id_venta': 1, 'estado': 'despachado', 'total': 9000, 'cliente': {'usuario': {'nombre': 'Cliente Uno'}}},
          ]});
        }
        return _json({'data': []});
      }
      return _json({'data': []});
    });

    await tester.pumpWidget(_harness());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byTooltip('Marcar como entregado'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Sí, entregado'), findsOneWidget, reason: 'el modal debe estar abierto');

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Sí, entregado'), findsNothing,
        reason: 'sin nada en curso, el back debe cerrar el modal normalmente');
  });

  testWidgets('el back del sistema NO cierra el modal Confirmar Entrega mientras la petición está en curso', (tester) async {
    ApiService.client = MockClient((req) async {
      if (req.method == 'GET' && req.url.path == '/api/ventas') return _json({'data': []});
      if (req.method == 'GET' && req.url.path == '/api/ventas/mis-despachos') {
        if (req.url.queryParameters['estado'] == 'despachado') {
          return _json({'data': [
            {'id_venta': 1, 'estado': 'despachado', 'total': 9000, 'cliente': {'usuario': {'nombre': 'Cliente Uno'}}},
          ]});
        }
        return _json({'data': []});
      }
      if (req.method == 'PATCH' && req.url.path.contains('/api/ventas/1/estado')) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        return _json({'data': {}});
      }
      return _json({'data': []});
    });

    await tester.pumpWidget(_harness());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byTooltip('Marcar como entregado'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Sí, entregado'));
    await tester.pump(); // arranca la petición lenta -> procesando = true

    // Con la petición en curso, el back del sistema NO debe cerrar el modal
    // -- esto es justo lo que PopScope(canPop: !procesando) debe evitar,
    // ya que al ser ahora una ruta real, sin ese guard el back haría
    // Navigator.pop() directo saltándose el bloqueo.
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('Sí, entregado'), findsOneWidget,
        reason: 'el back no debe cerrar el modal mientras la petición de marcar entregado está en curso');

    // Deja que la petición termine para no dejar timers pendientes.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  });
}
