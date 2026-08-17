// Verifica el hallazgo "persistencia del carrito" de la auditoría: que el
// carrito sobreviva a que Android mate el proceso (simulado acá creando una
// instancia NUEVA de CarritoProvider, sin compartir memoria con la
// anterior, y confirmando que se rehidrata desde SharedPreferences) y que
// el carrito de un usuario nunca se cargue bajo la sesión de otro.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chocoadmin/features/cliente/providers/carrito_provider.dart';
import 'package:chocoadmin/core/models/producto.dart';

Producto _producto({int id = 1, String nombre = 'Fresas con crema'}) => Producto(
      id: id,
      nombre: nombre,
      precio: 12000,
      permiteToppings: true,
    );

// _persistir() dentro de CarritoProvider es fire-and-forget (no se espera
// desde agregar/incrementar/etc, a propósito, para no bloquear la UI) --
// en el test hay que darle una vuelta al event loop para que el
// SharedPreferences.setString() en curso termine antes de leer.
Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('el carrito sobrevive a "matar" el proceso: se rehidrata en una instancia nueva', () async {
    final carritoAntes = CarritoProvider();
    await carritoAntes.sincronizarUsuario(7);
    carritoAntes.agregar(producto: _producto(), toppings: const [], adiciones: const []);
    expect(carritoAntes.items.length, 1);
    await _flush();

    // Nueva instancia -- ninguna memoria compartida con carritoAntes, como
    // si Android hubiera matado el proceso y la app arrancara de cero.
    final carritoDespues = CarritoProvider();
    expect(carritoDespues.items, isEmpty); // arranca vacío antes de sincronizar
    await carritoDespues.sincronizarUsuario(7);

    expect(carritoDespues.items.length, 1);
    expect(carritoDespues.items.first.producto.nombre, 'Fresas con crema');
    expect(carritoDespues.items.first.producto.id, 1);
  });

  test('incrementar/decrementar/eliminar se reflejan en lo guardado', () async {
    final carrito = CarritoProvider();
    await carrito.sincronizarUsuario(1);
    carrito.agregar(producto: _producto(id: 1), toppings: const [], adiciones: const []);
    final lineaId = carrito.items.first.lineaId;
    carrito.incrementar(lineaId);
    carrito.incrementar(lineaId);
    await _flush();

    final rehidratado = CarritoProvider();
    await rehidratado.sincronizarUsuario(1);
    expect(rehidratado.items.first.cantidad, 3);

    rehidratado.decrementar(rehidratado.items.first.lineaId);
    await _flush();
    final rehidratado2 = CarritoProvider();
    await rehidratado2.sincronizarUsuario(1);
    expect(rehidratado2.items.first.cantidad, 2);

    rehidratado2.eliminar(rehidratado2.items.first.lineaId);
    await _flush();
    final rehidratado3 = CarritoProvider();
    await rehidratado3.sincronizarUsuario(1);
    expect(rehidratado3.items, isEmpty);
  });

  test('limpiar() (post-compra) deja el carrito guardado vacío, no solo el de memoria', () async {
    final carrito = CarritoProvider();
    await carrito.sincronizarUsuario(3);
    carrito.agregar(producto: _producto(), toppings: const [], adiciones: const []);
    await _flush();
    carrito.limpiar();
    await _flush();

    final rehidratado = CarritoProvider();
    await rehidratado.sincronizarUsuario(3);
    expect(rehidratado.items, isEmpty);
  });

  test('el carrito de un usuario NO se carga bajo la sesión de otro usuario', () async {
    final carritoA = CarritoProvider();
    await carritoA.sincronizarUsuario(1);
    carritoA.agregar(producto: _producto(nombre: 'Producto de usuario 1'), toppings: const [], adiciones: const []);
    await _flush();

    final carritoB = CarritoProvider();
    await carritoB.sincronizarUsuario(2); // usuario DISTINTO
    expect(carritoB.items, isEmpty,
        reason: 'el carrito del usuario 1 no debe filtrarse a la sesión del usuario 2');
  });

  test('el carrito de invitado (sin sesión) no se filtra a un usuario que luego inicia sesión, ni viceversa', () async {
    final carritoInvitado = CarritoProvider();
    await carritoInvitado.sincronizarUsuario(null); // invitado, catálogo público
    carritoInvitado.agregar(producto: _producto(nombre: 'Agregado como invitado'), toppings: const [], adiciones: const []);
    await _flush();

    // El mismo dispositivo, pero ahora con un usuario logueado -- no debe
    // ver lo que agregó el invitado.
    final carritoLogueado = CarritoProvider();
    await carritoLogueado.sincronizarUsuario(9);
    expect(carritoLogueado.items, isEmpty);

    // Y si vuelve a cerrar sesión, el carrito de invitado original sigue
    // intacto bajo su propia clave.
    final carritoInvitadoDeNuevo = CarritoProvider();
    await carritoInvitadoDeNuevo.sincronizarUsuario(null);
    expect(carritoInvitadoDeNuevo.items.length, 1);
    expect(carritoInvitadoDeNuevo.items.first.producto.nombre, 'Agregado como invitado');
  });

  test('sincronizarUsuario con el mismo usuario no recarga (evita perder cambios en memoria sin guardar aún)', () async {
    final carrito = CarritoProvider();
    await carrito.sincronizarUsuario(4);
    carrito.agregar(producto: _producto(), toppings: const [], adiciones: const []);
    // Llamar de nuevo con el MISMO userId (ej. AuthProvider notifica por
    // otro motivo, no un cambio real de sesión) no debe vaciar el carrito
    // en memoria releyendo el guardado (que en este instante aún podría no
    // reflejar el último agregar()).
    await carrito.sincronizarUsuario(4);
    expect(carrito.items.length, 1);
  });
}
