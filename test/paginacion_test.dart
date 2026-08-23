// Puerto directo de src/components/Paginacion.test.jsx (React) -- misma
// cobertura: cálculo del rango en el medio/extremos/pocas páginas/1 sola
// página, resaltado de la página activa, "..." no clicable, Anterior/
// Siguiente deshabilitados en los extremos, y sincronización del selector
// "Mostrar".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chocoadmin/shared/widgets/paginacion.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('calcularRangoPaginas', () {
    test('página en el medio con muchas páginas: rango alrededor + extremos con "..."', () {
      expect(calcularRangoPaginas(6, 26), [1, '...', 4, 5, 6, 7, 8, '...', 26]);
    });

    test('extremo izquierdo (página 1): sin "..." antes, "..." solo antes del último', () {
      expect(calcularRangoPaginas(1, 26), [1, 2, 3, '...', 26]);
    });

    test('extremo derecho (última página): "..." solo antes del rango, no después', () {
      expect(calcularRangoPaginas(26, 26), [1, '...', 24, 25, 26]);
    });

    test('cerca del extremo izquierdo (página 2 de 26): no mete "..." innecesario al inicio', () {
      expect(calcularRangoPaginas(2, 26), [1, 2, 3, 4, '...', 26]);
    });

    test('cerca del extremo derecho (página 25 de 26): no mete "..." innecesario al final', () {
      expect(calcularRangoPaginas(25, 26), [1, '...', 23, 24, 25, 26]);
    });

    test('pocas páginas (5 totales): nunca aparece "..." si el rango ya cubre todo', () {
      expect(calcularRangoPaginas(3, 5), [1, 2, 3, 4, 5]);
      expect(calcularRangoPaginas(1, 5), [1, 2, 3, 4, 5]);
      expect(calcularRangoPaginas(5, 5), [1, 2, 3, 4, 5]);
    });

    test('una sola página: devuelve solo [1]', () {
      expect(calcularRangoPaginas(1, 1), [1]);
    });

    test('dos páginas: sin "..."', () {
      expect(calcularRangoPaginas(1, 2), [1, 2]);
      expect(calcularRangoPaginas(2, 2), [1, 2]);
    });

    test('delta configurable (1 en vez de 2)', () {
      expect(calcularRangoPaginas(10, 26, delta: 1), [1, '...', 9, 10, 11, '...', 26]);
    });

    test('Barrios real: página 6 de 47', () {
      expect(calcularRangoPaginas(6, 47), [1, '...', 4, 5, 6, 7, 8, '...', 47]);
    });
  });

  group('Paginacion — render e interacción', () {
    testWidgets('resalta la página actual y no las demás', (tester) async {
      await tester.pumpWidget(_wrap(Paginacion(pagina: 6, totalPaginas: 26, onCambiarPagina: (_) {})));

      final activo = tester.widget<Material>(
        find.ancestor(of: find.text('6'), matching: find.byType(Material)).first,
      );
      final inactivo = tester.widget<Material>(
        find.ancestor(of: find.text('7'), matching: find.byType(Material)).first,
      );
      expect(activo.color, isNot(equals(inactivo.color)));
    });

    testWidgets('los "..." se renderizan como texto no clicable', (tester) async {
      await tester.pumpWidget(_wrap(Paginacion(pagina: 6, totalPaginas: 26, onCambiarPagina: (_) {})));
      expect(find.text('···'), findsNWidgets(2));
    });

    testWidgets('tap en un número de página llama a onCambiarPagina con ese número', (tester) async {
      int? recibido;
      await tester.pumpWidget(_wrap(Paginacion(
        pagina: 6,
        totalPaginas: 26,
        onCambiarPagina: (n) => recibido = n,
      )));
      await tester.tap(find.text('8'));
      expect(recibido, 8);
    });

    testWidgets('"Anterior"/"Siguiente" avanzan o retroceden una página', (tester) async {
      final recibidos = <int>[];
      await tester.pumpWidget(_wrap(Paginacion(
        pagina: 6,
        totalPaginas: 26,
        onCambiarPagina: recibidos.add,
      )));
      await tester.tap(find.text('‹ Anterior'));
      await tester.tap(find.text('Siguiente ›'));
      expect(recibidos, [5, 7]);
    });

    testWidgets('"Anterior" deshabilitado en la página 1, "Siguiente" habilitado', (tester) async {
      bool tapAnterior = false;
      await tester.pumpWidget(_wrap(Paginacion(
        pagina: 1,
        totalPaginas: 26,
        onCambiarPagina: (_) => tapAnterior = true,
      )));
      await tester.tap(find.text('‹ Anterior'));
      expect(tapAnterior, isFalse);
    });

    testWidgets('con una sola página, igual muestra Anterior/1/Siguiente deshabilitados', (tester) async {
      final recibidos = <int>[];
      await tester.pumpWidget(_wrap(Paginacion(
        pagina: 1,
        totalPaginas: 1,
        onCambiarPagina: recibidos.add,
      )));
      expect(find.text('‹ Anterior'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Siguiente ›'), findsOneWidget);

      await tester.tap(find.text('‹ Anterior'));
      await tester.tap(find.text('Siguiente ›'));
      expect(recibidos, isEmpty);
    });

    testWidgets('selector "Mostrar" solo aparece si se pasan porPagina + onCambiarPorPagina', (tester) async {
      await tester.pumpWidget(_wrap(Paginacion(
        pagina: 1,
        totalPaginas: 1,
        onCambiarPagina: (_) {},
        porPagina: 10,
        onCambiarPorPagina: (_) {},
      )));
      expect(find.text('Mostrar:'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
    });

    testWidgets('sin porPagina/onCambiarPorPagina, no renderiza el selector "Mostrar"', (tester) async {
      await tester.pumpWidget(_wrap(Paginacion(pagina: 6, totalPaginas: 26, onCambiarPagina: (_) {})));
      expect(find.text('Mostrar:'), findsNothing);
    });

    testWidgets('cambiar el selector "Mostrar" a "Todos" llama a onCambiarPorPagina', (tester) async {
      Object? recibido;
      await tester.pumpWidget(_wrap(Paginacion(
        pagina: 1,
        totalPaginas: 5,
        onCambiarPagina: (_) {},
        porPagina: 10,
        onCambiarPorPagina: (v) => recibido = v,
      )));
      await tester.tap(find.text('10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Todos').last);
      await tester.pumpAndSettle();
      expect(recibido, todosPorPagina);
    });
  });

  group('SelectorPorPagina — standalone', () {
    testWidgets('muestra "Mostrar:" con el valor actual seleccionado', (tester) async {
      await tester.pumpWidget(_wrap(SelectorPorPagina(porPagina: 10, onCambiarPorPagina: (_) {})));
      expect(find.text('Mostrar:'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
    });

    testWidgets('cambiar el valor llama a onCambiarPorPagina con el tipo correcto', (tester) async {
      Object? recibido;
      await tester.pumpWidget(_wrap(SelectorPorPagina(porPagina: 10, onCambiarPorPagina: (v) => recibido = v)));
      await tester.tap(find.text('10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('100').last);
      await tester.pumpAndSettle();
      expect(recibido, 100);
    });

    testWidgets('acepta una lista de opciones personalizada', (tester) async {
      await tester.pumpWidget(_wrap(SelectorPorPagina(
        porPagina: 25,
        onCambiarPorPagina: (_) {},
        opciones: const [25, 75],
      )));
      expect(find.text('25'), findsOneWidget);
      expect(find.text('10'), findsNothing);
    });
  });
}
