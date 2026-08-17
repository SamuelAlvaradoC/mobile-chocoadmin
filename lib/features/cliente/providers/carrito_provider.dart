import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/models/carrito_item.dart';
import '../../../core/models/producto.dart';
import '../../../core/models/topping.dart';
import '../../../core/models/adicion.dart';

/// Persiste el carrito en SharedPreferences, igual que React persiste en
/// localStorage (CartContext.jsx) -- una clave por usuario
/// (`carrito_<id_usuario>` o `carrito_anon` para invitados) para que el
/// carrito de un cliente nunca se filtre a otro en el mismo dispositivo.
class CarritoProvider extends ChangeNotifier {
  final List<CarritoItem> _items = [];

  // Clave de SharedPreferences bajo la que está cargado el carrito actual.
  // null hasta que sincronizarUsuario() se llama por primera vez (arranque
  // de la app, vía ChangeNotifierProxyProvider en main.dart).
  String? _claveActual;

  List<CarritoItem> get items => List.unmodifiable(_items);
  int get totalItems => _items.fold(0, (s, i) => s + i.cantidad);
  double get total => _items.fold(0.0, (s, i) => s + i.subtotal);
  bool get isEmpty => _items.isEmpty;

  static String _claveParaUsuario(int? userId) =>
      userId != null ? 'carrito_$userId' : 'carrito_anon';

  /// Cambia el carrito activo al del usuario dado (o al de invitado si es
  /// null), cargando lo que haya guardado bajo esa clave. Si ya está
  /// sincronizado con esa misma clave, no hace nada (evita recargas
  /// redundantes en cada notificación de AuthProvider).
  Future<void> sincronizarUsuario(int? userId) async {
    final clave = _claveParaUsuario(userId);
    if (_claveActual == clave) return;
    _claveActual = clave;

    _items.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(clave);
      if (raw != null) {
        final lista = jsonDecode(raw) as List;
        for (final e in lista) {
          final item = _itemDesdeJson(e as Map<String, dynamic>);
          if (item != null) _items.add(item);
        }
      }
    } catch (_) {
      // Carrito guardado corrupto o de un formato viejo -- se ignora y se
      // arranca vacío en vez de romper el catálogo.
    }
    notifyListeners();
  }

  Future<void> _persistir() async {
    final clave = _claveActual;
    if (clave == null) return; // aún no se sincronizó con ningún usuario
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(clave, jsonEncode(_items.map(_itemAJson).toList()));
  }

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
    _persistir();
  }

  void incrementar(String lineaId) {
    final idx = _items.indexWhere((i) => i.lineaId == lineaId);
    if (idx >= 0) {
      _items[idx].cantidad++;
      notifyListeners();
      _persistir();
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
      _persistir();
    }
  }

  void eliminar(String lineaId) {
    _items.removeWhere((i) => i.lineaId == lineaId);
    notifyListeners();
    _persistir();
  }

  void limpiar() {
    _items.clear();
    notifyListeners();
    _persistir();
  }

  // ─── Serialización para SharedPreferences ──────────────────────────────
  // Formato propio (no ligado a los campos que devuelve la API), solo para
  // ida y vuelta local del carrito guardado.

  Map<String, dynamic> _itemAJson(CarritoItem i) => {
        'lineaId': i.lineaId,
        'cantidad': i.cantidad,
        'cargoExtra': i.cargoExtra,
        'tipoChocolate': i.tipoChocolate,
        'salsas': i.salsas,
        'producto': {
          'id': i.producto.id,
          'nombre': i.producto.nombre,
          'descripcion': i.producto.descripcion,
          'precio': i.producto.precio,
          'permiteToppings': i.producto.permiteToppings,
          'maxToppings': i.producto.maxToppings,
          'permiteSalsas': i.producto.permiteSalsas,
          'permiteChocolate': i.producto.permiteChocolate,
          'esBowl': i.producto.esBowl,
          'idCategoria': i.producto.idCategoria,
          'imagen': i.producto.imagen,
          'estado': i.producto.estado,
        },
        'toppings': i.toppings
            .map((t) => {'id': t.id, 'nombre': t.nombre, 'precio': t.precio, 'tipo': t.tipo, 'img': t.img})
            .toList(),
        'adiciones': i.adiciones
            .map((a) => {'id': a.id, 'nombre': a.nombre, 'precio': a.precio, 'img': a.img})
            .toList(),
      };

  CarritoItem? _itemDesdeJson(Map<String, dynamic> json) {
    try {
      final p = json['producto'] as Map<String, dynamic>;
      final producto = Producto(
        id: p['id'] as int,
        nombre: p['nombre'] as String,
        descripcion: p['descripcion'] as String?,
        precio: (p['precio'] as num).toDouble(),
        permiteToppings: p['permiteToppings'] as bool,
        maxToppings: p['maxToppings'] as int,
        permiteSalsas: p['permiteSalsas'] as bool,
        permiteChocolate: p['permiteChocolate'] as bool,
        esBowl: p['esBowl'] as bool,
        idCategoria: p['idCategoria'] as int?,
        imagen: p['imagen'] as String?,
        estado: p['estado'] as int,
      );
      final toppings = (json['toppings'] as List)
          .map((t) => Topping(
                id: t['id'] as int,
                nombre: t['nombre'] as String,
                precio: (t['precio'] as num).toDouble(),
                tipo: t['tipo'] as String? ?? 'topping',
                img: t['img'] as String?,
              ))
          .toList();
      final adiciones = (json['adiciones'] as List)
          .map((a) => Adicion(
                id: a['id'] as int,
                nombre: a['nombre'] as String,
                precio: (a['precio'] as num).toDouble(),
                img: a['img'] as String?,
              ))
          .toList();
      final salsas = (json['salsas'] as List? ?? const [])
          .map((s) => Map<String, dynamic>.from(s as Map))
          .toList();
      return CarritoItem(
        lineaId: json['lineaId'] as String,
        producto: producto,
        toppings: toppings,
        adiciones: adiciones,
        salsas: salsas,
        tipoChocolate: json['tipoChocolate'] as String?,
        cargoExtra: (json['cargoExtra'] as num?)?.toDouble() ?? 0,
        cantidad: json['cantidad'] as int? ?? 1,
      );
    } catch (_) {
      // Una línea individual corrupta no debe tumbar todo el carrito guardado.
      return null;
    }
  }
}
