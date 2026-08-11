import 'package:flutter/material.dart';
import '../../../core/models/pedido.dart';
import '../../../core/services/api_service.dart';

class DomiciliarioProvider extends ChangeNotifier {
  List<Pedido> _porDespachar = [];
  List<Pedido> _despachados = []; // orden: último cogido primero
  bool _loadingPorDespachar = false;
  bool _loadingDespachados = false;
  int? _procesandoId; // ID del pedido con operación en curso
  String? _error;

  List<Pedido> get porDespachar => _porDespachar;

  /// Último cogido aparece primero
  List<Pedido> get despachados => _despachados.reversed.toList();

  bool get loadingPorDespachar => _loadingPorDespachar;
  bool get loadingDespachados => _loadingDespachados;
  int? get procesandoId => _procesandoId;
  String? get error => _error;

  // ── Carga inicial ────────────────────────────────────────────────────────────

  Future<void> cargar() async {
    await Future.wait([cargarPorDespachar(), cargarDespachados()]);
  }

  Future<void> cargarPorDespachar() async {
    _loadingPorDespachar = true;
    notifyListeners();
    try {
      final data = await ApiService.get('/api/domicilios');
      _porDespachar = _parseList(data);
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Error al cargar pedidos';
    }
    _loadingPorDespachar = false;
    notifyListeners();
  }

  Future<void> cargarDespachados() async {
    _loadingDespachados = true;
    notifyListeners();
    try {
      final data = await ApiService.get(
        '/api/domicilios/filtrar',
        queryParams: {'estado': 'despachado'},
      );
      _despachados = _parseList(data);
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Error al cargar despachados';
    }
    _loadingDespachados = false;
    notifyListeners();
  }

  // ── Coger pedido ─────────────────────────────────────────────────────────────

  Future<bool> cogerPedido(int id) async {
    _procesandoId = id;
    notifyListeners();

    try {
      await ApiService.patch('/api/domicilios/$id/estado', {'estado': 'despachado'});

      final pedido = _porDespachar.firstWhere((p) => p.id == id);
      _porDespachar.removeWhere((p) => p.id == id);

      // Lo agregamos al final de _despachados (reversed → aparecerá primero)
      _despachados.add(Pedido.fromJson({
        'id': pedido.id,
        'estado': 'despachado',
        'total': pedido.total,
        'costo_domicilio': pedido.costoDomicilio,
        'cliente_nombre': pedido.clienteNombre,
        'cliente_telefono': pedido.clienteTelefono,
        'direccion': pedido.direccion,
        'ciudad': pedido.ciudad,
        'barrio': pedido.barrio,
        'latitud': pedido.latitud,
        'longitud': pedido.longitud,
        'metodo_pago': pedido.metodoPago,
        'creado_en': pedido.creadoEn?.toIso8601String(),
        'lineas': pedido.lineas.map(_lineaToJson).toList(),
      }));

      _procesandoId = null;
      notifyListeners();
      return true;
    } catch (e) {
      _procesandoId = null;
      notifyListeners();
      return false;
    }
  }

  // ── Devolver pedido ──────────────────────────────────────────────────────────

  Future<bool> devolverPedido(int id) async {
    _procesandoId = id;
    notifyListeners();

    try {
      await ApiService.patch('/api/domicilios/$id/estado', {'estado': 'listo'});

      final pedido = _despachados.firstWhere((p) => p.id == id);
      _despachados.removeWhere((p) => p.id == id);
      _porDespachar.insert(0, Pedido.fromJson({
        'id': pedido.id,
        'estado': 'listo',
        'total': pedido.total,
        'costo_domicilio': pedido.costoDomicilio,
        'cliente_nombre': pedido.clienteNombre,
        'cliente_telefono': pedido.clienteTelefono,
        'direccion': pedido.direccion,
        'ciudad': pedido.ciudad,
        'barrio': pedido.barrio,
        'latitud': pedido.latitud,
        'longitud': pedido.longitud,
        'metodo_pago': pedido.metodoPago,
        'creado_en': pedido.creadoEn?.toIso8601String(),
        'lineas': pedido.lineas.map(_lineaToJson).toList(),
      }));

      _procesandoId = null;
      notifyListeners();
      return true;
    } catch (e) {
      _procesandoId = null;
      notifyListeners();
      return false;
    }
  }

  // ── Facturar pedido ──────────────────────────────────────────────────────────

  Future<bool> facturarPedido({
    required int id,
    required String metodoPago,
    double? montoEfectivo,
    double? montoTransferencia,
  }) async {
    _procesandoId = id;
    notifyListeners();

    try {
      final body = <String, dynamic>{
        'estado': 'entregado',
        'metodo_pago': metodoPago,
      };
      if (montoEfectivo != null) body['monto_efectivo'] = montoEfectivo;
      if (montoTransferencia != null) body['monto_transferencia'] = montoTransferencia;

      await ApiService.patch('/api/domicilios/$id/estado', body);

      // Marcar como entregado sin quitar de la lista
      final idx = _despachados.indexWhere((p) => p.id == id);
      if (idx >= 0) {
        final p = _despachados[idx];
        _despachados[idx] = Pedido.fromJson({
          'id': p.id,
          'estado': 'entregado',
          'total': p.total,
          'costo_domicilio': p.costoDomicilio,
          'cliente_nombre': p.clienteNombre,
          'cliente_telefono': p.clienteTelefono,
          'direccion': p.direccion,
          'ciudad': p.ciudad,
          'barrio': p.barrio,
          'latitud': p.latitud,
          'longitud': p.longitud,
          'metodo_pago': metodoPago,
          'creado_en': p.creadoEn?.toIso8601String(),
          'lineas': p.lineas.map(_lineaToJson).toList(),
        });
      }

      _procesandoId = null;
      notifyListeners();
      return true;
    } catch (e) {
      _procesandoId = null;
      notifyListeners();
      return false;
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  List<Pedido> _parseList(dynamic data) {
    List raw = [];
    if (data is List) {
      raw = data;
    } else if (data is Map && data['data'] is List) {
      raw = data['data'] as List;
    } else if (data is Map && data['pedidos'] is List) {
      raw = data['pedidos'] as List;
    }
    return raw
        .map((e) => Pedido.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Map<String, dynamic> _lineaToJson(LineaDetalle l) => {
        'id_producto': l.idProducto,
        'nombre_producto': l.nombreProducto,
        'cantidad': l.cantidad,
        'precio_unitario': l.precioUnitario,
        'toppings': l.toppings,
        'adiciones': l.adiciones,
      };

  void limpiarError() {
    _error = null;
    notifyListeners();
  }
}
