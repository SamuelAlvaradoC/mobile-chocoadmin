import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/models/pedido.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/layouts/admin_layout.dart';

class CocinaScreen extends StatefulWidget {
  const CocinaScreen({super.key});

  @override
  State<CocinaScreen> createState() => _CocinaScreenState();
}

class _CocinaScreenState extends State<CocinaScreen> {
  List<Pedido> _pedidos = [];
  bool _cargando = true;
  bool _marcando = false;
  int? _confirmandoId;
  Pedido? _detalleAbierto;
  Timer? _timer;

  final _fmt = NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _cargar();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _cargar());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final data = await ApiService.get('/api/ventas',
          queryParams: {'estado': 'en_proceso'});
      List raw = [];
      if (data is List) {
        raw = data;
      } else if (data is Map && data['data'] is List) {
        raw = data['data'] as List;
      }
      final pedidos = raw
          .map((e) => Pedido.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      if (mounted) {
        final detalleIdActual = _detalleAbierto?.id;
        final confirmandoIdActual = _confirmandoId;
        final sigueDetalle = detalleIdActual == null || pedidos.any((p) => p.id == detalleIdActual);
        final sigueConfirmando = confirmandoIdActual == null || pedidos.any((p) => p.id == confirmandoIdActual);
        setState(() {
          _pedidos = pedidos;
          _cargando = false;
          if (!sigueDetalle) _detalleAbierto = null;
          if (!sigueConfirmando) _confirmandoId = null;
        });
        if (!sigueDetalle || !sigueConfirmando) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Este pedido cambió de estado en otro dispositivo.')),
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _marcarListo(int id) async {
    setState(() => _marcando = true);
    try {
      await ApiService.patch('/api/ventas/$id/estado', {'nombre_estado': 'listo'});
      if (mounted) {
        setState(() {
          _pedidos.removeWhere((p) => p.id == id);
          _confirmandoId = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pedido marcado como listo'), backgroundColor: Color(0xFF16A34A)),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.primary),
        );
      }
    } finally {
      if (mounted) setState(() { _marcando = false; _confirmandoId = null; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      currentRoute: '/cocina',
      body: Column(
        children: [
          // Page header — matches React's .page-header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Panel Cocina',
                          style: GoogleFonts.nunito(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF1a1a1a))),
                      Text(
                        '${_pedidos.length} pedido${_pedidos.length != 1 ? 's' : ''} en preparación',
                        style: GoogleFonts.nunito(
                            fontSize: 13,
                            color: const Color(0xFF888888),
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                // Actualizar button — matches React's green button style
                GestureDetector(
                  onTap: _cargar,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.refresh_rounded,
                            size: 13, color: Color(0xFF16A34A)),
                        const SizedBox(width: 6),
                        Text('Actualizar',
                            style: GoogleFonts.nunito(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF16A34A))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                _buildBody(),
                if (_confirmandoId != null) _buildDialogoConfirmacion(),
                if (_detalleAbierto != null)
                  _ModalDetalle(
                    pedido: _detalleAbierto!,
                    fmt: _fmt,
                    onClose: () => setState(() => _detalleAbierto = null),
                    onConfirmar: (id) {
                      setState(() {
                        _detalleAbierto = null;
                        _confirmandoId = id;
                      });
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_pedidos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.restaurant_menu_rounded, size: 80, color: AppColors.primary),
            const SizedBox(height: 16),
            Text('Todo listo por ahora', style: GoogleFonts.nunito(fontSize: 20, fontWeight: FontWeight.w700, color: const Color(0xFF1a1a1a))),
            const SizedBox(height: 8),
            Text('Los pedidos confirmados aparecerán aquí', style: GoogleFonts.nunito(fontSize: 14, color: const Color(0xFF888888))),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        itemCount: _pedidos.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _PedidoCard(
            pedido: _pedidos[i],
            onVerDetalle: (p) => setState(() => _detalleAbierto = p),
            onConfirmar: (id) => setState(() => _confirmandoId = id),
          ),
        ),
      ),
    );
  }

  Widget _buildDialogoConfirmacion() {
    return _Overlay(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 20, offset: Offset(0, 8))]),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 40, color: Color(0xFFF59E0B)),
            const SizedBox(height: 12),
            Text('¿Confirmar pedido listo?',
                style: GoogleFonts.nunito(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF1a1a1a)),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('¿Estás seguro de marcar el pedido #$_confirmandoId como listo para despachar?',
                style: GoogleFonts.nunito(fontSize: 14, color: const Color(0xFF666666)),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _marcando ? null : () => setState(() => _confirmandoId = null),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Cancelar', style: GoogleFonts.nunito(fontWeight: FontWeight.w600, color: const Color(0xFF1a1a1a))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _marcando ? null : () => _marcarListo(_confirmandoId!),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: _marcando
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Sí, está listo', style: GoogleFonts.nunito(fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Overlay
// ─────────────────────────────────────────────────────────────────────────────

class _Overlay extends StatelessWidget {
  final Widget child;
  const _Overlay({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0x88000000),
    child: Center(child: child),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

// React Cocina doesn't show price for adiciones (only nombre ×n).
// The shared Pedido model adds prices; strip them here for the cocina view.
String _adicionLabel(String raw) => raw.replaceAll(RegExp(r' \$[\d.]+$'), '').trim();

String _nombreSalsa(String s) => s.replaceAll('_', ' ').replaceAllMapped(
    RegExp(r'\b\w'), (m) => m.group(0)!.toUpperCase());

// ─────────────────────────────────────────────────────────────────────────────
// Pedido card
// ─────────────────────────────────────────────────────────────────────────────

class _PedidoCard extends StatelessWidget {
  final Pedido pedido;
  final void Function(Pedido) onVerDetalle;
  final void Function(int) onConfirmar;

  const _PedidoCard({required this.pedido, required this.onVerDetalle, required this.onConfirmar});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header rojo
          Container(
            color: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('#${pedido.id}', style: GoogleFonts.nunito(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                    Text(pedido.clienteNombre ?? '—', style: GoogleFonts.nunito(fontSize: 13, color: Colors.white.withValues(alpha: 0.85))),
                  ]),
                ),
                if (pedido.hora != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                    child: Text(pedido.hora!, style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  ),
              ],
            ),
          ),

          // Cuerpo
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (pedido.observaciones != null && pedido.observaciones!.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('⚠️ Observación', style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFFB45309))),
                      const SizedBox(height: 3),
                      Text(pedido.observaciones!, style: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFF92400E))),
                    ]),
                  ),
                Text('PRODUCTOS', style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF999999), letterSpacing: 1)),
                const SizedBox(height: 8),
                ...pedido.lineas.map((l) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ProductRow(linea: l),
                )),
              ],
            ),
          ),

          // Footer
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFF0F0F0)))),
            child: Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => onVerDetalle(pedido),
                      icon: const Icon(Icons.visibility_outlined, size: 13),
                      label: Text('Ver detalle', style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF666666),
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => onConfirmar(pedido.id),
                        icon: const Icon(Icons.check_rounded, size: 14),
                        label: Text('Marcar como listo', style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Product row within card
// ─────────────────────────────────────────────────────────────────────────────

class _ProductRow extends StatelessWidget {
  final LineaDetalle linea;
  const _ProductRow({required this.linea});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${linea.cantidad}× ${linea.nombreProducto}',
            style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1a1a1a))),
        if (linea.chocolate != null) ...[
          const SizedBox(height: 4),
          _Chip(
            label: '${linea.chocolate! == 'Negro' ? '🍫' : '⬜'} Chocolate ${linea.chocolate!}',
            bg: const Color(0xFF1E3A5F),
            fg: Colors.white,
          ),
        ],
        if (linea.salsas.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(spacing: 4, runSpacing: 4,
            children: linea.salsas.map((s) => _Chip(label: _nombreSalsa(s), outlined: true, outlineColor: const Color(0xFFEA580C), fg: const Color(0xFFEA580C), bg: const Color(0xFFFFF7ED))).toList(),
          ),
        ],
        if (linea.toppings.isNotEmpty || linea.adiciones.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(spacing: 4, runSpacing: 4, children: [
            ...linea.toppings.map((t) => _Chip(label: t, bg: const Color(0xFF1A1A1A), fg: Colors.white)),
            ...linea.adiciones.map((a) => _Chip(label: _adicionLabel(a), bg: const Color(0xFFD97706), fg: Colors.white)),
          ]),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chip
// ─────────────────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final bool outlined;
  final Color? outlineColor;

  const _Chip({required this.label, required this.bg, required this.fg, this.outlined = false, this.outlineColor});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      border: outlined ? Border.all(color: outlineColor ?? fg) : null,
    ),
    child: Text(label, style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Detail modal
// ─────────────────────────────────────────────────────────────────────────────

class _ModalDetalle extends StatelessWidget {
  final Pedido pedido;
  final NumberFormat fmt;
  final VoidCallback onClose;
  final void Function(int) onConfirmar;

  const _ModalDetalle({required this.pedido, required this.fmt, required this.onClose, required this.onConfirmar});

  @override
  Widget build(BuildContext context) {
    return _Overlay(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 40),
        constraints: const BoxConstraints(maxWidth: 420),
        width: double.infinity,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
            boxShadow: const [BoxShadow(color: Color(0x4C000000), blurRadius: 30, offset: Offset(0, 10))]),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header rojo
            Container(
              color: AppColors.primary,
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Pedido #${pedido.id}', style: GoogleFonts.nunito(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                      if (pedido.creadoEn != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${DateFormat('dd MMM', 'es_CO').format(pedido.creadoEn!)} · ${pedido.hora ?? ''}',
                          style: GoogleFonts.nunito(fontSize: 13, color: Colors.white.withValues(alpha: 0.85)),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(20)),
                        child: Text('En preparación', style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.5)),
                      ),
                    ]),
                  ),
                  GestureDetector(
                    onTap: onClose,
                    child: Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(17)),
                      alignment: Alignment.center,
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cliente
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(10)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('CLIENTE', style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF999999), letterSpacing: 1)),
                          const SizedBox(height: 6),
                          Text(pedido.clienteNombre ?? '—', style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1a1a1a))),
                          if (pedido.clienteTelefono != null) ...[
                            const SizedBox(height: 4),
                            Row(children: [
                              const Text('📞', style: TextStyle(fontSize: 13)),
                              const SizedBox(width: 6),
                              Text(pedido.clienteTelefono!, style: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFF555555))),
                            ]),
                          ],
                          if (pedido.direccionCompleta.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('📍', style: TextStyle(fontSize: 13)),
                              const SizedBox(width: 6),
                              Expanded(child: Text(pedido.direccionCompleta, style: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFF555555)))),
                            ]),
                          ],
                        ],
                      ),
                    ),

                    // Observaciones
                    if (pedido.observaciones != null && pedido.observaciones!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('⚠️ Observación', style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFFB45309))),
                          const SizedBox(height: 4),
                          Text(pedido.observaciones!, style: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFF92400E))),
                        ]),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Productos
                    Text('PRODUCTOS', style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF999999), letterSpacing: 1)),
                    const SizedBox(height: 10),
                    ...pedido.lineas.asMap().entries.map((entry) {
                      final i = entry.key;
                      final l = entry.value;
                      return Container(
                        padding: const EdgeInsets.only(bottom: 14),
                        decoration: i < pedido.lineas.length - 1
                            ? const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))))
                            : null,
                        margin: const EdgeInsets.only(bottom: 14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${l.cantidad}× ${l.nombreProducto}',
                              style: GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF1a1a1a))),
                          const SizedBox(height: 6),
                          Wrap(spacing: 5, runSpacing: 5, children: [
                            if (l.chocolate != null)
                              _Chip(
                                label: 'Chocolate ${l.chocolate!}',
                                bg: l.chocolate!.toLowerCase().contains('negro') ? const Color(0xFF1E3A5F) : const Color(0xFFF0F0F0),
                                fg: l.chocolate!.toLowerCase().contains('negro') ? Colors.white : const Color(0xFF555555),
                              ),
                            ...l.salsas.map((s) => _Chip(label: _nombreSalsa(s), outlined: true, outlineColor: const Color(0xFFEA580C), fg: const Color(0xFFEA580C), bg: const Color(0xFFFFF7ED))),
                            ...l.toppings.map((t) => _Chip(label: t, bg: const Color(0xFF1A1A1A), fg: Colors.white)),
                            ...l.adiciones.map((a) => _Chip(label: _adicionLabel(a), bg: const Color(0xFFD97706), fg: Colors.white)),
                          ]),
                        ]),
                      );
                    }),

                    // Totales
                    Container(
                      padding: const EdgeInsets.only(top: 12),
                      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFF0F0F0)))),
                      child: Column(children: [
                        _TotalRow(label: 'Subtotal', valor: fmt.format(pedido.subtotal)),
                        if (pedido.descuentoPuntos > 0)
                          _TotalRow(label: 'Descuento puntos (${pedido.puntosUsados} pts)', valor: '- ${fmt.format(pedido.descuentoPuntos)}', green: true),
                        _TotalRow(label: 'Domicilio', valor: fmt.format(pedido.costoDomicilio)),
                        const SizedBox(height: 4),
                        _TotalRow(label: 'Total', valor: fmt.format(pedido.total), bold: true),
                      ]),
                    ),

                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () { onConfirmar(pedido.id); onClose(); },
                        icon: const Icon(Icons.check_rounded, size: 16),
                        label: Text('Marcar como listo', style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w800)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String valor;
  final bool bold;
  final bool green;
  const _TotalRow({required this.label, required this.valor, this.bold = false, this.green = false});

  @override
  Widget build(BuildContext context) {
    final color = green ? const Color(0xFF16A34A) : (bold ? const Color(0xFF1a1a1a) : const Color(0xFF555555));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.nunito(fontSize: bold ? 16 : 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color)),
          Text(valor, style: GoogleFonts.nunito(fontSize: bold ? 16 : 13, fontWeight: FontWeight.w800, color: bold ? const Color(0xFF1a1a1a) : (green ? const Color(0xFF16A34A) : const Color(0xFF555555)))),
        ],
      ),
    );
  }
}
