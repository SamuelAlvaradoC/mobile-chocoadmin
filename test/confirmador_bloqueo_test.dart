// Verifica el hallazgo "bloqueo por-tarjeta en Confirmador": simula
// confirmar un pedido con una respuesta LENTA del backend (para tener una
// ventana real de "petición en curso"), y confirma que mientras esa
// petición sigue pendiente, los botones rápidos de confirmar/rechazar de
// OTRA tarjeta distinta desaparecen -- no se pueden disparar dos acciones
// en simultáneo.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chocoadmin/core/services/api_service.dart';
import 'package:chocoadmin/core/services/auth_service.dart';
import 'package:chocoadmin/features/admin/screens/domicilios_screen.dart';
import 'package:chocoadmin/features/auth/providers/auth_provider.dart';

Future<AuthProvider> _confirmadorAutenticado() async {
  SharedPreferences.setMockInitialValues({
    'token': 'tok',
    'user_id': 1,
    'user_name': 'Confirmador Test',
    'user_email': 'confirmador@test.com',
    'user_role': UserRole.confirmadorDomicilio.name,
    'user_permisos': ['confirmar_domicilios'],
  });
  final auth = AuthProvider();
  await auth.checkSession();
  return auth;
}

http.Response _pedidosPendientes() => http.Response(
      jsonEncode({'data': [
        {'id_venta': 1, 'estado': 'pendiente', 'total': 10000, 'cliente': {'usuario': {'nombre': 'Cliente Uno'}}},
        {'id_venta': 2, 'estado': 'pendiente', 'total': 20000, 'cliente': {'usuario': {'nombre': 'Cliente Dos'}}},
      ]}),
      200,
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

  testWidgets('mientras se confirma un pedido, los botones rápidos de OTRO pedido desaparecen', (tester) async {
    var llamadasConfirmar = 0;
    ApiService.client = MockClient((req) async {
      if (req.method == 'GET' && req.url.path == '/api/ventas') return _pedidosPendientes();
      if (req.method == 'PATCH' && req.url.path.contains('/estado')) {
        llamadasConfirmar++;
        // Respuesta lenta a propósito -- deja una ventana real de "petición
        // en curso" para poder comprobar el bloqueo mientras está pendiente.
        await Future<void>.delayed(const Duration(milliseconds: 400));
        return http.Response(jsonEncode({'data': {}}), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('No mockeado', 404);
    });

    final auth = await _confirmadorAutenticado();
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider<AuthProvider>.value(value: auth, child: const DomiciliosScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final tarjetas = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_DomicilioCard');
    expect(tarjetas, findsNWidgets(2));

    // Antes de tocar nada: ambas tarjetas tienen su botón de confirmar (✓).
    expect(find.descendant(of: tarjetas, matching: find.byIcon(Icons.check_rounded)), findsNWidgets(2));

    // Confirma el pedido de la PRIMERA tarjeta.
    await tester.tap(find.descendant(of: tarjetas.first, matching: find.byIcon(Icons.check_rounded)));
    await tester.pump(); // procesa el tap, dispara _confirmar() -> setState(_bloqueado = true)

    // Mientras esa petición sigue en curso (todavía no pasaron los 400ms
    // mockeados), la SEGUNDA tarjeta ya no debe tener botón de confirmar
    // (ni de rechazar) -- el bloqueo es global, no solo de la tarjeta activa.
    final tarjetasAhora = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_DomicilioCard');
    expect(find.descendant(of: tarjetasAhora, matching: find.byIcon(Icons.check_rounded)), findsNothing,
        reason: 'ninguna tarjeta debe poder confirmarse mientras otra está en curso');
    expect(find.descendant(of: tarjetasAhora, matching: find.byIcon(Icons.close_rounded)), findsNothing,
        reason: 'tampoco debe poder rechazarse otro pedido mientras uno está en curso');

    // Deja que la petición lenta termine y la lista se refresque.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(llamadasConfirmar, 1, reason: 'solo debió dispararse UNA confirmación, la de la primera tarjeta');
  });
}
