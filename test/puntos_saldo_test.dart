// Verifica el hallazgo "Puntos leía un campo 'saldo' que el backend nunca
// envía": confirma que ahora lee saldo_pesos (el campo real), y que sigue
// teniendo un comportamiento claro (fallback documentado, no un crash ni un
// silencio) cuando ese campo no viene en la respuesta.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chocoadmin/core/services/api_service.dart';
import 'package:chocoadmin/features/cliente/screens/puntos_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'token': 'un-token-cualquiera'});
  });

  tearDown(() {
    ApiService.client = MockClient((_) async => http.Response('No mockeado', 400));
  });

  testWidgets('lee saldo_pesos real del backend, no lo recalcula desde puntos', (tester) async {
    // saldo_pesos deliberadamente NO es puntos*12.5 (sería 100*12.5=1250) --
    // si el código todavía leyera el campo inexistente 'saldo' y cayera al
    // fallback, mostraría 1250, no 987654. Así se prueba que de verdad está
    // leyendo el campo real, no acertando por coincidencia matemática.
    ApiService.client = MockClient((req) async {
      if (req.url.path.contains('/api/puntos/mis-puntos')) {
        return http.Response(
          jsonEncode({'data': {'puntos': 100, 'saldo_pesos': 987654}}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('No mockeado', 404);
    });

    await tester.pumpWidget(const MaterialApp(home: PuntosScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('100'), findsOneWidget); // puntos disponibles
    expect(find.textContaining('987.654'), findsOneWidget,
        reason: 'debe mostrar el saldo_pesos real del backend, no puntos*12.5 (que sería 1.250)');
    expect(find.textContaining('1.250'), findsNothing,
        reason: 'NO debe caer al fallback cuando saldo_pesos sí vino en la respuesta');
  });

  testWidgets('si saldo_pesos no viene en la respuesta, usa el fallback documentado (puntos * 12.5) en vez de fallar en silencio', (tester) async {
    ApiService.client = MockClient((req) async {
      if (req.url.path.contains('/api/puntos/mis-puntos')) {
        // Respuesta de un backend viejo/roto que solo manda "puntos", sin
        // saldo_pesos -- el caso que antes se cubría "por casualidad".
        return http.Response(
          jsonEncode({'data': {'puntos': 40}}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('No mockeado', 404);
    });

    await tester.pumpWidget(const MaterialApp(home: PuntosScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // No debe crashear ni quedar en loading infinito -- usa el fallback
    // documentado (_puntos * 12.5 = 40 * 12.5 = 500) para no dejar la
    // pantalla en blanco si el backend cambia de forma.
    expect(tester.takeException(), isNull);
    expect(find.text('40'), findsOneWidget);
    expect(find.textContaining('500'), findsOneWidget,
        reason: 'fallback documentado (puntos * 12.5) cuando falta saldo_pesos');
  });
}
