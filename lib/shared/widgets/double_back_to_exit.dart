import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Lógica compartida del patrón estándar de Android "presiona atrás de
/// nuevo para salir": la primera vez que se intenta salir se muestra un
/// SnackBar; si se vuelve a intentar dentro de la ventana de tiempo, se
/// cierra la app de verdad. Se usa tanto en el back-handler de la raíz de
/// cada shell con bottom nav (RootShellScaffold) como en las pantallas de
/// un solo rol sin bottom nav (Cocina, Confirmador).
mixin DoubleBackToExitMixin<T extends StatefulWidget> on State<T> {
  DateTime? _ultimoIntento;

  void handleDoubleBackToExit(BuildContext context) {
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
    } else {
      SystemNavigator.pop();
    }
  }
}
