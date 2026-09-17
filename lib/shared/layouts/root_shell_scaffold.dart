import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Scaffold raíz compartido por los 3 roles con bottom nav (Cliente,
/// Domiciliario, Admin). Envuelve el `navigationShell` de un
/// StatefulShellRoute (un Navigator independiente por tab, para que el
/// historial de "atrás" de cada sección sea propio).
///
/// El manejo del back del sistema en la RAÍZ de un tab (pop dentro del tab
/// automático vía Navigator anidado; ir al tab home si no es home; doble-
/// back-para-salir si es home) vive en `ShellAwareBackButtonDispatcher`
/// (double_back_to_exit.dart), conectado en main.dart vía
/// `MaterialApp.router(backButtonDispatcher: ...)`. NO vive acá como
/// PopScope -- se probó y no funciona: go_router's popRoute() solo dispara
/// PopScope cuando algún Navigator tiene algo que popear, cosa que nunca es
/// cierta en la raíz de un branch. Ver el comentario completo en
/// double_back_to_exit.dart.
class RootShellScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  final Widget Function(StatefulNavigationShell shell) bottomNavBuilder;
  final Widget? floatingActionButton;
  /// Franja opcional fija arriba de todos los tabs (ej. ResenaPendienteBanner
  /// en el shell Cliente). Se reserva su altura real -- envuelta en
  /// SafeArea propia -- y se le quita el padding superior de MediaQuery al
  /// navigationShell para que el AppBar de cada branch no vuelva a sumar el
  /// alto de la status bar por su cuenta (quedaría un doble espacio).
  final Widget? banner;

  const RootShellScaffold({
    super.key,
    required this.navigationShell,
    required this.bottomNavBuilder,
    this.floatingActionButton,
    this.banner,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: banner == null
          ? navigationShell
          : Column(
              children: [
                SafeArea(bottom: false, child: banner!),
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: navigationShell,
                  ),
                ),
              ],
            ),
      bottomNavigationBar: bottomNavBuilder(navigationShell),
      floatingActionButton: floatingActionButton,
    );
  }
}
