// Verificación automática (sin dispositivo físico) de la mecánica de back
// button que usan los 3 roles con bottom nav (Cliente/Domiciliario/Admin).
// Usa un GoRouter + StatefulShellRoute de prueba con pantallas triviales
// (Text/ElevatedButton) en vez de las pantallas reales de la app, para no
// depender de red/providers/auth — solo se pone a prueba
// ShellAwareBackButtonDispatcher (el código real que decide el
// comportamiento del back, compartido por Cliente/Domiciliario/Admin).
//
// Se probaron 2 alternativas antes de llegar a esta (PopScope en la raíz
// del shell, luego GoRoute.onExit) y ambas fallaron en este mismo archivo
// de test antes de corregirse -- ver double_back_to_exit.dart para el
// porqué de cada una.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chocoadmin/shared/layouts/root_shell_scaffold.dart';
import 'package:chocoadmin/shared/widgets/double_back_to_exit.dart';

Widget _bottomNavDeIndices(StatefulNavigationShell shell) {
  return BottomNavigationBar(
    currentIndex: shell.currentIndex,
    onTap: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
    items: const [
      BottomNavigationBarItem(icon: Icon(Icons.home), label: 'A'),
      BottomNavigationBarItem(icon: Icon(Icons.star), label: 'B'),
      BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'C'),
    ],
  );
}

GoRouter _buildTestRouter() {
  return GoRouter(
    initialLocation: '/a',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => RootShellScaffold(
          navigationShell: navigationShell,
          bottomNavBuilder: _bottomNavDeIndices,
        ),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/a',
              builder: (context, state) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const Scaffold(body: Center(child: Text('Sub A')))),
                    ),
                    child: const Text('Home A'),
                  ),
                ),
              ),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/b', builder: (_, __) => const Scaffold(body: Center(child: Text('Home B')))),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/c', builder: (_, __) => const Scaffold(body: Center(child: Text('Home C')))),
          ]),
        ],
      ),
    ],
  );
}

Widget _appWithDispatcher(GoRouter router) {
  // MaterialApp.router prohíbe combinar `routerConfig` con un
  // backButtonDispatcher propio (assertion en app.dart: "If the
  // routerConfig is provided, all the other router delegates must not be
  // provided") -- hay que pasar las piezas de GoRouter por separado.
  return MaterialApp.router(
    routeInformationProvider: router.routeInformationProvider,
    routeInformationParser: router.routeInformationParser,
    routerDelegate: router.routerDelegate,
    backButtonDispatcher: ShellAwareBackButtonDispatcher(
      router,
      nonHomeToHome: const {'/b': '/a', '/c': '/a'},
    ),
  );
}

void main() {
  testWidgets(
    'back dentro de un tab hace pop de la pantalla empujada, sin salir del tab',
    (tester) async {
      final router = _buildTestRouter();
      await tester.pumpWidget(_appWithDispatcher(router));
      await tester.pumpAndSettle();

      expect(find.text('Home A'), findsOneWidget);

      await tester.tap(find.text('Home A'));
      await tester.pumpAndSettle();
      expect(find.text('Sub A'), findsOneWidget);

      // Simula el back del sistema (hardware/gesto de Android).
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Sub A'), findsNothing);
      expect(find.text('Home A'), findsOneWidget, reason: 'el back debió quedarse dentro del tab A, no saltar de tab ni salir');
    },
  );

  testWidgets(
    'tocar otro tab en el bottom nav SÍ navega normal (el dispatcher no debe interferir)',
    (tester) async {
      final router = _buildTestRouter();
      await tester.pumpWidget(_appWithDispatcher(router));
      await tester.pumpAndSettle();

      // De B a C directamente (ninguno es home) -- este es justo el caso
      // que la alternativa con onExit rompía.
      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();
      expect(find.text('Home B'), findsOneWidget);

      await tester.tap(find.text('C'));
      await tester.pumpAndSettle();
      expect(find.text('Home C'), findsOneWidget, reason: 'tocar el tab C desde B debe navegar a C, no quedarse en B ni saltar a home');
      expect(find.text('Home B'), findsNothing);
    },
  );

  testWidgets(
    'back en la raiz de un tab que NO es home lleva al tab home (branch 0)',
    (tester) async {
      final router = _buildTestRouter();
      await tester.pumpWidget(_appWithDispatcher(router));
      await tester.pumpAndSettle();

      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();
      expect(find.text('Home B'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Home A'), findsOneWidget, reason: 'el back en la raiz del tab B debió llevar al tab home (A)');
      expect(find.text('Home B'), findsNothing);
    },
  );

  testWidgets(
    'back en la raiz del tab home muestra el snackbar de doble-back antes de salir',
    (tester) async {
      final router = _buildTestRouter();
      await tester.pumpWidget(_appWithDispatcher(router));
      await tester.pumpAndSettle();

      expect(find.text('Home A'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);

      // Primer back en la raiz del home: debe mostrar el snackbar, NO salir
      // (no hay forma de comprobar "salida real" en un widget test — eso
      // requiere SystemNavigator.pop, que no se puede probar sin plataforma
      // real — pero sí se puede confirmar que el primer intento no navega a
      // ningún otro lado y muestra el aviso).
      await tester.binding.handlePopRoute();
      await tester.pump(); // deja que el SnackBar entre en escena (sin pumpAndSettle: la animación del SnackBar tarda >0)

      expect(find.text('Presiona atrás de nuevo para salir'), findsOneWidget);
      expect(find.text('Home A'), findsOneWidget, reason: 'la primera vez no debe salir de la pantalla');
    },
  );
}
