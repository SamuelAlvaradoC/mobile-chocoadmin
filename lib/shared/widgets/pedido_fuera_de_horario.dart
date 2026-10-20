import 'package:flutter/material.dart';

import '../../core/utils/formato.dart';

/// Para el equipo: marca los pedidos que el cliente hizo fuera de horario
/// (quedaron para la hora de apertura). No muestra nada en los demás.
/// Ej: "🌙 Pedido hecho fuera de horario: lunes 10:05 PM".
class PedidoFueraDeHorario extends StatelessWidget {
  const PedidoFueraDeHorario({super.key, required this.fechaReal, this.margen = EdgeInsets.zero});

  final DateTime? fechaReal;
  final EdgeInsets margen;

  @override
  Widget build(BuildContext context) {
    final fecha = fechaReal;
    if (fecha == null) return const SizedBox.shrink();
    return Padding(
      padding: margen,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFEEF2FF),
          border: Border.all(color: const Color(0xFFC7D2FE)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '🌙 Pedido hecho fuera de horario: ${diaYHoraColombia(fecha)}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF3730A3)),
        ),
      ),
    );
  }
}
