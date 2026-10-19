/// Equivalente a formatHora12() del frontend React (src/utils/formatHora.js).
String formatHora12(dynamic hora24) {
  final h = num.tryParse(hora24?.toString() ?? '') ?? 0;
  final period = h < 12 ? 'AM' : 'PM';
  final h12raw = h % 12;
  final h12 = h12raw == 0 ? 12 : h12raw.toInt();
  return '$h12:00 $period';
}

/// Aviso cuando la tienda no recibe pedidos (igual que mensajeTiendaCerrada
/// en React). Con cierre manual ("closed") no hay hora de reapertura.
String mensajeTiendaCerrada({String? estado, dynamic horaApertura}) {
  if (estado == 'closed' || horaApertura == null) {
    return 'Estamos cerrados por ahora. Puedes dejar tu pedido armado y hacerlo cuando volvamos a abrir.';
  }
  return 'Estamos cerrados. Puedes dejar tu pedido armado y hacerlo desde la ${formatHora12(horaApertura)}.';
}
