// Verifica el hallazgo "manejo de expiración de JWT": que un 401 en un
// endpoint autenticado dispare ApiService.onUnauthorized, y que un 401 en
// el login (auth:false) NO lo dispare -- la distinción exacta que main.dart
// usa para no confundir "sesión expirada" con "credenciales incorrectas".
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chocoadmin/core/services/api_service.dart';

// http.Response(body, status) sin `encoding:` explícito usa latin1 para
// bodyBytes -- pero _handleResponse decodifica con utf8 (igual que un
// backend real enviando JSON en UTF-8), así que cualquier tilde rompía con
// "FormatException: Missing extension byte". Este helper simula una
// respuesta real del backend correctamente.
http.Response _jsonResponse(Map<String, dynamic> body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'token': 'un-token-cualquiera'});
  });

  tearDown(() {
    // No dejar el MockClient ni el callback pegados para otros test files.
    // (Se deja OTRO MockClient inerte, no un http.Client() real -- eso
    // dispararía el warning de flutter_test sobre crear un HttpClient real
    // dentro de un test suite con TestWidgetsFlutterBinding.)
    ApiService.client = MockClient((_) async => http.Response('No mockeado', 400));
    ApiService.onUnauthorized = null;
  });

  test('401 en un endpoint autenticado dispara onUnauthorized', () async {
    ApiService.client = MockClient((req) async {
      return _jsonResponse({'message': 'Token inválido o expirado'}, 401);
    });

    var disparado = 0;
    ApiService.onUnauthorized = () => disparado++;

    await expectLater(
      () => ApiService.get('/api/auth/perfil'), // auth: true por defecto
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 401)
          .having((e) => e.message, 'message', 'Token inválido o expirado')),
    );

    expect(disparado, 1, reason: 'un 401 en un endpoint que sí pedía sesión debe disparar el interceptor');
  });

  test('401 en /api/auth/login (auth:false) NO dispara onUnauthorized -- es credenciales incorrectas, no sesión expirada', () async {
    ApiService.client = MockClient((req) async {
      return _jsonResponse({'message': 'Credenciales incorrectas'}, 401);
    });

    var disparado = 0;
    ApiService.onUnauthorized = () => disparado++;

    await expectLater(
      () => ApiService.post('/api/auth/login', {'email': 'a@a.com', 'contrasena': 'mala'}, auth: false),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
    );

    expect(disparado, 0, reason: 'el 401 del login mismo no debe disparar el flujo de sesión expirada');
  });

  test('401 en un endpoint sin auth (ej. catálogo público) tampoco dispara onUnauthorized', () async {
    ApiService.client = MockClient((req) async {
      return _jsonResponse({'message': 'no debería pasar, pero por si acaso'}, 401);
    });

    var disparado = 0;
    ApiService.onUnauthorized = () => disparado++;

    await expectLater(
      () => ApiService.get('/api/catalogo/productos', auth: false),
      throwsA(isA<ApiException>()),
    );

    expect(disparado, 0);
  });

  test('una respuesta 200 normal no dispara onUnauthorized ni lanza excepción', () async {
    ApiService.client = MockClient((req) async {
      return _jsonResponse({'data': []}, 200);
    });

    var disparado = 0;
    ApiService.onUnauthorized = () => disparado++;

    final resultado = await ApiService.get('/api/auth/perfil');

    expect(disparado, 0);
    expect(resultado, isA<Map>());
  });

  test('un 403 (permiso insuficiente, no sesión expirada) tampoco dispara onUnauthorized', () async {
    ApiService.client = MockClient((req) async {
      return _jsonResponse({'message': 'No tienes permiso'}, 403);
    });

    var disparado = 0;
    ApiService.onUnauthorized = () => disparado++;

    await expectLater(
      () => ApiService.get('/api/admin/algo-restringido'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403)),
    );

    expect(disparado, 0, reason: 'solo 401 debe disparar el flujo de sesión expirada, no cualquier error');
  });
}
