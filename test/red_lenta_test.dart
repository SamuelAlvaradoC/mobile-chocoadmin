// Simula condiciones de red adversas (respuesta que nunca llega dentro del
// timeout, y un error de red directo) para confirmar que ninguna pantalla
// se queda en loading infinito -- el timeout de 30s de ApiService debe
// convertirse en un error visible con opción de reintentar, no en un
// spinner eterno.
//
// El reloj falso de flutter_test (avanzado con tester.pump(duration)) deja
// probar el timeout de 30 segundos reales sin que el test tarde 30
// segundos de verdad.
import 'dart:convert';
import 'dart:io';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    ApiService.client = MockClient((_) async => http.Response('No mockeado', 400));
  });

  testWidgets('ApiService.get: una respuesta que nunca llega termina en un error claro a los 30s, no cuelga para siempre', (tester) async {
    ApiService.client = MockClient((req) async {
      // Nunca resuelve dentro de la ventana del timeout real (30s de
      // ApiService) -- el reloj falso de la prueba avanza sin esperar de verdad.
      await Future<void>.delayed(const Duration(seconds: 45));
      return http.Response('{}', 200);
    });

    Object? errorCapturado;
    // ignore: unawaited_futures
    ApiService.get('/api/algo').catchError((e) {
      errorCapturado = e;
      return null;
    });

    await tester.pump(const Duration(seconds: 31)); // pasa el timeout de 30s
    await tester.pump(); // deja correr el catchError

    expect(errorCapturado, isA<ApiException>());
    expect((errorCapturado as ApiException).message, contains('Tiempo de espera'),
        reason: 'debe convertirse en un ApiException con mensaje claro, no quedar pendiente para siempre');

    // El mock sigue "en vuelo" hasta los 45s (aunque su resultado ya no le
    // importa a nadie, .timeout() no cancela la operación original) -- se
    // deja correr el reloj falso hasta ahí para no terminar el test con un
    // Timer todavía pendiente (invariante que flutter_test valida al final).
    await tester.pump(const Duration(seconds: 15));
  });

  testWidgets('Catálogo: si la carga nunca responde, deja de mostrar el spinner y ofrece Reintentar', (tester) async {
    ApiService.client = MockClient((req) async {
      await Future<void>.delayed(const Duration(seconds: 45));
      return http.Response(jsonEncode({'data': []}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
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

    // Mientras la petición sigue pendiente, se ve el shimmer/spinner de carga.
    expect(find.text('Reintentar'), findsNothing);

    await tester.pump(const Duration(seconds: 31)); // pasa el timeout de 30s
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Reintentar'), findsOneWidget,
        reason: 'tras el timeout, debe salir del estado de carga y ofrecer reintentar -- no quedar en loading infinito');

    // Mismo motivo que en el test anterior: deja correr el reloj falso
    // hasta que el mock "en vuelo" también resuelva, para no dejar un
    // Timer pendiente al final del test.
    await tester.pump(const Duration(seconds: 15));
  });

  testWidgets('Sin conexión (caída inmediata, no timeout): también da un error claro, no un crash', (tester) async {
    ApiService.client = MockClient((req) async {
      throw const SocketException('Sin conexión a internet');
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

    expect(tester.takeException(), isNull, reason: 'una caída de red no debe crashear la pantalla');
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('Sin conexión a internet'), findsOneWidget);
  });
}
