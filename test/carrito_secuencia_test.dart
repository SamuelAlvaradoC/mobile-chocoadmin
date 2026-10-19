// Secuencia reportada: sin sesión agrega Fresas -> inicia sesión -> cierra
// sesión -> agrega otro producto -> inicia sesión y pide. La confirmación
// debe mostrar SOLO el último producto. En cada paso se imprime el carrito
// local (SharedPreferences), el del servidor y lo que ve la pantalla
// (CarritoProvider.items: lo que leen el carrito, el checkout, la
// confirmación y el pedido que se envía).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chocoadmin/core/models/producto.dart';
import 'package:chocoadmin/features/cliente/providers/carrito_provider.dart';

final _productos = {
  1: Producto(id: 1, nombre: 'Fresas con crema', precio: 20000, permiteToppings: false),
  46: Producto(id: 46, nombre: 'Chococeviche', precio: 18000, permiteToppings: false),
};

/// Servidor falso: guarda el carrito de la cuenta y valida como la API.
class _Servidor implements CarritoRemoto {
  List<Map<String, dynamic>> items = [];

  @override
  Future<List<Map<String, dynamic>>> obtener() async => items;

  @override
  Future<void> guardar(List<Map<String, dynamic>> nuevos) async => items = nuevos;

  @override
  Future<List<Map<String, dynamic>>> validar(List<Map<String, dynamic>> lineas) async => [
        for (final l in lineas)
          {
            ...l,
            'disponible': true,
            'cambios': <String>[],
            'producto': {
              'id_producto': l['id_producto'],
              'nombre': _productos[l['id_producto']]!.nombre,
              'precio': _productos[l['id_producto']]!.precio,
              'estado': 1,
            },
            'cargo_extra': 0,
            'precio_unitario': _productos[l['id_producto']]!.precio,
          }
      ];

  List<String> get legible =>
      items.map((i) => '${i['cantidad']}x ${_productos[i['id_producto']]!.nombre}').toList();
}

Future<Map<String, List<String>>> _local() async {
  final prefs = await SharedPreferences.getInstance();
  return {
    for (final k in prefs.getKeys().where((k) => k.startsWith('carrito')))
      k: (jsonDecode(prefs.getString(k)!) as List)
          .map((e) => '${e['cantidad']}x ${e['producto']['nombre']}')
          .toList(),
  };
}

List<String> _pantalla(CarritoProvider c) =>
    c.items.map((i) => '${i.cantidad}x ${i.producto.nombre}').toList();

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 900));

Future<void> _estado(String paso, CarritoProvider c, _Servidor s) async {
  await _flush();
  // ignore: avoid_print
  print('[$paso]\n  local    : ${await _local()}\n  servidor : ${s.legible}\n  pantalla : ${_pantalla(c)}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('secuencia reportada: la confirmación muestra SOLO el último producto', () async {
    final s = _Servidor();
    final c = CarritoProvider(remoto: s);
    await c.sincronizarUsuario(null); // arranca sin sesión

    c.agregar(producto: _productos[1]!, toppings: const [], adiciones: const []);
    await _estado('1. sin sesión, agregó Fresas', c, s);

    await c.sincronizarUsuario(7); // inicia sesión
    await _estado('2. inició sesión', c, s);
    expect(s.legible, ['1x Fresas con crema']);

    await c.sincronizarUsuario(null); // cierra sesión
    await _estado('3. cerró sesión', c, s);
    expect(c.items, isEmpty, reason: 'al cerrar sesión el dispositivo queda sin carrito');
    expect((await _local()).values.every((l) => l.isEmpty), isTrue);
    expect(s.legible, ['1x Fresas con crema'], reason: 'sigue guardado en la cuenta');

    c.agregar(producto: _productos[46]!, toppings: const [], adiciones: const []);
    await _estado('4. sin sesión, agregó Chococeviche', c, s);

    await c.sincronizarUsuario(7); // inicia sesión y sigue el pedido
    await _estado('5. inició sesión otra vez', c, s);
    expect(_pantalla(c), ['1x Chococeviche'], reason: 'el carrito armado sin cuenta reemplaza al de la cuenta');
    expect(s.legible, ['1x Chococeviche']);

    // Lo que se envía en el pedido sale de los mismos items que se ven.
    final enviado = c.items.map(CarritoProvider.aCanonico).toList();
    expect(enviado.map((i) => i['id_producto']), [46]);

    await c.vaciarTrasPedido();
    await _estado('6. después del pedido', c, s);
    expect(c.items, isEmpty);
    expect(s.items, isEmpty);
    expect((await _local()).values.every((l) => l.isEmpty), isTrue);
  });

  test('iniciar sesión sin carrito local recupera el de la cuenta', () async {
    final s = _Servidor()
      ..items = [
        {'id_producto': 46, 'cantidad': 3, 'toppings': [], 'adiciones': [], 'salsas': [], 'chocolate': null, 'frutas': null, 'observacion': null},
      ];
    final c = CarritoProvider(remoto: s);
    await c.sincronizarUsuario(null);
    await c.sincronizarUsuario(7);
    await _flush();
    expect(_pantalla(c), ['3x Chococeviche']);
    expect(s.legible, ['3x Chococeviche'], reason: 'recuperar no cambia lo guardado');
  });

  test('cerrar sesión deja el carrito vacío en el dispositivo y no toca el de la cuenta', () async {
    final s = _Servidor();
    final c = CarritoProvider(remoto: s);
    await c.sincronizarUsuario(7);
    c.agregar(producto: _productos[1]!, toppings: const [], adiciones: const []);
    await _flush();
    await c.sincronizarUsuario(null);
    await _flush();
    expect(c.items, isEmpty);
    expect((await _local()).values.every((l) => l.isEmpty), isTrue);
    expect(s.legible, ['1x Fresas con crema']);
  });

  test('al abrir la app ya con sesión se conserva el carrito del dispositivo', () async {
    final s = _Servidor();
    final antes = CarritoProvider(remoto: s);
    await antes.sincronizarUsuario(7);
    antes.agregar(producto: _productos[46]!, toppings: const [], adiciones: const []);
    await _flush();

    final despues = CarritoProvider(remoto: s); // la app se cerró y se abrió
    await despues.sincronizarUsuario(7);
    await _flush();
    expect(_pantalla(despues), ['1x Chococeviche']);
  });
}
