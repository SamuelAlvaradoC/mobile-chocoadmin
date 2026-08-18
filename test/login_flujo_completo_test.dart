// Prueba de extremo a extremo del bug reportado: monta la pantalla REAL de
// Login dentro de un GoRouter conectado a la MISMA computeAuthRedirect que
// usa main.dart (importada, no copiada) y refreshListenable: authProvider
// -- exactamente la misma cadena que produce el bug real (AuthProvider.
// notifyListeners() dispara el redirect de GoRouter en cada cambio de
// estado, incluido el status=loading que se pone ANTES de que el backend
// responda). Los tests anteriores (login_credenciales_test.dart) montaban
// LoginScreen sola dentro de un MaterialApp sin GoRouter -- por eso no
// alcanzaron a detectar este bug: nunca ejercitaron el redirect real.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chocoadmin/core/routing/auth_redirect.dart';
import 'package:chocoadmin/core/services/api_service.dart';
import 'package:chocoadmin/features/auth/providers/auth_provider.dart';
import 'package:chocoadmin/features/auth/screens/login_screen.dart';

void _forzarViewportMobile(WidgetTester tester) {
  tester.view.physicalSize = const Size(600, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

({GoRouter router, Widget widget}) _buildApp() {
  final authProvider = AuthProvider();
  late final GoRouter router;

  String? redirect(BuildContext context, GoRouterState state) {
    return computeAuthRedirect(
      status: authProvider.status,
      location: state.matchedLocation,
      role: authProvider.user?.role,
    );
  }

  router = GoRouter(
    initialLocation: '/login',
    refreshListenable: authProvider,
    redirect: redirect,
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const Scaffold(body: Text('Splash'))),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/catalogo', builder: (_, __) => const Scaffold(body: Text('Home Catálogo'))),
      GoRoute(path: '/admin/dashboard', builder: (_, __) => const Scaffold(body: Text('Home Dashboard'))),
    ],
  );

  final widget = ChangeNotifierProvider<AuthProvider>.value(
    value: authProvider,
    child: MaterialApp.router(
      routeInformationProvider: router.routeInformationProvider,
      routeInformationParser: router.routeInformationParser,
      routerDelegate: router.routerDelegate,
    ),
  );

  return (router: router, widget: widget);
}

Future<void> _login(WidgetTester tester, {required String email, required String pass}) async {
  await tester.enterText(find.byType(TextField).first, email);
  await tester.enterText(find.byType(TextField).at(1), pass);
  await tester.tap(find.text('Iniciar sesión'));
  await tester.pump(); // status pasa a loading -- acá es donde el bug real rebotaba a /splash
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    ApiService.client = MockClient((_) async => http.Response('No mockeado', 400));
  });

  testWidgets('credenciales incorrectas: se queda en Login con el error visible, NO llega a Catálogo ni a Splash', (tester) async {
    _forzarViewportMobile(tester);

    ApiService.client = MockClient((req) async {
      if (req.url.path.contains('/api/auth/login')) {
        return http.Response('{"message":"Credenciales inválidas"}', 401,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('No mockeado', 404);
    });

    final app = _buildApp();
    await tester.pumpWidget(app.widget);
    await tester.pumpAndSettle();

    await _login(tester, email: 'alguien@test.com', pass: 'password-que-no-es');

    expect(find.text('Bienvenido de nuevo'), findsOneWidget,
        reason: 'debe seguir en LoginScreen -- el bug real lo sacaba de acá sin mostrar nada');
    expect(find.text('Home Catálogo'), findsNothing,
        reason: 'este era exactamente el síntoma reportado: terminar en el catálogo con credenciales inválidas');
    expect(find.text('Splash'), findsNothing);
    expect(find.textContaining('incorrect'), findsOneWidget,
        reason: 'el mensaje de error del backend debe verse en pantalla');
  });

  testWidgets('credenciales correctas: SÍ navega al home del rol (no se rompió el caso de éxito)', (tester) async {
    _forzarViewportMobile(tester);

    ApiService.client = MockClient((req) async {
      if (req.url.path.contains('/api/auth/login')) {
        return http.Response(
          jsonEncode({'data': {
            'token': 'un-token-valido',
            'usuario': {
              'id_usuario': 1, 'nombre': 'Ana', 'email': 'ana@test.com',
              'rol': {'nombre': 'admin'},
            },
          }}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      // /api/auth/perfil y /api/auth/mis-permisos son "best-effort" (AuthService.login
      // los atrapa con try/catch) -- responder 404 no debe romper el login.
      return http.Response('No mockeado', 404);
    });

    final app = _buildApp();
    await tester.pumpWidget(app.widget);
    await tester.pumpAndSettle();

    await _login(tester, email: 'ana@test.com', pass: 'password-correcta');

    expect(find.text('Home Dashboard'), findsOneWidget,
        reason: 'admin con credenciales correctas debe llegar a su home de rol');
    expect(find.text('Bienvenido de nuevo'), findsNothing);
  });

  testWidgets('correo que no existe en el sistema: no navega (backend da el mismo 401 genérico)', (tester) async {
    _forzarViewportMobile(tester);

    ApiService.client = MockClient((req) async {
      if (req.url.path.contains('/api/auth/login')) {
        // El backend real (auth/service.js) da el MISMO 401 "Credenciales
        // inválidas" para un correo inexistente que para una contraseña
        // incorrecta -- nunca revela si el correo existe o no.
        return http.Response('{"message":"Credenciales inválidas"}', 401,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('No mockeado', 404);
    });

    final app = _buildApp();
    await tester.pumpWidget(app.widget);
    await tester.pumpAndSettle();
    await _login(tester, email: 'noexiste@test.com', pass: 'cualquiercosa123');

    expect(find.text('Bienvenido de nuevo'), findsOneWidget);
    expect(find.text('Home Catálogo'), findsNothing);
    expect(find.text('Splash'), findsNothing);
  });

  testWidgets('correo existente + contraseña incorrecta: no navega', (tester) async {
    _forzarViewportMobile(tester);

    ApiService.client = MockClient((req) async {
      if (req.url.path.contains('/api/auth/login')) {
        return http.Response('{"message":"Credenciales inválidas"}', 401,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('No mockeado', 404);
    });

    final app = _buildApp();
    await tester.pumpWidget(app.widget);
    await tester.pumpAndSettle();
    await _login(tester, email: 'usuarioreal@test.com', pass: 'password-incorrecta');

    expect(find.text('Bienvenido de nuevo'), findsOneWidget);
    expect(find.text('Home Catálogo'), findsNothing);
    expect(find.text('Splash'), findsNothing);
  });

  group('campos vacíos: validación local, ni siquiera llama al backend', () {
    Future<int> intentarConCampos(WidgetTester tester, {required String email, required String pass}) async {
      _forzarViewportMobile(tester);
      var llamadas = 0;
      ApiService.client = MockClient((req) async {
        llamadas++;
        return http.Response('{"message":"Credenciales inválidas"}', 401,
            headers: {'content-type': 'application/json; charset=utf-8'});
      });

      final app = _buildApp();
      await tester.pumpWidget(app.widget);
      await tester.pumpAndSettle();
      await _login(tester, email: email, pass: pass);
      return llamadas;
    }

    testWidgets('correo vacío: no llama al backend, sigue en Login', (tester) async {
      final llamadas = await intentarConCampos(tester, email: '', pass: 'algunaCosa123');
      expect(llamadas, 0, reason: 'debe bloquearse en validación local antes de tocar la red');
      expect(find.text('Bienvenido de nuevo'), findsOneWidget);
    });

    testWidgets('contraseña vacía: no llama al backend, sigue en Login', (tester) async {
      final llamadas = await intentarConCampos(tester, email: 'alguien@test.com', pass: '');
      expect(llamadas, 0);
      expect(find.text('Bienvenido de nuevo'), findsOneWidget);
    });

    testWidgets('ambos vacíos: no llama al backend, sigue en Login', (tester) async {
      final llamadas = await intentarConCampos(tester, email: '', pass: '');
      expect(llamadas, 0);
      expect(find.text('Bienvenido de nuevo'), findsOneWidget);
    });
  });

  testWidgets('backend caído (SocketException) durante login: no navega, error visible', (tester) async {
    _forzarViewportMobile(tester);

    ApiService.client = MockClient((req) async {
      throw const SocketException('Sin conexión a internet');
    });

    final app = _buildApp();
    await tester.pumpWidget(app.widget);
    await tester.pumpAndSettle();
    await _login(tester, email: 'alguien@test.com', pass: 'cualquiercosa123');

    expect(tester.takeException(), isNull, reason: 'una caída de red no debe crashear la pantalla');
    expect(find.text('Bienvenido de nuevo'), findsOneWidget,
        reason: 'debe seguir en Login, no navegar a ningún lado por una falla de red');
    expect(find.text('Home Catálogo'), findsNothing);
    expect(find.text('Splash'), findsNothing);
    expect(find.textContaining('conexión'), findsOneWidget);
  });

  testWidgets('timeout del backend durante login: no navega, error visible (reloj falso, sin esperar 30s de verdad)', (tester) async {
    _forzarViewportMobile(tester);

    ApiService.client = MockClient((req) async {
      await Future<void>.delayed(const Duration(seconds: 45)); // pasa el timeout real de 30s de ApiService
      return http.Response('{"message":"no debería llegar acá"}', 200);
    });

    final app = _buildApp();
    await tester.pumpWidget(app.widget);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'alguien@test.com');
    await tester.enterText(find.byType(TextField).at(1), 'cualquiercosa123');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 31)); // pasa el timeout de 30s
    await tester.pumpAndSettle();

    expect(find.text('Bienvenido de nuevo'), findsOneWidget);
    expect(find.text('Home Catálogo'), findsNothing);
    expect(find.text('Splash'), findsNothing);
    expect(find.textContaining('conexión'), findsOneWidget,
        reason: 'ApiService convierte el timeout en un ApiException con mensaje de "Tiempo de espera..."; '
            'login_screen.dart lo traduce a "Sin conexión a internet" (ver _parsearErrorBackend)');

    // Deja correr el mock "en vuelo" (sigue pendiente hasta los 45s) para no
    // dejar un Timer pendiente al final del test.
    await tester.pump(const Duration(seconds: 15));
  });

  testWidgets('doble tap con credenciales incorrectas: solo 1 llamada al backend, no navega', (tester) async {
    _forzarViewportMobile(tester);

    var llamadas = 0;
    ApiService.client = MockClient((req) async {
      if (req.url.path.contains('/api/auth/login')) {
        llamadas++;
        await Future.delayed(const Duration(milliseconds: 300));
        return http.Response('{"message":"Credenciales inválidas"}', 401,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('No mockeado', 404);
    });

    final app = _buildApp();
    await tester.pumpWidget(app.widget);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'alguien@test.com');
    await tester.enterText(find.byType(TextField).at(1), 'password-mala');

    final boton = find.byType(ElevatedButton);
    await tester.tap(boton);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(boton, warnIfMissed: false); // botón deshabilitado mientras _loading es true
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(llamadas, 1, reason: 'el segundo tap no debe disparar una segunda petición');
    expect(find.text('Bienvenido de nuevo'), findsOneWidget);
    expect(find.text('Home Catálogo'), findsNothing);
    expect(find.text('Splash'), findsNothing);
  });

  testWidgets('respuesta MUY lenta (varios segundos) con credenciales incorrectas: loading persiste sin parpadeo a Catálogo/Splash, error al final', (tester) async {
    // Este es el escenario de carrera más parecido al bug original: si el
    // redirect global llegara a rebotar a /splash en algún punto intermedio
    // mientras la petición sigue pendiente, se detectaría acá revisando el
    // árbol en varios puntos DURANTE la espera, no solo al final.
    _forzarViewportMobile(tester);

    ApiService.client = MockClient((req) async {
      if (req.url.path.contains('/api/auth/login')) {
        await Future.delayed(const Duration(seconds: 6));
        return http.Response('{"message":"Credenciales inválidas"}', 401,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('No mockeado', 404);
    });

    final app = _buildApp();
    await tester.pumpWidget(app.widget);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'alguien@test.com');
    await tester.enterText(find.byType(TextField).at(1), 'password-mala');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pump(); // dispara status=loading -- el punto exacto donde rebotaba el bug original

    // Revisa el árbol en varios puntos intermedios mientras la petición
    // sigue pendiente (segundo 1, 3 y 5 de 6) -- en NINGUNO debe aparecer
    // Catálogo ni Splash.
    for (final segundos in [1, 3, 5]) {
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Home Catálogo'), findsNothing,
          reason: 'en el segundo $segundos, todavía en vuelo, no debe haber ningún parpadeo hacia el catálogo');
      expect(find.text('Splash'), findsNothing,
          reason: 'en el segundo $segundos, todavía en vuelo, no debe rebotar a splash');
      expect(find.byType(CircularProgressIndicator), findsWidgets,
          reason: 'debe seguir mostrando el loading del botón mientras espera');
    }

    await tester.pump(const Duration(seconds: 2)); // completa los 6s del mock
    await tester.pumpAndSettle();

    expect(find.text('Bienvenido de nuevo'), findsOneWidget);
    expect(find.text('Home Catálogo'), findsNothing);
    expect(find.text('Splash'), findsNothing);
    expect(find.textContaining('incorrect'), findsOneWidget);
  });
}
