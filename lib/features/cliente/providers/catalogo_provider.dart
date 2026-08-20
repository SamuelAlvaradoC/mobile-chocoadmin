import 'package:flutter/material.dart';
import '../../../core/models/categoria.dart';
import '../../../core/models/producto.dart';
import '../../../core/models/topping.dart';
import '../../../core/models/adicion.dart';
import '../../../core/services/api_service.dart';

class CatalogoProvider extends ChangeNotifier {
  List<Categoria> _categorias = [];
  List<Producto> _productos = [];
  List<Topping> _toppings = [];
  List<Adicion> _adiciones = [];
  List<Producto> _masPedidos = [];

  int? _categoriaSeleccionada; // null = todas
  bool _loading = false;
  String? _error;

  List<Categoria> get categorias => _categorias;
  List<Producto> get productos => _productos;
  List<Topping> get toppings => _toppings;
  List<Adicion> get adiciones => _adiciones;
  List<Producto> get masPedidos => _masPedidos;
  int? get categoriaSeleccionada => _categoriaSeleccionada;
  bool get loading => _loading;
  String? get error => _error;

  List<Producto> get productosFiltrados {
    final activos = _productos.where((p) => p.estado != 0).toList();
    if (_categoriaSeleccionada == null) {
      // Igual que React: en "Todos" se ordena por id_categoria.
      activos.sort((a, b) => (a.idCategoria ?? 0).compareTo(b.idCategoria ?? 0));
      return activos;
    }
    return activos
        .where((p) => p.idCategoria == _categoriaSeleccionada)
        .toList();
  }

  Future<void> cargarTodo() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        ApiService.get('/api/catalogo/categorias', auth: false),
        ApiService.get('/api/catalogo/productos', auth: false),
        ApiService.get('/api/catalogo/toppings', auth: false),
        ApiService.get('/api/catalogo/adiciones', auth: false),
      ]);

      _categorias = _parseList(results[0], Categoria.fromJson);
      _productos = _parseList(results[1], Producto.fromJson);
      _toppings = _parseList(results[2], Topping.fromJson);
      _adiciones = _parseList(results[3], Adicion.fromJson);
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'No se pudo conectar con el servidor. Verifica tu conexión.';
    }

    _loading = false;
    notifyListeners();

    // Independiente del resto: si falla, el catálogo normal sigue funcionando.
    _cargarMasPedidos();
  }

  Future<void> _cargarMasPedidos() async {
    try {
      final res = await ApiService.get('/api/catalogo/mas-pedidos', auth: false);
      _masPedidos = _parseList(res, Producto.fromJson);
      notifyListeners();
    } catch (_) {
      // Silencioso: la sección simplemente no aparece.
    }
  }

  void seleccionarCategoria(int? id) {
    _categoriaSeleccionada = id;
    notifyListeners();
  }

  List<T> _parseList<T>(dynamic raw, T Function(Map<String, dynamic>) fromJson) {
    if (raw is List) return raw.map((e) => fromJson(e as Map<String, dynamic>)).toList();
    if (raw is Map && raw['data'] is List) {
      return (raw['data'] as List).map((e) => fromJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }
}
