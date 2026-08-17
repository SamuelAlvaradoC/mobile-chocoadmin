import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_config.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class ApiService {
  // AppConfig.apiBaseUrl is '.../api', but endpoints already include '/api/...'
  // so strip the '/api' suffix for the base host used here.
  static final String _baseUrl = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/api$'), '');
  static const Duration _timeout = Duration(seconds: 30);

  /// Cliente HTTP inyectable -- por defecto un http.Client real. Los tests
  /// pueden reemplazarlo por un MockClient (package:http/testing.dart) para
  /// simular respuestas del backend (401, timeouts, respuestas lentas) sin
  /// red real ni tocar ningún comportamiento de producción; todas las
  /// llamadas de este archivo pasan por `client` en vez de las funciones
  /// top-level http.get/post/etc.
  static http.Client client = http.Client();

  /// Registrado una sola vez desde _AppRouterState.initState() (main.dart).
  /// Se dispara cuando un endpoint que SÍ requería sesión (auth:true)
  /// responde 401 -- es decir, un token expirado/inválido, no el 401 de
  /// "credenciales incorrectas" del login mismo (que llama con auth:false
  /// y por eso nunca pasa por acá). ApiService es una clase estática sin
  /// BuildContext propio, así que solo expone el enganche; la limpieza de
  /// sesión, la navegación a /login y el aviso al usuario viven en main.dart.
  static void Function()? onUnauthorized;

  // ─── Headers ────────────────────────────────────────────────────────────────

  static Future<Map<String, String>> _headers({bool auth = true}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (auth) {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  // ─── Response handler ───────────────────────────────────────────────────────

  static dynamic _handleResponse(http.Response response, {required bool auth}) {
    final body = utf8.decode(response.bodyBytes);
    final data = body.isNotEmpty ? jsonDecode(body) : {};

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    final message = data is Map ? (data['message'] ?? data['error'] ?? 'Error desconocido') : 'Error ${ response.statusCode}';

    if (response.statusCode == 401 && auth) {
      onUnauthorized?.call();
    }

    throw ApiException(message.toString(), statusCode: response.statusCode);
  }

  // ─── GET ────────────────────────────────────────────────────────────────────

  static Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParams,
    bool auth = true,
  }) async {
    try {
      var uri = Uri.parse('$_baseUrl$endpoint');
      if (queryParams != null && queryParams.isNotEmpty) {
        uri = uri.replace(
          queryParameters: queryParams.map(
            (k, v) => MapEntry(k, v.toString()),
          ),
        );
      }
      final response = await client
          .get(uri, headers: await _headers(auth: auth))
          .timeout(_timeout);
      return _handleResponse(response, auth: auth);
    } on SocketException {
      throw ApiException('Sin conexión a internet');
    } on HttpException {
      throw ApiException('Error de conexión');
    } on TimeoutException {
      throw ApiException('Tiempo de espera agotado. Verifica tu conexión.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Error inesperado: $e');
    }
  }

  // ─── POST ───────────────────────────────────────────────────────────────────

  static Future<dynamic> post(
    String endpoint,
    Map<String, dynamic> body, {
    bool auth = true,
  }) async {
    try {
      final response = await client
          .post(
            Uri.parse('$_baseUrl$endpoint'),
            headers: await _headers(auth: auth),
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      return _handleResponse(response, auth: auth);
    } on SocketException {
      throw ApiException('Sin conexión a internet');
    } on HttpException {
      throw ApiException('Error de conexión');
    } on TimeoutException {
      throw ApiException('Tiempo de espera agotado. Verifica tu conexión.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Error inesperado: $e');
    }
  }

  // ─── PUT ────────────────────────────────────────────────────────────────────

  static Future<dynamic> put(
    String endpoint,
    Map<String, dynamic> body, {
    bool auth = true,
  }) async {
    try {
      final response = await client
          .put(
            Uri.parse('$_baseUrl$endpoint'),
            headers: await _headers(auth: auth),
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      return _handleResponse(response, auth: auth);
    } on SocketException {
      throw ApiException('Sin conexión a internet');
    } on TimeoutException {
      throw ApiException('Tiempo de espera agotado. Verifica tu conexión.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Error inesperado: $e');
    }
  }

  // ─── PATCH ──────────────────────────────────────────────────────────────────

  static Future<dynamic> patch(
    String endpoint,
    Map<String, dynamic> body, {
    bool auth = true,
  }) async {
    try {
      final response = await client
          .patch(
            Uri.parse('$_baseUrl$endpoint'),
            headers: await _headers(auth: auth),
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      return _handleResponse(response, auth: auth);
    } on SocketException {
      throw ApiException('Sin conexión a internet');
    } on TimeoutException {
      throw ApiException('Tiempo de espera agotado. Verifica tu conexión.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Error inesperado: $e');
    }
  }

  // ─── DELETE ─────────────────────────────────────────────────────────────────

  static Future<dynamic> delete(
    String endpoint, {
    bool auth = true,
  }) async {
    try {
      final response = await client
          .delete(
            Uri.parse('$_baseUrl$endpoint'),
            headers: await _headers(auth: auth),
          )
          .timeout(_timeout);
      return _handleResponse(response, auth: auth);
    } on SocketException {
      throw ApiException('Sin conexión a internet');
    } on TimeoutException {
      throw ApiException('Tiempo de espera agotado. Verifica tu conexión.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Error inesperado: $e');
    }
  }
}
