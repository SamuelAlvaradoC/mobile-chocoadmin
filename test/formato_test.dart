import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:chocoadmin/core/utils/formato.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es_CO'));

  group('fmtCop', () {
    test('símbolo adelante y punto de miles', () {
      expect(fmtCop.format(43000), '\$43.000');
      expect(fmtCop.format(0), '\$0');
      expect(fmtCop.format(1250000), '\$1.250.000');
    });
  });

  group('hora Colombia', () {
    test('#522: 21:11 UTC se muestra 4:11 PM', () {
      final dt = parseFechaApi('2026-10-12T21:11:32.715Z')!;
      expect(horaColombia(dt), '4:11 PM');
      expect(fechaHoraColombia(dt), '12/10/2026 4:11 PM');
    });

    test('venta de las 8 PM Colombia (01:12 UTC del día siguiente) sigue siendo ese día', () {
      final dt = parseFechaApi('2026-10-02T00:12:51.567Z')!;
      expect(horaColombia(dt), '7:12 PM');
      expect(fechaColombia(dt, 'yyyy-MM-dd'), '2026-10-01');
    });

    test('11:59 PM Colombia', () {
      final dt = parseFechaApi('2026-10-13T04:59:00Z')!;
      expect(horaColombia(dt), '11:59 PM');
      expect(fechaColombia(dt, 'yyyy-MM-dd'), '2026-10-12');
    });

    test('timestamp sin zona se interpreta como UTC (no como hora del celular)', () {
      final dt = parseFechaApi('2026-10-12T21:11:32.715')!;
      expect(dt.isUtc, isTrue);
      expect(horaColombia(dt), '4:11 PM');
    });

    test('medianoche y mediodía', () {
      expect(horaColombia(parseFechaApi('2026-10-12T05:00:00Z')!), '12:00 AM');
      expect(horaColombia(parseFechaApi('2026-10-12T17:00:00Z')!), '12:00 PM');
    });

    test('valores vacíos o inválidos', () {
      expect(parseFechaApi(null), isNull);
      expect(parseFechaApi(''), isNull);
      expect(parseFechaApi('no-es-fecha'), isNull);
    });
  });
}
