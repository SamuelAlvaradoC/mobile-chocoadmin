// Pedido hecho fuera de horario: la API lo guarda con fecha = hora de
// apertura y fecha_real = hora real. El equipo ve "Pedido hecho fuera de
// horario: lunes 10:05 PM"; en los pedidos normales no aparece nada.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chocoadmin/core/models/pedido.dart';
import 'package:chocoadmin/core/utils/formato.dart';
import 'package:chocoadmin/shared/widgets/pedido_fuera_de_horario.dart';

void main() {
  // Lunes 19 de octubre de 2026, 10:05 PM Colombia = martes 20, 03:05 UTC
  final json = {
    'id_venta': 900,
    'estado': {'nombre_estado': 'pendiente'},
    'total': 25000,
    'fecha': '2026-10-20T18:00:00.000Z',      // martes 1:00 PM (apertura)
    'fecha_real': '2026-10-20T03:05:00.000Z', // lunes 10:05 PM (hora real)
  };

  test('el modelo lee fecha_real; los pedidos normales la dejan en null', () {
    final p = Pedido.fromJson(json);
    expect(p.fechaReal, isNotNull);
    expect(diaYHoraColombia(p.fechaReal!), 'lunes 10:05 PM');
    expect(p.hora, '1:00 PM'); // la hora del pedido es la de apertura
    expect(Pedido.fromJson({...json, 'fecha_real': null}).fechaReal, isNull);
  });

  testWidgets('la etiqueta solo aparece en los pedidos hechos fuera de horario', (tester) async {
    final p = Pedido.fromJson(json);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PedidoFueraDeHorario(fechaReal: p.fechaReal))));
    expect(find.text('🌙 Pedido hecho fuera de horario: lunes 10:05 PM'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PedidoFueraDeHorario(fechaReal: null))));
    expect(find.textContaining('fuera de horario'), findsNothing);
  });
}
