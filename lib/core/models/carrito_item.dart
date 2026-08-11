import 'producto.dart';
import 'topping.dart';
import 'adicion.dart';

class CarritoItem {
  final String lineaId;
  final Producto producto;
  final List<Topping> toppings;
  final List<Adicion> adiciones;
  final List<Map<String, dynamic>> salsas;
  final String? tipoChocolate;
  final double cargoExtra;
  int cantidad;

  CarritoItem({
    required this.lineaId,
    required this.producto,
    required this.toppings,
    required this.adiciones,
    this.salsas = const [],
    this.tipoChocolate,
    this.cargoExtra = 0,
    this.cantidad = 1,
  });

  double get precioUnitario {
    final precioAdiciones = adiciones.fold(0.0, (s, a) => s + a.precio);
    return producto.precio + precioAdiciones + cargoExtra;
  }

  double get subtotal => precioUnitario * cantidad;

  static String generarLineaId({
    required int productoId,
    required List<int> toppingIds,
    required List<int> adicionIds,
    List<String> salsaIds = const [],
    String? tipoChocolate,
  }) {
    final t = (List<int>.from(toppingIds)..sort()).join(',');
    final a = (List<int>.from(adicionIds)..sort()).join(',');
    final s = (List<String>.from(salsaIds)..sort()).join(',');
    return 'p${productoId}_t${t}_a${a}_s${s}_c${tipoChocolate ?? ''}';
  }
}
