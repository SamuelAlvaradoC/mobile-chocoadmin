import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_config.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/models/pedido.dart';
import '../../../core/models/producto.dart';
import '../../../core/services/api_service.dart';
import '../../../core/utils/validar_sin_html.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/cliente/providers/catalogo_provider.dart';
import '../../../features/cliente/widgets/toppings_modal.dart';
import '../../../shared/widgets/paginacion.dart';

// Pago mixto (igual React handleEfMixto/handleEfectivoMixto): al escribir en
// un campo se recorta al rango [0,total] y el otro campo se autocompleta con
// el complemento, de forma que la suma siempre sea igual al total. Se usa
// tanto para el campo editado (para no dejar valores fuera de rango mientras
// se escribe) como para el campo complementario.
double _clampMonto(String raw, double total) =>
    (double.tryParse(raw) ?? 0).clamp(0, total).toDouble();

void _aplicarPagoMixto({
  required String raw,
  required double total,
  required TextEditingController ctrlEditado,
  required TextEditingController ctrlComplemento,
  required void Function(double editado, double complemento) onCalculado,
}) {
  final editado = _clampMonto(raw, total);
  final complemento = (total - editado).clamp(0, total).toDouble();
  final editadoTexto = editado > 0 ? editado.round().toString() : '';
  if (ctrlEditado.text != editadoTexto) {
    ctrlEditado.value = TextEditingValue(
      text: editadoTexto,
      selection: TextSelection.collapsed(offset: editadoTexto.length),
    );
  }
  ctrlComplemento.text = complemento > 0 ? complemento.round().toString() : '';
  onCalculado(editado, complemento);
}

// Igual que React generarComprobante() en Ventas.jsx: recarga la venta
// completa, recalcula subtotal/puntos y emite 'reimprimir' por socket.
Future<void> _generarComprobante(BuildContext context, int idVenta) async {
  Map<String, dynamic> ventaCompleta = {};
  try {
    final data = await ApiService.get('/api/ventas/$idVenta');
    ventaCompleta = data is Map && data['data'] is Map
        ? Map<String, dynamic>.from(data['data'] as Map)
        : (data is Map ? Map<String, dynamic>.from(data) : {});
  } catch (_) {}

  double calcularPrecioDetalle(Map d) {
    final producto = d['producto'] is Map ? d['producto'] as Map : {};
    final base = double.tryParse(producto['precio']?.toString() ?? '0') ?? 0;
    final permiteToppings = producto['permite_toppings'];
    final maxInc = (permiteToppings == true || permiteToppings == 1)
        ? (int.tryParse(producto['max_toppings']?.toString() ?? '0') ?? 0)
        : 0;
    final detalleToppings = d['detalleToppings'] is List ? d['detalleToppings'] as List : [];
    final totTop = detalleToppings.fold<int>(0, (s, tp) => s + (int.tryParse((tp as Map?)?['cantidad']?.toString() ?? '1') ?? 1));
    final topExtra = (totTop - maxInc).clamp(0, totTop);
    List salsas = [];
    try {
      final raw = d['salsas'];
      if (raw is String && raw.isNotEmpty) {
        final parsed = jsonDecode(raw);
        if (parsed is List) salsas = parsed;
      } else if (raw is List) {
        salsas = raw;
      }
    } catch (_) {}
    final salExtra = (salsas.length - 2).clamp(0, salsas.length);
    final detalleAdiciones = d['detalleAdiciones'] is List ? d['detalleAdiciones'] as List : [];
    final precAdi = detalleAdiciones.fold<double>(0, (a, ad) {
      final adMap = ad is Map ? ad : <String, dynamic>{};
      final adicion = adMap['adicion'] is Map ? adMap['adicion'] as Map : <String, dynamic>{};
      final precio = double.tryParse(adicion['precio']?.toString() ?? '0') ?? 0;
      final cant = double.tryParse(adMap['cantidad']?.toString() ?? '1') ?? 1;
      return a + precio * cant;
    });
    final precUnit = base + topExtra * 2000 + salExtra * 5000 + precAdi;
    final precBD = double.tryParse(d['precio_unitario']?.toString() ?? '0') ?? 0;
    final cantidad = double.tryParse(d['cantidad']?.toString() ?? '1') ?? 1;
    return (precUnit > precBD ? precUnit : precBD) * cantidad;
  }

  final detalleVentas = ventaCompleta['detalleVentas'] is List ? ventaCompleta['detalleVentas'] as List : [];
  final subtotalProductos = detalleVentas.fold<double>(0, (s, d) => s + calcularPrecioDetalle(d as Map));

  final estado = ventaCompleta['estado'] is Map ? ventaCompleta['estado'] as Map : {};
  final esAnulada = estado['nombre_estado'] == 'anulado';
  final puntosUsados = int.tryParse(ventaCompleta['puntos_usados']?.toString() ?? '0') ?? 0;
  final puntosGanados = (esAnulada || puntosUsados > 0) ? 0 : (subtotalProductos / 500).floor();

  final clienteMap = ventaCompleta['cliente'] is Map ? ventaCompleta['cliente'] as Map : {};
  final idCliente = clienteMap['id_cliente'] ?? ventaCompleta['id_cliente'];
  int puntosActuales = 0;
  if (!esAnulada && idCliente != null) {
    try {
      final dp = await ApiService.get('/api/puntos/cliente/$idCliente');
      final inner = dp is Map && dp['data'] is Map ? dp['data'] as Map : {};
      puntosActuales = int.tryParse(inner['puntos']?.toString() ?? '0') ?? 0;
    } catch (_) {}
  }

  final yaEntregada = estado['nombre_estado'] == 'entregado';
  final puntosTotal = esAnulada ? null : (yaEntregada ? puntosActuales : puntosActuales + puntosGanados);

  final usuarioMap = clienteMap['usuario'] is Map ? clienteMap['usuario'] as Map : {};
  final telefono = clienteMap['telefono'] ?? usuarioMap['telefono'] ?? '—';

  // La dirección se lee de las columnas propias de la venta (copiadas al
  // momento de la compra), no de la relación con `direcciones` -- así una
  // reimpresión sigue funcionando aunque esa dirección se haya borrado.
  final dirLinea = ventaCompleta['direccion_linea'] ?? '—';
  final barrio = ventaCompleta['barrio'] ?? '';
  final ciudad = ventaCompleta['ciudad'] ?? '';
  final referencia = ventaCompleta['referencia_direccion'] ?? '';

  try {
    final socketUrl = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/api$'), '');
    final socket = io.io(socketUrl, io.OptionBuilder().setTransports(['websocket']).build());
    socket.onConnect((_) {
      socket.emit('reimprimir', {
        'id_venta': ventaCompleta['id_venta'],
        'cliente': usuarioMap['nombre'] ?? '—',
        'telefono': telefono,
        'direccion': dirLinea,
        'barrio': barrio,
        'ciudad': ciudad,
        'referencia': referencia,
        'total': ventaCompleta['total'],
        'subtotal': subtotalProductos,
        'costo_domicilio': ventaCompleta['costo_domicilio'],
        'metodo_pago': ventaCompleta['metodo_pago'],
        'monto_efectivo': ventaCompleta['monto_efectivo'],
        'monto_transferencia': ventaCompleta['monto_transferencia'],
        'observaciones': ventaCompleta['observaciones'],
        'puntos_usados': esAnulada ? 0 : puntosUsados,
        'descuento_puntos': esAnulada ? 0 : ventaCompleta['descuento_puntos'],
        'puntosGanados': puntosGanados,
        'puntosActuales': puntosActuales,
        'puntosTotal': puntosTotal,
        'detalleVentas': detalleVentas,
        'fecha': ventaCompleta['fecha'],
      });
    });
    Future.delayed(const Duration(seconds: 2), () => socket.disconnect());
  } catch (_) {}

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Enviando a imprimir...'), backgroundColor: AppColors.success),
    );
  }
}

Future<void> _confirmarImprimir(BuildContext context, Pedido venta) async {
  final confirmar = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('¿Imprimir comprobante?'),
      content: Text('Pedido #${venta.id} — ${venta.clienteNombre ?? ''}'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Imprimir'),
        ),
      ],
    ),
  );
  if (confirmar == true && context.mounted) {
    await _generarComprobante(context, venta.id);
  }
}

class VentasScreen extends StatefulWidget {
  // VentasModuloScreen usa IndexedStack para conservar el estado de ambas
  // pestañas (scroll, búsqueda, filtros) al cambiar entre Ventas y Pedidos
  // -- pero eso significa que un cambio hecho en una pestaña (ej. "Devolver
  // a listo" en Ventas) no refresca por sí solo la otra, que sigue montada
  // con su lista vieja en memoria. onReady expone la función de recarga de
  // este widget hacia el módulo, que la dispara al entrar a esta pestaña.
  final void Function(Future<void> Function() recargar)? onReady;

  const VentasScreen({super.key, this.onReady});

  @override
  State<VentasScreen> createState() => _VentasScreenState();
}

class _VentasScreenState extends State<VentasScreen> {
  bool _loading = true;
  String? _error;
  List<Pedido> _ventas = [];

  String? _filtroMetodoPago;
  String? _filtroFecha;
  final _busquedaCtrl = TextEditingController();
  int _pagina = 1;
  Object _porPagina = 10;

  final _fmt =
      NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);
  final _fmtFecha = DateFormat('dd/MM/yy HH:mm', 'es_CO');

  static const _metodosPago = ['efectivo', 'transferencia', 'mixto'];

  final _fmtFechaDisplay = DateFormat("EEEE d 'de' MMMM", 'es_CO');

  @override
  void initState() {
    super.initState();
    _filtroFecha = DateFormat('yyyy-MM-dd').format(DateTime.now().toUtc().subtract(const Duration(hours: 5)));
    _cargar();
    widget.onReady?.call(_cargar);
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final qp = <String, dynamic>{};
      // El estado se filtra en el cliente (ver _ventasFiltradas), nunca en el
      // backend: /api/ventas cambia el orden (id_venta asc en vez de fecha
      // desc) cuando se manda estado, y React nunca lo manda por lo mismo —
      // mandarlo aquí desordenaba la lista solo en Flutter.
      if (_filtroMetodoPago != null) qp['metodo_pago'] = _filtroMetodoPago!;
      if (_filtroFecha     != null) qp['fecha']       = _filtroFecha!;

      final data = await ApiService.get(
        '/api/ventas',
        queryParams: qp.isNotEmpty ? qp : null,
      );
      List raw = [];
      if (data is List) {
        raw = data;
      } else if (data is Map && data['data'] is List) {
        raw = data['data'] as List;
      }
      _ventas = raw
          .map((e) => Pedido.fromJson(e as Map<String, dynamic>))
          .toList();
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Error al cargar ventas';
    }
    setState(() => _loading = false);
  }

  List<Pedido> get _ventasFiltradas {
    // Ventas solo muestra entregados -- pendiente/confirmado/cocina/listo/
    // despachado/anulado viven en Pedidos.
    var lista = _ventas.where((v) => v.estado == 'entregado').toList();

    // El backend (GET /ventas) ignora el query param metodo_pago — hay que
    // filtrar acá igual que React (Ventas.jsx matchMetodo), si no el filtro
    // no filtra nada.
    if (_filtroMetodoPago != null) {
      lista = lista.where((v) => v.metodoPago == _filtroMetodoPago).toList();
    }

    final q = _busquedaCtrl.text.toLowerCase().trim();
    if (q.isEmpty) return lista;
    return lista.where((v) {
      return v.clienteNombre?.toLowerCase().contains(q) == true ||
          v.idFormateado.toLowerCase().contains(q) ||
          v.id.toString().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtradas = _ventasFiltradas;
    final ventasCount = _ventas.where((v) => v.estado == 'entregado').length;
    final mostrandoTodos = _porPagina == todosPorPagina;
    final porPagina = mostrandoTodos ? filtradas.length : _porPagina as int;
    final totalPaginas = mostrandoTodos || filtradas.isEmpty
        ? 1
        : ((filtradas.length + porPagina - 1) ~/ porPagina);
    final paginaActual = _pagina.clamp(1, totalPaginas);
    final paginadas = mostrandoTodos
        ? filtradas
        : filtradas.skip((paginaActual - 1) * porPagina).take(porPagina).toList();

    return Column(
        children: [
          // ── Header ───────────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Ventas',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1a1a1a),
                        ),
                      ),
                      Text(
                        '$ventasCount registro${ventasCount != 1 ? 's' : ''} en total',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF888888),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Filtros ───────────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding:
                const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              children: [
                // Buscador pill
                TextField(
                  controller: _busquedaCtrl,
                  onChanged: (_) => setState(() => _pagina = 1),
                  style: const TextStyle(fontSize: 12, height: 1.0),
                  decoration: InputDecoration(
                    hintText: 'Buscar por cliente, #venta...',
                    hintStyle: const TextStyle(
                        fontSize: 12, color: Color(0xFFAAAAAA)),
                    prefixIcon: const Icon(Icons.search_rounded,
                        size: 16, color: Color(0xFF888888)),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 6),
                    filled: true,
                    fillColor: const Color(0xFFF7F8FD),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(50),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(50),
                      borderSide: const BorderSide(
                          color: Color(0xFFE8E8E8)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(50),
                      borderSide: const BorderSide(
                          color: AppColors.primary, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // Sin dropdown de estado -- esta pantalla siempre muestra
                // solo 'entregado' (ver _ventasFiltradas), no tiene sentido
                // ofrecer un filtro de un solo valor posible.

                // Dropdown método de pago
                DropdownButtonFormField<String?>(
                  value: _filtroMetodoPago,
                  isDense: true,
                  style: const TextStyle(fontSize: 12, height: 1.0, color: Color(0xFF1a1a1a)),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: Color(0xFFE8E8E8))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Todos los métodos', style: TextStyle(fontSize: 12))),
                    ..._metodosPago.map((m) => DropdownMenuItem<String?>(value: m, child: Text(_labelMetodo(m), style: const TextStyle(fontSize: 12)))),
                  ],
                  // El backend ignora este query param (ver comentario en
                  // _cargar); el filtro real se aplica en _ventasFiltradas.
                  onChanged: (v) => setState(() { _filtroMetodoPago = v; _pagina = 1; }),
                ),
                const SizedBox(height: 6),

                // Selector de fecha + limpiar filtros
                Row(children: [
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _filtroFecha != null
                            ? (DateTime.tryParse(_filtroFecha!) ?? DateTime.now())
                            : DateTime.now(),
                        firstDate: DateTime(2024),
                        lastDate: DateTime.now(),
                        locale: const Locale('es', 'CO'),
                      );
                      if (picked != null) {
                        setState(() { _filtroFecha = DateFormat('yyyy-MM-dd').format(picked); _pagina = 1; });
                        _cargar();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _filtroFecha != null
                            ? AppColors.primary.withValues(alpha: 0.08)
                            : const Color(0xFFF7F8FD),
                        border: Border.all(
                            color: _filtroFecha != null
                                ? AppColors.primary
                                : const Color(0xFFE8E8E8)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.calendar_today_outlined, size: 13,
                            color: _filtroFecha != null ? AppColors.primary : const Color(0xFF888888)),
                        const SizedBox(width: 5),
                        Text(
                          _filtroFecha != null
                              ? _fmtFechaDisplay.format(DateTime.tryParse(_filtroFecha!) ?? DateTime.now())
                              : 'Fecha',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _filtroFecha != null ? AppColors.primary : const Color(0xFF888888),
                          ),
                        ),
                        if (_filtroFecha != null) ...[
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () { setState(() { _filtroFecha = null; _pagina = 1; }); _cargar(); },
                            child: const Icon(Icons.close_rounded, size: 13, color: AppColors.primary),
                          ),
                        ],
                      ]),
                    ),
                  ),
                  const Spacer(),
                  if (_filtroMetodoPago != null || _filtroFecha != null || _busquedaCtrl.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _filtroMetodoPago = null;
                          _filtroFecha      = null;
                          _busquedaCtrl.clear();
                          _pagina = 1;
                        });
                        _cargar();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF5F5),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.filter_alt_off_rounded, size: 13, color: AppColors.primary),
                          SizedBox(width: 4),
                          Text('Limpiar filtros', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                        ]),
                      ),
                    ),
                ]),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          // ── Lista ─────────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primary))
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline,
                                color: AppColors.error, size: 48),
                            const SizedBox(height: 12),
                            Text(_error!,
                                style: const TextStyle(
                                    color: AppColors.error)),
                            const SizedBox(height: 12),
                            TextButton(
                                onPressed: _cargar,
                                child: const Text('Reintentar')),
                          ],
                        ),
                      )
                    : filtradas.isEmpty
                        ? const Center(
                            child: Text('No se encontraron ventas',
                                style: TextStyle(
                                    color: AppColors.textSecondary)),
                          )
                        : Column(
                            children: [
                              Expanded(
                                child: RefreshIndicator(
                                  color: AppColors.primary,
                                  onRefresh: _cargar,
                                  child: ListView.separated(
                                    padding: const EdgeInsets.all(
                                        AppSizes.screenPadding),
                                    itemCount: paginadas.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 8),
                                    itemBuilder: (context, i) {
                                      final v = paginadas[i];
                                      return _VentaRow(
                                        venta: v,
                                        fmt: _fmt,
                                        fmtFecha: _fmtFecha,
                                        onRefresh: _cargar,
                                      );
                                    },
                                  ),
                                ),
                              ),
                              Paginacion(
                                pagina: paginaActual,
                                totalPaginas: totalPaginas,
                                onCambiarPagina: (n) =>
                                    setState(() => _pagina = n),
                                porPagina: _porPagina,
                                onCambiarPorPagina: (v) => setState(() {
                                  _porPagina = v;
                                  _pagina = 1;
                                }),
                              ),
                            ],
                          ),
          ),
        ],
    );
  }

  static String _labelMetodo(String m) {
    switch (m) {
      case 'efectivo':     return 'Efectivo';
      case 'transferencia': return 'Transferencia';
      case 'mixto':        return 'Mixto';
      default:             return m;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _VentaRow extends StatelessWidget {
  final Pedido venta;
  final NumberFormat fmt;
  final DateFormat fmtFecha;
  final VoidCallback onRefresh;

  const _VentaRow(
      {required this.venta, required this.fmt, required this.fmtFecha, required this.onRefresh});

  static _EstadoStyle _estadoStyle(String estado) {
    switch (estado) {
      case 'pendiente':
        return const _EstadoStyle(
            bg: Color(0xFFFFF5F5), fg: Color(0xFFCA0B0B));
      case 'en_proceso':
        return const _EstadoStyle(
            bg: Color(0xFFEFF6FF), fg: Color(0xFF3B82F6)); // blue (Confirmado)
      case 'listo':
        return const _EstadoStyle(
            bg: Color(0xFFFEFCE8), fg: Color(0xFFCA8A04)); // yellow (Listo para despachar)
      case 'despachado':
        return const _EstadoStyle(
            bg: Color(0xFFF5F3FF), fg: Color(0xFF7C3AED));
      case 'entregado':
        return const _EstadoStyle(
            bg: Color(0xFFF0FDF4), fg: Color(0xFF16A34A));
      case 'anulado':
        return const _EstadoStyle(
            bg: Color(0xFFF5F5F5), fg: Color(0xFF888888));
      default:
        return const _EstadoStyle(
            bg: Color(0xFFF5F5F5), fg: Color(0xFF888888));
    }
  }

  static String _labelEstado(String e) {
    switch (e) {
      case 'pendiente':   return 'Pendiente';
      case 'en_proceso':  return 'Confirmado';
      case 'listo':       return 'Listo para despachar';
      case 'despachado':  return 'Despachado';
      case 'entregado':   return 'Entregado';
      case 'anulado':     return 'Anulado';
      default:
        return e.isNotEmpty ? e[0].toUpperCase() + e.substring(1) : e;
    }
  }

  @override
  Widget build(BuildContext context) {
    final estStyle = _estadoStyle(venta.estado);
    final fecha = venta.creadoEn != null ? fmtFecha.format(venta.creadoEn!) : '--';
    // Igual que React Ventas.jsx: esta pantalla solo muestra entregados, así
    // que "anular" queda fuera (ya no aplica a una venta cerrada). "Devolver
    // a listo" SÍ aplica -- un pedido puede marcarse entregado por error (el
    // domiciliario se equivocó, o se confirmó antes de tiempo).
    final auth = context.watch<AuthProvider>();
    final puedeGestionar = auth.tienePermiso('gestionar_ventas');
    final dir = venta.direccion;

    void abrirDetalle() => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _VentaDetalleScreen(pedido: venta, fmt: fmt, onRefresh: onRefresh)),
    );
    void abrirEditar() => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _EditarVentaScreen(pedido: venta, onRefresh: onRefresh)),
    );
    Future<void> devolver() async {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('¿Devolver la venta ${venta.idFormateado}?'),
          content: const Text('Esto la saca de Ventas y la regresa a Pedidos, en estado Listo.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFEF3C7), foregroundColor: const Color(0xFFCA8A04)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Devolver'),
            ),
          ],
        ),
      );
      if (confirm == true) {
        try {
          await ApiService.patch('/api/ventas/${venta.id}/estado', {'nombre_estado': 'listo'});
          onRefresh();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Venta devuelta a Listo'), backgroundColor: Color(0xFF16A34A)),
            );
          }
        } on ApiException catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
          }
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Error al devolver la venta')));
          }
        }
      }
    }

    final mostrarEditar = puedeGestionar;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
      onTap: abrirDetalle,
      borderRadius: BorderRadius.circular(10),
      child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Fila 1: ID + estado + fecha ──
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(6)),
              child: Text(venta.idFormateado,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF666666))),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: estStyle.bg, borderRadius: BorderRadius.circular(20)),
              child: Text(_labelEstado(venta.estado),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: estStyle.fg)),
            ),
            const Spacer(),
            Text(fecha, style: const TextStyle(fontSize: 11, color: Color(0xFF888888))),
          ]),
          const SizedBox(height: 7),

          // ── Fila 2: Cliente ──
          Text(venta.clienteNombre ?? 'Sin nombre',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1a1a1a)),
              overflow: TextOverflow.ellipsis),

          // ── Fila 3: Dirección ──
          if (dir != null && dir.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.location_on_outlined, size: 13, color: Color(0xFF888888)),
              const SizedBox(width: 4),
              Expanded(child: Text(dir,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
                  overflow: TextOverflow.ellipsis)),
            ]),
          ],

          const SizedBox(height: 8),

          // ── Fila 4: Total + método + menú overflow ──
          // Solo ver detalle (tocar la tarjeta), cambiar método de pago e
          // imprimir comprobante -- una venta entregada ya está cerrada.
          Row(
            children: [
              Text(fmt.format(venta.total),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF16A34A))),
              if (venta.metodoPago != null) ...[
                const SizedBox(width: 8),
                _MetodoBadge(venta.metodoPago!),
              ],
              const Spacer(),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF888888)),
                onSelected: (v) {
                  switch (v) {
                    case 'editar': abrirEditar(); break;
                    case 'imprimir': _confirmarImprimir(context, venta); break;
                    case 'devolver': devolver(); break;
                  }
                },
                itemBuilder: (_) => [
                  if (mostrarEditar)
                    const PopupMenuItem(
                      value: 'editar',
                      child: Row(children: [
                        Icon(Icons.edit_outlined, size: 18, color: Color(0xFF666666)),
                        SizedBox(width: 10),
                        Text('Cambiar método de pago'),
                      ]),
                    ),
                  const PopupMenuItem(
                    value: 'imprimir',
                    child: Row(children: [
                      Icon(Icons.receipt_long_outlined, size: 18, color: Color(0xFF666666)),
                      SizedBox(width: 10),
                      Text('Imprimir comprobante'),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'devolver',
                    child: Row(children: [
                      Icon(Icons.replay_rounded, size: 18, color: Color(0xFFCA8A04)),
                      SizedBox(width: 10),
                      Text('Devolver a listo', style: TextStyle(color: Color(0xFFCA8A04))),
                    ]),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      ),
      ),
    );
  }
}

class _EstadoStyle {
  final Color bg;
  final Color fg;
  const _EstadoStyle({required this.bg, required this.fg});
}

class _MetodoBadge extends StatelessWidget {
  final String metodo;
  const _MetodoBadge(this.metodo);
  @override
  Widget build(BuildContext context) {
    final isEf = metodo == 'efectivo';
    final isMx = metodo == 'mixto';
    final color = isEf ? const Color(0xFFCA8A04) : isMx ? const Color(0xFF7C3AED) : const Color(0xFF3B82F6);
    final bg    = isEf ? const Color(0xFFFEFCE8) : isMx ? const Color(0xFFF5F3FF) : const Color(0xFFEFF6FF);
    final label = isEf ? 'Efectivo' : isMx ? 'Mixto' : 'Transferencia';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Modal detalle venta admin
// ─────────────────────────────────────────────────────────────────────────────

class _VentaDetalleScreen extends StatefulWidget {
  final Pedido pedido;
  final NumberFormat fmt;
  final VoidCallback onRefresh;

  const _VentaDetalleScreen(
      {required this.pedido, required this.fmt, required this.onRefresh});

  @override
  State<_VentaDetalleScreen> createState() => _VentaDetalleScreenState();
}

class _VentaDetalleScreenState extends State<_VentaDetalleScreen> {
  // Igual que React ModalDetalle: es de solo lectura, sin acciones que
  // cambien estado — esas viven únicamente en la fila de la tabla.

  @override
  Widget build(BuildContext context) {
    final p = widget.pedido;
    final fmt = widget.fmt;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Venta ${p.idFormateado}'),
      ),
      body: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSizes.screenPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info cliente — grid compacto igual React ModalDetalle,
                  // orden: Estado|Fecha, Cliente|Teléfono, Barrio|Ciudad,
                  // Dirección|Domiciliario, Referencia, Observaciones.
                  _EstadoDetalleBadge(p.estado),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (p.creadoEn != null)
                      _DetalleRow('Fecha', DateFormat('dd/MM/yyyy HH:mm', 'es_CO').format(p.creadoEn!)),
                    _DetalleRow('Cliente', p.clienteNombre),
                    _DetalleRow('Teléfono', p.clienteTelefono),
                    _DetalleRow('Pago', p.metodoPago),
                    if (p.barrio != null && p.barrio!.isNotEmpty)
                      _DetalleRow('Barrio', p.barrio),
                    if (p.ciudad != null && p.ciudad!.isNotEmpty)
                      _DetalleRow('Ciudad', p.ciudad),
                    if (p.direccion != null && p.direccion!.isNotEmpty)
                      _DetalleRow('Dirección', p.direccion),
                    if (p.nombreDomiciliario != null && p.nombreDomiciliario!.isNotEmpty)
                      _DetalleRow('Domiciliario', p.nombreDomiciliario),
                    if (p.referencia != null && p.referencia!.isNotEmpty)
                      _DetalleRow('Referencia', p.referencia, full: true),
                  ]),
                  // Observaciones y motivo de anulación -- van justo después
                  // del bloque de info (igual React), antes de desglose/
                  // comprobante/productos.
                  if (p.observaciones != null && p.observaciones!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Observaciones', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFB45309))),
                        const SizedBox(height: 4),
                        Text(p.observaciones!, style: const TextStyle(fontSize: 13, color: Color(0xFF92400E), fontStyle: FontStyle.italic)),
                      ]),
                    ),
                  ],
                  if (p.estado == 'anulado' && p.motivoAnulacion != null && p.motivoAnulacion!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF5F5),
                        border: Border.all(color: AppColors.error),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Motivo de anulación',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.error)),
                        const SizedBox(height: 4),
                        Text(p.motivoAnulacion!,
                            style: const TextStyle(fontSize: 13, color: AppColors.error, fontStyle: FontStyle.italic)),
                      ]),
                    ),
                  ],
                  // Desglose mixto
                  if (p.metodoPago == 'mixto') ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFFF7F8FD), borderRadius: BorderRadius.circular(8)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('DESGLOSE', style: GoogleFonts.nunito(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF888888))),
                        const SizedBox(height: 4),
                        if (p.montoEfectivo != null) Text('Efectivo: ${fmt.format(p.montoEfectivo!)}', style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600)),
                        if (p.montoTransferencia != null) Text('Transferencia: ${fmt.format(p.montoTransferencia!)}', style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ],
                  // Comprobante de transferencia
                  if (p.comprobanteUrl != null && p.comprobanteUrl!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text('Comprobante',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => showDialog(
                        context: context,
                        builder: (_) => Dialog(
                          child: Image.network(p.comprobanteUrl!, fit: BoxFit.contain),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          p.comprobanteUrl!,
                          height: 160,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            height: 80,
                            color: const Color(0xFFF0F0F0),
                            child: const Center(child: Icon(Icons.broken_image_outlined, color: Color(0xFFAAAAAA))),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],

                  const SizedBox(height: AppSizes.md),

                  // Productos
                  if (p.lineas.isNotEmpty) ...[
                    const Text('Productos',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 8),
                    ...p.lineas.asMap().entries.map((entry) {
                      final l = entry.value;
                      final i = entry.key;
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: i < p.lineas.length - 1
                            ? const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))))
                            : null,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(child: Text('${l.cantidad}x ${l.nombreProducto}',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                              Text(fmt.format(l.subtotal),
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF16A34A))),
                            ],
                          ),
                          if (l.chocolate != null || l.salsas.isNotEmpty || l.toppings.isNotEmpty || l.adiciones.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Wrap(spacing: 4, runSpacing: 4, children: [
                              if (l.chocolate != null)
                                _VentaChip(label: 'Chocolate ${l.chocolate!}',
                                    bg: l.chocolate!.toLowerCase().contains('negro') ? const Color(0xFF1E3A5F) : const Color(0xFFF0F0F0),
                                    fg: l.chocolate!.toLowerCase().contains('negro') ? Colors.white : const Color(0xFF555555)),
                              ...l.salsas.map((s) => _VentaChip(
                                    label: l.esBowl ? 'Cobertura: $s' : s,
                                    outlined: true,
                                    outlineColor: const Color(0xFFEA580C),
                                    fg: const Color(0xFFEA580C),
                                    bg: const Color(0xFFFFF7ED),
                                  )),
                              ...l.toppings.map((t) => _VentaChip(label: t, bg: const Color(0xFF1A1A1A), fg: Colors.white)),
                              ...l.adiciones.map((a) => _VentaChip(label: a, bg: const Color(0xFFD97706), fg: Colors.white)),
                            ]),
                          ],
                        ]),
                      );
                    }),
                    const Divider(),
                  ],

                  // Totales
                  _TotalRowVenta(label: 'Subtotal productos', valor: fmt.format(p.subtotal)),
                  if (p.descuentoPuntos > 0)
                    _TotalRowVenta(label: 'Descuento puntos (${p.puntosUsados} pts)', valor: '- ${fmt.format(p.descuentoPuntos)}', green: true),
                  if (p.puntosGanados > 0)
                    _TotalRowVenta(label: 'Puntos ganados', valor: '+${p.puntosGanados} pts', green: true),
                  if (p.costoDomicilio > 0)
                    _TotalRowVenta(label: 'Costo domicilio', valor: fmt.format(p.costoDomicilio)),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      Text(fmt.format(p.total),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF16A34A),
                              fontSize: 16)),
                    ],
                  ),

                  // Botón acción — solo WhatsApp, igual React ModalDetalle (solo lectura)
                  if (p.clienteTelefono != null && p.clienteTelefono!.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.chat_outlined, size: 18),
                        label: const Text('WhatsApp',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        onPressed: () async {
                          final tel = p.clienteTelefono!.replaceAll(RegExp(r'\D'), '');
                          final numero = tel.startsWith('57') ? tel : '57$tel';
                          final msg = Uri.encodeComponent(
                            'Hola ${p.clienteNombre ?? ''}, tu pedido ${p.idFormateado} de ChocoFreseo ya está confirmado y en preparación, en breves minutos será despachado hacia tu ubicación, por favor esté pendiente.\n\nCuando recibas tus productos, te invitamos a llenar este pequeño formulario, tu opinión es muy importante para nosotros:\nchocofreseo.com/#resenas',
                          );
                          final url = Uri.parse('https://wa.me/$numero?text=$msg');
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url, mode: LaunchMode.externalApplication);
                          }
                        },
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _DetalleRow extends StatelessWidget {
  final String label;
  final String? value;
  final bool full;
  const _DetalleRow(this.label, this.value, {this.full = false});

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.isEmpty) return const SizedBox.shrink();
    return Container(
      width: full ? double.infinity : 160,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF0F0F0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(), style: GoogleFonts.nunito(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF888888))),
        const SizedBox(height: 2),
        Text(value!, style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1a1a1a))),
      ]),
    );
  }
}

class _VentaChip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final bool outlined;
  final Color? outlineColor;
  const _VentaChip({required this.label, required this.bg, required this.fg, this.outlined = false, this.outlineColor});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      border: outlined ? Border.all(color: outlineColor ?? fg) : null,
    ),
    child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
  );
}

class _TotalRowVenta extends StatelessWidget {
  final String label;
  final String valor;
  final bool green;
  const _TotalRowVenta({required this.label, required this.valor, this.green = false});
  @override
  Widget build(BuildContext context) {
    final color = green ? const Color(0xFF16A34A) : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: color, fontWeight: green ? FontWeight.w700 : FontWeight.w400, fontSize: 13)),
          Text(valor, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }
}

class _EstadoDetalleBadge extends StatelessWidget {
  final String estado;
  const _EstadoDetalleBadge(this.estado);
  @override
  Widget build(BuildContext context) {
    final s = _VentaRow._estadoStyle(estado);
    final label = _VentaRow._labelEstado(estado);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(
            width: 90,
            child: Text('Estado',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: s.bg,
              borderRadius: BorderRadius.circular(50),
            ),
            child: Text(label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: s.fg)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Modal: Editar venta
// ─────────────────────────────────────────────────────────────────────────────

class _ItemEdit {
  final int idProducto;
  final String nombre;
  int cantidad;
  final double precioUnitario;
  // Costo de adiciones POR UNIDAD del producto (NO incluido en precioUnitario,
  // falta multiplicar por `cantidad`) — igual que React: calcItemEdit =
  // (precio_unitario + adicionPerUnit) * cantidad.
  final double costoAdiciones;
  final List<Map<String, dynamic>> rawToppings;
  final List<Map<String, dynamic>> rawAdiciones;
  final List<String> salsas;
  final String? chocolate;
  final bool esBowl;
  final int maxToppings;

  _ItemEdit({
    required this.idProducto,
    required this.nombre,
    required this.cantidad,
    required this.precioUnitario,
    this.costoAdiciones = 0,
    List<Map<String, dynamic>>? rawToppings,
    List<Map<String, dynamic>>? rawAdiciones,
    List<String>? salsas,
    this.chocolate,
    this.esBowl = false,
    this.maxToppings = 0,
  })  : rawToppings  = rawToppings  ?? const [],
        rawAdiciones = rawAdiciones ?? const [],
        salsas       = salsas       ?? const [];
}

class _EditarVentaScreen extends StatefulWidget {
  final Pedido pedido;
  final VoidCallback onRefresh;
  const _EditarVentaScreen({required this.pedido, required this.onRefresh});
  @override
  State<_EditarVentaScreen> createState() => _EditarVentaScreenState();
}

class _EditarVentaScreenState extends State<_EditarVentaScreen> {
  late double _costoDomicilio;
  bool _overrideDomicilio = false;
  late String _metodoPago;
  late double _montoEfectivo;
  late double _montoTransfer;
  late List<_ItemEdit> _items;
  bool _guardando = false;
  String? _error;

  final _costoCtrl  = TextEditingController();
  final _efCtrl     = TextEditingController();
  final _trCtrl     = TextEditingController();
  final _busqCtrl   = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _telCtrl    = TextEditingController();
  int? _filtroCat;
  String _busqProd = '';
  final _fmt = NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    final p = widget.pedido;
    _costoDomicilio = p.costoDomicilio;
    _metodoPago     = p.metodoPago ?? 'efectivo';
    _montoEfectivo  = p.montoEfectivo ?? 0;
    _montoTransfer  = p.montoTransferencia ?? 0;
    _costoCtrl.text  = _costoDomicilio.round().toString();
    _efCtrl.text     = _montoEfectivo.round().toString();
    _trCtrl.text     = _montoTransfer.round().toString();
    _nombreCtrl.text = p.clienteNombre ?? '';
    _telCtrl.text    = p.clienteTelefono ?? '';
    // El producto pudo cambiar de configuración después de esta venta — si
    // ya no permite chocolate/salsas, se limpia al cargar para que el
    // backend no lo rechace (400) con solo cambiar la cantidad, sin que el
    // admin haya tocado ese campo.
    final catalogo = context.read<CatalogoProvider>().productos;
    Producto? productoActual(int id) {
      for (final prod in catalogo) {
        if (prod.id == id) return prod;
      }
      return null;
    }
    _items = p.lineas.map((l) {
      final prodActual = productoActual(l.idProducto);
      final permiteChoc = prodActual?.permiteChocolate ?? true;
      final permiteSal  = prodActual?.permiteSalsas ?? true;
      return _ItemEdit(
        idProducto: l.idProducto,
        nombre: l.nombreProducto,
        cantidad: l.cantidad,
        precioUnitario: l.precioUnitario,
        costoAdiciones: l.costoAdiciones,
        rawToppings: List.from(l.rawToppings),
        rawAdiciones: List.from(l.rawAdiciones),
        salsas: permiteSal ? l.salsas : [],
        chocolate: permiteChoc ? l.chocolate : null,
        esBowl: l.esBowl,
        maxToppings: l.maxToppings,
      );
    }).toList();
  }

  @override
  void dispose() {
    _costoCtrl.dispose(); _efCtrl.dispose(); _trCtrl.dispose(); _busqCtrl.dispose();
    _nombreCtrl.dispose(); _telCtrl.dispose();
    super.dispose();
  }

  // Igual que React calcItemEdit: (precio_unitario + adicionPerUnit) × cantidad
  double get _subtotalItems => _items.fold(0.0, (s, i) => s + (i.precioUnitario + i.costoAdiciones) * i.cantidad);
  double get _total => _subtotalItems + _costoDomicilio;

  bool get _mixtoOk => _metodoPago != 'mixto' ||
      (_montoEfectivo > 0 && _montoTransfer > 0 &&
       (_montoEfectivo + _montoTransfer - _total).abs() < 1);

  Future<void> _guardar() async {
    if (_items.isEmpty) {
      setState(() => _error = 'Debe incluir al menos un producto');
      return;
    }
    if (!_mixtoOk) {
      setState(() => _error = 'Los montos mixto deben sumar \$${_total.round()} exacto');
      return;
    }
    if (contieneEtiquetaHtml(_nombreCtrl.text)) {
      setState(() => _error = mensajeHtml);
      return;
    }
    setState(() { _guardando = true; _error = null; });
    try {
      final id = widget.pedido.id;
      final items = _items.map((item) => <String, dynamic>{
        'id_producto':  item.idProducto,
        'cantidad':     item.cantidad,
        'max_toppings': item.maxToppings,
        'toppings':     item.rawToppings.map((t) => {'id_topping': t['id_topping'], 'cantidad': t['cantidad'] ?? 1}).toList(),
        'adiciones':    item.rawAdiciones.map((a) => {'id_adicion': a['id_adicion'], 'cantidad': a['cantidad'] ?? 1}).toList(),
        'salsas':       item.salsas,
        'chocolate':    item.chocolate,
      }).toList();
      final esEntregada = widget.pedido.estado == 'entregado';
      final body = <String, dynamic>{
        'items': items,
        'costo_domicilio': _costoDomicilio.round(),
        'override_costo_domicilio': _overrideDomicilio,
        'metodo_pago': _metodoPago,
        'monto_efectivo': _metodoPago == 'efectivo'
            ? _total.round()
            : _metodoPago == 'mixto' ? _montoEfectivo.round() : 0,
        'monto_transferencia': _metodoPago == 'transferencia'
            ? _total.round()
            : _metodoPago == 'mixto' ? _montoTransfer.round() : 0,
        if (!esEntregada) 'nombre_cliente':   _nombreCtrl.text.trim().isNotEmpty ? _nombreCtrl.text.trim() : null,
        if (!esEntregada) 'telefono_cliente':  _telCtrl.text.trim().isNotEmpty   ? _telCtrl.text.trim()    : null,
      };
      await ApiService.patch('/api/ventas/$id/editar', body);
      if (mounted) {
        widget.onRefresh();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Venta actualizada'), backgroundColor: AppColors.success),
        );
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Error al guardar');
    }
    if (mounted) setState(() => _guardando = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pedido;
    final esEntregada = p.estado == 'entregado';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(esEntregada ? 'Cambiar método de pago — ${p.idFormateado}' : 'Editar venta ${p.idFormateado}'),
      ),
      body: Column(children: [
        if (esEntregada)
          Container(
            margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFFEF3C7), border: Border.all(color: const Color(0xFFFDE68A)), borderRadius: BorderRadius.circular(8)),
            child: const Row(children: [
              Icon(Icons.warning_amber_rounded, size: 15, color: Color(0xFF92400E)),
              SizedBox(width: 8),
              Expanded(child: Text('Este pedido ya fue entregado. Solo puedes cambiar el método de pago.', style: TextStyle(fontSize: 13, color: Color(0xFF92400E)))),
            ]),
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ── Datos del cliente ────────────────────────────────────────
              if (!esEntregada) ...[
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('NOMBRE CLIENTE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF888888))),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _nombreCtrl,
                      decoration: InputDecoration(
                        hintText: 'Nombre del cliente',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ])),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('TELÉFONO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF888888))),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _telCtrl,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      decoration: InputDecoration(
                        hintText: 'Ej: 3001234567',
                        counterText: '',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ])),
                ]),
                const SizedBox(height: 16),
              ],

              // ── Productos del pedido ─────────────────────────────────────
              if (!esEntregada) ...[
                const Text('Productos del pedido', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF555555))),
                const SizedBox(height: 8),
                if (_items.isEmpty)
                  const Text('Sin productos', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ..._items.asMap().entries.map((entry) {
                  final i = entry.key;
                  final item = entry.value;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAFAFA),
                      border: Border.all(color: const Color(0xFFF0F0F0)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(item.nombre, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                        GestureDetector(
                          onTap: () => setState(() {
                            if (item.cantidad > 1) {
                              _items[i].cantidad--;
                            } else {
                              _items.removeAt(i);
                            }
                          }),
                          child: Container(width: 24, height: 24, decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(4)), alignment: Alignment.center, child: const Text('−', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
                        ),
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('${item.cantidad}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
                        GestureDetector(
                          onTap: () => setState(() => _items[i].cantidad++),
                          child: Container(width: 24, height: 24, decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(4)), alignment: Alignment.center, child: const Text('+', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => setState(() => _items.removeAt(i)),
                          child: Container(width: 24, height: 24, decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(4)), alignment: Alignment.center, child: const Icon(Icons.close_rounded, size: 13, color: AppColors.primary)),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        '${_fmt.format(item.precioUnitario)} × ${item.cantidad} = ${_fmt.format(item.precioUnitario * item.cantidad)}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF888888)),
                      ),
                      Builder(builder: (ctx) {
                        final toppingNames = item.rawToppings.map((t) {
                          final top = t['topping'];
                          return (top is Map ? top['nombre'] : t['nombre'])?.toString() ?? '';
                        }).where((n) => n.isNotEmpty).toList();
                        final adicionNames = item.rawAdiciones.map((a) {
                          final adic = a['adicion'];
                          return (adic is Map ? adic['nombre'] : a['nombre'])?.toString() ?? '';
                        }).where((n) => n.isNotEmpty).toList();
                        if (item.chocolate == null && item.salsas.isEmpty && toppingNames.isEmpty && adicionNames.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Wrap(spacing: 4, runSpacing: 4, children: [
                            if (item.chocolate != null)
                              _VentaChip(
                                label: 'Chocolate ${item.chocolate!}',
                                bg: item.chocolate!.toLowerCase().contains('negro') ? const Color(0xFF1E3A5F) : const Color(0xFFF0F0F0),
                                fg: item.chocolate!.toLowerCase().contains('negro') ? Colors.white : const Color(0xFF555555),
                              ),
                            ...(item.esBowl && item.salsas.isNotEmpty
                                ? [_VentaChip(label: 'Cobertura: ${_nombreSalsa(item.salsas.first)}', bg: const Color(0xFFFEF3C7), fg: const Color(0xFF92400E), outlined: true, outlineColor: const Color(0xFFD97706))]
                                : item.salsas.map((s) => _VentaChip(label: _nombreSalsa(s), outlined: true, outlineColor: const Color(0xFFEA580C), fg: const Color(0xFFEA580C), bg: const Color(0xFFFFF7ED))).toList()),
                            ...toppingNames.map((t) => _VentaChip(label: t, bg: const Color(0xFF1A1A1A), fg: Colors.white)),
                            ...adicionNames.map((a) => _VentaChip(label: a, bg: const Color(0xFFD97706), fg: Colors.white)),
                          ]),
                        );
                      }),
                    ]),
                  );
                }),
                const SizedBox(height: 12),
                // ── Agregar producto ─────────────────────────────────────
                Consumer<CatalogoProvider>(builder: (ctx, cat, _) {
                  if (cat.productosFiltrados.isEmpty && !cat.loading) {
                    cat.cargarTodo();
                  }
                  var prods = cat.productosFiltrados;
                  if (_filtroCat != null) {
                    prods = prods.where((p) => p.idCategoria == _filtroCat).toList();
                  }
                  if (_busqProd.isNotEmpty) {
                    final q = _busqProd.toLowerCase();
                    prods = prods.where((p) => p.nombre.toLowerCase().contains(q)).toList();
                  }
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Agregar producto', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF555555))),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int?>(
                      value: _filtroCat,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        filled: true, fillColor: const Color(0xFFF7F8FD),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
                      ),
                      hint: const Text('Todas las categorías', style: TextStyle(fontSize: 13)),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('Todas', style: TextStyle(fontSize: 13))),
                        ...cat.categorias.map((c) => DropdownMenuItem<int?>(
                          value: c.id,
                          child: Text(c.nombre, style: const TextStyle(fontSize: 13)),
                        )),
                      ],
                      onChanged: (v) => setState(() => _filtroCat = v),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _busqCtrl,
                      onChanged: (v) => setState(() => _busqProd = v),
                      decoration: InputDecoration(
                        hintText: 'Buscar producto...',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        filled: true, fillColor: const Color(0xFFF7F8FD),
                        prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF888888)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_filtroCat != null || _busqProd.isNotEmpty) ...[
                    if (cat.loading)
                      const Center(child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
                      ))
                    else if (prods.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Sin productos', style: TextStyle(fontSize: 13, color: Color(0xFF888888))),
                      )
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 2.5,
                        ),
                        itemCount: prods.length,
                        itemBuilder: (gctx, idx) {
                          final prod = prods[idx];
                          return GestureDetector(
                            onTap: () async {
                              // Igual que React (Ventas.jsx) y el catálogo cliente: el
                              // modal SIEMPRE se abre, sin importar los flags — su propio
                              // `_pasos` decide qué secciones mostrar y siempre incluye
                              // "adiciones" como paso final, incluso para productos sin
                              // ningún permite_X activo. Antes, esos productos "planos" se
                              // agregaban directo sin pasar por el modal y por eso nunca
                              // podían llevar adiciones.
                              final result = await showModalBottomSheet<ModalProductoResult>(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => ToppingsModal(
                                  allToppings: cat.toppings,
                                  allAdiciones: cat.adiciones,
                                  producto: prod,
                                ),
                              );
                              if (result != null && mounted) {
                                setState(() => _items.add(_ItemEdit(
                                  idProducto: prod.id,
                                  nombre: prod.nombre,
                                  cantidad: 1,
                                  precioUnitario: prod.precio + result.cargoExtra,
                                  costoAdiciones: result.adiciones.fold(0.0, (s, a) => s + a.precio),
                                  rawToppings: result.toppings.map((t) => <String, dynamic>{'id_topping': t.id, 'cantidad': 1}).toList(),
                                  rawAdiciones: result.adiciones.map((a) => <String, dynamic>{'id_adicion': a.id, 'cantidad': 1}).toList(),
                                  salsas: result.salsas.map((s) => (s['nombre'] ?? s['id'] ?? '').toString()).where((s) => s.isNotEmpty).toList(),
                                  chocolate: result.tipoChocolate,
                                  esBowl: prod.esBowl,
                                  maxToppings: prod.maxToppings,
                                )));
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: const Color(0xFFE0E0E0)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(prod.nombre, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  Text(_fmt.format(prod.precio), style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                  ]);
                }),
                const SizedBox(height: 4),
                // Total
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: const Color(0xFFF0FDF4), border: Border.all(color: const Color(0xFFBBF7D0)), borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Total', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF16A34A))),
                    Text(_fmt.format(_total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF16A34A))),
                  ]),
                ),
                const SizedBox(height: 16),
              ],
              // Costo domicilio (solo si no entregada) — de solo lectura si la
              // dirección tiene barrio del catálogo: el backend fuerza
              // Barrio.precio_domicilio salvo que se pida explícitamente
              // cambiarlo (override_costo_domicilio).
              if (!esEntregada) ...[
                const Text('Costo domicilio', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF555555))),
                const SizedBox(height: 8),
                if (widget.pedido.barrio != null && !_overrideDomicilio) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(color: const Color(0xFFF7F8FD), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE0E0E0))),
                    child: Text(_fmt.format(_costoDomicilio), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Expanded(child: Text('Precio fijado por el barrio del catálogo', style: TextStyle(fontSize: 11, color: Color(0xFF888888)))),
                    GestureDetector(
                      onTap: () => setState(() => _overrideDomicilio = true),
                      child: const Text('Cambiar precio manualmente', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary, decoration: TextDecoration.underline)),
                    ),
                  ]),
                ] else if (widget.pedido.barrio != null && _overrideDomicilio) ...[
                  TextField(
                    controller: _costoCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (v) => setState(() => _costoDomicilio = double.tryParse(v) ?? 0),
                    decoration: InputDecoration(
                      prefixText: '\$ ',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      filled: true, fillColor: const Color(0xFFF7F8FD),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('Precio manual — distinto al del barrio del catálogo', style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
                ] else
                  TextField(
                    controller: _costoCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (v) => setState(() => _costoDomicilio = double.tryParse(v) ?? 0),
                    decoration: InputDecoration(
                      prefixText: '\$ ',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      filled: true, fillColor: const Color(0xFFF7F8FD),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                    ),
                  ),
                const SizedBox(height: 16),
              ],
              // Método de pago
              const Text('Método de pago', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF555555))),
              const SizedBox(height: 8),
              Row(children: [
                // Efectivo
                Expanded(child: GestureDetector(
                  onTap: () => setState(() {
                    _metodoPago = 'efectivo';
                    _montoEfectivo = _total; _montoTransfer = 0;
                    _efCtrl.text = _montoEfectivo.round().toString();
                    _trCtrl.text = '0';
                  }),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _metodoPago == 'efectivo' ? AppColors.primary : const Color(0xFFE5E7EB), width: _metodoPago == 'efectivo' ? 2 : 1),
                      color: _metodoPago == 'efectivo' ? const Color(0xFFFFF5F5) : Colors.white,
                    ),
                    child: Column(children: [
                      Icon(Icons.payments_outlined, size: 18, color: _metodoPago == 'efectivo' ? AppColors.primary : const Color(0xFF555555)),
                      const SizedBox(height: 2),
                      Text('Efectivo', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _metodoPago == 'efectivo' ? AppColors.primary : const Color(0xFF555555))),
                    ]),
                  ),
                )),
                // Transferencia
                Expanded(child: GestureDetector(
                  onTap: () => setState(() {
                    _metodoPago = 'transferencia';
                    _montoTransfer = _total; _montoEfectivo = 0;
                    _trCtrl.text = _montoTransfer.round().toString();
                    _efCtrl.text = '0';
                  }),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _metodoPago == 'transferencia' ? AppColors.primary : const Color(0xFFE5E7EB), width: _metodoPago == 'transferencia' ? 2 : 1),
                      color: _metodoPago == 'transferencia' ? const Color(0xFFFFF5F5) : Colors.white,
                    ),
                    child: Column(children: [
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        CachedNetworkImage(
                          imageUrl: 'https://res.cloudinary.com/diqeuyoqo/image/upload/v1779736112/bancolombia_wiytke.png',
                          width: 16, height: 16, fit: BoxFit.contain,
                          errorWidget: (_, __, ___) => const Icon(Icons.account_balance_outlined, size: 16),
                        ),
                        const SizedBox(width: 3),
                        CachedNetworkImage(
                          imageUrl: 'https://res.cloudinary.com/diqeuyoqo/image/upload/v1779736049/nequi_pfgazy.png',
                          width: 16, height: 16, fit: BoxFit.contain,
                          errorWidget: (_, __, ___) => const Icon(Icons.phone_android_rounded, size: 16),
                        ),
                      ]),
                      const SizedBox(height: 2),
                      Text('Transferencia', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _metodoPago == 'transferencia' ? AppColors.primary : const Color(0xFF555555))),
                    ]),
                  ),
                )),
                // Mixto
                Expanded(child: GestureDetector(
                  onTap: () => setState(() {
                    _metodoPago = 'mixto';
                    _montoEfectivo = 0; _montoTransfer = 0;
                    _efCtrl.text = '0'; _trCtrl.text = '0';
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _metodoPago == 'mixto' ? AppColors.primary : const Color(0xFFE5E7EB), width: _metodoPago == 'mixto' ? 2 : 1),
                      color: _metodoPago == 'mixto' ? const Color(0xFFFFF5F5) : Colors.white,
                    ),
                    child: Column(children: [
                      Icon(Icons.sync_alt_rounded, size: 18, color: _metodoPago == 'mixto' ? AppColors.primary : const Color(0xFF555555)),
                      const SizedBox(height: 2),
                      Text('Mixto', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _metodoPago == 'mixto' ? AppColors.primary : const Color(0xFF555555))),
                    ]),
                  ),
                )),
              ]),
              if (_metodoPago == 'mixto') ...[
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Efectivo', style: TextStyle(fontSize: 12, color: Color(0xFF888888))),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _efCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (v) => _aplicarPagoMixto(
                        raw: v,
                        total: _total,
                        ctrlEditado: _efCtrl,
                        ctrlComplemento: _trCtrl,
                        onCalculado: (ef, tr) => setState(() {
                          _montoEfectivo = ef;
                          _montoTransfer = tr;
                        }),
                      ),
                      decoration: _buildInputDec(),
                    ),
                  ])),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Transferencia', style: TextStyle(fontSize: 12, color: Color(0xFF888888))),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _trCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (v) => _aplicarPagoMixto(
                        raw: v,
                        total: _total,
                        ctrlEditado: _trCtrl,
                        ctrlComplemento: _efCtrl,
                        onCalculado: (tr, ef) => setState(() {
                          _montoTransfer = tr;
                          _montoEfectivo = ef;
                        }),
                      ),
                      decoration: _buildInputDec(),
                    ),
                  ])),
                ]),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _mixtoOk ? const Color(0xFFF0FDF4) : const Color(0xFFFFF5F5),
                    border: Border.all(color: _mixtoOk ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(_mixtoOk ? '✓ Los montos cuadran' : 'Pago incompleto',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _mixtoOk ? const Color(0xFF166534) : AppColors.primary)),
                    Text(_fmt.format(_total), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _mixtoOk ? const Color(0xFF166534) : AppColors.primary)),
                  ]),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColors.errorLight, borderRadius: BorderRadius.circular(8)),
                  child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
                ),
              ],
            ]),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFE0E0E0)),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Cancelar', style: TextStyle(color: Color(0xFF666666), fontWeight: FontWeight.w700)),
            )),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton(
              onPressed: (_guardando || _items.isEmpty) ? null : _guardar,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              child: _guardando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Guardar cambios', style: TextStyle(fontWeight: FontWeight.w700)),
            )),
          ]),
        ),
      ]),
    );
  }

  InputDecoration _buildInputDec() => InputDecoration(
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    filled: true, fillColor: const Color(0xFFF7F8FD),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
  );
}

String _nombreSalsa(String s) => s.replaceAll('_', ' ').replaceAllMapped(
    RegExp(r'\b\w'), (m) => m.group(0)!.toUpperCase());

