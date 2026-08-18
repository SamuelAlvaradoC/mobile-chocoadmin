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
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

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
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

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
}
