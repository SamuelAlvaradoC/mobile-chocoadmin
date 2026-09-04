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
import '../../../shared/layouts/admin_layout.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/colombia_location_picker.dart';
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

  final dirObj = ventaCompleta['direccion'];
  final dirLinea = dirObj is Map ? (dirObj['direccion_linea'] ?? '—') : (dirObj ?? '—');
  final barrio = dirObj is Map ? (dirObj['barrio'] ?? '') : '';
  final ciudad = dirObj is Map ? (dirObj['ciudad'] ?? '') : '';
  final referencia = dirObj is Map ? (dirObj['referencia'] ?? '') : '';

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

// Réplica de React ModalAnular: motivo requerido (botón deshabilitado hasta llenarlo).
Future<void> _anularVentaRapidoDialog(
    BuildContext context, Pedido pedido, VoidCallback onRefresh) async {
  final motivoCtrl = TextEditingController();
  bool procesando = false;
  String? dlgError;

  // El diálogo solo hace la llamada API y se cierra; el refresh de la
  // lista (onRefresh, que dispara un setState de pantalla completa) y el
  // snackbar corren DESPUÉS, cuando el diálogo ya salió del árbol — mezclar
  // el pop de esta ruta con ese setState es lo que causaba el crash
  // "_dependents.isEmpty" / "Duplicate GlobalKeys".
  final anulada = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlg) => AlertDialog(
        title: const Text('Anular venta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('¿Anular la venta ${pedido.idFormateado}?'),
            const SizedBox(height: 12),
            TextField(
              controller: motivoCtrl,
              onChanged: (_) => setDlg(() {}),
              decoration: const InputDecoration(
                hintText: 'Motivo de anulación (requerido)...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Mínimo 5 caracteres (${motivoCtrl.text.trim().length}/5)',
                style: TextStyle(
                  fontSize: 11,
                  color: motivoCtrl.text.trim().length < 5 ? AppColors.error : AppColors.success,
                ),
              ),
            ),
            if (dlgError != null) ...[
              const SizedBox(height: 8),
              Text(dlgError!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: procesando ? null : () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: (motivoCtrl.text.trim().length < 5 || procesando) ? null : () async {
              final motivo = motivoCtrl.text.trim();
              if (contieneEtiquetaHtml(motivo)) {
                setDlg(() => dlgError = mensajeHtml);
                return;
              }
              setDlg(() { procesando = true; dlgError = null; });
              try {
                await ApiService.patch(
                  '/api/ventas/${pedido.id}/anular',
                  {'motivo_anulacion': motivo},
                );
                if (ctx.mounted) Navigator.pop(ctx, true);
              } on ApiException catch (e) {
                setDlg(() { procesando = false; dlgError = e.message; });
              } catch (_) {
                setDlg(() { procesando = false; dlgError = 'Error al anular la venta'; });
              }
            },
            child: procesando
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Anular'),
          ),
        ],
      ),
    ),
  );
  // No se dispone `motivoCtrl` aquí: el diálogo sigue montado unos frames
  // más durante su animación de salida después de que este Future se
  // resuelve, y el TextField ligado a él seguiría intentando usarlo →
  // "A TextEditingController was used after being disposed", que
  // desencadenaba toda la cascada ("_dependents.isEmpty", GlobalKeys
  // duplicadas, etc). Es un controller local de corta vida sin otras
  // referencias, así que no disponerlo no genera una fuga real.
  if (anulada == true) {
    onRefresh();
    if (context.mounted) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Venta anulada')),
      );
    }
  }
}

class VentasScreen extends StatefulWidget {
  const VentasScreen({super.key});

  @override
  State<VentasScreen> createState() => _VentasScreenState();
}

class _VentasScreenState extends State<VentasScreen> {
  bool _loading = true;
  String? _error;
  List<Pedido> _ventas = [];

  String? _filtroEstado;
  String? _filtroMetodoPago;
  String? _filtroFecha;
  final _busquedaCtrl = TextEditingController();
  int _pagina = 1;
  Object _porPagina = 10;

  final _fmt =
      NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);
  final _fmtFecha = DateFormat('dd/MM/yy HH:mm', 'es_CO');

  static const _estados = [
    'pendiente',
    'en_proceso',
    'listo',
    'despachado',
    'entregado',
    'anulado',
  ];

  static const _metodosPago = ['efectivo', 'transferencia', 'mixto'];

  final _fmtFechaDisplay = DateFormat("EEEE d 'de' MMMM", 'es_CO');

  @override
  void initState() {
    super.initState();
    _filtroFecha = DateFormat('yyyy-MM-dd').format(DateTime.now().toUtc().subtract(const Duration(hours: 5)));
    _cargar();
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
    var lista = _ventas;

    // Igual que React: el estado se filtra 100% en el cliente, nunca se
    // manda al backend (evita el reordenamiento que el backend aplica
    // cuando recibe ese filtro).
    if (_filtroEstado != null) {
      lista = lista.where((v) => v.estado == _filtroEstado).toList();
    }

    // El backend (GET /ventas) ignora el query param metodo_pago — hay que
    // filtrar acá igual que React (Ventas.jsx matchMetodo), si no el filtro
    // no filtra nada.
    if (_filtroMetodoPago != null) {
      lista = lista.where((v) => v.estado != 'anulado' && v.metodoPago == _filtroMetodoPago).toList();
    }

    final q = _busquedaCtrl.text.toLowerCase().trim();
    if (q.isEmpty) return lista;
    return lista.where((v) {
      return v.clienteNombre?.toLowerCase().contains(q) == true ||
          v.idFormateado.toLowerCase().contains(q) ||
          v.id.toString().contains(q);
    }).toList();
  }

  void _abrirCrearVenta() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _CrearVentaScreen(onVentaCreada: _cargar)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtradas = _ventasFiltradas;
    final mostrandoTodos = _porPagina == todosPorPagina;
    final porPagina = mostrandoTodos ? filtradas.length : _porPagina as int;
    final totalPaginas = mostrandoTodos || filtradas.isEmpty
        ? 1
        : ((filtradas.length + porPagina - 1) ~/ porPagina);
    final paginaActual = _pagina.clamp(1, totalPaginas);
    final paginadas = mostrandoTodos
        ? filtradas
        : filtradas.skip((paginaActual - 1) * porPagina).take(porPagina).toList();

    return AdminLayout(
      body: Column(
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
                        '${_ventas.length} registro${_ventas.length != 1 ? 's' : ''} en total',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF888888),
                        ),
                      ),
                    ],
                  ),
                ),
                // Igual que React Ventas.jsx:1896 — tienePermiso('gestionar_ventas')
                if (context.watch<AuthProvider>().tienePermiso('gestionar_ventas'))
                  GestureDetector(
                    onTap: _abrirCrearVenta,
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      height: 44,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_rounded,
                                  color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text(
                                'Nueva venta',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  height: 1.0,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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

                // Dropdown estado
                DropdownButtonFormField<String?>(
                  value: _filtroEstado,
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
                    const DropdownMenuItem<String?>(value: null, child: Text('Todos los estados', style: TextStyle(fontSize: 12))),
                    ..._estados.map((e) => DropdownMenuItem<String?>(value: e, child: Text(_labelEstado(e), style: const TextStyle(fontSize: 12)))),
                  ],
                  // El estado se filtra 100% en el cliente (ver _ventasFiltradas):
                  // no hace falta recargar del servidor al cambiarlo.
                  onChanged: (v) => setState(() { _filtroEstado = v; _pagina = 1; }),
                ),
                const SizedBox(height: 6),

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
                  if (_filtroEstado != null || _filtroMetodoPago != null || _filtroFecha != null || _busquedaCtrl.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _filtroEstado     = null;
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
      ),
    );
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
    // Igual que React Ventas.jsx:1971 (editar) y :1981 (anular)
    final auth = context.watch<AuthProvider>();
    final puedeGestionar = auth.tienePermiso('gestionar_ventas');
    final puedeAnular    = auth.tienePermiso('anular_venta');
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
          content: const Text('Volverá a estado Listo para poder editarla antes del despacho.'),
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

    // Mismas condiciones que antes tenía cada _VBtn individual — solo se
    // reorganizan como entradas de un menú overflow en vez de íconos sueltos.
    final mostrarEditar = venta.estado != 'anulado' && puedeGestionar;
    final mostrarDevolver = venta.estado == 'despachado' || venta.estado == 'entregado';
    final mostrarAnular = venta.estado != 'anulado' &&
        venta.estado != 'entregado' &&
        venta.estado != 'despachado' &&
        puedeAnular;

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
          // Antes: hasta 5 _VBtn (ver/editar/imprimir/devolver/anular) en
          // fila apretada. Ahora: tocar la tarjeta = ver detalle (InkWell de
          // arriba); el resto queda en un PopupMenuButton de 3 puntos con
          // area tocable nativa (~48x48), mismas condiciones de antes.
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
                    case 'anular': _anularVentaRapidoDialog(context, venta, onRefresh); break;
                  }
                },
                itemBuilder: (_) => [
                  if (mostrarEditar)
                    const PopupMenuItem(
                      value: 'editar',
                      child: Row(children: [
                        Icon(Icons.edit_outlined, size: 18, color: Color(0xFF666666)),
                        SizedBox(width: 10),
                        Text('Editar'),
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
                  if (mostrarDevolver)
                    const PopupMenuItem(
                      value: 'devolver',
                      child: Row(children: [
                        Icon(Icons.replay_rounded, size: 18, color: Color(0xFFCA8A04)),
                        SizedBox(width: 10),
                        Text('Devolver a listo', style: TextStyle(color: Color(0xFFCA8A04))),
                      ]),
                    ),
                  if (mostrarAnular)
                    const PopupMenuItem(
                      value: 'anular',
                      child: Row(children: [
                        Icon(Icons.close_rounded, size: 18, color: AppColors.error),
                        SizedBox(width: 10),
                        Text('Anular venta', style: TextStyle(color: AppColors.error)),
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
                  // Info cliente — grid compacto igual React ModalDetalle
                  _EstadoDetalleBadge(p.estado),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _DetalleRow('Cliente', p.clienteNombre),
                    if (p.creadoEn != null)
                      _DetalleRow('Fecha', DateFormat('dd/MM/yyyy HH:mm', 'es_CO').format(p.creadoEn!)),
                    _DetalleRow('Teléfono', p.clienteTelefono),
                    _DetalleRow('Pago', p.metodoPago),
                    if (p.nombreDomiciliario != null && p.nombreDomiciliario!.isNotEmpty)
                      _DetalleRow('Domiciliario', p.nombreDomiciliario),
                    if (p.direccionCompleta.isNotEmpty)
                      _DetalleRow('Dirección', p.direccionCompleta, full: true),
                  ]),
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

                  // Observaciones
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

                  // Motivo anulación (igual React ModalDetalle)
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
                            'Hola ${p.clienteNombre ?? ''}, tu pedido ${p.idFormateado} de ChocoFreseo ya está confirmado y en preparación 🍫🍦',
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
                if (widget.pedido.idBarrio != null && !_overrideDomicilio) ...[
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
                ] else if (widget.pedido.idBarrio != null && _overrideDomicilio) ...[
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

// ─────────────────────────────────────────────────────────────────────────────
// Modal: Crear venta manual (3 pasos)
// ─────────────────────────────────────────────────────────────────────────────

class _CarritoItemCreate {
  final String lineaId;
  final int idProducto;
  final String nombre;
  final String? imagen;
  final double precioBase;
  int cantidad;
  final List<Map<String, dynamic>> rawToppings;
  final List<Map<String, dynamic>> rawAdiciones;
  final List<String> salsas;
  final String? chocolate;
  final bool esBowl;
  final int maxToppings;
  final double cargoExtra;

  _CarritoItemCreate({
    required this.lineaId,
    required this.idProducto,
    required this.nombre,
    this.imagen,
    required this.precioBase,
    this.cantidad = 1,
    this.rawToppings = const [],
    this.rawAdiciones = const [],
    this.salsas = const [],
    this.chocolate,
    this.esBowl = false,
    this.maxToppings = 0,
    required this.cargoExtra,
  });

  double get costoAdicionesTotal => rawAdiciones.fold(
    0.0,
    (s, a) => s + ((a['precio'] as num?)?.toDouble() ?? 0.0) * ((a['cantidad'] as num?)?.toInt() ?? 1),
  );
  double get precioUnitario => precioBase + cargoExtra + costoAdicionesTotal;
  double get subtotal => precioUnitario * cantidad;
}

class _CrearVentaScreen extends StatefulWidget {
  final VoidCallback onVentaCreada;

  const _CrearVentaScreen({required this.onVentaCreada});

  @override
  State<_CrearVentaScreen> createState() => _CrearVentaScreenState();
}

class _CrearVentaScreenState extends State<_CrearVentaScreen> {
  int _paso = 0;

  // Cliente search — igual que React: se carga la lista completa una sola
  // vez y se filtra en memoria (nombre/email/teléfono), sin repetir la
  // consulta a la API en cada tecla.
  final _busquedaCtrl = TextEditingController();
  int? _clienteId;
  String _clienteNombre = '';
  List<Map<String, dynamic>> _resultados = [];
  List<Map<String, dynamic>> _todosClientes = [];
  bool _buscando = false;

  // Dirección del cliente
  int? _direccionId;
  List<Map<String, dynamic>> _direcciones = [];
  bool _cargandoDirs = false;
  bool _nuevaDireccion = false;
  // Valor compartido con el widget FormDireccion (mismo patrón que Checkout)
  Map<String, dynamic> _dirFormValue = {};

  final List<_CarritoItemCreate> _carritoItems = [];
  int? _filtroCategoriaCreate;
  String _busqProdCreate = '';
  final _busqProdCreateCtrl = TextEditingController();

  String _metodoPago = 'efectivo';
  double _montoEfectivo = 0;
  double _montoTransfer = 0;
  final _efMixtoCtrl = TextEditingController();
  final _trMixtoCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();

  // Puntos fidelidad (igual React Ventas.jsx paso 3)
  int  _puntosCliente = 0;
  int  _puntosAplicar = 0;
  bool _usarPuntos    = false;

  // Costo domicilio calculado dinámicamente
  double _costoDomicilio    = 5500;
  bool   _calculandoCosto   = false;
  bool   _overrideDomicilio = false;
  final _costoCtrl = TextEditingController(text: '5500');

  bool _guardando = false;
  String? _errorCrear;

  final _fmt =
      NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _cargarTodosClientes();
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    _busqProdCreateCtrl.dispose();
    _observacionesCtrl.dispose();
    _costoCtrl.dispose();
    _efMixtoCtrl.dispose();
    _trMixtoCtrl.dispose();
    super.dispose();
  }

  String _buildDireccionLinea() => _dirFormValue['direccion_linea']?.toString() ?? '';

  Future<void> _cargarTodosClientes() async {
    try {
      final data = await ApiService.get('/api/clientes');
      List raw = data is List ? data : (data is Map && data['data'] is List ? data['data'] as List : []);
      if (mounted) setState(() => _todosClientes = raw.cast<Map<String, dynamic>>());
    } catch (_) {
      _todosClientes = [];
    }
  }

  Future<void> _buscarClientes(String q) async {
    if (q.trim().length < 2) {
      setState(() => _resultados = []);
      return;
    }
    setState(() => _buscando = true);
    try {
      final lower = q.trim().toLowerCase();
      setState(() => _resultados = _todosClientes.where((c) {
        final u = c['usuario'] is Map ? c['usuario'] as Map : null;
        final nombre = u?['nombre']?.toString().toLowerCase() ?? '';
        final email = u?['email']?.toString().toLowerCase() ?? '';
        final telefono = c['telefono']?.toString() ?? '';
        return nombre.contains(lower) || email.contains(lower) || telefono.contains(q.trim());
      }).take(8).toList());
    } catch (_) {
      setState(() => _resultados = []);
    }
    setState(() => _buscando = false);
  }

  int get _maxPuntos {
    final max = (_totalCarrito / 12.5).floor();
    final limit = max < _puntosCliente ? max : _puntosCliente;
    return (limit ~/ 8) * 8;
  }
  int get _puntosAplicarEfectivo => _puntosAplicar < _maxPuntos ? _puntosAplicar : _maxPuntos;
  double get _descuentoPuntos => _usarPuntos ? _puntosAplicarEfectivo * 12.5 : 0;

  Future<void> _cargarPuntosCliente(int id) async {
    try {
      final data = await ApiService.get('/api/puntos/cliente/$id');
      final inner = data is Map && data['data'] is Map ? data['data'] as Map : (data is Map ? data : <String, dynamic>{});
      final pts = int.tryParse((inner['puntos'] ?? inner['total_puntos'] ?? 0).toString()) ?? 0;
      if (mounted) setState(() { _puntosCliente = pts; _puntosAplicar = 0; _usarPuntos = false; });
    } catch (_) {
      if (mounted) setState(() { _puntosCliente = 0; _puntosAplicar = 0; _usarPuntos = false; });
    }
  }

  Future<void> _cargarDirecciones(int clienteId) async {
    setState(() { _cargandoDirs = true; _direcciones = []; _direccionId = null; });
    try {
      final data = await ApiService.get('/api/clientes/$clienteId/direcciones');
      final List raw = data is List ? data : (data is Map && data['data'] is List ? data['data'] as List : []);
      if (mounted) {
        setState(() {
          _direcciones = raw
              .cast<Map<String, dynamic>>()
              .where((d) => d['estado'] != 0)
              .toList();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _direcciones = []);
    }
    if (mounted) setState(() => _cargandoDirs = false);
  }

  Future<void> _calcularCostoDomicilio(int? id) async {
    if (id == null) return;
    final dir = _direcciones.firstWhere(
      (d) => (d['id_direccion'] ?? d['id']) == id,
      orElse: () => {},
    );

    // Igual que React: si la dirección tiene barrio del catálogo, su precio
    // real manda — nunca se debe depender de lat/lng (la mayoría de
    // direcciones ya no las tienen desde la migración a barrios).
    final barrioRel = dir['barrioRel'];
    final precioBarrio = barrioRel is Map ? barrioRel['precio_domicilio'] : null;
    final precio = precioBarrio ?? dir['costo_domicilio'];
    if (precio != null) {
      final costo = double.tryParse(precio.toString()) ?? 5500;
      if (mounted) setState(() { _costoDomicilio = costo; _costoCtrl.text = costo.round().toString(); });
      return;
    }

    final lat = dir['lat'];
    final lng = dir['lng'];
    if (lat == null || lng == null) return;
    setState(() => _calculandoCosto = true);
    try {
      final data = await ApiService.post('/api/domicilio/calcular', {
        'lat': lat,
        'lng': lng,
        'ciudad': dir['ciudad']?.toString() ?? '',
      });
      final inner = data is Map && data['data'] is Map ? data['data'] as Map : (data is Map ? data : <String, dynamic>{});
      final costo = double.tryParse((inner['costo_domicilio'] ?? 5500).toString()) ?? 5500;
      if (mounted) setState(() { _costoDomicilio = costo; _costoCtrl.text = costo.round().toString(); _calculandoCosto = false; });
    } catch (_) {
      if (mounted) setState(() => _calculandoCosto = false);
    }
  }

  double get _totalCarrito =>
      _carritoItems.fold(0.0, (s, item) => s + item.subtotal);

  Future<void> _crear() async {
    setState(() {
      _guardando = true;
      _errorCrear = null;
    });

    try {
      if (_clienteId == null) {
        if (mounted) setState(() { _errorCrear = 'Selecciona un cliente'; _guardando = false; });
        return;
      }

      final items = _carritoItems.map((item) => {
        'id_producto':  item.idProducto,
        'cantidad':     item.cantidad,
        'max_toppings': item.maxToppings,
        'toppings':     item.rawToppings.map((t) => {'id_topping': t['id_topping'], 'cantidad': t['cantidad'] ?? 1}).toList(),
        'adiciones':    item.rawAdiciones.map((a) => {'id_adicion': a['id_adicion'], 'cantidad': a['cantidad'] ?? 1}).toList(),
        if (item.salsas.isNotEmpty) 'salsas':    item.salsas,
        if (item.chocolate != null) 'chocolate': item.chocolate,
      }).toList();

      // Validate mixto amounts — deben ser ambos > 0 y sumar exactamente el
      // total (igual que _mixtoOk en editar venta).
      final totalActual = _totalCarrito + _costoDomicilio - _descuentoPuntos;
      final mixtoCuadra = _montoEfectivo > 0 &&
          _montoTransfer > 0 &&
          (_montoEfectivo + _montoTransfer - totalActual).abs() < 1;
      if (_metodoPago == 'mixto' && !mixtoCuadra) {
        if (mounted) {
          setState(() {
            _errorCrear = 'Para pago mixto ingresa los montos de efectivo y transferencia';
            _guardando = false;
          });
        }
        return;
      }

      final totalFinal = _totalCarrito + _costoDomicilio - _descuentoPuntos;
      final body = <String, dynamic>{
        'id_cliente': _clienteId,
        'costo_domicilio': _costoDomicilio.round(),
        'override_costo_domicilio': _overrideDomicilio,
        'items': items,
        'puntos_usados': _usarPuntos ? _puntosAplicarEfectivo : 0,
        'metodo_pago': _metodoPago,
      };
      // Payment amounts — match React crearVenta payload
      if (_metodoPago == 'efectivo') {
        body['monto_efectivo'] = totalFinal.round();
      } else if (_metodoPago == 'transferencia') {
        body['monto_transferencia'] = totalFinal.round();
      } else if (_metodoPago == 'mixto') {
        body['monto_efectivo'] = _montoEfectivo.round();
        body['monto_transferencia'] = _montoTransfer.round();
      }
      // Dirección: saved vs. nueva
      if (_nuevaDireccion) {
        final dl = _buildDireccionLinea();
        if (dl.isNotEmpty) {
          String? sv(String k) {
            final v = _dirFormValue[k]?.toString().trim() ?? '';
            return v.isNotEmpty ? v : null;
          }
          body['nueva_direccion'] = {
            'direccion_linea': dl,
            'barrio':          sv('barrio'),
            'ciudad':          sv('ciudad'),
            'departamento':    'Antioquia',
            'referencia':      sv('referencia'),
            'id_barrio':       _dirFormValue['id_barrio'],
          };
        }
      } else if (_direccionId != null) {
        body['id_direccion'] = _direccionId;
      }
      // Observaciones (separate from address)
      if (_observacionesCtrl.text.trim().isNotEmpty) {
        body['observaciones'] = _observacionesCtrl.text.trim();
      }
      await ApiService.post('/api/ventas', body);

      if (mounted) {
        Navigator.pop(context);
        widget.onVentaCreada();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Venta creada exitosamente'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorCrear = e.message);
    } catch (_) {
      if (mounted) setState(() => _errorCrear = 'Error al crear la venta');
    }

    if (mounted) setState(() => _guardando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Nueva venta manual'),
      ),
      body: Column(
        children: [
          // Stepper
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.screenPadding),
            child: Row(
              children: List.generate(3, (i) {
                final labels = ['Cliente y dirección', 'Productos', 'Pago y resumen'];
                final active = i == _paso;
                final done = i < _paso;
                return Expanded(
                  child: Row(
                    children: [
                      if (i > 0)
                        Expanded(
                          child: Container(
                            height: 2,
                            color: done
                                ? AppColors.primary
                                : AppColors.border,
                          ),
                        ),
                      Column(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: active || done
                                  ? AppColors.primary
                                  : AppColors.surfaceVariant,
                              shape: BoxShape.circle,
                            ),
                            child: done
                                ? const Icon(Icons.check_rounded,
                                    size: 14, color: Colors.white)
                                : Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: active
                                          ? Colors.white
                                          : AppColors.textSecondary,
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            labels[i],
                            style: TextStyle(
                              fontSize: 10,
                              color: active
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                              fontWeight: active
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),

          const Divider(height: 20),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSizes.screenPadding),
              child: [_paso0, _paso1, _paso2][_paso](),
            ),
          ),

          Padding(
            padding: EdgeInsets.only(
              left: AppSizes.screenPadding,
              right: AppSizes.screenPadding,
              bottom:
                  MediaQuery.of(context).viewInsets.bottom + AppSizes.md,
            ),
            child: Row(
              children: [
                if (_paso > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _paso--),
                      child: const Text('Atrás'),
                    ),
                  ),
                if (_paso > 0) const SizedBox(width: AppSizes.sm),
                Expanded(
                  flex: 2,
                  child: AppButton(
                    label: _paso == 2 ? 'Crear venta' : 'Siguiente',
                    isLoading: _guardando,
                    onPressed: _paso == 2 ? _crear : _siguiente,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _siguiente() {
    if (_paso == 0 && _clienteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un cliente de la lista')),
      );
      return;
    }
    if (_paso == 0) {
      final tieneDireccion = _nuevaDireccion
          ? _buildDireccionLinea().trim().isNotEmpty
          : _direccionId != null;
      if (!tieneDireccion) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecciona o registra una dirección')),
        );
        return;
      }
    }
    if (_paso == 1 && _carritoItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega al menos un producto')),
      );
      return;
    }
    setState(() => _paso++);
  }

  Widget _paso0() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Datos del cliente',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: AppSizes.md),

        // Selected client chip
        if (_clienteId != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_clienteNombre,
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary))),
                if (_puntosCliente > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDBEAFE),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('🎯 $_puntosCliente pts',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1D4ED8))),
                  ),
                  const SizedBox(width: 6),
                ],
                GestureDetector(
                  onTap: () => setState(() {
                    _clienteId = null; _clienteNombre = '';
                    _busquedaCtrl.clear(); _direcciones = [];
                    _dirFormValue = {};
                    _direccionId = null; _nuevaDireccion = false;
                    _puntosCliente = 0; _puntosAplicar = 0; _usarPuntos = false;
                    _costoDomicilio = 5500; _costoCtrl.text = '5500';
                    _montoEfectivo = 0; _montoTransfer = 0;
                  }),
                  child: const Icon(Icons.close, size: 18, color: AppColors.primary),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.sm),
        ],

        TextField(
          controller: _busquedaCtrl,
          onChanged: _buscarClientes,
          decoration: InputDecoration(
            labelText: _clienteId != null ? 'Cambiar cliente' : 'Buscar cliente *',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _buscando ? const SizedBox(width: 16, height: 16, child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))) : null,
          ),
        ),
        // Search results
        if (_resultados.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
              boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: Column(
              children: _resultados.map((c) {
                final u = c['usuario'] is Map ? c['usuario'] as Map : null;
                final nombre = u?['nombre']?.toString() ?? '-';
                final email = u?['email']?.toString() ?? '';
                final id = c['id_cliente'] as int? ?? 0;
                return InkWell(
                  onTap: () {
                    setState(() {
                      _clienteId = id;
                      _clienteNombre = nombre;
                      _busquedaCtrl.clear();
                      _resultados = [];
                      _nuevaDireccion = false;
                    });
                    _cargarDirecciones(id);
                    _cargarPuntosCliente(id);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(children: [
                      const Icon(Icons.person_outline_rounded, size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(nombre, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        if (email.isNotEmpty) Text(email, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      ])),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ),
        ],

        const SizedBox(height: AppSizes.sm),

        // ── Dirección (igual React: guardada / nueva) ──────────────
        if (_clienteId != null) ...[
          if (_cargandoDirs)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
            )
          else ...[
            // Toggle Dirección guardada / Nueva dirección
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() { _nuevaDireccion = false; _overrideDomicilio = false; }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: !_nuevaDireccion ? AppColors.primary : AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.primary),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Dirección guardada',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: !_nuevaDireccion ? Colors.white : AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() { _nuevaDireccion = true; _overrideDomicilio = false; }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: _nuevaDireccion ? AppColors.primary : AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.primary),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Nueva dirección',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _nuevaDireccion ? Colors.white : AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSizes.sm),
            if (!_nuevaDireccion) ...[
              if (_direcciones.isEmpty)
                const Text(
                  'Sin direcciones guardadas',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                )
              else
                Column(
                  children: _direcciones.map((d) {
                    final id = d['id_direccion'] as int?;
                    final linea = d['direccion_linea']?.toString() ?? '';
                    final barrio = d['barrio']?.toString() ?? '';
                    final ciudad = d['ciudad']?.toString() ?? '';
                    final referencia = d['referencia']?.toString() ?? '';
                    final isSelected = _direccionId == id;
                    final sub = [barrio, ciudad].where((s) => s.isNotEmpty).join(', ');
                    return GestureDetector(
                      onTap: () {
                        setState(() { _direccionId = id; _overrideDomicilio = false; });
                        _calcularCostoDomicilio(id);
                      },
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFFFF5F5) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? AppColors.primary : const Color(0xFFE5E7EB),
                            width: 2,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(linea, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            if (sub.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(sub, style: const TextStyle(fontSize: 11, color: Color(0xFF888888))),
                              ),
                            if (referencia.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(referencia, style: const TextStyle(fontSize: 11, color: Color(0xFF888888))),
                              ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
            ] else
              FormDireccion(
                value: _dirFormValue,
                onChange: (field, value) {
                  setState(() => _dirFormValue = {..._dirFormValue, field: value});
                  // Igual que Checkout: el costo ya viene directo del barrio elegido.
                  if (field == 'costo_domicilio') {
                    final costo = (value as num?)?.toDouble() ?? 0.0;
                    setState(() { _costoDomicilio = costo; _costoCtrl.text = costo.round().toString(); _overrideDomicilio = false; });
                  }
                },
                errors: const {},
                isClient: false,
              ),
          ],
        ],
        const SizedBox(height: AppSizes.sm),
        Builder(builder: (context) {
          // Igual que en editar venta: si la dirección tiene barrio del
          // catálogo, el backend fuerza Barrio.precio_domicilio y descarta
          // cualquier valor manual sin avisar — no se debe dejar editar.
          final tieneBarrio = _nuevaDireccion
              ? _dirFormValue['id_barrio'] != null
              : _direcciones.any((d) => (d['id_direccion'] == _direccionId) && d['id_barrio'] != null);
          return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(
              children: [
                const Text(
                  'Costo domicilio \$',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF555555)),
                ),
                const SizedBox(width: 10),
                if (_calculandoCosto)
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                else if (tieneBarrio && !_overrideDomicilio)
                  Expanded(child: Text(_fmt.format(_costoDomicilio), style: const TextStyle(fontWeight: FontWeight.w700)))
                else
                  Expanded(
                    child: TextField(
                      controller: _costoCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      onChanged: (v) => setState(() => _costoDomicilio = double.tryParse(v) ?? 0),
                    ),
                  ),
              ],
            ),
            if (tieneBarrio && !_overrideDomicilio) Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                const Expanded(child: Text('Precio fijado por el barrio del catálogo', style: TextStyle(fontSize: 11, color: Color(0xFF888888)))),
                GestureDetector(
                  onTap: () => setState(() => _overrideDomicilio = true),
                  child: const Text('Cambiar precio manualmente', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary, decoration: TextDecoration.underline)),
                ),
              ]),
            ),
            if (tieneBarrio && _overrideDomicilio) const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Precio manual — distinto al del barrio del catálogo', style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
            ),
          ]),
          );
        }),
      ],
    );
  }

  Widget _paso1() {
    return Consumer<CatalogoProvider>(
      builder: (context, catalogo, _) {
        if (catalogo.loading) {
          WidgetsBinding.instance.addPostFrameCallback((_) => catalogo.cargarTodo());
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        }
        if (catalogo.productosFiltrados.isEmpty && !catalogo.loading) {
          WidgetsBinding.instance.addPostFrameCallback((_) => catalogo.cargarTodo());
        }

        final todasCategorias = catalogo.categorias;
        final mostrar = _filtroCategoriaCreate != null || _busqProdCreate.trim().length >= 2;
        final productosFiltrados = catalogo.productosFiltrados.where((p) {
          if (_busqProdCreate.trim().isNotEmpty) {
            return p.nombre.toLowerCase().contains(_busqProdCreate.toLowerCase());
          }
          if (_filtroCategoriaCreate != null) return p.idCategoria == _filtroCategoriaCreate;
          return true;
        }).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Seleccionar productos',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: AppSizes.sm),

            // Categoría + buscador
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<int?>(
                  value: _filtroCategoriaCreate,
                  isDense: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Categoría...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: Color(0xFFE5E7EB))),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Todas...', style: TextStyle(fontSize: 12))),
                    ...todasCategorias.map((c) => DropdownMenuItem<int?>(value: c.id, child: Text(c.nombre, style: const TextStyle(fontSize: 12)))),
                  ],
                  onChanged: (v) => setState(() => _filtroCategoriaCreate = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _busqProdCreateCtrl,
                  onChanged: (v) => setState(() => _busqProdCreate = v),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Buscar...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    suffixIcon: _busqProdCreate.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            onPressed: () { _busqProdCreateCtrl.clear(); setState(() => _busqProdCreate = ''); })
                        : null,
                    border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
                    enabledBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: Color(0xFFE5E7EB))),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: AppSizes.sm),

            // Grid de productos
            if (!mostrar)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: Text('Selecciona una categoría o busca un producto',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary), textAlign: TextAlign.center)),
              )
            else if (productosFiltrados.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('No hay productos', style: TextStyle(fontSize: 13, color: AppColors.textSecondary))),
              )
            else ...[
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.75,
                ),
                itemCount: productosFiltrados.length,
                itemBuilder: (gctx, idx) {
                  final prod = productosFiltrados[idx];
                  final unidades = _carritoItems
                      .where((i) => i.idProducto == prod.id)
                      .fold(0, (s, i) => s + i.cantidad);
                  return GestureDetector(
                    onTap: () async {
                      // Igual que React (Ventas.jsx) y el catálogo cliente: el modal
                      // SIEMPRE se abre, sin importar los flags — su propio `_pasos`
                      // decide qué secciones mostrar y siempre incluye "adiciones" como
                      // paso final, incluso para productos sin ningún permite_X activo.
                      final result = await showModalBottomSheet<ModalProductoResult>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => ToppingsModal(
                          allToppings: catalogo.toppings,
                          allAdiciones: catalogo.adiciones,
                          producto: prod,
                        ),
                      );
                      if (result == null || !mounted) return;
                      final salsas = result.salsas.map((s) => (s['nombre'] ?? s['id'] ?? '').toString()).where((s) => s.isNotEmpty).toList();
                      final rawTop = result.toppings.map((t) => <String, dynamic>{'id_topping': t.id, 'nombre': t.nombre, 'cantidad': 1}).toList();
                      final rawAdi = result.adiciones.map((a) => <String, dynamic>{'id_adicion': a.id, 'nombre': a.nombre, 'precio': a.precio, 'cantidad': 1}).toList();
                      final chocolate = result.tipoChocolate;
                      final cargoExtra = result.cargoExtra;
                      // Misma config → incrementa cantidad
                      final sameIdx = _carritoItems.indexWhere((i) {
                        if (i.idProducto != prod.id) return false;
                        if ((i.chocolate ?? '') != (chocolate ?? '')) return false;
                        final topA = i.rawToppings.map((t) => t['id_topping']).toList()..sort();
                        final topB = rawTop.map((t) => t['id_topping']).toList()..sort();
                        if (topA.join(',') != topB.join(',')) return false;
                        final salA = List<String>.from(i.salsas)..sort();
                        final salB = List<String>.from(salsas)..sort();
                        return salA.join(',') == salB.join(',');
                      });
                      setState(() {
                        if (sameIdx >= 0) {
                          _carritoItems[sameIdx].cantidad++;
                        } else {
                          _carritoItems.add(_CarritoItemCreate(
                            lineaId: '${DateTime.now().microsecondsSinceEpoch}',
                            idProducto: prod.id,
                            nombre: prod.nombre,
                            imagen: prod.imagen,
                            precioBase: prod.precio,
                            cantidad: 1,
                            rawToppings: rawTop,
                            rawAdiciones: rawAdi,
                            salsas: salsas,
                            chocolate: chocolate,
                            esBowl: prod.esBowl,
                            maxToppings: prod.maxToppings,
                            cargoExtra: cargoExtra,
                          ));
                        }
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: unidades > 0 ? const Color(0xFFFFF5F5) : Colors.white,
                        border: Border.all(
                          color: unidades > 0 ? AppColors.primary : const Color(0xFFE5E7EB),
                          width: unidades > 0 ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(children: [
                        Expanded(
                          flex: 3,
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                            child: prod.imagen != null && prod.imagen!.isNotEmpty
                                ? CachedNetworkImage(imageUrl: prod.imagen!, fit: BoxFit.cover, width: double.infinity,
                                    errorWidget: (_, __, ___) => _prodPlaceholder(prod.nombre))
                                : _prodPlaceholder(prod.nombre),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Text(prod.nombre,
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                                  maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                              Text(_fmt.format(prod.precio),
                                  style: const TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.w700)),
                              if (unidades > 0)
                                Container(
                                  margin: const EdgeInsets.only(top: 1),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
                                  child: Text('$unidades', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                                ),
                            ]),
                          ),
                        ),
                      ]),
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSizes.sm),
            ],

            // Lista del carrito
            if (_carritoItems.isNotEmpty) ...[
              const Divider(height: 20),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(
                    'Carrito (${_carritoItems.fold(0, (s, i) => s + i.cantidad)} uds.)',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary),
                  ),
                  Text(_fmt.format(_totalCarrito),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.primary)),
                ]),
              ),
              ..._carritoItems.map((item) => _buildCartItemCreate(item)),
            ],
          ],
        );
      },
    );
  }

  Widget _prodPlaceholder(String nombre) => Container(
    color: const Color(0xFFF0F0F0),
    child: Center(child: Text(
      nombre.isNotEmpty ? nombre[0].toUpperCase() : '?',
      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: Color(0xFFAAAAAA)),
    )),
  );

  Widget _buildCartItemCreate(_CarritoItemCreate item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        border: Border.all(color: const Color(0xFFF0F0F0)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(item.nombre,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
          Row(children: [
            GestureDetector(
              onTap: () => setState(() {
                if (item.cantidad <= 1) {
                  _carritoItems.remove(item);
                } else {
                  item.cantidad--;
                }
              }),
              child: Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: item.cantidad <= 1 ? const Color(0xFFFEE2E2) : const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(item.cantidad <= 1 ? Icons.close_rounded : Icons.remove_rounded,
                    size: 14, color: item.cantidad <= 1 ? AppColors.primary : AppColors.textPrimary),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('${item.cantidad}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            ),
            GestureDetector(
              onTap: () => setState(() => item.cantidad++),
              child: Container(
                width: 22, height: 22,
                decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(4)),
                child: const Icon(Icons.add_rounded, size: 14),
              ),
            ),
          ]),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            '${_fmt.format(item.precioUnitario)} c/u → ${_fmt.format(item.subtotal)}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF888888)),
          ),
        ),
        _buildCartChipsCreate(item),
      ]),
    );
  }

  Widget _buildCartChipsCreate(_CarritoItemCreate item) {
    final chips = <Widget>[];
    if (item.chocolate != null) {
      chips.add(_VentaChip(
        label: item.esBowl
            ? 'Cobertura: ${item.chocolate!}'
            : '${item.chocolate! == 'Negro' ? '🍫' : '⬜'} Chocolate ${item.chocolate!}',
        bg: item.chocolate! == 'Negro' ? const Color(0xFF1E3A5F) : const Color(0xFFF0F0F0),
        fg: item.chocolate! == 'Negro' ? Colors.white : const Color(0xFF555555),
      ));
    }
    if (item.esBowl && item.salsas.isNotEmpty) {
      chips.add(_VentaChip(
        label: 'Cobertura: ${_nombreSalsa(item.salsas.first)}',
        bg: const Color(0xFFFEF3C7),
        fg: const Color(0xFF92400E),
        outlined: true,
        outlineColor: const Color(0xFFD97706),
      ));
    }
    if (!item.esBowl) {
      for (final s in item.salsas) {
        chips.add(_VentaChip(
          label: _nombreSalsa(s),
          outlined: true,
          outlineColor: const Color(0xFFEA580C),
          fg: const Color(0xFFEA580C),
          bg: const Color(0xFFFFF7ED),
        ));
      }
    }
    for (final t in item.rawToppings) {
      final nombre = t['nombre']?.toString() ?? '';
      if (nombre.isNotEmpty) chips.add(_VentaChip(label: nombre, bg: const Color(0xFF1A1A1A), fg: Colors.white));
    }
    for (final a in item.rawAdiciones) {
      final nombre = a['nombre']?.toString() ?? '';
      if (nombre.isNotEmpty) chips.add(_VentaChip(label: '+$nombre', bg: const Color(0xFFFEF3C7), fg: const Color(0xFFD97706)));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(spacing: 4, runSpacing: 3, children: chips),
    );
  }

  Widget _paso2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Confirmar y pagar',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: AppSizes.md),

        Container(
          padding: const EdgeInsets.all(AppSizes.md),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
          child: Column(
            children: [
              ..._carritoItems.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${item.cantidad}x ${item.nombre}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Text(
                          _fmt.format(item.subtotal),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  )),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Domicilio', style: TextStyle(fontSize: 13)),
                  _calculandoCosto
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                      : Text(_fmt.format(_costoDomicilio), style: const TextStyle(fontSize: 13)),
                ]),
              ),
              if (_usarPuntos && _puntosAplicarEfectivo > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Descuento ($_puntosAplicarEfectivo pts)',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF16A34A), fontWeight: FontWeight.w700)),
                    Text('− ${_fmt.format(_descuentoPuntos)}',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF16A34A), fontWeight: FontWeight.w700)),
                  ]),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('TOTAL',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    _fmt.format(_totalCarrito + _costoDomicilio - _descuentoPuntos),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Puntos de fidelidad (igual React Ventas.jsx paso 3)
        if (_puntosCliente > 0) ...[
          const SizedBox(height: AppSizes.md),
          Container(
            padding: const EdgeInsets.all(AppSizes.md),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              border: Border.all(color: const Color(0xFFBFDBFE)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Puntos de fidelidad',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1D4ED8))),
                Text('$_puntosCliente pts = \$${(_puntosCliente * 12.5).toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.')}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF1D4ED8), fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => setState(() {
                  _usarPuntos = !_usarPuntos;
                  _puntosAplicar = _usarPuntos ? _maxPuntos : 0;
                }),
                child: Row(children: [
                  Container(
                    width: 18, height: 18,
                    decoration: BoxDecoration(
                      color: _usarPuntos ? const Color(0xFF1D4ED8) : Colors.white,
                      border: Border.all(color: const Color(0xFF1D4ED8)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: _usarPuntos ? const Icon(Icons.check_rounded, size: 13, color: Colors.white) : null,
                  ),
                  const SizedBox(width: 8),
                  const Text('Usar puntos en este pedido',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1D4ED8))),
                ]),
              ),
              if (_usarPuntos && _maxPuntos > 0) ...[
                const SizedBox(height: 8),
                Slider(
                  value: _puntosAplicar.toDouble(),
                  min: 0, max: _maxPuntos.toDouble(), divisions: _maxPuntos ~/ 8,
                  activeColor: AppColors.primary,
                  onChanged: (v) => setState(() => _puntosAplicar = (v ~/ 8) * 8),
                ),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('$_puntosAplicarEfectivo pts aplicados',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF1D4ED8))),
                  Text('− ${_fmt.format(_descuentoPuntos)}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF16A34A))),
                ]),
              ],
            ]),
          ),
        ],

        const SizedBox(height: AppSizes.md),
        const Text('Método de pago',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSizes.sm),

        Row(
          children: [
            _PagoChip(
                label: 'Efectivo',
                icon: Icons.payments_outlined,
                selected: _metodoPago == 'efectivo',
                onTap: () => setState(() {
                      _metodoPago = 'efectivo';
                      _montoEfectivo = 0;
                      _montoTransfer = 0;
                      _efMixtoCtrl.clear();
                      _trMixtoCtrl.clear();
                    })),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() {
                  _metodoPago = 'transferencia';
                  _montoEfectivo = 0;
                  _montoTransfer = 0;
                  _efMixtoCtrl.clear();
                  _trMixtoCtrl.clear();
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: _metodoPago == 'transferencia'
                        ? AppColors.primary.withValues(alpha: 0.08)
                        : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    border: Border.all(
                      color: _metodoPago == 'transferencia' ? AppColors.primary : Colors.transparent,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        CachedNetworkImage(
                          imageUrl: 'https://res.cloudinary.com/diqeuyoqo/image/upload/v1779736112/bancolombia_wiytke.png',
                          width: 18, height: 18, fit: BoxFit.contain,
                          errorWidget: (_, __, ___) => const Icon(Icons.account_balance_outlined, size: 18),
                        ),
                        const SizedBox(width: 4),
                        CachedNetworkImage(
                          imageUrl: 'https://res.cloudinary.com/diqeuyoqo/image/upload/v1779736049/nequi_pfgazy.png',
                          width: 18, height: 18, fit: BoxFit.contain,
                          errorWidget: (_, __, ___) => const Icon(Icons.account_balance_outlined, size: 18),
                        ),
                      ]),
                      const SizedBox(height: 2),
                      Text('Transferencia',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _metodoPago == 'transferencia' ? AppColors.primary : AppColors.textSecondary,
                          )),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            _PagoChip(
                label: 'Mixto',
                icon: Icons.sync_alt_rounded,
                selected: _metodoPago == 'mixto',
                onTap: () => setState(() {
                      _metodoPago = 'mixto';
                      _montoEfectivo = 0;
                      _montoTransfer = 0;
                      _efMixtoCtrl.clear();
                      _trMixtoCtrl.clear();
                    })),
          ],
        ),

        // ── Mixto: montos individuales (igual React paso 3) ──────────────────
        if (_metodoPago == 'mixto') ...[
          const SizedBox(height: 10),
          Builder(builder: (context) {
            final total = _totalCarrito + _costoDomicilio - _descuentoPuntos;
            final suma = _montoEfectivo + _montoTransfer;
            final cuadra = _montoEfectivo > 0 &&
                _montoTransfer > 0 &&
                (suma - total).abs() < 1;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Efectivo', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _efMixtoCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        hintText: '0',
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => _aplicarPagoMixto(
                        raw: v,
                        total: total,
                        ctrlEditado: _efMixtoCtrl,
                        ctrlComplemento: _trMixtoCtrl,
                        onCalculado: (ef, tr) => setState(() {
                          _montoEfectivo = ef;
                          _montoTransfer = tr;
                        }),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Transferencia', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _trMixtoCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        hintText: '0',
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => _aplicarPagoMixto(
                        raw: v,
                        total: total,
                        ctrlEditado: _trMixtoCtrl,
                        ctrlComplemento: _efMixtoCtrl,
                        onCalculado: (tr, ef) => setState(() {
                          _montoTransfer = tr;
                          _montoEfectivo = ef;
                        }),
                      ),
                    ),
                  ]),
                ),
              ]),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: cuadra ? const Color(0xFFF0FDF4) : const Color(0xFFFFF5F5),
                  border: Border.all(
                      color: cuadra ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(
                    cuadra ? '✓ Pago completo' : 'Pago incompleto',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: cuadra ? const Color(0xFF166534) : AppColors.primary),
                  ),
                  Text(
                    '\$${suma.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.')} / \$${total.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.')}',
                    style: TextStyle(
                        fontSize: 12,
                        color: cuadra ? const Color(0xFF166534) : AppColors.primary),
                  ),
                ]),
              ),
            ]);
          }),
        ],

        // ── Observaciones (igual React paso 3) ───────────────────────────────
        const SizedBox(height: 12),
        const Text('Observaciones (opcional)',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          controller: _observacionesCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Instrucciones especiales para el pedido...',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.all(10),
          ),
        ),

        if (_errorCrear != null) ...[
          const SizedBox(height: AppSizes.sm),
          Container(
            padding: const EdgeInsets.all(AppSizes.sm),
            decoration: BoxDecoration(
              color: AppColors.errorLight,
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
            child: Text(_errorCrear!,
                style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ],
    );
  }
}

class _PagoChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _PagoChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.08)
                : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            border: Border.all(
              color: selected ? AppColors.primary : Colors.transparent,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  size: 18,
                  color: selected
                      ? AppColors.primary
                      : AppColors.textSecondary),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _nombreSalsa(String s) => s.replaceAll('_', ' ').replaceAllMapped(
    RegExp(r'\b\w'), (m) => m.group(0)!.toUpperCase());
