import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_config.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/layouts/client_bottom_nav.dart';
import '../../../core/models/producto.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../providers/catalogo_provider.dart';
import '../providers/carrito_provider.dart';
import '../widgets/toppings_modal.dart';

class CatalogoScreen extends StatefulWidget {
  const CatalogoScreen({super.key});

  @override
  State<CatalogoScreen> createState() => _CatalogoScreenState();
}

/// Equivalente a formatHora12() del frontend React (src/utils/formatHora.js).
String _formatHora12(dynamic hora24) {
  final h = num.tryParse(hora24?.toString() ?? '') ?? 0;
  final period = h < 12 ? 'AM' : 'PM';
  final h12raw = h % 12;
  final h12 = h12raw == 0 ? 12 : h12raw.toInt();
  return '$h12:00 $period';
}

class _CatalogoScreenState extends State<CatalogoScreen> {
  final _busquedaCtrl = TextEditingController();
  String _busqueda = '';
  bool _carritoExpandido = false;
  bool? _tiendaAbierta;
  dynamic _horaApertura;
  dynamic _horaCierre;
  int _tiempoEspera = 30;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CatalogoProvider>().cargarTodo();
      _fetchEstadoTienda();
      _fetchTiempoEspera();
    });
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchEstadoTienda() async {
    try {
      final res = await http.get(Uri.parse('${AppConfig.apiBaseUrl}/configuracion/estado-tienda'));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body) as Map;
        final inner = data['data'] is Map ? data['data'] as Map : data;
        setState(() {
          _tiendaAbierta = inner['abierto'] == true;
          _horaApertura = inner['hora_apertura'];
          _horaCierre = inner['hora_cierre'];
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchTiempoEspera() async {
    try {
      final res = await http.get(Uri.parse('${AppConfig.apiBaseUrl}/configuracion/tiempo-espera'));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body) as Map;
        final inner = data['data'] is Map ? data['data'] as Map : data;
        final min = inner['minutos'];
        if (min != null) setState(() => _tiempoEspera = int.tryParse(min.toString()) ?? 30);
      }
    } catch (_) {}
  }

  void _mostrarTiendaCerrada() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🕐', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text('Estamos cerrados',
                  style: GoogleFonts.nunito(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF1a1a1a)),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('No estamos aceptando pedidos en este momento. ¡Vuelve pronto!',
                  style: GoogleFonts.nunito(fontSize: 13, color: AppColors.textSecondary),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Entendido'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarLoginRequerido() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🔒', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text(
                'Inicia sesión para comprar',
                style: GoogleFonts.nunito(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF1a1a1a)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Necesitas una cuenta para agregar productos al carrito.',
                style: GoogleFonts.nunito(fontSize: 13, color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        context.go('/login');
                      },
                      child: const Text('Iniciar sesión'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  context.go('/register');
                },
                child: RichText(
                  text: TextSpan(
                    style: GoogleFonts.nunito(fontSize: 12, color: AppColors.textSecondary),
                    children: [
                      const TextSpan(text: '¿No tienes cuenta? '),
                      TextSpan(
                        text: 'Regístrate gratis',
                        style: GoogleFonts.nunito(color: AppColors.primary, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _agregarProducto(Producto producto) async {
    if (_tiendaAbierta == false) { _mostrarTiendaCerrada(); return; }
    final user = context.read<AuthProvider>().user;
    if (user == null) { _mostrarLoginRequerido(); return; }

    final catalogo = context.read<CatalogoProvider>();
    final carrito  = context.read<CarritoProvider>();
    if (!mounted) return;

    final result = await showModalBottomSheet<ModalProductoResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ToppingsModal(
        allToppings:  catalogo.toppings,
        allAdiciones: catalogo.adiciones,
        producto:     producto,
      ),
    );
    if (result == null || !mounted) return;

    carrito.agregar(
      producto:      producto,
      toppings:      result.toppings,
      adiciones:     result.adiciones,
      salsas:        result.salsas,
      tipoChocolate: result.tipoChocolate,
      cargoExtra:    result.cargoExtra,
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalogo = context.watch<CatalogoProvider>();
    final carrito = context.watch<CarritoProvider>();
    final auth = context.watch<AuthProvider>();
    final fmt = NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('ChocoFreseo'),
        actions: const [ClientVolverAlPanelAction()],
      ),
      bottomNavigationBar: const ClientBottomNav(currentRoute: '/catalogo'),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  catalogo.loading
                      ? _buildShimmer()
                      : catalogo.error != null
                          ? _buildError(catalogo)
                          : _buildContent(catalogo, fmt),
                  // Backdrop cuando el carrito está expandido
                  if (_carritoExpandido)
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () => setState(() => _carritoExpandido = false),
                        child: Container(color: Colors.black.withValues(alpha: 0.4)),
                      ),
                    ),
                  // Carrito bottom bar
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _CarritoBottomBar(
                      carrito: carrito,
                      fmt: fmt,
                      expandido: _carritoExpandido,
                      onToggle: () => setState(() => _carritoExpandido = !_carritoExpandido),
                      onCheckout: auth.user == null
                          ? (_) => _mostrarLoginRequerido()
                          : _tiendaAbierta == false
                              ? (_) => _mostrarTiendaCerrada()
                              : (int pts) => context.go('/checkout', extra: {'puntosAUsar': pts}),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(CatalogoProvider catalogo, NumberFormat fmt) {
    final filtrados = _busqueda.isEmpty
        ? catalogo.productosFiltrados
        : catalogo.productosFiltrados
            .where((p) => p.nombre.toLowerCase().contains(_busqueda.toLowerCase()))
            .toList();

    return Column(
      children: [
        // Estado tienda banner
        if (_tiendaAbierta == false)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF5F5),
              border: Border.all(color: const Color(0xFFFECACA)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              const Text('🔒', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Estamos cerrados por el momento',
                    style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary)),
                Text(
                    'Todos los días · ${_formatHora12(_horaApertura)} - ${_formatHora12(_horaCierre)}',
                    style: GoogleFonts.nunito(fontSize: 12, color: AppColors.primary)),
              ])),
            ]),
          ),

        // ── Tiempo estimado (cuando tienda abierta) ──────────
        if (_tiendaAbierta == true)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              border: Border.all(color: const Color(0xFFBBF7D0)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              const Text('⏱️', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFF166534)),
                    children: [
                      const TextSpan(text: 'Tiempo estimado de entrega: ', style: TextStyle(fontWeight: FontWeight.w600)),
                      TextSpan(text: '$_tiempoEspera–${_tiempoEspera + 20} min', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ]),
          ),

        // ── Chips de categorías ──────────────────────────────
        if (catalogo.categorias.isNotEmpty)
          SizedBox(
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.screenPadding,
                vertical: 8,
              ),
              itemCount: catalogo.categorias.length + 1,
              itemBuilder: (_, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('Todos'),
                      selected: catalogo.categoriaSeleccionada == null,
                      onSelected: (_) => catalogo.seleccionarCategoria(null),
                      selectedColor: AppColors.primary,
                      labelStyle: TextStyle(
                        color: catalogo.categoriaSeleccionada == null
                            ? Colors.white
                            : AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  );
                }
                final cat = catalogo.categorias[i - 1];
                final sel = catalogo.categoriaSeleccionada == cat.id;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(cat.nombre),
                    selected: sel,
                    onSelected: (_) => catalogo.seleccionarCategoria(cat.id),
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(
                      color: sel ? Colors.white : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                );
              },
            ),
          ),

        // ── Buscador ──────────────────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(AppSizes.screenPadding, 6, AppSizes.screenPadding, 8),
          child: TextField(
            controller: _busquedaCtrl,
            onChanged: (v) => setState(() => _busqueda = v),
            style: GoogleFonts.nunito(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Buscar producto...',
              hintStyle: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFFAAAAAA)),
              prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF888888)),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              filled: true,
              fillColor: const Color(0xFFF7F8FD),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(50), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(50), borderSide: const BorderSide(color: Color(0xFFE8E8E8))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(50), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
            ),
          ),
        ),

        // ── Grid de productos ────────────────────────────────
        Expanded(
          child: filtrados.isEmpty
              ? const Center(child: Text('No se encontraron productos'))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppSizes.screenPadding, AppSizes.screenPadding,
                    AppSizes.screenPadding, 80, // espacio para bottom bar
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.62,
                  ),
                  itemCount: filtrados.length,
                  itemBuilder: (_, i) => _ProductoCard(
                    producto: filtrados[i],
                    fmt: fmt,
                    onAgregar: () => _agregarProducto(filtrados[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: GridView.builder(
        padding: const EdgeInsets.all(AppSizes.screenPadding),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.75,
        ),
        itemCount: 6,
        itemBuilder: (_, __) => Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          ),
        ),
      ),
    );
  }

  Widget _buildError(CatalogoProvider catalogo) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.screenPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 48, color: AppColors.textHint),
            const SizedBox(height: 16),
            Text(catalogo.error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: catalogo.cargarTodo,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Carrito Bottom Bar ───────────────────────────────────────────────────────

class _CarritoBottomBar extends StatefulWidget {
  final CarritoProvider carrito;
  final NumberFormat fmt;
  final bool expandido;
  final VoidCallback onToggle;
  final void Function(int puntosAUsar) onCheckout;

  const _CarritoBottomBar({
    required this.carrito,
    required this.fmt,
    required this.expandido,
    required this.onToggle,
    required this.onCheckout,
  });

  @override
  State<_CarritoBottomBar> createState() => _CarritoBottomBarState();
}

class _CarritoBottomBarState extends State<_CarritoBottomBar> {
  int _puntos = 0;
  int _puntosAUsar = 0;
  bool _usarPuntos = false;
  bool _cargandoPuntos = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargarPuntos());
  }

  Future<void> _cargarPuntos() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    setState(() => _cargandoPuntos = true);
    try {
      final data = await ApiService.get('/api/puntos/mis-puntos');
      if (!mounted) return;
      final pts = data is Map
          ? (data['data']?['puntos'] ?? data['puntos'] ?? data['total_puntos'] ?? 0)
          : 0;
      setState(() => _puntos = (pts as num).toInt());
    } catch (_) {}
    if (mounted) setState(() => _cargandoPuntos = false);
  }

  int _maxPuntosUsables(double subtotal) {
    final maxPorPts = _puntos;
    final maxPorTotal = (subtotal / 12.5).floor();
    final raw = maxPorPts < maxPorTotal ? maxPorPts : maxPorTotal;
    return (raw / 8).floor() * 8;
  }

  void _toggleUsarPuntos(double subtotal) {
    final maxUsables = _maxPuntosUsables(subtotal);
    setState(() {
      _usarPuntos = !_usarPuntos;
      _puntosAUsar = _usarPuntos ? maxUsables : 0;
    });
  }

  Widget _thumbFallback(String nombre) => Container(
        color: AppColors.primary.withValues(alpha: 0.1),
        alignment: Alignment.center,
        child: Text(
          nombre.isNotEmpty ? nombre[0].toUpperCase() : '?',
          style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final carrito = widget.carrito;
    final fmt = widget.fmt;
    final expandido = widget.expandido;

    if (carrito.items.isEmpty) {
      // Barra vacía discreta
      return Container(
        height: 52,
        color: AppColors.primary.withValues(alpha: 0.85),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            const Icon(Icons.shopping_cart_outlined, color: Colors.white54, size: 16),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Tu carrito está vacío — agrega productos para comenzar',
                style: GoogleFonts.nunito(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    final subtotal = carrito.total;
    final maxUsables = _maxPuntosUsables(subtotal);
    final descuentoPuntos = _usarPuntos ? _puntosAUsar * 12.5 : 0.0;
    final totalConDescuento = subtotal - descuentoPuntos;
    final mostrarPuntos = _puntos > 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Panel expandido — se ajusta al contenido hasta un máximo de 75% de
        // pantalla (antes tenía altura fija de 75% siempre, dejando mucho
        // espacio en blanco con pocos productos).
        AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOut,
          constraints: BoxConstraints(
            maxHeight: expandido ? MediaQuery.of(context).size.height * 0.75 : 0,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Color(0x4DCA0B0B), blurRadius: 24, offset: Offset(0, -4))],
          ),
          child: ClipRect(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              // Handle (drag pill)
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4),
                  width: 36, height: 4,
                  decoration: BoxDecoration(color: const Color(0xFFDDDDDD), borderRadius: BorderRadius.circular(2)),
                ),
              ),

              // Lista de items — se ajusta a su contenido, con scroll propio
              // si supera el máximo de altura del panel.
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  itemCount: carrito.items.length,
                  itemBuilder: (_, i) {
                    final item = carrito.items[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Thumb — imagen real del producto (igual que React: imgCl(item.img, 104, 104)
                          // renderizado en .carrito-item-thumb de 52×52)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 52, height: 52,
                              child: (item.producto.imagen != null && item.producto.imagen!.isNotEmpty)
                                  ? CachedNetworkImage(
                                      imageUrl: item.producto.imagen!,
                                      fit: BoxFit.cover,
                                      placeholder: (_, __) => Container(color: AppColors.surfaceVariant),
                                      errorWidget: (_, __, ___) => _thumbFallback(item.producto.nombre),
                                    )
                                  : _thumbFallback(item.producto.nombre),
                            ),
                          ),
                          const SizedBox(width: 14),
                          // Info columna
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.producto.nombre,
                                    style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w800),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                if (item.tipoChocolate != null || item.toppings.isNotEmpty || item.adiciones.isNotEmpty || item.salsas.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Wrap(
                                    spacing: 4, runSpacing: 3,
                                    children: [
                                      if (item.tipoChocolate != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: item.tipoChocolate == 'Negro' ? const Color(0xFF1E3A5F) : const Color(0xFFF0F0F0),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text('Chocolate ${item.tipoChocolate}',
                                              style: GoogleFonts.nunito(fontSize: 9, fontWeight: FontWeight.w600,
                                                  color: item.tipoChocolate == 'Negro' ? Colors.white : const Color(0xFF555555))),
                                        ),
                                      ..._agruparPorId(item.toppings, (t) => t.id).map((g) => Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1A1A1A),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text('${g.item.nombre}${g.cantidad > 1 ? ' ×${g.cantidad}' : ''}', style: GoogleFonts.nunito(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white)),
                                      )),
                                      ..._agruparPorId(item.adiciones, (a) => a.id).map((g) => Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFD97706),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text('${g.item.nombre}${g.cantidad > 1 ? ' ×${g.cantidad}' : ''}', style: GoogleFonts.nunito(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white)),
                                      )),
                                      if (item.producto.esBowl && item.salsas.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFFBEB),
                                            border: Border.all(color: const Color(0xFFD97706)),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text('Cobertura: ${item.salsas.first['nombre'] ?? ''}',
                                              style: GoogleFonts.nunito(fontSize: 9, fontWeight: FontWeight.w700, color: const Color(0xFF92400E))),
                                        )
                                      else
                                        ...item.salsas.asMap().entries.map((e) => Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFF7ED),
                                            border: Border.all(color: const Color(0xFFEA580C)),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            '${e.value['nombre']?.toString() ?? ''}${e.key >= 2 ? ' +\$5k' : ''}',
                                            style: GoogleFonts.nunito(fontSize: 9, fontWeight: FontWeight.w600, color: const Color(0xFFEA580C)),
                                          ),
                                        )),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 3),
                                Text('${fmt.format(item.precioUnitario)} c/u',
                                    style: GoogleFonts.nunito(fontSize: 11, color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Controles − cantidad +
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () => carrito.decrementar(item.lineaId),
                                child: Container(
                                  width: 28, height: 28,
                                  decoration: BoxDecoration(color: const Color(0xFFF0F0F0), borderRadius: BorderRadius.circular(6)),
                                  alignment: Alignment.center,
                                  child: const Text('−', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Text('${item.cantidad}', style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w700)),
                              ),
                              GestureDetector(
                                onTap: () => carrito.incrementar(item.lineaId),
                                child: Container(
                                  width: 28, height: 28,
                                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                                  alignment: Alignment.center,
                                  child: const Text('+', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 8),
                          // Subtotal item
                          Text(fmt.format(item.subtotal),
                              style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w800)),
                          const SizedBox(width: 6),
                          // Quitar
                          GestureDetector(
                            onTap: () => carrito.eliminar(item.lineaId),
                            child: const Icon(Icons.close_rounded, size: 18, color: Color(0xFFBBBBBB)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Resumen fijo al fondo — siempre visible
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total productos', style: GoogleFonts.nunito(fontSize: 11, color: AppColors.textSecondary)),
                        Text(fmt.format(subtotal), style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Domicilio', style: GoogleFonts.nunito(fontSize: 11, color: AppColors.textSecondary)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('Por confirmar', style: GoogleFonts.nunito(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primary)),
                        ),
                      ],
                    ),
                    const Divider(height: 12, thickness: 1),

                    // ── Puntos de fidelidad ──────────────────────────────────
                    if (_cargandoPuntos)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
                      )
                    else if (mostrarPuntos) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFfff5f5),
                          border: Border.all(color: const Color(0xFFfecaca)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Puntos disponibles',
                                        style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF1a1a1a))),
                                    Text('$_puntos pts · saldo \$${(_puntos * 12.5).toStringAsFixed(0)}',
                                        style: GoogleFonts.nunito(fontSize: 10, color: AppColors.textSecondary)),
                                  ],
                                ),
                                GestureDetector(
                                  onTap: maxUsables > 0 ? () => _toggleUsarPuntos(subtotal) : null,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: _usarPuntos ? AppColors.primary : const Color(0xFFe5e7eb),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      _usarPuntos ? '✓ Activo' : 'Usar puntos',
                                      style: GoogleFonts.nunito(
                                        fontSize: 11, fontWeight: FontWeight.w700,
                                        color: _usarPuntos ? Colors.white : const Color(0xFF374151),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_usarPuntos && maxUsables > 0) ...[
                              const SizedBox(height: 8),
                              Slider(
                                value: _puntosAUsar.toDouble(),
                                min: 0,
                                max: maxUsables.toDouble(),
                                divisions: maxUsables ~/ 8,
                                activeColor: AppColors.primary,
                                label: '$_puntosAUsar pts',
                                onChanged: (v) => setState(() => _puntosAUsar = ((v / 8).round() * 8).clamp(0, maxUsables)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFf0fdf4),
                                  border: Border.all(color: const Color(0xFF86efac)),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Descuento ($_puntosAUsar pts)',
                                        style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF166534))),
                                    Text('-${fmt.format(descuentoPuntos)}',
                                        style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF166534))),
                                  ],
                                ),
                              ),
                              if (_puntosAUsar > 0) ...[
                                const SizedBox(height: 4),
                                Text('* Esta compra no acumulará puntos nuevos',
                                    style: GoogleFonts.nunito(fontSize: 10, color: AppColors.primary)),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ],
                    // ─────────────────────────────────────────────────────────

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Subtotal', style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        Text(fmt.format(totalConDescuento),
                            style: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w900, color: const Color(0xFF1a1a1a))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => widget.onCheckout(_puntosAUsar),
                        child: Text('Hacer pedido', style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${carrito.totalItems} ${carrito.totalItems == 1 ? 'ítem' : 'ítems'} en el carrito',
                      style: GoogleFonts.nunito(fontSize: 11, color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              ],
            ),
          ),
        ),

        // Barra roja principal (izq = toggle, der = checkout)
        Container(
          height: 54,
          color: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              // Lado izquierdo: toggle
              Expanded(
                child: GestureDetector(
                  onTap: widget.onToggle,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      Container(
                        width: 24, height: 24,
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: Text('${carrito.totalItems}',
                            style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white)),
                      ),
                      Container(width: 1, height: 20, color: Colors.white.withValues(alpha: 0.25), margin: const EdgeInsets.symmetric(horizontal: 10)),
                      Text('Ver pedido', style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              ...carrito.items.take(2).map((item) => Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                                child: Text('${item.cantidad}× ${item.producto.nombre}',
                                    style: GoogleFonts.nunito(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                              )),
                              if (carrito.items.length > 2)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                                  child: Text('+${carrito.items.length - 2} más',
                                      style: GoogleFonts.nunito(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Icon(expandido ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
                          color: Colors.white, size: 20),
                    ],
                  ),
                ),
              ),
              // Lado derecho: total con descuento + "Hacer pedido"
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => widget.onCheckout(_puntosAUsar),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(fmt.format(totalConDescuento),
                        style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white)),
                    const SizedBox(width: 6),
                    Text('Hacer pedido', style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 11),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProductoCard extends StatelessWidget {
  final Producto producto;
  final NumberFormat fmt;
  final VoidCallback onAgregar;

  const _ProductoCard({
    required this.producto,
    required this.fmt,
    required this.onAgregar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Imagen — tamaño fijo, no se expande
          AspectRatio(
            aspectRatio: 1.15,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppSizes.radiusLg),
                  ),
                  child: producto.imagen != null && producto.imagen!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: producto.imagen!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          placeholder: (_, __) => Container(color: AppColors.surfaceVariant),
                          errorWidget: (_, __, ___) => _placeholder(),
                        )
                      : _placeholder(),
                ),
                _BadgeProducto(producto: producto),
              ],
            ),
          ),

          // Nombre + descripción — absorbe el espacio variable
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    producto.nombre,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (producto.descripcion != null &&
                      producto.descripcion!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      producto.descripcion ?? '',
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Precio + botón — SIEMPRE al fondo, tamaño fijo
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    fmt.format(producto.precio),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onAgregar,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '+ Agregar',
                      style: GoogleFonts.nunito(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
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

  Widget _placeholder() => Container(
        color: AppColors.surfaceVariant,
        child: const Center(
          child: Icon(Icons.cake_rounded, size: 40, color: AppColors.textHint),
        ),
      );
}

// Badge dinámico de beneficios — igual que React BadgeProducto (Catalogo.jsx).
class _BadgeProducto extends StatelessWidget {
  final Producto producto;
  const _BadgeProducto({required this.producto});

  @override
  Widget build(BuildContext context) {
    final tieneCobertura = producto.esBowl;
    final tieneChocolate = producto.permiteChocolate;
    final tieneToppings  = producto.permiteToppings && producto.maxToppings > 0;
    final tieneSalsas    = producto.permiteSalsas;

    if (!tieneCobertura && !tieneChocolate && !tieneToppings && !tieneSalsas) {
      return const SizedBox.shrink();
    }

    final maxTop = producto.maxToppings;
    final labelTop = maxTop == 1 ? '1 topping gratis' : '$maxTop toppings gratis';

    final lineas = [
      if (tieneCobertura) 'Elige cobertura',
      if (tieneChocolate) 'Elige chocolate',
      if (tieneToppings) labelTop,
      if (tieneSalsas) '2 salsas gratis',
    ];

    return Positioned(
      top: 8,
      right: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xCC3C0505),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xA6CA0B0B)),
        ),
        // IntrinsicWidth: dentro de un Positioned sin left/width, el Column no
        // tiene un ancho acotado — el separador `width: double.infinity` de
        // abajo necesita que el padre le dé un ancho finito para "estirarse"
        // hasta él, si no Flutter lanza "BoxConstraints forces an infinite
        // width" (visto en vivo en el catálogo).
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (int i = 0; i < lineas.length; i++) ...[
                if (i > 0)
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    height: 1,
                    width: double.infinity,
                    color: const Color(0x59CA0B0B),
                  ),
                Text(
                  lineas[i],
                  textAlign: TextAlign.center,
                  style: GoogleFonts.nunito(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.3,
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Agrupa una lista con elementos repetidos (un topping/adición aparece una
// vez por unidad) en {item, cantidad} — igual que React, que ya guarda
// cantidad en el objeto en vez de repetir el elemento.
class _ItemAgrupado<T> {
  final T item;
  final int cantidad;
  const _ItemAgrupado(this.item, this.cantidad);
}

List<_ItemAgrupado<T>> _agruparPorId<T>(List<T> items, Object Function(T) idDe) {
  final orden = <Object>[];
  final conteo = <Object, int>{};
  final porId = <Object, T>{};
  for (final it in items) {
    final id = idDe(it);
    if (!conteo.containsKey(id)) orden.add(id);
    conteo[id] = (conteo[id] ?? 0) + 1;
    porId[id] = it;
  }
  return orden.map((id) => _ItemAgrupado(porId[id] as T, conteo[id]!)).toList();
}
