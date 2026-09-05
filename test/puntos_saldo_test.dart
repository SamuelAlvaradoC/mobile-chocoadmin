// Verifica el hallazgo "Puntos leía un campo 'saldo' que el backend nunca
// envía": confirma que ahora lee saldo_pesos (el campo real), y que sigue
// teniendo un comportamiento claro (fallback documentado, no un crash ni un
// silencio) cuando ese campo no viene en la respuesta.
//
// Puntos ahora vive dentro de Perfil como pestaña (ya no es su propia
// pantalla/branch), así que estos tests montan PerfilScreen y tocan el pill
// "Puntos" antes de verificar -- mismo patrón que pull_to_refresh_test.dart
// usa para Historial/Direcciones. El saldo también aparece en una franja
// compacta siempre visible en el header de Perfil, así que una vez en la
// pestaña "Puntos" el mismo valor está en pantalla dos veces.
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
import 'package:chocoadmin/features/cliente/screens/perfil_screen.dart';

Widget _harness() => MaterialApp(
      home: MultiProvider(providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CarritoProvider()),
      ], child: const PerfilScreen()),
    );

Future<void> _irATabPuntos(WidgetTester tester) async {
  await tester.pumpWidget(_harness());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  // El pill "Puntos" es el último de 5 en un selector horizontal
  // desplazable -- puede quedar fuera del viewport visible.
  await tester.ensureVisible(find.text('Puntos'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Puntos'));
  await tester.pumpAndSettle();
}

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

    await _irATabPuntos(tester);

    expect(find.text('100'), findsOneWidget); // puntos disponibles (tarjeta de la pestaña)
    // El saldo aparece dos veces a la vez: en la franja compacta del header
    // (siempre visible) y en la tarjeta grande de la pestaña "Puntos" -- ese
    // es justo el punto de este cambio (visibilidad inmediata sin duplicar
    // la fuente de datos, ambos leen el mismo estado levantado en
    // _PerfilScreenState).
    expect(find.textContaining('987.654'), findsNWidgets(2),
        reason: 'debe mostrar el saldo_pesos real del backend (header + pestaña), no puntos*12.5 (que sería 1.250)');
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

    await _irATabPuntos(tester);

    // No debe crashear ni quedar en loading infinito -- usa el fallback
    // documentado (_puntos * 12.5 = 40 * 12.5 = 500) para no dejar la
    // pantalla en blanco si el backend cambia de forma.
    expect(tester.takeException(), isNull);
    expect(find.text('40'), findsOneWidget);
    // Igual que en el otro test: el saldo con fallback aparece en el header
    // y en la pestaña a la vez, ambos desde el mismo estado compartido.
    expect(find.textContaining('500'), findsNWidgets(2),
        reason: 'fallback documentado (puntos * 12.5) cuando falta saldo_pesos, visible en header + pestaña');
  });
}
