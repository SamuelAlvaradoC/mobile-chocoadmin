import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/models/pedido.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/layouts/domiciliario_layout.dart';
import '../../../shared/widgets/brand_icons.dart';

class PedidosScreen extends StatefulWidget {
  const PedidosScreen({super.key});
  @override
  State<PedidosScreen> createState() => _PedidosScreenState();
}

class _PedidosScreenState extends State<PedidosScreen> {
  bool _loading = false;
  bool _procesando = false;
  List<Pedido> _porDespachar = [];
  List<Pedido> _despachados  = [];
  bool _secDespacharOpen = true;
  bool _secDespachadosOpen = true;
  Pedido? _detalle;
  Pedido? _facturando;
  String _fecha = DateFormat('yyyy-MM-dd').format(DateTime.now().toUtc().subtract(const Duration(hours: 5)));

  final _fmt = NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);
  final _fmtFecha = DateFormat('yyyy-MM-dd');
  final _fmtFechaDisplay = DateFormat("EEEE d 'de' MMMM", 'es_CO');

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _seleccionarFecha() async {
    final parsed = _fecha.isNotEmpty ? DateTime.tryParse(_fecha) : null;
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed ?? DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      locale: const Locale('es'),
    );
    if (picked != null) {
      setState(() => _fecha = _fmtFecha.format(picked));
      _cargar();
    }
  }

  List<Pedido> _parseVentas(dynamic data) {
    final List raw = data is List ? data : (data is Map && data['data'] is List ? data['data'] as List : []);
    return raw.map((e) => Pedido.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      // React usa: GET /api/ventas?estado=listo  (por despachar)
      //            GET /api/ventas?estado=despachado + entregado (despachados)
      final results = await Future.wait([
        ApiService.get('/api/ventas',            queryParams: {'estado': 'listo', if (_fecha.isNotEmpty) 'fecha': _fecha}),
        ApiService.get('/api/ventas/mis-despachos', queryParams: {'estado': 'despachado', if (_fecha.isNotEmpty) 'fecha': _fecha}),
        ApiService.get('/api/ventas/mis-despachos', queryParams: {'estado': 'entregado', if (_fecha.isNotEmpty) 'fecha': _fecha}),
      ]);
      if (mounted) {
        setState(() {
          _porDespachar = _parseVentas(results[0]);
          _despachados  = [
            ..._parseVentas(results[1]),
            ..._parseVentas(results[2]),
          ]..sort((a, b) => (b.id).compareTo(a.id));
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.message : 'Error al cargar pedidos')));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _coger(Pedido p) async {
    // React: intenta cogerPedido → PATCH /domicilios/:id/coger (crea registro ventasDomiciliario)
    // luego fallback a cambiarEstadoVenta → PATCH /ventas/:id/estado { nombre_estado: 'despachado' }
    if (_procesando) return;
    setState(() => _procesando = true);
    try {
      try {
        await ApiService.patch('/api/domicilios/${p.id}/coger', {});
      } catch (_) {
        await ApiService.patch('/api/ventas/${p.id}/estado', {'nombre_estado': 'despachado'});
      }
      if (mounted) await _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.message : 'Error al coger el pedido')));
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  void _devolver(Pedido p) async {
    if (_procesando) return;
    setState(() => _procesando = true);
    try {
      await ApiService.patch('/api/ventas/${p.id}/estado', {'nombre_estado': 'listo'});
      if (mounted) await _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.message : 'Error al devolver el pedido')));
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  void _marcarEntregado(Pedido p) async {
    // Igual que React (ModalConfirmarEntrega): actualiza estado localmente sin recargar
    if (_procesando) return;
    setState(() => _procesando = true);
    try {
      await ApiService.patch('/api/ventas/${p.id}/estado', {'nombre_estado': 'entregado'});
      if (mounted) {
        setState(() {
          _facturando = null;
          _despachados = _despachados.map((d) =>
              d.id == p.id ? d.copyWith(estado: 'entregado') : d).toList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.message : 'Error al marcar como entregado')));
      }
    }
    if (mounted) setState(() => _procesando = false);
  }

  @override
  Widget build(BuildContext context) {
    return DomiciliarioLayout(
      currentRoute: '/domiciliario/pedidos',
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _cargar,
              child: Stack(
                children: [
                  ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      // ── Barra de fecha (igual React) ─────────────────────
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0,1))],
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Text('Fecha:', style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF444444))),
                            const SizedBox(width: 8),
                            Expanded(
                              child: GestureDetector(
                                onTap: _seleccionarFecha,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: const Color(0xFFE0E0E0)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _fecha.isEmpty ? 'Todas las fechas' : _fmtFechaDisplay.format(DateTime.parse(_fecha)),
                                    style: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFF444444)),
                                  ),
                                ),
                              ),
                            ),
                            if (_fecha.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () { setState(() => _fecha = ''); _cargar(); },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: const Color(0xFFE0E0E0)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text('✕ Limpiar', style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFF666666))),
                                ),
                              ),
                            ],
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: _cargar,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                child: Text('Actualizar', style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _Seccion(
                        titulo: 'Por despachar',
                        count: _porDespachar.length,
                        badgeColor: AppColors.primary,
                        open: _secDespacharOpen,
                        onToggle: () => setState(() => _secDespacharOpen = !_secDespacharOpen),
                        child: _porDespachar.isEmpty
                            ? _vacio(Icons.inventory_2_outlined, AppColors.primary, 'No hay pedidos listos por despachar')
                            : Column(children: _porDespachar.map((p) => _PedidoCard(
                                pedido: p, tipo: 'despachar', fmt: _fmt,
                                procesando: _procesando,
                                onCoger: () => _coger(p),
                                onVerDetalle: () => setState(() => _detalle = p),
                              )).toList()),
                      ),
                      const SizedBox(height: 16),
                      _Seccion(
                        titulo: 'Despachados',
                        count: _despachados.length,
                        badgeColor: const Color(0xFF22C55E),
                        open: _secDespachadosOpen,
                        onToggle: () => setState(() => _secDespachadosOpen = !_secDespachadosOpen),
                        child: _despachados.isEmpty
                            ? _vacio(Icons.pedal_bike_rounded, const Color(0xFF16A34A), 'Aún no has cogido ningún pedido')
                            : Column(children: _despachados.map((p) => _PedidoCard(
                                pedido: p, tipo: 'despachado', fmt: _fmt,
                                procesando: _procesando,
                                onDevolver: () => _devolver(p),
                                onFacturar: () => setState(() => _facturando = p),
                                onVerDetalle: () => setState(() => _detalle = p),
                              )).toList()),
                      ),
                      const SizedBox(height: 80),
                    ],
                  ),

                  // Modales
                  if (_detalle != null)
                    _ModalDetalle(pedido: _detalle!, fmt: _fmt, onClose: () => setState(() => _detalle = null)),
                  if (_facturando != null)
                    _ModalConfirmarEntrega(
                      pedido: _facturando!, fmt: _fmt,
                      onClose: () => setState(() => _facturando = null),
                      onConfirmar: () => _marcarEntregado(_facturando!),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _vacio(IconData icon, Color color, String msg) => Container(
    padding: const EdgeInsets.all(24),
    alignment: Alignment.center,
    child: Column(children: [
      Icon(icon, size: 36, color: color),
      const SizedBox(height: 8),
      Text(msg, style: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFF888888))),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sección colapsable
// ���────────────────────────────────────────────────────────────────────────────

class _Seccion extends StatelessWidget {
  final String titulo;
  final int count;
  final Color badgeColor;
  final bool open;
  final VoidCallback onToggle;
  final Widget child;

  const _Seccion({required this.titulo, required this.count, required this.badgeColor,
      required this.open, required this.onToggle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0,1))],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: onToggle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: open ? const BorderRadius.vertical(top: Radius.circular(12)) : BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Text(titulo, style: GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF1a1a1a))),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                    child: Text('$count', style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w800, color: badgeColor)),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF888888)),
                  ),
                ],
              ),
            ),
          ),
          if (open) ...[
            const Divider(height: 1, color: Color(0xFFF0F0F0)),
            Padding(padding: const EdgeInsets.all(12), child: child),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pedido Card
// ─────────────────────────────────────────────────────────────────────────────

class _PedidoCard extends StatelessWidget {
  final Pedido pedido;
  final String tipo; // 'despachar' | 'despachado'
  final NumberFormat fmt;
  final bool procesando;
  final VoidCallback? onCoger;
  final VoidCallback? onDevolver;
  final VoidCallback? onFacturar;
  final VoidCallback onVerDetalle;

  const _PedidoCard({required this.pedido, required this.tipo, required this.fmt,
      this.procesando = false,
      this.onCoger, this.onDevolver, this.onFacturar, required this.onVerDetalle});

  Future<void> _abrirUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _abrirWhatsApp() async {
    final rawTel = (pedido.clienteTelefono ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    final tel = rawTel.startsWith('57') ? rawTel : '57$rawTel';
    final texto = Uri.encodeComponent('Hola');
    final wppUri = Uri.parse('whatsapp://send?phone=$tel&text=$texto');
    try {
      await launchUrl(wppUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      await launchUrl(Uri.parse('https://wa.me/$tel?text=$texto'), mode: LaunchMode.externalApplication);
    }
  }

String get _mapsUrl {
    final parts = [pedido.direccion, pedido.barrio, pedido.ciudad]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(', ');
    return 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(parts)}';
  }

  bool get _entregado => pedido.estado == 'entregado';

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _entregado ? const Color(0xFFF0FDF4) : Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Banner entregado (chip pequeño, igual que React pd-ok-banner)
                if (_entregado) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF16A34A)),
                        const SizedBox(width: 4),
                        Text('ENTREGADO', style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF16A34A))),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                // Fila 1: ID + hora + pago
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('#${pedido.id}',
                          style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF1a1a1a))),
                    ),
                    const SizedBox(width: 8),
                    Text(pedido.hora ?? '',
                        style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFF888888))),
                    const Spacer(),
                    _PagoBadge(formaPago: pedido.formaPago ?? 'efectivo'),
                  ],
                ),
                const SizedBox(height: 8),

                // Nombre + tel
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        pedido.clienteNombre ?? 'Sin nombre',
                        style: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w900, color: const Color(0xFF1a1a1a)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(pedido.clienteTelefono ?? '',
                          style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFF888888)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Dirección
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF888888)),
                    const SizedBox(width: 4),
                    Expanded(child: Text(pedido.direccion ?? '',
                        style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFF666666)))),
                  ],
                ),
                const SizedBox(height: 8),

                // Estado badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _entregado ? const Color(0xFFDCFCE7) : const Color(0xFFFEFCE8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _entregado ? '✓ Domicilio entregado' : pedido.estado,
                    style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700,
                        color: _entregado ? const Color(0xFF16A34A) : const Color(0xFFCA8A04)),
                  ),
                ),
                const SizedBox(height: 10),

                // Footer: total + botones
                Row(
                  children: [
                    Flexible(
                      child: Text(fmt.format(pedido.total),
                          style: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w900, color: const Color(0xFF1a1a1a)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    const Spacer(),
                    Row(children: [
                      // Maps
                      _ActionBtn(
                        color: AppColors.primary,
                        bg: const Color(0xFFFFF0F0),
                        borderColor: const Color(0xFFFECACA),
                        onTap: () => _abrirUrl(_mapsUrl),
                        tooltip: 'Ver en mapa',
                        child: const Icon(Icons.location_on, size: 16, color: AppColors.primary),
                      ),
                      const SizedBox(width: 6),
                      if (pedido.clienteTelefono != null && pedido.clienteTelefono!.isNotEmpty) ...[
                        _ActionBtn(
                          color: const Color(0xFF25D366),
                          bg: const Color(0xFFF0FDF4),
                          borderColor: const Color(0xFFBBF7D0),
                          onTap: () => _abrirWhatsApp(),
                          tooltip: 'WhatsApp',
                          child: const LogoWhatsApp(size: 16, color: Color(0xFF25D366)),
                        ),
                        const SizedBox(width: 6),
                      ],

                      if (tipo == 'despachar') ...[
                        _ActionBtn(
                          color: AppColors.primary,
                          bg: const Color(0xFFFFF5F5),
                          onTap: procesando ? null : onCoger,
                          tooltip: 'Coger pedido',
                          child: const Icon(Icons.arrow_forward_rounded, size: 16),
                        ),
                      ] else if (!_entregado) ...[
                        _ActionBtn(
                          color: const Color(0xFFCA8A04),
                          bg: const Color(0xFFFEFCE8),
                          onTap: procesando ? null : onDevolver,
                          tooltip: 'Devolver',
                          child: const Icon(Icons.arrow_back_rounded, size: 16),
                        ),
                        const SizedBox(width: 6),
                        _ActionBtn(
                          color: const Color(0xFF7C3AED),
                          bg: const Color(0xFFF5F3FF),
                          onTap: procesando ? null : onFacturar,
                          tooltip: 'Marcar como entregado',
                          child: const Icon(Icons.receipt_outlined, size: 16),
                        ),
                      ],
                      const SizedBox(width: 6),
                      _ActionBtn(
                        color: const Color(0xFF555555),
                        bg: const Color(0xFFF5F5F5),
                        onTap: onVerDetalle,
                        tooltip: 'Ver detalle',
                        child: const Icon(Icons.visibility_outlined, size: 16),
                      ),
                    ]),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final Widget child;
  final Color color;
  final Color? bg;
  final Color? borderColor;
  final VoidCallback? onTap;
  final String tooltip;

  const _ActionBtn({required this.child, required this.color, this.bg, this.borderColor, this.onTap, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: bg ?? color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: borderColor != null ? Border.all(color: borderColor!) : null,
          ),
          alignment: Alignment.center,
          child: IconTheme(data: IconThemeData(color: color, size: 16), child: child),
        ),
      ),
    );
  }
}

class _PagoBadge extends StatelessWidget {
  final String formaPago;
  const _PagoBadge({required this.formaPago});

  @override
  Widget build(BuildContext context) {
    final isEf = formaPago == 'efectivo';
    final isMx = formaPago == 'mixto';
    final color = isEf ? const Color(0xFFCA8A04) : isMx ? const Color(0xFF7C3AED) : const Color(0xFF3B82F6);
    final bg    = isEf ? const Color(0xFFFEFCE8) : isMx ? const Color(0xFFF5F3FF) : const Color(0xFFEFF6FF);
    final label = isEf ? 'Efectivo' : isMx ? 'Mixto' : 'Transferencia';
    final icon  = isEf
        ? Icon(Icons.payments_outlined, size: 11, color: color)
        : isMx
            ? Icon(Icons.sync_alt_rounded, size: 11, color: color)
            : Icon(Icons.phone_android_rounded, size: 11, color: color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        icon,
        const SizedBox(width: 3),
        Text(label, style: GoogleFonts.nunito(fontSize: 10, fontWeight: FontWeight.w800, color: color)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Modal Detalle
// ─────────────────────────────────────────────────────────────────────────────

class _ModalDetalle extends StatelessWidget {
  final Pedido pedido;
  final NumberFormat fmt;
  final VoidCallback onClose;

  const _ModalDetalle({required this.pedido, required this.fmt, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: Colors.black.withValues(alpha: 0.45),
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              margin: const EdgeInsets.all(20),
              constraints: const BoxConstraints(maxWidth: 480),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                    child: Row(
                      children: [
                        Text('Pedido #${pedido.id}',
                            style: GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w800)),
                        const Spacer(),
                        IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded, size: 20)),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFF0F0F0)),

                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Grid info — igual que React: Cliente, Hora, Dirección, Teléfono, Pago, [Desglose si mixto]
                          Column(
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: _DetalleItem(label: 'Cliente', valor: pedido.clienteNombre ?? '-', full: true)),
                                  const SizedBox(width: 8),
                                  Expanded(child: _DetalleItem(label: 'Hora', valor: pedido.hora ?? '-', full: true)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: _DetalleItem(label: 'Dirección', valor: pedido.direccionCompleta.isNotEmpty ? pedido.direccionCompleta : '-', full: true)),
                                  const SizedBox(width: 8),
                                  Expanded(child: _DetalleItem(label: 'Teléfono', valor: pedido.clienteTelefono ?? '-', full: true)),
                                ],
                              ),
                              if (pedido.formaPago != null && pedido.formaPago!.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFAFAFA),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFF0F0F0)),
                                  ),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('PAGO', style: GoogleFonts.nunito(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF888888))),
                                    const SizedBox(height: 4),
                                    _PagoBadge(formaPago: pedido.formaPago!),
                                  ]),
                                ),
                              ],
                            ],
                          ),
                          if (pedido.formaPago == 'mixto') ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF7F8FD),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Desglose', style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF888888))),
                                  const SizedBox(height: 4),
                                  Text('Efectivo: ${fmt.format(pedido.montoEfectivo ?? 0)}',
                                      style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 2),
                                  Text('Transferencia: ${fmt.format(pedido.montoTransferencia ?? 0)}',
                                      style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),

                          // Productos
                          Text('Productos', style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF1a1a1a))),
                          const SizedBox(height: 8),
                          ...pedido.lineas.map((l) => Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: const Color(0xFFF7F8FD), borderRadius: BorderRadius.circular(8)),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Expanded(child: Text('${l.cantidad}× ${l.nombreProducto}',
                                      style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700))),
                                  Text(fmt.format(l.subtotal),
                                      style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
                                ]),
                                if (l.chocolate != null || l.salsas.isNotEmpty || l.toppings.isNotEmpty || l.adiciones.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Wrap(spacing: 4, runSpacing: 4, children: [
                                    if (l.chocolate != null)
                                      _Chip(
                                        label: 'Chocolate ${l.chocolate!}',
                                        bg: l.chocolate!.toLowerCase().contains('negro')
                                            ? const Color(0xFF1E3A5F)
                                            : const Color(0xFFF0F0F0),
                                        fg: l.chocolate!.toLowerCase().contains('negro')
                                            ? Colors.white
                                            : const Color(0xFF1a1a1a),
                                      ),
                                    ...l.salsas.map((s) => _Chip(
                                        label: _nombreSalsa(s),
                                        bg: const Color(0xFFFFF7ED),
                                        fg: const Color(0xFFEA580C),
                                        outlined: true,
                                        outlineColor: const Color(0xFFEA580C),
                                    )),
                                    ...l.toppings.map((t) => _Chip(label: t, bg: const Color(0xFF1A1A1A), fg: Colors.white)),
                                    ...l.adiciones.map((a) => _Chip(label: a, bg: const Color(0xFFD97706), fg: Colors.white)),
                                  ]),
                                ],
                              ]),
                            )),

                          const SizedBox(height: 12),
                          // Totales
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: const Color(0xFFF7F8FD), borderRadius: BorderRadius.circular(10)),
                            child: Column(children: [
                              _TotalFila(label: 'Subtotal productos', valor: fmt.format(pedido.subtotal)),
                              if (pedido.descuentoPuntos > 0)
                                _TotalFila(label: 'Descuento puntos (${pedido.puntosUsados} pts)', valor: '- ${fmt.format(pedido.descuentoPuntos)}', green: true),
                              _TotalFila(label: 'Domicilio', valor: fmt.format(pedido.costoDomicilio)),
                              const Divider(color: Color(0xFFE0E0E0)),
                              _TotalFila(label: 'Total', valor: fmt.format(pedido.total), bold: true),
                            ]),
                          ),
                        ],
                      ),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: onClose,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFE0E0E0)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text('Cerrar', style: GoogleFonts.nunito(fontWeight: FontWeight.w700, color: const Color(0xFF666666))),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetalleItem extends StatelessWidget {
  final String label;
  final String valor;
  final bool full;
  const _DetalleItem({required this.label, required this.valor, this.full = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: full ? double.infinity : 180,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF0F0F0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(), style: GoogleFonts.nunito(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF888888))),
        const SizedBox(height: 2),
        Text(valor, style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1a1a1a))),
      ]),
    );
  }
}

String _nombreSalsa(String s) => s.replaceAll('_', ' ').replaceAllMapped(
    RegExp(r'\b\w'), (m) => m.group(0)!.toUpperCase());

class _Chip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final bool outlined;
  final Color? outlineColor;
  const _Chip({required this.label, required this.bg, required this.fg, this.outlined = false, this.outlineColor});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      border: outlined ? Border.all(color: outlineColor ?? fg) : null,
    ),
    child: Text(label, style: GoogleFonts.nunito(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
  );
}

class _TotalFila extends StatelessWidget {
  final String label;
  final String valor;
  final bool bold;
  final bool green;
  const _TotalFila({required this.label, required this.valor, this.bold = false, this.green = false});
  @override
  Widget build(BuildContext context) {
    final color = green ? const Color(0xFF16A34A) : (bold ? AppColors.primary : const Color(0xFF1a1a1a));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.nunito(fontSize: 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: bold ? const Color(0xFF1a1a1a) : (green ? const Color(0xFF16A34A) : const Color(0xFF666666)))),
          Text(valor, style: GoogleFonts.nunito(
            fontSize: bold ? 22 : 13,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w800,
            color: color,
          )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Modal Confirmar Entrega — igual que React (ModalConfirmarEntrega): solo
// confirma, sin pedir método de pago ni comprobante.
// ─────────────────────────────────────────────────────────────────────────────

class _ModalConfirmarEntrega extends StatelessWidget {
  final Pedido pedido;
  final NumberFormat fmt;
  final VoidCallback onClose;
  final VoidCallback onConfirmar;

  const _ModalConfirmarEntrega({required this.pedido, required this.fmt, required this.onClose, required this.onConfirmar});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: Colors.black.withValues(alpha: 0.5),
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              margin: const EdgeInsets.all(20),
              constraints: const BoxConstraints(maxWidth: 360),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_rounded, size: 40, color: Color(0xFF16A34A)),
                  const SizedBox(height: 12),
                  Text('¿Confirmas que entregaste el pedido #${pedido.id}?',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunito(fontSize: 17, fontWeight: FontWeight.w800, color: const Color(0xFF1a1a1a))),
                  const SizedBox(height: 6),
                  Text('${pedido.clienteNombre ?? ''} · ${fmt.format(pedido.total)}',
                      style: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFF555555))),
                  const SizedBox(height: 24),
                  Row(children: [
                    Expanded(child: OutlinedButton(
                      onPressed: onClose,
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFE0E0E0)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      child: Text('Cancelar', style: GoogleFonts.nunito(fontWeight: FontWeight.w600, color: const Color(0xFF1a1a1a))),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: ElevatedButton(
                      onPressed: onConfirmar,
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 0),
                      child: Text('Sí, entregado', style: GoogleFonts.nunito(fontWeight: FontWeight.w700, color: Colors.white)),
                    )),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
