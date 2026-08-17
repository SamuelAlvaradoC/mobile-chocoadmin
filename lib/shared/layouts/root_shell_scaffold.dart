import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/double_back_to_exit.dart';

/// Scaffold raíz compartido por los 3 roles con bottom nav (Cliente,
/// Domiciliario, Admin). Envuelve el `navigationShell` de un
/// StatefulShellRoute (un Navigator independiente por tab, para que el
/// historial de "atrás" de cada sección sea propio) y controla el back del
/// sistema en la raíz:
/// - Si hay algo que popear dentro del tab activo, Flutter lo resuelve solo
///   (Navigator anidado por branch) — este widget nunca llega a intervenir
///   en ese caso.
/// - Si el tab activo está en su pantalla raíz y NO es el tab home (índice
///   0), atrás lleva de vuelta al tab home.
/// - Si el tab activo es el home y está en su raíz, atrás aplica el patrón
///   estándar de Android "presiona atrás de nuevo para salir".
class RootShellScaffold extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  final Widget Function(StatefulNavigationShell shell) bottomNavBuilder;

  const RootShellScaffold({
    super.key,
    required this.navigationShell,
    required this.bottomNavBuilder,
  });

  @override
  State<RootShellScaffold> createState() => _RootShellScaffoldState();
}

class _RootShellScaffoldState extends State<RootShellScaffold> with DoubleBackToExitMixin {
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (widget.navigationShell.currentIndex != 0) {
          widget.navigationShell.goBranch(0);
        } else {
          handleDoubleBackToExit(context);
        }
      },
      child: Scaffold(
        body: widget.navigationShell,
        bottomNavigationBar: widget.bottomNavBuilder(widget.navigationShell),
      ),
    );
  }
}
