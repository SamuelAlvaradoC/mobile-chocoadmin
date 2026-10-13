import 'package:flutter_test/flutter_test.dart';
import 'package:chocoadmin/core/models/pedido.dart';
import 'package:chocoadmin/core/utils/formato.dart';

// Venta #522 tal como la devuelve GET /api/ventas (Decimal de Prisma -> texto).
Map<String, dynamic> venta522({List<dynamic> pagos = const []}) => {
      'id_venta': 522,
      'fecha': '2026-10-12T21:11:32.715Z',
      'subtotal': '43000',
      'costo_domicilio': '17000',
      'total': '60000',
      'metodo_pago': 'mixto',
      'monto_efectivo': '7000',
      'monto_transferencia': '53000',
      'estado': {'id_estado': 3, 'nombre_estado': 'despachado'},
      'detalleVentas': [],
      'pagos': pagos,
    };

void main() {
  test('mixto antes de entregar (sin pagos): montos salen de la venta, no 0', () {
    final p = Pedido.fromJson(venta522());
    expect(p.formaPago, 'mixto');
    expect(p.montoEfectivo, 7000);
    expect(p.montoTransferencia, 53000);
    expect(fmtCop.format(p.montoEfectivo), '\$7.000');
  });

  test('mixto entregado (con detallePagos): mismos montos', () {
    final p = Pedido.fromJson(venta522(pagos: [
      {
        'detallePagos': [
          {'monto': '7000', 'metodoPago': {'nombre': 'efectivo'}},
          {'monto': '53000', 'metodoPago': {'nombre': 'transferencia'}},
        ],
      },
    ]));
    expect(p.montoEfectivo, 7000);
    expect(p.montoTransferencia, 53000);
  });

  test('venta vieja sin montos en la venta: cae a detallePagos', () {
    final json = venta522(pagos: [
      {
        'detallePagos': [
          {'monto': '7000', 'metodoPago': {'nombre': 'efectivo'}},
          {'monto': '53000', 'metodoPago': {'nombre': 'transferencia'}},
        ],
      },
    ])
      ..remove('monto_efectivo')
      ..remove('monto_transferencia');
    final p = Pedido.fromJson(json);
    expect(p.montoEfectivo, 7000);
    expect(p.montoTransferencia, 53000);
  });

  test('#522 muestra la hora en Colombia: 4:11 PM', () {
    expect(Pedido.fromJson(venta522()).hora, '4:11 PM');
  });
}
