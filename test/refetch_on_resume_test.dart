// Prueba real (no mock) del mecanismo que dispara la recarga de datos
// cuando la app vuelve de segundo plano (AppLifecycleState.resumed) --
// hueco que causaba que Dashboard/Ventas/Pedidos/Catálogo se quedaran
// "pegados" con datos viejos tras dejar la app en background un rato.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chocoadmin/shared/utils/refetch_on_resume.dart';

// Misma secuencia real que Flutter exige para un ciclo completo de
// background -> foreground (ver lifecycle_test.dart).
Future<void> _simularBackgroundYForeground(WidgetTester tester) async {
  for (final s in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('llama al callback cuando la app vuelve de segundo plano', (tester) async {
    var llamadas = 0;
    final r = RefetchOnResume(callback: () => llamadas++, minInterval: Duration.zero);

    await _simularBackgroundYForeground(tester);

    expect(llamadas, 1);
    r.dispose();
  });

  testWidgets('NO llama al callback en estados intermedios (solo en resumed)', (tester) async {
    var llamadas = 0;
    final r = RefetchOnResume(callback: () => llamadas++, minInterval: Duration.zero);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(llamadas, 0, reason: 'pausado/inactivo no debe disparar recarga, solo resumed');

    r.dispose();
  });

  testWidgets('NO relanza la carga si la app entra y sale de foreground varias veces seguidas', (tester) async {
    var llamadas = 0;
    final r = RefetchOnResume(callback: () => llamadas++, minInterval: const Duration(milliseconds: 200));
    // RefetchOnResume usa DateTime.now() (reloj real), no el reloj falso de
    // testWidgets -- hay que escapar la zona fake-async con runAsync() para
    // que un delay real efectivamente pase, si no tester.pump() nunca lo
    // resuelve y el test cuelga hasta el timeout.
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 250)));

    await _simularBackgroundYForeground(tester);
    await _simularBackgroundYForeground(tester);
    await _simularBackgroundYForeground(tester);

    expect(llamadas, 1, reason: 'las siguientes 2 veces ocurrieron dentro del intervalo mínimo');
    r.dispose();
  });

  testWidgets('vuelve a permitir la recarga después de pasado el intervalo mínimo', (tester) async {
    var llamadas = 0;
    final r = RefetchOnResume(callback: () => llamadas++, minInterval: const Duration(milliseconds: 100));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 150)));

    await _simularBackgroundYForeground(tester);
    expect(llamadas, 1);

    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 150)));
    await _simularBackgroundYForeground(tester);
    expect(llamadas, 2);

    r.dispose();
  });

  testWidgets('dispose() detiene la escucha -- no llama al callback después', (tester) async {
    var llamadas = 0;
    final r = RefetchOnResume(callback: () => llamadas++, minInterval: Duration.zero);
    r.dispose();

    await _simularBackgroundYForeground(tester);

    expect(llamadas, 0);
  });
}
