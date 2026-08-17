// Verifica el hallazgo "modal Confirmar Entrega se podía cerrar a mitad de
// la petición": abre el modal, dispara "Sí, entregado" contra un backend
// LENTO (mock con delay), y confirma que ni el botón "Cancelar" ni el tap
// en el fondo cierran el modal mientras la petición sigue en curso -- y que
// si termina bien, el modal sí se cierra después.
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
import 'package:chocoadmin/features/domiciliario/screens/pedidos_screen.dart';

http.Response _json(Map<String, dynamic> body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Widget _harness() => MaterialApp(
      home: ChangeNotifierProvider(create: (_) => AuthProvider(), child: const PedidosScreen()),
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

  testWidgets('el modal no se cierra por Cancelar ni por el fondo mientras la petición está en curso', (tester) async {
    var llamadasMarcarEntregado = 0;
    ApiService.client = MockClient((req) async {
      if (req.method == 'GET' && req.url.path == '/api/ventas') return _json({'data': []}); // por despachar: vacío
      if (req.method == 'GET' && req.url.path == '/api/ventas/mis-despachos') {
        final estado = req.url.queryParameters['estado'];
        if (estado == 'despachado') {
          return _json({'data': [
            {'id_venta': 1, 'estado': 'despachado', 'total': 12000, 'cliente': {'usuario': {'nombre': 'Cliente Uno'}}},
          ]});
        }
        return _json({'data': []}); // entregados: vacío
      }
      if (req.method == 'PATCH' && req.url.path.contains('/api/ventas/1/estado')) {
        llamadasMarcarEntregado++;
        await Future<void>.delayed(const Duration(milliseconds: 400));
        return _json({'data': {}});
      }
      return http.Response('No mockeado', 404);
    });

    await tester.pumpWidget(_harness());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Abre el modal "Confirmar Entrega" del único pedido despachado.
    await tester.tap(find.byTooltip('Marcar como entregado'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Sí, entregado'), findsOneWidget, reason: 'el modal debe estar abierto');

    // Dispara la confirmación (petición lenta, 400ms).
    await tester.tap(find.text('Sí, entregado'));
    await tester.pump(); // arranca _marcarEntregado -> _procesando = true

    // Mientras la petición sigue en curso: "Cancelar" no debe cerrar el modal.
    await tester.tap(find.text('Cancelar'), warnIfMissed: false);
    await tester.pump();
    expect(find.text('Sí, entregado'), findsOneWidget,
        reason: 'Cancelar no debe cerrar el modal mientras la petición está en curso');

    // Tampoco el tap en el fondo (backdrop) debe cerrarlo.
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    expect(find.text('Sí, entregado'), findsOneWidget,
        reason: 'el tap en el fondo tampoco debe cerrar el modal mientras la petición está en curso');

    // Deja que la petición lenta termine.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Sí, entregado'), findsNothing,
        reason: 'una vez la petición termina con éxito, el modal sí se cierra');
    expect(llamadasMarcarEntregado, 1, reason: 'solo debió dispararse UNA petición de marcar entregado');
  });
}
