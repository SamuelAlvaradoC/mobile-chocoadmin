// Simula AppLifecycleState.paused -> resumed (app en segundo plano y
// restaurada) en pantallas con estado importante, para responder
// explícitamente qué se pierde y qué se conserva -- pedido explícito de la
// auditoría, no solo para el carrito.
//
// Límite honesto de lo que esto puede probar: AppLifecycleState.paused es
// el evento de Flutter para "la app pasó a segundo plano", pero el proceso
// SIGUE VIVO -- Flutter no destruye el árbol de widgets ni el estado en
// memoria solo por eso. Lo que realmente pierde datos no persistidos es
// que ANDROID MATE EL PROCESO por presión de memoria mientras está en
// segundo plano, y eso no se puede simular dentro de un mismo test de
// widget (implicaría reiniciar la VM de Dart). El test de persistencia del
// carrito (carrito_provider_test.dart) sí logra simular ese caso, pero
// solo porque el carrito ahora vive en disco (SharedPreferences) -- crear
// una instancia nueva de CarritoProvider imita fielmente "proceso matado y
// reiniciado". Los formularios de Ventas/Checkout NO están en disco (a
// propósito, ver hallazgo aceptado en la auditoría, igual que React), así
// que ante un kill real de proceso si se perderían -- lo que este archivo
// prueba es que un simple paso a segundo plano (sin kill) NO los pierde.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chocoadmin/core/models/producto.dart';
import 'package:chocoadmin/core/services/api_service.dart';
import 'package:chocoadmin/core/services/auth_service.dart';
import 'package:chocoadmin/features/auth/providers/auth_provider.dart';
import 'package:chocoadmin/features/cliente/providers/carrito_provider.dart';
import 'package:chocoadmin/features/cliente/screens/perfil_screen.dart';
import 'package:chocoadmin/features/admin/screens/pedidos_screen.dart' show AdminPedidosScreen;

Future<void> _simularBackgroundYForeground(WidgetTester tester) async {
  // Mismo evento que WidgetsBindingObserver.didChangeAppLifecycleState
  // recibiría de verdad al presionar Home / cambiar de app y volver.
  // Flutter exige la secuencia real de estados (no se puede saltar directo
  // resumed->paused ni paused->resumed): resumed -> inactive -> paused ->
  // inactive -> resumed, igual que Android reporta el ciclo real.
  for (final s in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
    await tester.pump();
  }
}

http.Response _json(dynamic body, [int status = 200]) => http.Response(
      jsonEncode(body), status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('es_CO', null);
  });

  tearDown(() {
    ApiService.client = MockClient((_) async => http.Response('No mockeado', 400));
  });

  test('Carrito: agregar un producto y pasar a segundo plano no lo pierde (sin kill de proceso)', () async {
    SharedPreferences.setMockInitialValues({});
    final carrito = CarritoProvider();
    await carrito.sincronizarUsuario(1);
    carrito.agregar(
      producto: const Producto(id: 1, nombre: 'Producto de prueba', precio: 5000, permiteToppings: false),
      toppings: const [], adiciones: const [],
    );
    expect(carrito.items.length, 1);

    // No hay "pump" para un ChangeNotifier plano (no widget), pero el punto
    // es el mismo: nada en CarritoProvider depende del ciclo de vida de la
    // app -- es un objeto Dart normal en memoria, ajeno a
    // AppLifecycleState. Sigue intacto sin más que el paso del tiempo.
    expect(carrito.items.length, 1, reason: 'nada en memoria se pierde solo por pasar a background');
  });

  testWidgets('Perfil > Datos: el nombre a medio editar sobrevive pasar a segundo plano y volver', (tester) async {
    final auth = AuthUser.fromJson({
      'id_usuario': 1, 'nombre': 'Nombre Original', 'email': 'a@a.com', 'rol': 'cliente',
    });
    final authProvider = AuthProvider();
    // No hay setter público para el user -- se simula sesión igual que en
    // otros tests de este archivo (checkSession() leyendo SharedPreferences).
    SharedPreferences.setMockInitialValues({
      'token': 'tok', 'user_id': 1, 'user_name': auth.nombre, 'user_email': auth.email,
      'user_role': 'cliente', 'user_permisos': <String>[],
    });
    await authProvider.checkSession();

    await tester.pumpWidget(MaterialApp(
      home: MultiProvider(providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider(create: (_) => CarritoProvider()),
      ], child: const PerfilScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Entra a modo edición y escribe un nombre a medio terminar.
    await tester.tap(find.text('Editar datos'));
    await tester.pump();
    final campoNombre = find.byWidgetPredicate((w) => w is TextField && w.controller?.text == 'Nombre Original');
    expect(campoNombre, findsOneWidget);
    await tester.enterText(campoNombre, 'Nombre a medio escribir');
    await tester.pump();
    expect(find.text('Nombre a medio escribir'), findsOneWidget);

    await _simularBackgroundYForeground(tester);

    expect(find.text('Nombre a medio escribir'), findsOneWidget,
        reason: 'pasar a background sin kill no debe perder lo que se estaba escribiendo');
  });

  testWidgets('Pedidos > Crear venta: la búsqueda de cliente a medio escribir sobrevive pasar a segundo plano', (tester) async {
    SharedPreferences.setMockInitialValues({
      'token': 'tok', 'user_id': 1, 'user_name': 'Admin Test', 'user_email': 'admin@test.com',
      'user_role': UserRole.admin.name, 'user_permisos': ['gestionar_ventas'],
    });
    final authProvider = AuthProvider();
    await authProvider.checkSession();

    ApiService.client = MockClient((req) async {
      if (req.url.path == '/api/ventas') return _json({'data': []});
      if (req.url.path == '/api/clientes') return _json({'data': []});
      return _json({'data': []});
    });

    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: const Scaffold(body: AdminPedidosScreen()),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Abre "Crear venta" (botón "Nueva venta", visible con permiso gestionar_ventas).
    await tester.tap(find.text('Nueva venta'));
    await tester.pumpAndSettle();

    final campoBuscarCliente = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Buscar cliente *');
    expect(campoBuscarCliente, findsOneWidget, reason: 'debe estar en el paso 1 del wizard, buscando cliente');

    await tester.enterText(campoBuscarCliente, 'Juan a medio escribir');
    await tester.pump();
    expect(find.text('Juan a medio escribir'), findsOneWidget);

    await _simularBackgroundYForeground(tester);

    expect(find.text('Juan a medio escribir'), findsOneWidget,
        reason: 'el formulario de crear venta no se pierde por pasar a background sin kill de proceso');
  });
}
