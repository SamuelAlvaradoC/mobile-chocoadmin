// Nuevo flujo de compra: cualquiera arma el carrito; al iniciar sesión el
// armado sin cuenta reemplaza al guardado en la cuenta; antes de pedir se
// revalidan precios y disponibilidad.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chocoadmin/core/models/producto.dart';
import 'package:chocoadmin/core/models/topping.dart';
import 'package:chocoadmin/features/cliente/providers/carrito_provider.dart';

Producto _producto({int id = 1, String nombre = 'Fresas con crema', double precio = 20000}) => Producto(
      id: id,
      nombre: nombre,
      precio: precio,
      permiteToppings: true,
      maxToppings: 2,
      permiteSalsas: true,
    );

const _oreo = Topping(id: 10, nombre: 'Oreo', precio: 0);

/// Línea como la devuelve POST /api/carrito/validar.
Map<String, dynamic> _linea({
  int id = 1,
  String nombre = 'Fresas con crema',
  double precio = 20000,
  int cantidad = 1,
  List<Map<String, dynamic>> toppings = const [{'id_topping': 10, 'nombre': 'Oreo', 'cantidad': 1}],
  List<String> salsas = const ['arequipe'],
  List<String> cambios = const [],
}) =>
    {
      'id_producto': id,
      'cantidad': cantidad,
      'disponible': true,
      'cambios': cambios,
      'toppings': toppings,
      'adiciones': <Map<String, dynamic>>[],
      'salsas': salsas,
      'chocolate': null,
      'frutas': null,
      'observacion': null,
      'producto': {
        'id_producto': id, 'nombre': nombre, 'precio': precio, 'permite_toppings': 1,
        'max_toppings': 2, 'permite_salsas': true, 'estado': 1,
      },
      'cargo_extra': 0,
      'precio_unitario': precio,
    };

class _RemotoFalso implements CarritoRemoto {
  List<Map<String, dynamic>> enServidor = [];
  List<Map<String, dynamic>> Function(List<Map<String, dynamic>>)? respuestaValidar;
  final guardados = <List<Map<String, dynamic>>>[];

  @override
  Future<List<Map<String, dynamic>>> obtener() async => enServidor;

  @override
  Future<void> guardar(List<Map<String, dynamic>> items) async => guardados.add(items);

  @override
  Future<List<Map<String, dynamic>>> validar(List<Map<String, dynamic>> items) async =>
      respuestaValidar!(items);
}

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 20));

void _agregarFresas(CarritoProvider c) => c.agregar(
      producto: _producto(),
      toppings: const [_oreo],
      adiciones: const [],
      salsas: const [{'id': 'arequipe', 'nombre': 'Arequipe'}],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('sin sesión se puede agregar y queda guardado como invitado', () async {
    final remoto = _RemotoFalso();
    final c = CarritoProvider(remoto: remoto);
    await c.sincronizarUsuario(null);
    _agregarFresas(c);
    await _flush();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('carrito_anon'), isNotNull);
    expect(remoto.guardados, isEmpty); // sin sesión no se sube nada
  });

  test('al iniciar sesión con carrito armado sin cuenta, ESE reemplaza al de la cuenta (no se combinan)', () async {
    final remoto = _RemotoFalso()
      ..enServidor = [{'id_producto': 2}]
      ..respuestaValidar = (_) => [_linea(id: 2, nombre: 'Bowl', toppings: const [], salsas: const [])];
    final c = CarritoProvider(remoto: remoto);
    await c.sincronizarUsuario(null);
    _agregarFresas(c);
    _agregarFresas(c); // 2 unidades como invitado
    await _flush();

    await c.sincronizarUsuario(7); // inició sesión

    expect(c.items.map((i) => i.producto.nombre), ['Fresas con crema']);
    expect(c.items.single.cantidad, 2);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('carrito_anon'), isNull);
    expect(prefs.getString('carrito_7'), isNotNull);
    expect(remoto.guardados.last, hasLength(1));
    expect(remoto.guardados.last.single['id_producto'], 1);
    expect(remoto.guardados.last.single['salsas'], ['arequipe']);
  });

  test('validar(): quita lo agotado, avisa el cambio de precio y actualiza el carrito', () async {
    final remoto = _RemotoFalso()
      ..respuestaValidar = (items) => items.length == 2
          ? [
              _linea(precio: 22000),
              {'id_producto': 2, 'cantidad': 1, 'disponible': false, 'cambios': ['Bowl ya no está disponible']},
            ]
          : [];
    final c = CarritoProvider(remoto: remoto);
    await c.sincronizarUsuario(null);
    _agregarFresas(c);
    c.agregar(producto: _producto(id: 2, nombre: 'Bowl', precio: 15000), toppings: const [], adiciones: const []);

    final cambios = await c.validar();

    expect(cambios, [
      r'Fresas con crema: el precio cambió de $20.000 a $22.000',
      'Bowl ya no está disponible y se quitó del carrito',
    ]);
    expect(c.items, hasLength(1));
    expect(c.items.first.subtotal, 22000);
    expect(c.items.first.salsas.first['nombre'], 'Arequipe');
  });

  test('validar(): si la API no responde, no toca el carrito', () async {
    final remoto = _RemotoFalso()..respuestaValidar = (_) => throw Exception('sin red');
    final c = CarritoProvider(remoto: remoto);
    await c.sincronizarUsuario(null);
    _agregarFresas(c);
    expect(await c.validar(), isNull);
    expect(c.items, hasLength(1));
  });
}
