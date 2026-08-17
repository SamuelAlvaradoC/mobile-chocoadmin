// Verifica el hallazgo "totales de Caja no filtraban por forma_pago": arma
// 3 ventas con campos monto_efectivo/monto_transferencia "señuelo" que NO
// corresponden a su forma_pago real, y confirma que el total mostrado en
// pantalla es el que resulta de FILTRAR por forma_pago (como React), no el
// que resultaría de sumar esos campos a ciegas.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chocoadmin/core/services/api_service.dart';
import 'package:chocoadmin/features/auth/providers/auth_provider.dart';
import 'package:chocoadmin/features/domiciliario/screens/cierre_caja_screen.dart';

final _fmt = NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);

Widget _harness() => MaterialApp(
      home: MultiProvider(
        providers: [ChangeNotifierProvider(create: (_) => AuthProvider())],
        child: const CierreCajaScreen(),
      ),
    );

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

  testWidgets('el total de efectivo y transferencia se calculan filtrando por forma_pago, no sumando todo', (tester) async {
    ApiService.client = MockClient((req) async {
      if (req.url.path.contains('/api/ventas/mis-despachos')) {
        final ventas = [
          // Efectivo puro -- monto_transferencia es un señuelo que NO debe
          // sumarse a _totalTransf. costo_domicilio distinto de 0 para que
          // "Total efectivo a entregar" no coincida por casualidad con
          // "Total ventas en efectivo".
          {
            'id_venta': 1, 'fecha': '2026-08-17T10:00:00.000Z',
            'cliente': {'usuario': {'nombre': 'Cliente A'}},
            'total': 10000, 'costo_domicilio': 1500,
            'metodo_pago': 'efectivo',
            'monto_transferencia': 5000, // señuelo
          },
          // Transferencia pura -- monto_efectivo es un señuelo que NO debe
          // sumarse a _totalEfectivo.
          {
            'id_venta': 2, 'fecha': '2026-08-17T11:00:00.000Z',
            'cliente': {'usuario': {'nombre': 'Cliente B'}},
            'total': 20000, 'costo_domicilio': 0,
            'metodo_pago': 'transferencia',
            'monto_efectivo': 3000, // señuelo
          },
          // Mixto -- ambos montos parciales son reales y SÍ deben sumarse.
          {
            'id_venta': 3, 'fecha': '2026-08-17T12:00:00.000Z',
            'cliente': {'usuario': {'nombre': 'Cliente C'}},
            'total': 15000, 'costo_domicilio': 500,
            'metodo_pago': 'mixto',
            'monto_efectivo': 6000, 'monto_transferencia': 9000,
          },
        ];
        return http.Response(jsonEncode({'data': ventas}), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('No mockeado', 404);
    });

    await tester.pumpWidget(_harness());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Correcto (filtrando por forma_pago):
    //   efectivo = 10000 (A, puro) + 6000 (C, parte mixta) = 16000
    //   transferencia = 20000 (B, puro) + 9000 (C, parte mixta) = 29000
    //   domicilios = 1500 (A) + 0 (B) + 500 (C) = 2000
    //   a entregar = 16000 - 2000 = 14000
    expect(find.text(_fmt.format(16000)), findsOneWidget,
        reason: 'total efectivo correcto: A completo + parte efectivo de C, sin el señuelo de B');
    expect(find.text(_fmt.format(29000)), findsOneWidget,
        reason: 'total transferencia correcto: B completo + parte transferencia de C, sin el señuelo de A');
    expect(find.text(_fmt.format(14000)), findsOneWidget,
        reason: 'total a entregar = efectivo correcto (16000) - domicilios (2000)');

    // Si el bug de "sumar todo sin filtrar" siguiera presente, los señuelos
    // se colarían y darían estos totales incorrectos -- deben estar AUSENTES.
    expect(find.text(_fmt.format(19000)), findsNothing,
        reason: 'sería el total efectivo BUGUEADO si se sumara el señuelo de B (3000) sin filtrar');
    expect(find.text(_fmt.format(34000)), findsNothing,
        reason: 'sería el total transferencia BUGUEADO si se sumara el señuelo de A (5000) sin filtrar');
  });

  testWidgets('con una sola venta en efectivo, el total de transferencia es cero (no arrastra el total)', (tester) async {
    ApiService.client = MockClient((req) async {
      if (req.url.path.contains('/api/ventas/mis-despachos')) {
        return http.Response(jsonEncode({'data': [
          {
            'id_venta': 1, 'fecha': '2026-08-17T10:00:00.000Z',
            'cliente': {'usuario': {'nombre': 'Cliente A'}},
            'total': 8000, 'costo_domicilio': 1000,
            'metodo_pago': 'efectivo',
          },
        ]}), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('No mockeado', 404);
    });

    await tester.pumpWidget(_harness());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text(_fmt.format(8000)), findsNWidgets(2)); // total día == total efectivo (misma cifra, 2 tarjetas)
    expect(find.text(_fmt.format(0)), findsOneWidget); // total transferencia
    expect(find.text(_fmt.format(7000)), findsOneWidget); // a entregar = 8000 - 1000
  });
}
