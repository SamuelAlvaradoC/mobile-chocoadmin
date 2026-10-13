// Método y montos de pago de una venta, con la VENTA como fuente de verdad
// (mismo criterio que src/utils/pago.js en la web).
//
// monto_efectivo / monto_transferencia se guardan al crear la venta (y la API
// valida que en un mixto sumen el total). Los detallePagos, en cambio, solo
// existen DESPUÉS de marcar el pedido como entregado, y no se actualizan si la
// venta se edita luego (ej. #109 y #164: mixtos con un solo detallePago) -- por
// eso solo se usan como respaldo para ventas viejas sin montos en la venta.

class PagoVenta {
  final String? metodo;
  final double efectivo;
  final double transferencia;
  const PagoVenta({required this.metodo, required this.efectivo, required this.transferencia});

  bool get esMixto => metodo == 'mixto';
}

double? _num(Object? v) => v == null ? null : double.tryParse(v.toString());

List<Map> _detallePagos(Map venta) {
  final pagos = venta['pagos'];
  if (pagos is List && pagos.isNotEmpty && pagos[0] is Map) {
    final dp = (pagos[0] as Map)['detallePagos'];
    if (dp is List) return dp.whereType<Map>().toList();
  }
  return const [];
}

String? _nombreMetodo(Map detalle) {
  final mp = detalle['metodoPago'];
  return mp is Map ? mp['nombre']?.toString() : null;
}

PagoVenta pagoDeVenta(Map venta) {
  final detalles = _detallePagos(venta);
  double sumaDetalle(String nombre) => detalles
      .where((d) => _nombreMetodo(d) == nombre)
      .fold(0.0, (s, d) => s + (_num(d['monto']) ?? 0));

  String? metodo = venta['metodo_pago']?.toString();
  if (metodo == null || metodo.isEmpty) {
    metodo = detalles.length > 1 ? 'mixto' : (detalles.isNotEmpty ? _nombreMetodo(detalles.first) : null);
  }

  final total = _num(venta['total']) ?? 0;
  final ef = _num(venta['monto_efectivo']);
  final tr = _num(venta['monto_transferencia']);
  if (metodo == 'efectivo') return PagoVenta(metodo: metodo, efectivo: total, transferencia: 0);
  if (metodo == 'transferencia') return PagoVenta(metodo: metodo, efectivo: 0, transferencia: total);
  if (ef != null || tr != null) return PagoVenta(metodo: metodo, efectivo: ef ?? 0, transferencia: tr ?? 0);
  return PagoVenta(metodo: metodo, efectivo: sumaDetalle('efectivo'), transferencia: sumaDetalle('transferencia'));
}
