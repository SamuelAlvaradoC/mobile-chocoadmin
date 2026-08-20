// Verifica la sección "Más Pedidos" del catálogo cliente: que se muestre
// con los 6 productos y la insignia "MÁS PEDIDO" cuando el backend trae
// datos, que se oculte cuando no hay datos, y que tocar una tarjeta de esa
// sección abra el mismo flujo de personalización (ToppingsModal) que el
// resto del catálogo. Mismo patrón que pull_to_refresh_test.dart /
// logout_header_test.dart (MockClient + checkSession real).
import 'dart:convert';

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
import 'package:chocoadmin/features/cliente/widgets/toppings_modal.dart';

Map<String, dynamic> _producto(int id, String nombre, {bool permiteSalsas = false}) => {
      'id_producto': id, 'id_categoria': 1, 'nombre': nombre, 'descripcion': 'desc',
      'precio': '19000', 'permite_toppings': 0, 'max_toppings': 0,
      'permite_chocolate': false, 'permite_salsas': permiteSalsas, 'es_bowl': false,
      'img': null, 'estado': 1,
    };

final _productoNormal = _producto(1, 'Producto Normal');
// El primero lleva permiteSalsas:true para poder verificar, al abrir el
// modal, que muestra el nombre del producto correcto (el paso "adiciones"
// -- el único que aplicaría sin ningún flag -- no muestra el nombre, igual
// que en React).
final _masPedidosMock = List.generate(
  6, (i) => _producto(100 + i, 'Producto Top ${i + 1}', permiteSalsas: i == 0),
);

http.Response _json(dynamic data) => http.Response(
      jsonEncode({'data': data}), 200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Widget _harness() => MaterialApp(
      home: MultiProvider(providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CatalogoProvider()),
        ChangeNotifierProvider(create: (_) => CarritoProvider()),
      ], child: const CatalogoScreen()),
    );

void _mockCatalogo(List<Map<String, dynamic>> masPedidos) {
  ApiService.client = MockClient((req) async {
    final path = req.url.path;
    if (path.contains('/api/catalogo/mas-pedidos')) return _json(masPedidos);
    if (path.contains('/api/catalogo/productos')) return _json([_productoNormal]);
    if (path.contains('/api/catalogo/categorias')) return _json([{'id_categoria': 1, 'nombre': 'Bebidas'}]);
    if (path.contains('/api/catalogo/')) return _json([]);
    if (path.contains('/api/configuracion/')) {
      return _json({'abierto': true, 'estado': 'schedule', 'hora_apertura': 13, 'hora_cierre': 20, 'minutos': 30});
    }
    return http.Response('No mockeado', 404);
  });
}

Future<void> _autenticar(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'token': 'un-token', 'user_id': 1, 'user_name': 'Ana',
    'user_email': 'ana@test.com', 'user_role': 'cliente', 'user_permisos': <String>[],
  });
  final ctx = tester.element(find.byType(CatalogoScreen));
  await ctx.read<AuthProvider>().checkSession();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    ApiService.client = MockClient((_) async => http.Response('No mockeado', 400));
  });

  testWidgets('con datos: muestra "Más Pedidos" con los 6 productos y la insignia en cada uno', (tester) async {
    _mockCatalogo(_masPedidosMock);
    await tester.pumpWidget(_harness());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('🔥 Más Pedidos'), findsOneWidget);

    // El provider debe traer los 6, aunque el ListView (lazy, horizontal) no
    // los monte todos al mismo tiempo -- se recorre la lista completa
    // arrastrando, verificando cada nombre y su insignia a medida que
    // entran en viewport (evita asumir que los 6 caben en pantalla a la vez).
    final ctx = tester.element(find.byType(CatalogoScreen));
    expect(ctx.read<CatalogoProvider>().masPedidos.length, 6);

    final lista = find.byKey(const Key('mas_pedidos_list'));
    for (final p in _masPedidosMock) {
      final nombre = p['nombre'] as String;
      await tester.scrollUntilVisible(find.text(nombre), 200, scrollable: find.descendant(
        of: lista, matching: find.byType(Scrollable),
      ));
      expect(find.text(nombre), findsOneWidget);
      final tarjeta = find.byKey(ValueKey('mas_pedido_card_${p['id_producto']}'));
      expect(find.descendant(of: tarjeta, matching: find.text('MÁS PEDIDO')), findsOneWidget);
    }
  });

  testWidgets('sin datos: la sección "Más Pedidos" no se renderiza', (tester) async {
    _mockCatalogo([]);
    await tester.pumpWidget(_harness());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text(_productoNormal['nombre'] as String), findsOneWidget,
        reason: 'el catálogo normal sí debe cargar');
    expect(find.text('🔥 Más Pedidos'), findsNothing);
    expect(find.text('MÁS PEDIDO'), findsNothing);
  });

  testWidgets('tocar una tarjeta de "Más Pedidos" abre el mismo ToppingsModal del catálogo normal', (tester) async {
    _mockCatalogo(_masPedidosMock);
    await tester.pumpWidget(_harness());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await _autenticar(tester);

    final primerId = _masPedidosMock[0]['id_producto'];
    final tarjeta = find.byKey(ValueKey('mas_pedido_card_$primerId'));
    expect(tarjeta, findsOneWidget);

    final botonAgregar = find.descendant(of: tarjeta, matching: find.text('+ Agregar'));
    expect(botonAgregar, findsOneWidget);
    await tester.tap(botonAgregar);
    await tester.pump(); // abre el bottom sheet
    await tester.pump(const Duration(milliseconds: 300)); // anima la entrada

    expect(find.byType(ToppingsModal), findsOneWidget,
        reason: 'debe abrir el mismo widget de personalización que usa el catálogo normal');
    expect(
      find.descendant(of: find.byType(ToppingsModal), matching: find.text(_masPedidosMock[0]['nombre'] as String)),
      findsOneWidget,
      reason: 'el modal debe corresponder al producto correcto de la tarjeta tocada',
    );
  });
}
