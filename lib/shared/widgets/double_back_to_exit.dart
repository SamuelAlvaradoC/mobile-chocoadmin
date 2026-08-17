import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Lógica compartida del patrón estándar de Android "presiona atrás de
/// nuevo para salir": la primera vez que se intenta salir se muestra un
/// SnackBar; si se vuelve a intentar dentro de la ventana de tiempo, se deja
/// salir de verdad.
class BackExitController {
  BackExitController._();

  static DateTime? _ultimoIntento;

  /// Devuelve `true` si debe dejarse salir/exitear de verdad (segundo
  /// intento dentro de la ventana), o `false` si solo se mostró el aviso
  /// (primer intento, o pasó la ventana de tiempo).
  static bool attemptExit(BuildContext context) {
    final ahora = DateTime.now();
    if (_ultimoIntento == null || ahora.difference(_ultimoIntento!) > const Duration(seconds: 2)) {
      _ultimoIntento = ahora;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Presiona atrás de nuevo para salir'),
          duration: Duration(seconds: 2),
        ),
      );
      return false;
    }
    _ultimoIntento = null;
    return true;
  }

  /// Solo para tests: el debounce usa DateTime.now() (tiempo real, no el
  /// reloj simulado de flutter_test), así que varios tests en el mismo
  /// archivo pueden "verse" unos a otros si corren en menos de 2 segundos
  /// de tiempo real. Llamar en setUp()/tearDown() para que cada test
  /// empiece limpio.
  @visibleForTesting
  static void resetParaTests() => _ultimoIntento = null;
}

/// BackButtonDispatcher a medida: intercepta el back del sistema ANTES de
/// que llegue a go_router.
///
/// Se probaron dos alternativas más "obvias" y las dos fallan, confirmado
/// con tests (ver test/root_shell_scaffold_test.dart) contra el código
/// fuente real de go_router 13.2.5 (delegate.dart):
/// - `PopScope` en la raíz del shell: go_router's `popRoute()` solo llama a
///   `Navigator.maybePop()` (lo único que dispara PopScope) cuando ALGÚN
///   Navigator en la cadena tiene `canPop()==true`. En la raíz de un branch
///   eso nunca es cierto, así que PopScope simplemente nunca se consulta.
/// - `GoRoute.onExit` en la raíz de cada branch: SÍ se dispara sin
///   dispositivo... pero se dispara para CUALQUIER salida de esa ruta, no
///   solo el back del sistema -- incluida la navegación NORMAL entre tabs
///   (`setNewRoutePath` calcula qué rutas "salen" comparando la
///   configuración vieja/nueva y llama onExit ahí, sin importar si el
///   cambio vino de un back-press o de tocar el bottom nav). Con eso
///   puesto, tocar cualquier otro tab quedaba bloqueado.
///
/// La solución que sí funciona: interceptar en la capa que Flutter reserva
/// específicamente para el botón/gesto de atrás del sistema
/// (BackButtonDispatcher), un nivel ANTES de que go_router decida qué
/// hacer. Si go_router puede popear algo (un Navigator.push dentro de un
/// tab, un dialog, un bottom sheet), se le deja resolverlo normal. Si no
/// puede popear nada en ningún lado, se decide acá según la ubicación
/// actual: ir al tab home, o aplicar doble-back-para-salir.
class ShellAwareBackButtonDispatcher extends RootBackButtonDispatcher {
  final GoRouter router;
  final Map<String, String> nonHomeToHome;
  final Map<String, FutureOr<bool> Function(BuildContext context)> flatRouteHandlers;

  ShellAwareBackButtonDispatcher(
    this.router, {
    required this.nonHomeToHome,
    this.flatRouteHandlers = const {},
  });

  @override
  Future<bool> didPopRoute() async {
    if (router.canPop()) {
      return super.didPopRoute();
    }

    final context = router.routerDelegate.navigatorKey.currentContext;
    if (context == null) return super.didPopRoute();

    final location = router.routerDelegate.currentConfiguration.uri.path;

    final homePath = nonHomeToHome[location];
    if (homePath != null) {
      router.go(homePath);
      return true;
    }

    final flatHandler = flatRouteHandlers[location];
    if (flatHandler != null) {
      final debeSalir = await flatHandler(context);
      return !debeSalir;
    }

    // Raíz de un tab home, o cualquier pantalla plana sin handler propio.
    return !BackExitController.attemptExit(context);
  }
}
