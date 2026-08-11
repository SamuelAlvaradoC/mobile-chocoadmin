import 'package:flutter/material.dart';
import '../../../core/models/carrito_item.dart';
import '../../../core/models/producto.dart';
import '../../../core/models/topping.dart';
import '../../../core/models/adicion.dart';

class CarritoProvider extends ChangeNotifier {
  final List<CarritoItem> _items = [];

  List<CarritoItem> get items => List.unmodifiable(_items);
  int get totalItems => _items.fold(0, (s, i) => s + i.cantidad);
  double get total => _items.fold(0.0, (s, i) => s + i.subtotal);
  bool get isEmpty => _items.isEmpty;

  void agregar({
    required Producto producto,
    required List<Topping> toppings,
    required List<Adicion> adiciones,
    List<Map<String, dynamic>> salsas = const [],
    String? tipoChocolate,
    double cargoExtra = 0,
  }) {
    final lineaId = CarritoItem.generarLineaId(
      productoId: producto.id,
      toppingIds: toppings.map((t) => t.id).toList(),
      adicionIds: adiciones.map((a) => a.id).toList(),
      salsaIds: salsas.map((s) => (s['id'] ?? s['nombre'])?.toString() ?? '').toList(),
      tipoChocolate: tipoChocolate,
    );

    final idx = _items.indexWhere((i) => i.lineaId == lineaId);
    if (idx >= 0) {
      _items[idx].cantidad++;
    } else {
      _items.add(CarritoItem(
        lineaId: lineaId,
        producto: producto,
        toppings: toppings,
        adiciones: adiciones,
        salsas: salsas,
        tipoChocolate: tipoChocolate,
        cargoExtra: cargoExtra,
      ));
    }
    notifyListeners();
  }

  void incrementar(String lineaId) {
    final idx = _items.indexWhere((i) => i.lineaId == lineaId);
    if (idx >= 0) {
      _items[idx].cantidad++;
      notifyListeners();
    }
  }

  void decrementar(String lineaId) {
    final idx = _items.indexWhere((i) => i.lineaId == lineaId);
    if (idx >= 0) {
      if (_items[idx].cantidad > 1) {
        _items[idx].cantidad--;
      } else {
        _items.removeAt(idx);
      }
      notifyListeners();
    }
  }

  void eliminar(String lineaId) {
    _items.removeWhere((i) => i.lineaId == lineaId);
    notifyListeners();
  }

  void limpiar() {
    _items.clear();
    notifyListeners();
  }
}
