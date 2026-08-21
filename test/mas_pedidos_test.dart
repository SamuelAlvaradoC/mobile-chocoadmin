// Verifica "Más Pedidos" integrado en la grilla normal del catálogo
// (réplica del diseño ya aprobado en React, corregido en esta sesión):
// SIN sección/carrusel separado, los destacados reordenados al frente de
// la grilla (en "Todos" y también dentro de un filtro de categoría), la
// insignia de estrella presente solo en esas tarjetas, y que tocarlas
// abre el mismo ToppingsModal que el resto del catálogo. Mismo patrón de
// MockClient + checkSession real que pull_to_refresh_test.dart /
// logout_header_test.dart.
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

Map<String, dynamic> _producto(
  int id, String nombre, int idCategoria, {
  bool permiteSalsas = false,
}) => {
  'id_producto': id, 'id_categoria': idCategoria, 'nombre': nombre, 'descripcion': 'desc',
  'precio': '19000', 'permite_toppings': 0, 'max_toppings': 0,
  'permite_chocolate': false, 'permite_salsas': permiteSalsas, 'es_bowl': false,
  'img': null, 'estado': 1,
};

final _normalA = _producto(1, 'Normal A', 1);
final _normalB = _producto(2, 'Normal B', 1);
// Comparte categoría (2, Postres) con "Top 1" -- para probar que, al
// filtrar por Postres, Top 1 sale primero y Normal C después.
final _normalC = _producto(3, 'Normal C', 2);

// permiteSalsas:true en "Top 1" (único destacado en categoría 2) porque el
// paso por defecto del modal ("Adiciones") no muestra el nombre del
// producto en su encabezado -- el paso "salsas" sí, y hace falta para el
// test de click más abajo.
final _masPedidosMock = [
  _producto(100, 'Top 1', 2, permiteSalsas: true),
  _producto(101, 'Top 2', 1),
  _producto(102, 'Top 3', 1),
  _producto(103, 'Top 4', 1),
  _producto(104, 'Top 5', 1),
  _producto(105, 'Top 6', 1),
];

final _todosLosProductos = [_normalA, _normalB, _normalC, ..._masPedidosMock];
final _categorias = [
  {'id_categoria': 1, 'nombre': 'Bebidas'},
  {'id_categoria': 2, 'nombre': 'Postres'},
];

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
    if (path.contains('/api/catalogo/productos')) return _json(_todosLosProductos);
    if (path.contains('/api/catalogo/categorias')) return _json(_categorias);
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

// Viewport alto para que la grilla de 2 columnas (9 productos como máximo
// en estos tests) se construya completa sin necesitar scroll -- así el
// orden se puede leer directamente del árbol de widgets.
void _agrandarViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 4200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// Devuelve los nombres de producto en el orden en que Flutter los visita
// al recorrer el árbol -- para una SliverGrid eso coincide con el orden
// real de la lista (índice 0, 1, 2...), igual que leer el DOM en orden
// en el test de React.
List<String> _nombresEnGrid(WidgetTester tester, List<String> candidatos) {
  final elementos = tester.elementList(
    find.byWidgetPredicate((w) => w is Text && candidatos.contains(w.data)),
  );
  return elementos.map((e) => (e.widget as Text).data!).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    ApiService.client = MockClient((_) async => http.Response('No mockeado', 400));
  });

  testWidgets('NO existe ninguna sección/carrusel separado con título propio', (tester) async {
    _agrandarViewport(tester);
    _mockCatalogo(_masPedidosMock);
    await tester.pumpWidget(_harness());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('🔥 Más Pedidos'), findsNothing);
    expect(find.text('Más Pedidos'), findsNothing);
    expect(find.byKey(const Key('mas_pedidos_list')), findsNothing);
    // Un solo GridView en toda la pantalla -- no dos listas paralelas.
    expect(find.byType(GridView), findsOneWidget);
  });

  testWidgets('en "Todos": los 6 más pedidos aparecen primero, en orden, seguidos del resto', (tester) async {
    _agrandarViewport(tester);
    _mockCatalogo(_masPedidosMock);
    await tester.pumpWidget(_harness());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final candidatos = ['Top 1', 'Top 2', 'Top 3', 'Top 4', 'Top 5', 'Top 6', 'Normal A', 'Normal B', 'Normal C'];
    expect(_nombresEnGrid(tester, candidatos), [
      'Top 1', 'Top 2', 'Top 3', 'Top 4', 'Top 5', 'Top 6', 'Normal A', 'Normal B', 'Normal C',
    ]);
  });

  testWidgets('la insignia de estrella aparece SOLO en las 6 tarjetas destacadas', (tester) async {
    _agrandarViewport(tester);
    _mockCatalogo(_masPedidosMock);
    await tester.pumpWidget(_harness());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    for (final p in _masPedidosMock) {
      final tarjeta = find.byKey(ValueKey('producto_card_${p['id_producto']}'));
      expect(find.descendant(of: tarjeta, matching: find.byKey(const Key('badge_mas_pedido'))), findsOneWidget,
          reason: 'producto ${p['nombre']} debería tener la estrella');
    }
    for (final id in [1, 2, 3]) {
      final tarjeta = find.byKey(ValueKey('producto_card_$id'));
      expect(find.descendant(of: tarjeta, matching: find.byKey(const Key('badge_mas_pedido'))), findsNothing,
          reason: 'producto normal $id NO debería tener la estrella');
    }
  });

  testWidgets('al filtrar por categoría: el destacado de esa categoría sigue saliendo primero', (tester) async {
    _agrandarViewport(tester);
    _mockCatalogo(_masPedidosMock);
    await tester.pumpWidget(_harness());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Postres'));
    await tester.pumpAndSettle();

    // Postres solo tiene "Top 1" (destacado) y "Normal C" -- Top 1 primero.
    expect(_nombresEnGrid(tester, ['Top 1', 'Normal C', 'Top 2']), ['Top 1', 'Normal C']);
    expect(
      find.descendant(of: find.byKey(const ValueKey('producto_card_100')), matching: find.byKey(const Key('badge_mas_pedido'))),
      findsOneWidget,
    );
  });

  testWidgets('sin datos de "más pedidos": la grilla se ve igual que antes, sin ninguna estrella', (tester) async {
    _agrandarViewport(tester);
    _mockCatalogo([]);
    await tester.pumpWidget(_harness());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Normal A'), findsOneWidget);
    expect(find.byKey(const Key('badge_mas_pedido')), findsNothing);
  });

  testWidgets('tocar una tarjeta destacada abre el mismo ToppingsModal del catálogo normal', (tester) async {
    _agrandarViewport(tester);
    _mockCatalogo(_masPedidosMock);
    await tester.pumpWidget(_harness());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await _autenticar(tester);

    final tarjeta = find.byKey(const ValueKey('producto_card_100')); // Top 1
    final botonAgregar = find.descendant(of: tarjeta, matching: find.text('+ Agregar'));
    await tester.tap(botonAgregar);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ToppingsModal), findsOneWidget,
        reason: 'debe abrir el mismo widget de personalización que usa el catálogo normal');
    expect(
      find.descendant(of: find.byType(ToppingsModal), matching: find.text('Top 1')),
      findsOneWidget,
      reason: 'el modal debe corresponder al producto correcto de la tarjeta tocada',
    );
  });
}
