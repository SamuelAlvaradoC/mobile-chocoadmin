import 'package:flutter/widgets.dart';

/// Vuelve a llamar `callback` cuando la app regresa de segundo plano
/// (AppLifecycleState.resumed) -- antes de esto, pantallas como Dashboard/
/// Ventas/Pedidos/Catálogo solo cargaban datos una vez en initState, así que
/// se veían "pegadas" con datos viejos si el usuario dejaba la app en
/// background y volvía después de un rato (sin necesidad de que el token
/// expirara). `minInterval` evita relanzar la carga si el usuario entra y
/// sale de la app varias veces seguidas en poco tiempo.
///
/// Uso:
/// ```dart
/// late final RefetchOnResume _refetchOnResume;
///
/// @override
/// void initState() {
///   super.initState();
///   _cargar();
///   _refetchOnResume = RefetchOnResume(callback: _cargar);
/// }
///
/// @override
/// void dispose() {
///   _refetchOnResume.dispose();
///   super.dispose();
/// }
/// ```
class RefetchOnResume {
  final VoidCallback callback;
  final Duration minInterval;
  DateTime _ultimoRefetch = DateTime.now();
  late final _RefetchObserver _observer;

  RefetchOnResume({required this.callback, this.minInterval = const Duration(seconds: 10)}) {
    _observer = _RefetchObserver(_onResumed);
    WidgetsBinding.instance.addObserver(_observer);
  }

  void _onResumed() {
    final ahora = DateTime.now();
    if (ahora.difference(_ultimoRefetch) < minInterval) return;
    _ultimoRefetch = ahora;
    callback();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(_observer);
  }
}

class _RefetchObserver with WidgetsBindingObserver {
  final VoidCallback onResumed;
  _RefetchObserver(this.onResumed);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResumed();
  }
}
