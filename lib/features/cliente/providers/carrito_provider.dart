import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/models/carrito_item.dart';
import '../../../core/models/producto.dart';
import '../../../core/models/topping.dart';
import '../../../core/models/adicion.dart';
import '../../../core/services/api_service.dart';
import '../../../core/utils/formato.dart';
import '../../../core/utils/salsas.dart';

/// Carrito guardado en el servidor (GET/PUT /api/carrito) y su revalidación
/// (POST /api/carrito/validar). Es una interfaz para poder reemplazarla en
/// los tests sin red.
abstract class CarritoRemoto {
  Future<List<Map<String, dynamic>>> obtener();
  Future<void> guardar(List<Map<String, dynamic>> items);
  Future<List<Map<String, dynamic>>> validar(List<Map<String, dynamic>> items);
}

class CarritoRemotoApi implements CarritoRemoto {
  static List<Map<String, dynamic>> _lista(dynamic data, String clave) {
    final inner = data is Map && data['data'] is Map ? data['data'] as Map : data;
    final lista = inner is Map ? inner[clave] : null;
    return lista is List ? lista.map((e) => Map<String, dynamic>.from(e as Map)).toList() : [];
  }

  @override
  Future<List<Map<String, dynamic>>> obtener() async =>
      _lista(await ApiService.get('/api/carrito'), 'items');

  @override
  Future<void> guardar(List<Map<String, dynamic>> items) =>
      ApiService.put('/api/carrito', {'items': items});

  @override
  Future<List<Map<String, dynamic>>> validar(List<Map<String, dynamic>> items) async =>
      _lista(await ApiService.post('/api/carrito/validar', {'items': items}), 'lineas');
}

/// Persiste el carrito en SharedPreferences, igual que React persiste en
/// localStorage (CartContext.jsx) -- una clave por usuario
/// (`carrito_<id_usuario>` o `carrito_anon` para invitados) para que el
/// carrito de un cliente nunca se filtre a otro en el mismo dispositivo.
///
/// Cualquiera puede armar el carrito (con o sin sesión, con la tienda abierta
/// o cerrada). Al iniciar sesión, lo que se armó como invitado se pasa al
/// carrito de la cuenta y se combina con el guardado en el servidor sin
/// duplicar líneas.
class CarritoProvider extends ChangeNotifier {
  CarritoProvider({this.remoto});

  /// null = solo local (tests); en la app es CarritoRemotoApi (main.dart).
  final CarritoRemoto? remoto;

  final List<CarritoItem> _items = [];

  // Clave de SharedPreferences bajo la que está cargado el carrito actual.
  // null hasta que sincronizarUsuario() se llama por primera vez (arranque
  // de la app, vía ChangeNotifierProxyProvider en main.dart).
  String? _claveActual;

  // Hasta combinar con el carrito del servidor no se le sube nada, para no
  // pisar lo que el cliente dejó guardado desde otro dispositivo.
  bool _servidorListo = false;
  bool _sincronizando = false;
  Timer? _debounceServidor;

  List<CarritoItem> get items => List.unmodifiable(_items);
  int get totalItems => _items.fold(0, (s, i) => s + i.cantidad);
  double get total => _items.fold(0.0, (s, i) => s + i.subtotal);
  bool get isEmpty => _items.isEmpty;

  /// true mientras se trae el carrito guardado en el servidor.
  bool get sincronizando => _sincronizando;

  static String _claveParaUsuario(int? userId) =>
      userId != null ? 'carrito_$userId' : 'carrito_anon';

  /// Cambia el carrito activo al del usuario dado (o al de invitado si es
  /// null), cargando lo que haya guardado bajo esa clave. Si ya está
  /// sincronizado con esa misma clave, no hace nada (evita recargas
  /// redundantes en cada notificación de AuthProvider).
  ///
  /// Si se pasa de invitado a una cuenta en esta misma sesión de la app
  /// (inició sesión o se registró), el carrito de invitado se combina con el
  /// de la cuenta y la clave de invitado se vacía. Al arrancar la app ya con
  /// sesión no hay combinación: cada clave carga solo lo suyo.
  Future<void> sincronizarUsuario(int? userId) async {
    final clave = _claveParaUsuario(userId);
    if (_claveActual == clave) return;
    final veniaDeInvitado = _claveActual == 'carrito_anon' && userId != null;
    final invitado = veniaDeInvitado ? List<CarritoItem>.from(_items) : const <CarritoItem>[];
    _claveActual = clave;
    _servidorListo = false;
    _debounceServidor?.cancel();

    final guardado = await _leerLocal(clave);
    if (_claveActual != clave) return; // cambió de usuario mientras leía
    _items
      ..clear()
      ..addAll(guardado);

    if (invitado.isNotEmpty) {
      _combinarEn(_items, invitado);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('carrito_anon');
      await _persistirLocal();
    }
    notifyListeners();

    if (userId != null) await _sincronizarConServidor(clave);
  }

  Future<List<CarritoItem>> _leerLocal(String clave) async {
    final lista = <CarritoItem>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(clave);
      if (raw != null) {
        for (final e in jsonDecode(raw) as List) {
          final item = _itemDesdeJson(e as Map<String, dynamic>);
          if (item != null) lista.add(item);
        }
      }
    } catch (_) {
      // Carrito guardado corrupto o de un formato viejo -- se ignora y se
      // arranca vacío en vez de romper el catálogo.
    }
    return lista;
  }

  /// Agrega a [destino] las líneas de [otras] que no tenga. Si la misma línea
  /// (mismo lineaId) está en ambos, queda una sola con la cantidad mayor.
  static void _combinarEn(List<CarritoItem> destino, List<CarritoItem> otras) {
    for (final o in otras) {
      final idx = destino.indexWhere((d) => d.lineaId == o.lineaId);
      if (idx < 0) {
        destino.add(o);
      } else if (o.cantidad > destino[idx].cantidad) {
        destino[idx].cantidad = o.cantidad;
      }
    }
  }

  /// Trae el carrito guardado en el servidor, lo revalida (para tener
  /// nombres, precios e imágenes actuales), lo combina con el local y guarda
  /// el resultado en ambos lados.
  Future<void> _sincronizarConServidor(String clave) async {
    final r = remoto;
    if (r == null) return;
    _sincronizando = true;
    notifyListeners();
    try {
      final guardados = await r.obtener();
      final delServidor = <CarritoItem>[];
      if (guardados.isNotEmpty) {
        for (final l in await r.validar(guardados)) {
          if (l['disponible'] == true) delServidor.add(_itemDesdeLinea(l));
        }
      }
      if (_claveActual != clave) return;
      _combinarEn(_items, delServidor);
      _servidorListo = true;
      notifyListeners();
      await _persistirLocal();
      await r.guardar(_items.map(aCanonico).toList());
    } catch (_) {
      // Sin red: se sigue con el carrito local; se reintenta en el próximo
      // cambio de sesión.
    } finally {
      if (_claveActual == clave) {
        _sincronizando = false;
        notifyListeners();
      }
    }
  }

  Future<void> _persistirLocal() async {
    final clave = _claveActual;
    if (clave == null) return; // aún no se sincronizó con ningún usuario
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(clave, jsonEncode(_items.map(_itemAJson).toList()));
  }

  Future<void> _persistir() async {
    await _persistirLocal();
    final r = remoto;
    if (r == null || !_servidorListo || _claveActual == 'carrito_anon') return;
    _debounceServidor?.cancel();
    _debounceServidor = Timer(const Duration(milliseconds: 800), () {
      r.guardar(_items.map(aCanonico).toList()).catchError((_) {});
    });
  }

  /// Revalida el carrito contra la API (precios, productos, toppings y
  /// adiciones activos) y lo actualiza. Devuelve los cambios para mostrarle
  /// al cliente (vacío si no cambió nada) o null si la API no respondió.
  Future<List<String>?> validar() async {
    final r = remoto;
    if (r == null || _items.isEmpty) return const [];
    final clave = _claveActual;
    final antes = List<CarritoItem>.from(_items);
    final List<Map<String, dynamic>> lineas;
    try {
      lineas = await r.validar(antes.map(aCanonico).toList());
    } catch (_) {
      return null;
    }
    if (_claveActual != clave || lineas.length != antes.length) return null;

    final cambios = <String>[];
    final nuevos = <CarritoItem>[];
    for (var i = 0; i < lineas.length; i++) {
      final l = lineas[i];
      final previo = antes[i];
      if (l['disponible'] != true) {
        cambios.add('${previo.nombreCompleto} ya no está disponible y se quitó del carrito');
        continue;
      }
      cambios.addAll(((l['cambios'] as List?) ?? const []).map((c) => '${previo.nombreCompleto}: $c'));
      final ahora = _itemDesdeLinea(l, previo: previo);
      if ((ahora.precioUnitario - previo.precioUnitario).abs() >= 1) {
        cambios.add('${ahora.nombreCompleto}: el precio cambió de '
            '${fmtCop.format(previo.precioUnitario)} a ${fmtCop.format(ahora.precioUnitario)}');
      }
      nuevos.add(ahora);
    }
    if (cambios.isEmpty) return cambios;

    _items.clear();
    // Una línea pudo quedar igual a otra (ej. se quitó el topping que las
    // diferenciaba): se juntan sumando cantidades.
    for (final n in nuevos) {
      final idx = _items.indexWhere((x) => x.lineaId == n.lineaId);
      if (idx >= 0) {
        _items[idx].cantidad += n.cantidad;
      } else {
        _items.add(n);
      }
    }
    notifyListeners();
    _persistir();
    return cambios;
  }

  /// Línea en el formato de la API (el mismo de crear el pedido), sin precios.
  static Map<String, dynamic> aCanonico(CarritoItem i) => {
        'id_producto': i.producto.id,
        'cantidad': i.cantidad,
        'toppings': i.toppings.map((t) => {'id_topping': t.id, 'cantidad': 1}).toList(),
        'adiciones': i.adiciones.map((a) => {'id_adicion': a.id, 'cantidad': 1}).toList(),
        'salsas': i.salsas.map((s) => (s['id'] ?? s['nombre']).toString()).toList(),
        'chocolate': i.tipoChocolate,
        'frutas': i.tipoFrutas,
        'observacion': i.observacion,
      };

  /// Arma una línea del carrito a partir de una línea validada por la API.
  /// [previo] conserva lo que la API no devuelve (precio y tipo de cada
  /// topping).
  static CarritoItem _itemDesdeLinea(Map<String, dynamic> l, {CarritoItem? previo}) {
    final producto = Producto.fromJson(Map<String, dynamic>.from(l['producto'] as Map));
    final toppings = <Topping>[];
    for (final t in (l['toppings'] as List? ?? const [])) {
      final id = (t['id_topping'] as num).toInt();
      final local = previo?.toppings.where((x) => x.id == id).firstOrNull;
      final topping = local ?? Topping(id: id, nombre: t['nombre']?.toString() ?? '', precio: 0, img: t['img'] as String?);
      for (var k = 0; k < ((t['cantidad'] as num?)?.toInt() ?? 1); k++) {
        toppings.add(topping);
      }
    }
    final adiciones = <Adicion>[];
    for (final a in (l['adiciones'] as List? ?? const [])) {
      final adicion = Adicion.fromJson(Map<String, dynamic>.from(a as Map));
      for (var k = 0; k < ((a['cantidad'] as num?)?.toInt() ?? 1); k++) {
        adiciones.add(adicion);
      }
    }
    final salsas = (l['salsas'] as List? ?? const []).map((s) => salsaDesdeId(s.toString())).toList();
    final chocolate = l['chocolate'] as String?;
    final frutas = l['frutas'] as String?;
    final observacion = l['observacion'] as String?;
    return CarritoItem(
      lineaId: CarritoItem.generarLineaId(
        productoId: producto.id,
        toppingIds: toppings.map((t) => t.id).toList(),
        adicionIds: adiciones.map((a) => a.id).toList(),
        salsaIds: salsas.map((s) => (s['id'] ?? s['nombre']).toString()).toList(),
        tipoChocolate: chocolate,
        tipoFrutas: frutas,
        observacion: observacion,
      ),
      producto: producto,
      toppings: toppings,
      adiciones: adiciones,
      salsas: salsas,
      tipoChocolate: chocolate,
      tipoFrutas: frutas,
      observacion: observacion,
      cargoExtra: (l['cargo_extra'] as num?)?.toDouble() ?? 0,
      cantidad: (l['cantidad'] as num?)?.toInt() ?? 1,
    );
  }

  @override
  void dispose() {
    _debounceServidor?.cancel();
    super.dispose();
  }

  void agregar({
    required Producto producto,
    required List<Topping> toppings,
    required List<Adicion> adiciones,
    List<Map<String, dynamic>> salsas = const [],
    String? tipoChocolate,
    String? tipoFrutas,
    String? observacion,
    double cargoExtra = 0,
  }) {
    final lineaId = CarritoItem.generarLineaId(
      productoId: producto.id,
      toppingIds: toppings.map((t) => t.id).toList(),
      adicionIds: adiciones.map((a) => a.id).toList(),
      salsaIds: salsas.map((s) => (s['id'] ?? s['nombre'])?.toString() ?? '').toList(),
      tipoChocolate: tipoChocolate,
      tipoFrutas: tipoFrutas,
      observacion: observacion,
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
        tipoFrutas: tipoFrutas,
        observacion: observacion,
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
        'tipoFrutas': i.tipoFrutas,
        'observacion': i.observacion,
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
          'permiteFrutas': i.producto.permiteFrutas,
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
        permiteFrutas: p['permiteFrutas'] as bool? ?? false,
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
        tipoFrutas: json['tipoFrutas'] as String?,
        observacion: json['observacion'] as String?,
        cargoExtra: (json['cargoExtra'] as num?)?.toDouble() ?? 0,
        cantidad: json['cantidad'] as int? ?? 1,
      );
    } catch (_) {
      // Una línea individual corrupta no debe tumbar todo el carrito guardado.
      return null;
    }
  }
}
