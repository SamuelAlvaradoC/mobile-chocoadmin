import 'producto.dart';
import 'topping.dart';
import 'adicion.dart';
import '../utils/nombre_producto.dart';

class CarritoItem {
  final String lineaId;
  final Producto producto;
  final List<Topping> toppings;
  final List<Adicion> adiciones;
  final List<Map<String, dynamic>> salsas;
  final String? tipoChocolate;
  final String? tipoFrutas;
  final String? observacion;
  final double cargoExtra;
  int cantidad;

  CarritoItem({
    required this.lineaId,
    required this.producto,
    required this.toppings,
    required this.adiciones,
    this.salsas = const [],
    this.tipoChocolate,
    this.tipoFrutas,
    this.observacion,
    this.cargoExtra = 0,
    this.cantidad = 1,
  });

  String get nombreCompleto => nombreConFrutas(producto.nombre, tipoFrutas);

  double get precioUnitario {
    final precioAdiciones = adiciones.fold(0.0, (s, a) => s + a.precio);
    return producto.precio + precioAdiciones + cargoExtra;
  }

  double get subtotal => precioUnitario * cantidad;

  // observacion entra en la clave para que dos unidades del mismo producto
  // con notas de preparación distintas queden en líneas separadas del
  // carrito en vez de fusionarse en una sola cantidad (mismo criterio que
  // choc/frutas ya usan acá).
  static String generarLineaId({
    required int productoId,
    required List<int> toppingIds,
    required List<int> adicionIds,
    List<String> salsaIds = const [],
    String? tipoChocolate,
    String? tipoFrutas,
    String? observacion,
  }) {
    final t = (List<int>.from(toppingIds)..sort()).join(',');
    final a = (List<int>.from(adicionIds)..sort()).join(',');
    final s = (List<String>.from(salsaIds)..sort()).join(',');
    return 'p${productoId}_t${t}_a${a}_s${s}_c${tipoChocolate ?? ''}_f${tipoFrutas ?? ''}_o${observacion ?? ''}';
  }
}
