// Verifica el hallazgo "Login/Register/ForgotPassword no se comportaban
// como el back de una web": antes las 3 pantallas se cruzaban entre sí con
// context.go() (reemplaza la ubicación, no arma un historial real), así que
// el back del sistema SIEMPRE caía al destino fijo /catalogo sin importar
// desde cuál de las 3 se vino. Ahora los links cruzados usan context.push(),
// así que router.canPop() es true y el back normal de Flutter hace pop a la
// pantalla anterior -- igual que la flechita de atrás de un navegador.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:chocoadmin/features/auth/providers/auth_provider.dart';
import 'package:chocoadmin/features/auth/screens/forgot_password_screen.dart';
import 'package:chocoadmin/features/auth/screens/login_screen.dart';
import 'package:chocoadmin/features/auth/screens/register_screen.dart';
import 'package:chocoadmin/shared/widgets/double_back_to_exit.dart';

({GoRouter router, Widget widget}) _buildApp({required String initialLocation}) {
  late final GoRouter router;

  // Copia real de _authScreenExitHandler en main.dart.
  Future<bool> authScreenExitHandler(BuildContext context) async {
    router.go('/catalogo');
    return false;
  }

  router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/catalogo', builder: (_, __) => const Scaffold(body: Text('Home Catálogo'))),
      GoRoute(path: '/landing', builder: (_, __) => const Scaffold(body: Text('Home Landing'))),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
    ],
  );

  final widget = MultiProvider(
    providers: [ChangeNotifierProvider(create: (_) => AuthProvider())],
    child: MaterialApp.router(
      routeInformationProvider: router.routeInformationProvider,
      routeInformationParser: router.routeInformationParser,
      routerDelegate: router.routerDelegate,
      backButtonDispatcher: ShellAwareBackButtonDispatcher(
        router,
        nonHomeToHome: const {},
        flatRouteHandlers: {
          '/login': authScreenExitHandler,
          '/register': authScreenExitHandler,
          '/forgot-password': authScreenExitHandler,
        },
      ),
    ),
  );

  return (router: router, widget: widget);
}

// LoginScreen/RegisterScreen/ForgotPasswordScreen tienen un layout
// responsive heredado del port de React (MediaQuery.width > 700 muestra un
// panel de branding lado a lado, pensado para desktop web). El tamaño por
// defecto del surface de flutter_test (800x600) cae en ese rango y esa
// variante desborda a 600 de alto -- se fuerza un tamaño angosto de celular
// real para que renderice la variante mobile, la única que un usuario de
// esta app realmente ve.
void _forzarViewportMobile(WidgetTester tester) {
  tester.view.physicalSize = const Size(600, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => BackExitController.resetParaTests());

  testWidgets('Login -> Regístrate (push) -> back del sistema vuelve a Login, no salta a Catálogo', (tester) async {
    _forzarViewportMobile(tester);
    final app = _buildApp(initialLocation: '/login');
    await tester.pumpWidget(app.widget);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Regístrate gratis'));
    await tester.tap(find.text('Regístrate gratis'));
    await tester.pumpAndSettle();
    expect(find.text('🎁 ¡Gana 200 puntos solo por registrarte!'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Bienvenido de nuevo'), findsOneWidget,
        reason: 'router.canPop() debe ser true (push real) -- vuelve a Login, no a /catalogo');
  });

  testWidgets('Login -> Olvidaste tu contraseña (push) -> back del sistema vuelve a Login', (tester) async {
    _forzarViewportMobile(tester);
    final app = _buildApp(initialLocation: '/login');
    await tester.pumpWidget(app.widget);
    await tester.pumpAndSettle();

    await tester.tap(find.text('¿Olvidaste tu contraseña?'));
    await tester.pumpAndSettle();
    expect(find.text('Recuperar contraseña'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Bienvenido de nuevo'), findsOneWidget);
  });

  testWidgets('ForgotPassword alcanzado con push: "Volver a iniciar sesión" hace pop, no apila otro Login', (tester) async {
    _forzarViewportMobile(tester);
    final app = _buildApp(initialLocation: '/login');
    await tester.pumpWidget(app.widget);
    await tester.pumpAndSettle();

    await tester.tap(find.text('¿Olvidaste tu contraseña?'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('← Volver al inicio de sesión'));
    await tester.pumpAndSettle();

    expect(find.text('Bienvenido de nuevo'), findsOneWidget);
    expect(app.router.routerDelegate.currentConfiguration.matches.length, 1,
        reason: 'debe volver por pop (mismo Login de siempre), no apilar un Login nuevo encima');
  });

  testWidgets('Login alcanzado directo (sin push): back cae al destino fijo /catalogo', (tester) async {
    _forzarViewportMobile(tester);
    final app = _buildApp(initialLocation: '/login');
    await tester.pumpWidget(app.widget);
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Home Catálogo'), findsOneWidget,
        reason: 'sin nada que popear, el fallback real (_authScreenExitHandler) sigue aplicando');
  });
}
