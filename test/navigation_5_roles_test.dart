// Extiende root_shell_scaffold_test.dart (que probó el mecanismo genérico
// del ShellAwareBackButtonDispatcher con un router de juguete de 3 branches)
// a los 5 roles REALES de la app, usando las mismas rutas y el mismo mapa
// nonHomeToHome/flatRouteHandlers que main.dart -- para que un typo o un
// path que se mueva sin actualizar el mapa lo agarre un test, no una
// prueba manual en el celular.
//
// Pantallas triviales (Text), mismos paths y misma config que main.dart:
// Cliente (/landing home, /catalogo, /perfil -- Puntos vive dentro de
// Perfil, no es branch propio), Domiciliario (/domiciliario/pedidos home,
// /domiciliario/caja), Admin (/admin/dashboard home, /admin/productos,
// /admin/ventas), y las rutas planas rol-conscientes (/cocina,
// /admin/domicilios) con el mismo patrón de _staffFlatRouteExitHandler de
// main.dart (admin -> vuelve al dashboard, cualquier otro rol ->
// doble-back-para-salir). /login, /register y /forgot-password también son
// planas, con el mismo patrón de _authScreenExitHandler real: back siempre
// va a /catalogo (no hay "de dónde vine" real porque se llega con
// context.go(), no con push).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chocoadmin/shared/layouts/root_shell_scaffold.dart';
import 'package:chocoadmin/shared/widgets/double_back_to_exit.dart';

void _resetDebounce() => BackExitController.resetParaTests();

enum _RolStaff { admin, otro }

Widget _bottomNavDeIndices(StatefulNavigationShell shell, List<String> labels) {
  return BottomNavigationBar(
    currentIndex: shell.currentIndex,
    onTap: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
    items: [for (final l in labels) BottomNavigationBarItem(icon: const Icon(Icons.circle), label: l)],
  );
}

({GoRouter router, Widget widget}) _buildApp({
  required String initialLocation,
  _RolStaff rol = _RolStaff.otro,
}) {
  late final GoRouter router;

  // Copia real de _ultimaRutaAdminShell + su tracking en _redirect
  // (main.dart): admin vuelve al branch del shell admin que tenía abierto
  // antes (Dashboard/Productos/Ventas), no siempre al Dashboard.
  const ramasAdminShell = {'/admin/dashboard', '/admin/productos', '/admin/ventas'};
  var ultimaRutaAdminShell = '/admin/dashboard';
  String? redirect(BuildContext context, GoRouterState state) {
    if (ramasAdminShell.contains(state.matchedLocation)) {
      ultimaRutaAdminShell = state.matchedLocation;
    }
    return null;
  }

  // Mismo patrón que _staffFlatRouteExitHandler en main.dart: admin vuelve
  // al último branch del shell admin visitado; cualquier otro rol
  // (cocina/confirmador) aplica doble-back-para-salir. `rol` queda fijo
  // para toda la vida de este router de prueba (cada test construye el
  // suyo con el rol que necesita).
  Future<bool> staffFlatHandler(BuildContext context) async {
    if (rol == _RolStaff.admin) {
      router.go(ultimaRutaAdminShell);
      return false;
    }
    return BackExitController.attemptExit(context);
  }

  // Copia real de _authScreenExitHandler en main.dart.
  Future<bool> authScreenExitHandler(BuildContext context) async {
    router.go('/catalogo');
    return false;
  }

  // Copia real de _checkoutExitHandler en main.dart.
  Future<bool> checkoutExitHandler(BuildContext context) async {
    router.go('/catalogo');
    return false;
  }

  router = GoRouter(
    initialLocation: initialLocation,
    redirect: redirect,
    routes: [
      // ── Cliente ──────────────────────────────────────────────
      // Puntos vive dentro de Perfil como pestaña, no como branch propio.
      // Landing es el home del shell (índice 0 para el back-button, aunque
      // el bottom nav real lo muestra en el medio) -- Catálogo y Perfil son
      // no-home y vuelven a Landing.
      StatefulShellRoute.indexedStack(
        builder: (c, s, shell) => RootShellScaffold(
          navigationShell: shell,
          bottomNavBuilder: (shell) => _bottomNavDeIndices(shell, const ['Catálogo', 'Landing', 'Perfil']),
        ),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/catalogo', builder: (_, __) => const Text('Home Catálogo'))]),
          StatefulShellBranch(routes: [GoRoute(path: '/landing', builder: (_, __) => const Text('Home Landing'))]),
          StatefulShellBranch(routes: [GoRoute(path: '/perfil', builder: (_, __) => const Text('Home Perfil'))]),
        ],
      ),
      // ── Domiciliario ─────────────────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (c, s, shell) => RootShellScaffold(
          navigationShell: shell,
          bottomNavBuilder: (shell) => _bottomNavDeIndices(shell, const ['Pedidos', 'Caja']),
        ),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/domiciliario/pedidos', builder: (_, __) => const Text('Home Pedidos'))]),
          StatefulShellBranch(routes: [GoRoute(path: '/domiciliario/caja', builder: (_, __) => const Text('Home Caja'))]),
        ],
      ),
      // ── Admin ────────────────────────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (c, s, shell) => RootShellScaffold(
          navigationShell: shell,
          bottomNavBuilder: (shell) => _bottomNavDeIndices(shell, const ['Dashboard', 'Productos', 'Ventas']),
        ),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/admin/dashboard', builder: (_, __) => const Text('Home Dashboard'))]),
          StatefulShellBranch(routes: [GoRoute(path: '/admin/productos', builder: (_, __) => const Text('Home Productos'))]),
          StatefulShellBranch(routes: [GoRoute(path: '/admin/ventas', builder: (_, __) => const Text('Home Ventas'))]),
        ],
      ),
      // ── Cocina / Confirmador (planas, rol-conscientes) ──────────
      // Scaffold propio -- son pantallas de un solo rol sin bottom nav, así
      // que a diferencia de los branches (que lo heredan de
      // RootShellScaffold) necesitan el suyo para que ScaffoldMessenger
      // encuentre dónde mostrar el SnackBar de doble-back.
      GoRoute(path: '/admin/domicilios', builder: (_, __) => const Scaffold(body: Text('Confirmador (plano)'))),
      GoRoute(path: '/cocina', builder: (_, __) => const Scaffold(body: Text('Cocina (plano)'))),
      GoRoute(path: '/login', builder: (_, __) => const Scaffold(body: Text('Login (plano)'))),
      GoRoute(path: '/checkout', builder: (_, __) => const Scaffold(body: Text('Checkout (plano)'))),
    ],
  );

  final widget = MaterialApp.router(
    routeInformationProvider: router.routeInformationProvider,
    routeInformationParser: router.routeInformationParser,
    routerDelegate: router.routerDelegate,
    backButtonDispatcher: ShellAwareBackButtonDispatcher(
      router,
      // Copiado literal del mapa real en main.dart.
      nonHomeToHome: const {
        '/catalogo': '/landing',
        '/perfil': '/landing',
        '/domiciliario/caja': '/domiciliario/pedidos',
        '/admin/productos': '/admin/dashboard',
        '/admin/ventas': '/admin/dashboard',
      },
      flatRouteHandlers: {
        '/admin/domicilios': staffFlatHandler,
        '/cocina': staffFlatHandler,
        // main.dart registra /login, /register y /forgot-password con el
        // mismo handler -- alcanza con probar uno acá, los otros 2 son la
        // misma función registrada 2 veces más.
        '/login': authScreenExitHandler,
        '/checkout': checkoutExitHandler,
      },
    ),
  );

  return (router: router, widget: widget);
}

void main() {
  setUp(_resetDebounce);

  group('Cliente (3 branches, Landing es home, Puntos vive dentro de Perfil)', () {
    testWidgets('back en la raíz de Catálogo (no-home) lleva a Landing (home)', (tester) async {
      final app = _buildApp(initialLocation: '/catalogo');
      await tester.pumpWidget(app.widget);
      await tester.pumpAndSettle();
      expect(find.text('Home Catálogo'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Home Landing'), findsOneWidget,
          reason: 'Landing es ahora un branch más (home del shell), no una ruta plana aparte');
      expect(find.text('Presiona atrás de nuevo para salir'), findsNothing);
    });

    testWidgets('back en la raíz de Perfil (no-home) lleva a Landing (home)', (tester) async {
      final app = _buildApp(initialLocation: '/perfil');
      await tester.pumpWidget(app.widget);
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Home Landing'), findsOneWidget);
    });

    testWidgets('back en la raíz de Landing (home) muestra el snackbar de doble-back', (tester) async {
      final app = _buildApp(initialLocation: '/landing');
      await tester.pumpWidget(app.widget);
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.text('Presiona atrás de nuevo para salir'), findsOneWidget);
    });

    testWidgets('tocar Catálogo↔Perfil directamente SÍ navega normal (el dispatcher no debe interferir)', (tester) async {
      final app = _buildApp(initialLocation: '/catalogo');
      await tester.pumpWidget(app.widget);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();

      expect(find.text('Home Perfil'), findsOneWidget);
      expect(find.text('Home Landing'), findsNothing,
          reason: 'cambiar de tab directamente no debe rebotar a Landing');
    });
  });

  group('Login/Register/ForgotPassword (planas, mismo destino fijo)', () {
    testWidgets('back en Login lleva a Catálogo, no aplica doble-back-para-salir', (tester) async {
      final app = _buildApp(initialLocation: '/login');
      await tester.pumpWidget(app.widget);
      await tester.pumpAndSettle();
      expect(find.text('Login (plano)'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Home Catálogo'), findsOneWidget,
          reason: 'sin push real no hay "de dónde vine" -- el destino fijo es /catalogo, no salir de la app');
      expect(find.text('Presiona atrás de nuevo para salir'), findsNothing);
    });
  });

  group('Domiciliario (2 branches)', () {
    testWidgets('back en la raíz de Caja (no-home) lleva a Pedidos (home)', (tester) async {
      final app = _buildApp(initialLocation: '/domiciliario/caja');
      await tester.pumpWidget(app.widget);
      await tester.pumpAndSettle();
      expect(find.text('Home Caja'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Home Pedidos'), findsOneWidget);
      expect(find.text('Home Caja'), findsNothing);
    });

    testWidgets('back en la raíz de Pedidos (home) muestra el snackbar de doble-back', (tester) async {
      final app = _buildApp(initialLocation: '/domiciliario/pedidos');
      await tester.pumpWidget(app.widget);
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.text('Presiona atrás de nuevo para salir'), findsOneWidget);
      expect(find.text('Home Pedidos'), findsOneWidget);
    });
  });

  group('Admin (3 branches)', () {
    testWidgets('back en la raíz de Productos lleva a Dashboard (home)', (tester) async {
      final app = _buildApp(initialLocation: '/admin/productos');
      await tester.pumpWidget(app.widget);
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Home Dashboard'), findsOneWidget);
    });

    testWidgets('back en la raíz de Ventas lleva a Dashboard (home)', (tester) async {
      final app = _buildApp(initialLocation: '/admin/ventas');
      await tester.pumpWidget(app.widget);
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Home Dashboard'), findsOneWidget);
    });

    testWidgets('back en la raíz de Dashboard (home) muestra el snackbar de doble-back', (tester) async {
      final app = _buildApp(initialLocation: '/admin/dashboard');
      await tester.pumpWidget(app.widget);
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.text('Presiona atrás de nuevo para salir'), findsOneWidget);
    });

    testWidgets('tocar Productos↔Ventas directamente SÍ navega normal (el dispatcher no debe interferir)', (tester) async {
      final app = _buildApp(initialLocation: '/admin/productos');
      await tester.pumpWidget(app.widget);
      await tester.pumpAndSettle();
      expect(find.text('Home Productos'), findsOneWidget);

      await tester.tap(find.text('Ventas')); // toca el tab directamente, sin pasar por Dashboard
      await tester.pumpAndSettle();

      expect(find.text('Home Ventas'), findsOneWidget,
          reason: 'cambiar de tab directamente no debe rebotar a Dashboard como pasaba con el bug de onExit');
      expect(find.text('Home Dashboard'), findsNothing);
    });

    testWidgets('admin en Ventas -> Confirmar pedidos -> back vuelve a Ventas, no siempre al Dashboard', (tester) async {
      // Reproduce el caso reportado: "soy el admin, paso a Ventas, de Ventas
      // a Confirmar, debería devolver a Ventas" -- back "estilo navegador"
      // en vez de un destino fijo.
      final app = _buildApp(initialLocation: '/admin/ventas', rol: _RolStaff.admin);
      await tester.pumpWidget(app.widget);
      await tester.pumpAndSettle();
      expect(find.text('Home Ventas'), findsOneWidget);

      app.router.go('/admin/domicilios'); // "Confirmar pedidos" desde Ventas
      await tester.pumpAndSettle();
      expect(find.text('Confirmador (plano)'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Home Ventas'), findsOneWidget,
          reason: 'debe recordar que Ventas fue el último branch admin visitado, no caer siempre a Dashboard');
      expect(find.text('Home Dashboard'), findsNothing);
    });
  });

  group('Checkout (ruta plana, mismo destino fijo que su flechita de AppBar)', () {
    testWidgets('back en Checkout lleva a Catálogo, no aplica doble-back-para-salir', (tester) async {
      final app = _buildApp(initialLocation: '/checkout');
      await tester.pumpWidget(app.widget);
      await tester.pumpAndSettle();
      expect(find.text('Checkout (plano)'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Home Catálogo'), findsOneWidget,
          reason: 'debe coincidir con la flechita del AppBar de checkout_screen.dart, no salir de la app a mitad de un pedido');
      expect(find.text('Presiona atrás de nuevo para salir'), findsNothing);
    });
  });

  group('Cocina (ruta plana, rol-consciente)', () {
    testWidgets('visto por admin: back vuelve al Dashboard', (tester) async {
      final app = _buildApp(initialLocation: '/cocina', rol: _RolStaff.admin);
      await tester.pumpWidget(app.widget);
      await tester.pumpAndSettle();
      expect(find.text('Cocina (plano)'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Home Dashboard'), findsOneWidget);
    });

    testWidgets('visto por cocina: back muestra el snackbar de doble-back (no hay tab home al cual volver)', (tester) async {
      final app = _buildApp(initialLocation: '/cocina', rol: _RolStaff.otro);
      await tester.pumpWidget(app.widget);
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.text('Presiona atrás de nuevo para salir'), findsOneWidget);
      expect(find.text('Cocina (plano)'), findsOneWidget, reason: 'el primer back no debe salir todavía');
    });
  });

  group('Confirmador (ruta plana /admin/domicilios, rol-consciente)', () {
    testWidgets('visto por admin: back vuelve al Dashboard', (tester) async {
      final app = _buildApp(initialLocation: '/admin/domicilios', rol: _RolStaff.admin);
      await tester.pumpWidget(app.widget);
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Home Dashboard'), findsOneWidget);
    });

    testWidgets('visto por confirmador: back muestra el snackbar de doble-back', (tester) async {
      final app = _buildApp(initialLocation: '/admin/domicilios', rol: _RolStaff.otro);
      await tester.pumpWidget(app.widget);
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.text('Presiona atrás de nuevo para salir'), findsOneWidget);
    });
  });
}
