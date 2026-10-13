import 'package:flutter_test/flutter_test.dart';
import 'package:chocoadmin/core/utils/pago.dart';

List detalle(List<(String, int)> pares) => [
      {'detallePagos': [for (final p in pares) {'monto': '${p.$2}', 'metodoPago': {'nombre': p.$1}}]}
    ];

void main() {
  test('mixto sin entregar (sin detallePagos): montos de la venta', () {
    final p = pagoDeVenta({'metodo_pago': 'mixto', 'total': '60000', 'monto_efectivo': '7000', 'monto_transferencia': '53000', 'pagos': []});
    expect((p.metodo, p.efectivo, p.transferencia), ('mixto', 7000.0, 53000.0));
  });

  test('mixto editado después de entregar (detallePagos viejo): manda la venta', () {
    final p = pagoDeVenta({'metodo_pago': 'mixto', 'total': '53000', 'monto_efectivo': '1000', 'monto_transferencia': '52000',
        'pagos': detalle([('transferencia', 53000)])});
    expect((p.efectivo, p.transferencia), (1000.0, 52000.0));
  });

  test('venta vieja sin montos ni método: cae a detallePagos', () {
    final p = pagoDeVenta({'total': '60000', 'pagos': detalle([('efectivo', 7000), ('transferencia', 53000)])});
    expect((p.metodo, p.efectivo, p.transferencia), ('mixto', 7000.0, 53000.0));
  });

  test('efectivo y transferencia puros usan el total', () {
    final e = pagoDeVenta({'metodo_pago': 'efectivo', 'total': '40000'});
    final t = pagoDeVenta({'metodo_pago': 'transferencia', 'total': '40000'});
    expect((e.efectivo, e.transferencia, t.efectivo, t.transferencia), (40000.0, 0.0, 0.0, 40000.0));
  });
}
