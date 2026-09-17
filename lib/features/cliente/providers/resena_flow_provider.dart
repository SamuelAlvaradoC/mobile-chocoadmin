import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/pedido.dart';
import '../../../core/services/api_service.dart';

/// Dueño del estado de "reseñas pendientes" del cliente -- mismo propósito
/// que ResenaBanner.jsx + resenaEvents.js + el query param ?pendiente_resena
/// en React web, pero consolidado en un solo ChangeNotifier porque
/// go_router no lleva query params al navegar entre branches de un
/// StatefulShellRoute (a diferencia de una URL en web).
///
/// Se sincroniza con el usuario logueado igual que CarritoProvider
/// (`ChangeNotifierProxyProvider<AuthProvider, ResenaFlowProvider>` en
/// main.dart), y expone `hayPendientes` para que RootShellScaffold sepa si
/// debe reservar espacio para el banner ANTES de construirlo -- necesario
/// para no quitarle presupuesto de MediaQuery.padding.top al navigationShell
/// cuando no hay nada que mostrar (ver comentario en root_shell_scaffold.dart).
class ResenaFlowProvider extends ChangeNotifier {
  List<Pedido> _pendientes = [];
  List<Pedido> get pendientes => _pendientes;
  bool get hayPendientes => _pendientes.isNotEmpty;
  Pedido? get masReciente => _pendientes.isEmpty ? null : _pendientes.first;

  /// id_venta que _CtaFinal debe vincular a la próxima reseña que envíe.
  int? _idVentaPendienteEnFormulario;
  int? get idVentaPendienteEnFormulario => _idVentaPendienteEnFormulario;

  int? _idUsuarioActual;

  String _clave(int idUsuario) => 'resenas_descartadas_$idUsuario';

  Future<void> sincronizarUsuario(int? idUsuario) async {
    if (idUsuario == _idUsuarioActual) return;
    _idUsuarioActual = idUsuario;
    if (idUsuario == null) {
      _pendientes = [];
      notifyListeners();
      return;
    }
    await _cargar(idUsuario);
  }

  Future<void> _cargar(int idUsuario) async {
    try {
      final data = await ApiService.get('/api/ventas/mis-pedidos');
      List raw = [];
      if (data is List) {
        raw = data;
      } else if (data is Map && data['data'] is List) {
        raw = data['data'] as List;
      }
      final pedidos = raw.map((e) => Pedido.fromJson(e as Map<String, dynamic>)).toList();

      final prefs = await SharedPreferences.getInstance();
      final descartadas = (prefs.getStringList(_clave(idUsuario)) ?? [])
          .map(int.parse)
          .toSet();

      _pendientes = pedidos
          .where((p) => p.esEntregado && !p.tieneResena && !descartadas.contains(p.id))
          .toList()
        ..sort((a, b) => (b.creadoEn ?? DateTime(0)).compareTo(a.creadoEn ?? DateTime(0)));
      notifyListeners();
    } catch (_) {
      // Silencioso -- este banner es un extra informativo, no debe romper
      // la navegación del cliente si el fetch falla (igual criterio que el
      // .catch(() => {}) del useEffect en React).
    }
  }

  Future<void> descartar(Pedido pedido) async {
    final idUsuario = _idUsuarioActual;
    if (idUsuario == null) return;
    final prefs = await SharedPreferences.getInstance();
    final actuales = prefs.getStringList(_clave(idUsuario)) ?? [];
    await prefs.setStringList(_clave(idUsuario), [...actuales, pedido.id.toString()]);
    _pendientes = _pendientes.where((v) => v.id != pedido.id).toList();
    notifyListeners();
  }

  void seleccionarParaFormulario(int idVenta) {
    _idVentaPendienteEnFormulario = idVenta;
    notifyListeners();
  }

  void marcarEnviada(int idVenta) {
    _idVentaPendienteEnFormulario = null;
    _pendientes = _pendientes.where((v) => v.id != idVenta).toList();
    notifyListeners();
  }
}
