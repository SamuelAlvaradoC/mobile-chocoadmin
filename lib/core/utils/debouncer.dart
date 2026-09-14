import 'dart:async';

/// Timer cancelable simple para validar mientras el usuario escribe sin
/// recalcular en cada tecla: cada llamada a run() cancela el temporizador
/// pendiente (si lo hay) y agenda uno nuevo -- solo corre la acción una vez
/// que pasan `delay` sin una nueva llamada.
class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer({this.delay = const Duration(milliseconds: 400)});

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() {
    _timer?.cancel();
  }
}
