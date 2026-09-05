import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/models/pedido.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/utils/validar_sin_html.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/layouts/client_bottom_nav.dart' show ClientLogoutAction;
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/colombia_location_picker.dart';

final _fmtMonedaPuntos = NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);

class PerfilScreen extends StatefulWidget {
  const PerfilScreen({super.key});

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Levantado aquí (en vez de vivir solo dentro de _PuntosTab) para que el
  // banner del header y la pestaña "Puntos" lean el mismo dato ya cargado
  // -- una sola llamada a la API, sin dos fuentes que puedan desincronizarse
  // si se refrescan en momentos distintos.
  int _puntos = 0;
  double _saldoPuntos = 0;
  bool _puntosLoading = true;
  // Configurable por el admin desde esta misma pantalla (pestaña "Puntos",
  // ver _PuntosTab/_ValorPuntoCard) -- 12.5 es solo el default mientras
  // carga o si la llamada falla. Endpoint de lectura público (como /horario).
  double _valorPunto = 12.5;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _cargarPuntos();
    _cargarValorPunto();
  }

  Future<void> _cargarValorPunto() async {
    try {
      final data = await ApiService.get('/api/configuracion/valor-punto');
      final inner = data is Map && data['data'] is Map ? data['data'] as Map : (data is Map ? data : <String, dynamic>{});
      final valor = double.tryParse(inner['valor_punto_pesos']?.toString() ?? '');
      if (valor != null && mounted) setState(() => _valorPunto = valor);
    } catch (_) {}
  }

  // Sin "valor histórico": cambiar esto actualiza de inmediato el saldo en
  // pesos de TODOS los clientes (lo calcula el backend en tiempo real, ver
  // puntos/service.js). Las ventas ya cerradas no se tocan. Movido aquí
  // desde Dashboard -- misma llamada, sin cambios de lógica.
  Future<void> _guardarValorPunto(double valor) async {
    await ApiService.patch('/api/configuracion/valor-punto', {'valor_punto_pesos': valor});
    if (mounted) setState(() => _valorPunto = valor);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _cargarPuntos() async {
    setState(() => _puntosLoading = true);
    try {
      final data = await ApiService.get('/api/puntos/mis-puntos');
      final inner = data is Map && data['data'] is Map ? data['data'] as Map : (data is Map ? data : <String, dynamic>{});
      if (mounted) {
        setState(() {
          _puntos = (inner['puntos'] ?? 0) is int
              ? inner['puntos'] as int
              : int.tryParse(inner['puntos']?.toString() ?? '0') ?? 0;
          _saldoPuntos = double.tryParse((inner['saldo_pesos'] ?? (_puntos * 12.5)).toString()) ?? (_puntos * 12.5);
          _puntosLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _puntosLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Mi perfil'),
        centerTitle: true,
        actions: const [ClientLogoutAction()],
      ),
      body: Column(
        children: [
          // ── Header usuario ─────────────────────────────────────────────
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.lg, vertical: AppSizes.md),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  child: const Icon(Icons.person_outline_rounded, color: AppColors.primary, size: 28),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.nombre ?? '',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        user?.email ?? '',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Saldo de puntos — visible de inmediato, igual que en React
          // (Perfil.jsx: la tarjeta "Mis puntos ChocoFreseo" vive en el
          // header, no detrás de una pestaña). Antes solo se veía dentro de
          // la pestaña "Puntos"; esta franja compacta muestra el mismo dato
          // apenas se entra al perfil, sin duplicar la fuente de datos.
          _PuntosBanner(puntos: _puntos, saldo: _saldoPuntos, loading: _puntosLoading),

          // ── Selector de secciones (segmented pills, no TabBar subrayado) ──
          _PerfilSegmentedControl(controller: _tabController),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _DatosTab(user: user),
                const _HistorialTab(),
                const _SeguridadTab(),
                const _DireccionesTab(),
                _PuntosTab(
                  puntos: _puntos,
                  saldo: _saldoPuntos,
                  loading: _puntosLoading,
                  valorPunto: _valorPunto,
                  onRefresh: _cargarPuntos,
                  onGuardarValorPunto: user?.role == UserRole.admin ? _guardarValorPunto : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Franja compacta de puntos en el header — mismo dato que la pestaña
// "Puntos" (levantado en _PerfilScreenState), solo que visible sin tener
// que navegar a esa pestaña.
// ────────────────────────────────────────────────────────────────────────────

class _PuntosBanner extends StatelessWidget {
  final int puntos;
  final double saldo;
  final bool loading;
  const _PuntosBanner({required this.puntos, required this.saldo, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSizes.md, AppSizes.sm, AppSizes.md, 0),
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFF8B0000)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: loading
          ? const SizedBox(
              height: 18,
              child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))),
            )
          : Row(
              children: [
                const Icon(Icons.stars_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text('$puntos pts',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                const SizedBox(width: 4),
                Text('disponibles', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
                const Spacer(),
                Text(_fmtMonedaPuntos.format(saldo),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
              ],
            ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Selector de secciones — chips horizontales que controlan el mismo
// TabController (mismo índice, mismo TabBarView), solo cambia la
// presentación visual del TabBar subrayado tipo web a pills nativos.
// ────────────────────────────────────────────────────────────────────────────

class _PerfilSegmentedControl extends StatelessWidget {
  final TabController controller;
  const _PerfilSegmentedControl({required this.controller});

  static const _secciones = [
    (icon: Icons.person_outline_rounded, label: 'Datos'),
    (icon: Icons.receipt_long_rounded, label: 'Historial'),
    (icon: Icons.lock_outline_rounded, label: 'Contraseña'),
    (icon: Icons.location_on_outlined, label: 'Direcciones'),
    (icon: Icons.stars_rounded, label: 'Puntos'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(AppSizes.md, 4, AppSizes.md, 12),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (int i = 0; i < _secciones.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _SegmentPill(
                      icon: _secciones[i].icon,
                      label: _secciones[i].label,
                      active: controller.index == i,
                      onTap: () => controller.animateTo(i),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SegmentPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SegmentPill({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Material + InkWell (en vez de GestureDetector) para que la pill dé
    // ripple táctil al tocarla; ConstrainedBox asegura los ~44px mínimos de
    // alto tocable aunque el contenido visual sea más compacto.
    final radius = BorderRadius.circular(AppSizes.radiusCircle);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Material(
        color: active ? AppColors.primary : AppColors.background,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: active ? AppColors.primary : AppColors.border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: active ? Colors.white : AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Tab Datos personales
// ────────────────────────────────────────────────────────────────────────────

class _DatosTab extends StatefulWidget {
  final AuthUser? user;
  const _DatosTab({this.user});

  @override
  State<_DatosTab> createState() => _DatosTabState();
}

String _rolLabel(UserRole? role) {
  switch (role) {
    case UserRole.admin:
      return 'Administrador';
    case UserRole.confirmadorDomicilio:
      return 'Confirmador de pedidos';
    case UserRole.cocina:
      return 'Cocinero';
    case UserRole.domiciliario:
      return 'Domiciliario';
    case UserRole.cliente:
      return 'Cliente';
    default:
      return '—';
  }
}

class _DatosTabState extends State<_DatosTab> {
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _telefonoCtrl;
  late final TextEditingController _rolCtrl;

  bool _editando = false;
  bool _guardando = false;
  String? _error;
  String? _exito;

  @override
  void initState() {
    super.initState();
    _nombreCtrl =
        TextEditingController(text: widget.user?.nombre ?? '');
    _emailCtrl =
        TextEditingController(text: widget.user?.email ?? '');
    _telefonoCtrl =
        TextEditingController(text: widget.user?.telefono ?? '');
    _rolCtrl =
        TextEditingController(text: _rolLabel(widget.user?.role));
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _emailCtrl.dispose();
    _telefonoCtrl.dispose();
    _rolCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() => _error = null);
    final nombre = _nombreCtrl.text.trim();
    if (nombre.length < 2) {
      setState(() => _error = 'El nombre debe tener al menos 2 caracteres');
      return;
    }
    if (contieneEtiquetaHtml(nombre)) {
      setState(() => _error = mensajeHtml);
      return;
    }
    final telefono = _telefonoCtrl.text.trim();
    if (telefono.isNotEmpty && !RegExp(r'^3[0-9]{9}$').hasMatch(telefono)) {
      setState(() => _error = 'El teléfono debe ser un número colombiano válido de 10 dígitos (ej: 3001234567)');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
      _exito = null;
    });
    try {
      // React: PATCH /api/auth/perfil con body exacto { nombre, telefono }
      await ApiService.patch('/api/auth/perfil', {
        'nombre':   _nombreCtrl.text.trim(),
        'telefono': _telefonoCtrl.text.trim(),
      });
      setState(() {
        _exito = 'Datos actualizados correctamente';
        _editando = false;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Error al actualizar datos');
    }
    setState(() => _guardando = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSizes.screenPadding),
      child: Column(
        children: [
          if (_exito != null)
            Container(
              margin: const EdgeInsets.only(bottom: AppSizes.sm),
              padding: const EdgeInsets.all(AppSizes.sm),
              decoration: BoxDecoration(
                color: AppColors.successLight,
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline,
                      color: AppColors.success, size: 16),
                  const SizedBox(width: 6),
                  Text(_exito!,
                      style:
                          const TextStyle(color: AppColors.success)),
                ],
              ),
            ),

          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: AppSizes.sm),
              padding: const EdgeInsets.all(AppSizes.sm),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              ),
              child: Text(_error!,
                  style: const TextStyle(color: AppColors.error)),
            ),

          AppTextField(
            controller: _nombreCtrl,
            label: 'Nombre',
            prefixIcon: Icons.person_outline_rounded,
            readOnly: !_editando,
          ),
          const SizedBox(height: AppSizes.sm),
          AppTextField(
            controller: _emailCtrl,
            label: 'Email',
            prefixIcon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            readOnly: true,
            visuallyDisabled: _editando,
          ),
          const SizedBox(height: AppSizes.sm),
          AppTextField(
            controller: _telefonoCtrl,
            label: 'Teléfono',
            prefixIcon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            readOnly: !_editando,
          ),
          const SizedBox(height: AppSizes.sm),
          AppTextField(
            controller: _rolCtrl,
            label: 'Rol',
            prefixIcon: Icons.badge_outlined,
            readOnly: true,
            visuallyDisabled: _editando,
          ),
          const SizedBox(height: AppSizes.md),

          if (!_editando)
            AppButton(
              label: 'Editar datos',
              onPressed: () => setState(() => _editando = true),
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.primary,
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _guardando
                        ? null
                        : () => setState(() => _editando = false),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: AppButton(
                    label: 'Guardar',
                    isLoading: _guardando,
                    onPressed: _guardar,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Tab Historial de pedidos
// ────────────────────────────────────────────────────────────────────────────

class _HistorialTab extends StatefulWidget {
  const _HistorialTab();

  @override
  State<_HistorialTab> createState() => _HistorialTabState();
}

class _HistorialTabState extends State<_HistorialTab> {
  bool _loading = true;
  String? _error;
  List<Pedido> _pedidos = [];
  int _tiempoEspera = 30;
  int _pagina = 1;
  static const int _porPagina = 5;

  final _fmt =
      NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _cargar();
    _cargarTiempo();
  }

  Future<void> _cargarTiempo() async {
    try {
      final data = await ApiService.get('/api/configuracion/tiempo-espera');
      final inner = data is Map && data['data'] is Map ? data['data'] as Map : (data is Map ? data : <String, dynamic>{});
      final min = inner['minutos'];
      if (min != null && mounted) setState(() => _tiempoEspera = int.tryParse(min.toString()) ?? 30);
    } catch (_) {}
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.get('/api/ventas/mis-pedidos');
      List raw = [];
      if (data is List) {
        raw = data;
      } else if (data is Map && data['data'] is List) {
        raw = data['data'] as List;
      }
      _pedidos =
          raw.map((e) => Pedido.fromJson(e as Map<String, dynamic>)).toList();
      _pagina = 1;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Error al cargar historial';
    }
    setState(() => _loading = false);
  }

  int get _totalPaginas => (_pedidos.length / _porPagina).ceil().clamp(1, 1 << 30);

  List<Pedido> get _paginados {
    final inicio = (_pagina - 1) * _porPagina;
    if (inicio >= _pedidos.length) return [];
    final fin = (inicio + _porPagina).clamp(0, _pedidos.length);
    return _pedidos.sublist(inicio, fin);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                color: AppColors.error, size: 48),
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(color: AppColors.error)),
            TextButton(
                onPressed: _cargar, child: const Text('Reintentar')),
          ],
        ),
      );
    }
    if (_pedidos.isEmpty) {
      return const Center(
        child: Text('No tienes pedidos aún',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    final paginados = _paginados;
    final totalPaginas = _totalPaginas;

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _cargar,
            child: ListView.separated(
      padding: const EdgeInsets.all(AppSizes.screenPadding),
      itemCount: paginados.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSizes.sm),
      itemBuilder: (context, i) {
        final p = paginados[i];

        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            boxShadow: const [
              BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 6,
                  offset: Offset(0, 1)),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pedido #${p.id}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700),
                          ),
                          if (p.creadoEn != null)
                            Text(
                              DateFormat('dd/MM/yyyy HH:mm', 'es_CO')
                                  .format(p.creadoEn!),
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary),
                            ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _fmt.format(p.total),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                        _EstadoBadge(estado: p.estado),
                      ],
                    ),
                    const SizedBox(width: AppSizes.xs),
                    // Igual React: botón dedicado "Ver detalle" que abre un
                    // modal (antes la tarjeta entera expandía inline).
                    IconButton(
                      tooltip: 'Ver detalle',
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) => _DetallePedidoModal(pedido: p, fmt: _fmt, tiempoEspera: _tiempoEspera),
                      ),
                      icon: const Icon(Icons.visibility_outlined, color: AppColors.textSecondary, size: 20),
                    ),
                  ],
                ),
                // Igual React: tiempo estimado y motivo de anulación ya
                // visibles sin abrir el detalle.
                if (p.estado == 'pendiente' || p.estado == 'en_proceso') ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.access_time_rounded, size: 12, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text('$_tiempoEspera–${_tiempoEspera + 20} min estimados',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  ]),
                ],
                if (p.estado == 'anulado' && p.motivoAnulacion != null && p.motivoAnulacion!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  RichText(text: TextSpan(
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    children: [
                      const TextSpan(text: 'Motivo: ', style: TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: p.motivoAnulacion),
                    ],
                  )),
                ],
              ],
            ),
          ),
        );
      },
          ),
          ),
        ),
        if (totalPaginas > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: _pagina > 1 ? () => setState(() => _pagina--) : null,
                  child: const Text('← Anterior'),
                ),
                const SizedBox(width: 8),
                Text('$_pagina / $totalPaginas',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _pagina < totalPaginas ? () => setState(() => _pagina++) : null,
                  child: const Text('Siguiente →'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Modal "Ver detalle" de un pedido — igual orden que React SeccionHistorial
// (Pedido.jsx): header → estado+fecha → tiempo estimado → dirección →
// productos → totales → método de pago → motivo de cancelación → WhatsApp.
// ────────────────────────────────────────────────────────────────────────────

class _DetallePedidoModal extends StatelessWidget {
  final Pedido pedido;
  final NumberFormat fmt;
  final int tiempoEspera;
  const _DetallePedidoModal({required this.pedido, required this.fmt, required this.tiempoEspera});

  @override
  Widget build(BuildContext context) {
    final p = pedido;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
              child: Row(
                children: [
                  Expanded(child: Text('Pedido #${p.id}',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary))),
                  IconButton(icon: const Icon(Icons.close_rounded, size: 20), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Estado + fecha
                    Row(children: [
                      _EstadoBadge(estado: p.estado),
                      const SizedBox(width: 10),
                      if (p.creadoEn != null)
                        Text(DateFormat('dd/MM/yyyy HH:mm', 'es_CO').format(p.creadoEn!),
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ]),
                    // Tiempo estimado
                    if (p.estado == 'pendiente' || p.estado == 'en_proceso') ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.access_time_rounded, size: 12, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text('⏱ $tiempoEspera–${tiempoEspera + 20} min estimados',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                        ]),
                      ),
                    ],
                    // Dirección
                    if (p.direccion != null && p.direccion!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.location_on_outlined, size: 13, color: AppColors.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              [p.direccion, p.barrio].where((s) => s != null && s.isNotEmpty).cast<String>().join(', '),
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    // Productos
                    if (p.lineas.isEmpty)
                      const Text('Sin detalle', style: TextStyle(color: AppColors.textSecondary))
                    else
                      ...p.lineas.map((l) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Wrap(
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    spacing: 6,
                                    children: [
                                      Text('${l.cantidad}× ${l.nombreProducto}',
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                      if (l.chocolate != null && l.chocolate!.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: l.chocolate == 'Negro' ? const Color(0xFF1E3A5F) : const Color(0xFFF0F0F0),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text('Chocolate ${l.chocolate}',
                                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                                                  color: l.chocolate == 'Negro' ? Colors.white : const Color(0xFF555555))),
                                        ),
                                    ],
                                  ),
                                ),
                                Text(fmt.format(l.subtotal),
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                              ],
                            ),
                            if (l.salsas.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 3, runSpacing: 3,
                                children: l.salsas.map((s) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF7ED),
                                    border: Border.all(color: const Color(0xFFEA580C)),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : s,
                                      style: const TextStyle(fontSize: 10, color: Color(0xFFEA580C), fontWeight: FontWeight.w600)),
                                )).toList(),
                              ),
                            ],
                            if (l.toppings.isNotEmpty || l.adiciones.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 3, runSpacing: 3,
                                children: [
                                  ...l.toppings.map((t) => Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(20)),
                                    child: Text(t, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
                                  )),
                                  // Igual React: adiciones sin precio en el badge (solo nombre ×cantidad).
                                  ...l.adiciones.map((a) => Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFFBEB),
                                      border: Border.all(color: const Color(0xFFD97706)),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text('+${a.replaceAll(RegExp(r' \$[\d.]+$'), '')}',
                                        style: const TextStyle(fontSize: 10, color: Color(0xFFD97706), fontWeight: FontWeight.w600)),
                                  )),
                                ],
                              ),
                            ],
                          ],
                        ),
                      )),
                    // Totales
                    const SizedBox(height: 4),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Subtotal', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        Text(fmt.format(p.subtotal), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                    if (p.descuentoPuntos > 0) ...[
                      const SizedBox(height: 3),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Descuento puntos (${p.puntosUsados} pts)',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF16A34A), fontWeight: FontWeight.w700)),
                          Text('-${fmt.format(p.descuentoPuntos)}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF16A34A), fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ],
                    if (p.puntosGanados > 0) ...[
                      const SizedBox(height: 3),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Puntos ganados',
                              style: TextStyle(fontSize: 12, color: Color(0xFFD97706), fontWeight: FontWeight.w700)),
                          Text('+${p.puntosGanados} pts',
                              style: const TextStyle(fontSize: 12, color: Color(0xFFD97706), fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 3),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Domicilio', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        Text(fmt.format(p.costoDomicilio), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Divider(height: 1),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF16A34A))),
                        Text(fmt.format(p.total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF16A34A))),
                      ],
                    ),
                    // Método de pago
                    if (p.metodoPago != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(20)),
                        child: Text(
                          p.metodoPago == 'efectivo' ? '💵 Efectivo' : p.metodoPago == 'transferencia' ? '🏦 Transferencia' : '💵🏦 Mixto',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                    // Motivo de cancelación
                    if (p.estado == 'anulado' && p.motivoAnulacion != null && p.motivoAnulacion!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF5F5),
                          border: Border.all(color: const Color(0xFFFECACA)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: RichText(text: TextSpan(
                          style: const TextStyle(fontSize: 12, color: AppColors.primary),
                          children: [
                            const TextSpan(text: 'Motivo de cancelación: ', style: TextStyle(fontWeight: FontWeight.w700)),
                            TextSpan(text: p.motivoAnulacion),
                          ],
                        )),
                      ),
                    ],
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: () => launchUrl(
                        Uri.parse('https://wa.me/573159914624'),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.chat_outlined, size: 14, color: Color(0xFF16A34A)),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text('¿Necesitas ayuda? Escríbenos por WhatsApp',
                                style: TextStyle(fontSize: 12, color: Color(0xFF16A34A), fontWeight: FontWeight.w700),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
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

// ────────────────────────────────────────────────────────────────────────────
// Tab Seguridad (cambiar contraseña)
// ────────────────────────────────────────────────────────────────────────────

class _SeguridadTab extends StatefulWidget {
  const _SeguridadTab();

  @override
  State<_SeguridadTab> createState() => _SeguridadTabState();
}

class _SeguridadTabState extends State<_SeguridadTab> {
  final _actualCtrl = TextEditingController();
  final _nuevaCtrl = TextEditingController();
  final _confirmarCtrl = TextEditingController();
  bool _guardando = false;
  String? _error;
  String? _exito;

  @override
  void dispose() {
    _actualCtrl.dispose();
    _nuevaCtrl.dispose();
    _confirmarCtrl.dispose();
    super.dispose();
  }

  Future<void> _cambiar() async {
    if (_actualCtrl.text.trim().isEmpty || _nuevaCtrl.text.trim().isEmpty || _confirmarCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Completa todos los campos');
      return;
    }
    if (_nuevaCtrl.text != _confirmarCtrl.text) {
      setState(() => _error = 'Las contraseñas nuevas no coinciden');
      return;
    }
    if (_nuevaCtrl.text.length < 8) {
      setState(() => _error = 'La contraseña debe tener al menos 8 caracteres');
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
      _exito = null;
    });

    try {
      await ApiService.patch('/api/auth/cambiar-contrasena-auth', {
        'contrasena_actual': _actualCtrl.text,
        'nueva_contrasena': _nuevaCtrl.text,
      });
      _actualCtrl.clear();
      _nuevaCtrl.clear();
      _confirmarCtrl.clear();
      setState(() => _exito = 'Contraseña cambiada exitosamente');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Error al cambiar contraseña');
    }

    setState(() => _guardando = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSizes.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_exito != null)
            Container(
              margin: const EdgeInsets.only(bottom: AppSizes.sm),
              padding: const EdgeInsets.all(AppSizes.sm),
              decoration: BoxDecoration(
                color: AppColors.successLight,
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline,
                      color: AppColors.success, size: 16),
                  const SizedBox(width: 6),
                  Text(_exito!,
                      style:
                          const TextStyle(color: AppColors.success)),
                ],
              ),
            ),

          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: AppSizes.sm),
              padding: const EdgeInsets.all(AppSizes.sm),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              ),
              child: Text(_error!,
                  style: const TextStyle(color: AppColors.error)),
            ),

          AppTextField(
            controller: _actualCtrl,
            label: 'Contraseña actual',
            prefixIcon: Icons.lock_outline,
            obscureText: true,
          ),
          const SizedBox(height: AppSizes.sm),
          AppTextField(
            controller: _nuevaCtrl,
            label: 'Nueva contraseña',
            prefixIcon: Icons.lock_reset_rounded,
            obscureText: true,
          ),
          const SizedBox(height: AppSizes.sm),
          AppTextField(
            controller: _confirmarCtrl,
            label: 'Confirmar nueva contraseña',
            prefixIcon: Icons.lock_reset_rounded,
            obscureText: true,
          ),
          const SizedBox(height: AppSizes.md),

          AppButton(
            label: 'Cambiar contraseña',
            isLoading: _guardando,
            onPressed: _cambiar,
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Tab Direcciones
// ────────────────────────────────────────────────────────────────────────────

class _DireccionesTab extends StatefulWidget {
  const _DireccionesTab();
  @override
  State<_DireccionesTab> createState() => _DireccionesTabState();
}

class _DireccionesTabState extends State<_DireccionesTab> {
  List<Map<String, dynamic>> _direcciones = [];
  bool _loading  = true;
  bool _agregando = false;
  bool _guardando = false;
  String? _error;
  int _formKey = 0;

  // Estado del formulario nueva dirección — mismo patrón que checkout
  Map<String, dynamic> _nuevaDireccion = {};
  Map<String, String>  _errores = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await ApiService.get('/api/auth/mis-direcciones');
      List raw = data is List ? data : (data is Map && data['data'] is List ? data['data'] as List : []);
      if (mounted) {
        setState(() => _direcciones = raw
            .where((e) => (e as Map)['estado'] != 0)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList());
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Error al cargar direcciones');
    }
    if (mounted) setState(() => _loading = false);
  }

  // Validación idéntica a React SeccionDirecciones.handleAgregar
  Future<void> _agregar() async {
    final errs = <String, String>{};
    if ((_nuevaDireccion['tipo_via']?.toString() ?? '').isEmpty)               errs['tipo_via']        = 'Selecciona el tipo de vía';
    if ((_nuevaDireccion['numero']?.toString().trim() ?? '').isEmpty)          errs['numero']          = 'Ingresa el número de la vía';
    if ((_nuevaDireccion['numeral']?.toString().trim() ?? '').isEmpty)         errs['numeral']         = 'Ingresa el numeral';
    if ((_nuevaDireccion['complemento']?.toString().trim() ?? '').isEmpty)     errs['complemento']     = 'Ingresa el complemento';
    if ((_nuevaDireccion['direccion_linea']?.toString().trim() ?? '').isEmpty) errs['direccion_linea'] = 'Ingresa la dirección';
    if ((_nuevaDireccion['barrio']?.toString().trim() ?? '').isEmpty)          errs['barrio']          = 'Ingresa el barrio';
    if ((_nuevaDireccion['ciudad']?.toString().trim() ?? '').isEmpty)          errs['ciudad']          = 'Selecciona el municipio';
    if (errs.isNotEmpty) { setState(() => _errores = errs); return; }

    setState(() { _guardando = true; _errores = {}; _error = null; });
    try {
      String? sv(String k) {
        final v = _nuevaDireccion[k]?.toString().trim() ?? '';
        return v.isNotEmpty ? v : null;
      }
      await ApiService.post('/api/auth/mis-direcciones', {
        'direccion_linea': _nuevaDireccion['direccion_linea'] ?? '',
        'barrio':          sv('barrio'),
        'ciudad':          sv('ciudad'),
        'departamento':    'Antioquia',
        'referencia':      sv('referencia'),
        'id_barrio':       _nuevaDireccion['id_barrio'],
      });
      if (mounted) {
        setState(() {
          _nuevaDireccion = {};
          _errores = {};
          _agregando = false;
          _formKey++;
        });
      }
      await _cargar();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Error al guardar dirección');
    }
    if (mounted) setState(() => _guardando = false);
  }

  Future<void> _eliminar(int id) async {
    try {
      await ApiService.delete('/api/auth/mis-direcciones/$id');
      await _cargar();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Error al eliminar dirección');
    }
  }

  void _pedirConfirmacion(Map<String, dynamic> dir) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        title: const Column(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: Color(0xFFFFF5F5),
              child: Icon(Icons.delete_outline_rounded, color: AppColors.primary, size: 24),
            ),
            SizedBox(height: 12),
            Text('¿Eliminar dirección?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Text(dir['direccion_linea']?.toString() ?? '',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              [dir['barrio'], dir['ciudad']].where((v) => v != null && v.toString().isNotEmpty).join(', '),
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      final id = dir['id_direccion'] ?? dir['id'];
                      if (id != null) _eliminar(id as int);
                    },
                    child: const Text('Sí, eliminar'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _cancelarAgregar() {
    setState(() {
      _agregando = false;
      _nuevaDireccion = {};
      _errores = {};
      _formKey++;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _cargar,
      child: SingleChildScrollView(
      padding: const EdgeInsets.all(AppSizes.screenPadding),
      child: Column(
        children: [
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: AppSizes.sm),
              padding: const EdgeInsets.all(AppSizes.sm),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              ),
              child: Text(_error!, style: const TextStyle(color: AppColors.error)),
            ),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_direcciones.length} dirección${_direcciones.length != 1 ? 'es' : ''} guardada${_direcciones.length != 1 ? 's' : ''}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              TextButton.icon(
                icon: Icon(_agregando ? Icons.close : Icons.add, size: 16),
                label: Text(_agregando ? 'Cancelar' : '+ Agregar'),
                onPressed: () {
                  if (_agregando) {
                    _cancelarAgregar();
                  } else {
                    setState(() => _agregando = true);
                  }
                },
              ),
            ],
          ),

          // ── Formulario nueva dirección (usa FormDireccion idéntico al checkout) ──
          if (_agregando) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FormDireccion(
                    key: ValueKey(_formKey),
                    value: _nuevaDireccion,
                    onChange: (field, value) {
                      setState(() {
                        _nuevaDireccion = {..._nuevaDireccion, field: value};
                        _errores.remove(field);
                        if (field == 'direccion_linea') _errores.remove('direccion_linea');
                      });
                    },
                    errors: _errores,
                    isClient: true,
                  ),
                  const SizedBox(height: AppSizes.md),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _guardando ? null : _cancelarAgregar,
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppButton(
                        label: 'Guardar dirección',
                        isLoading: _guardando,
                        onPressed: _agregar,
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          if (_direcciones.isEmpty)
            const Center(
              child: Column(
                children: [
                  SizedBox(height: 40),
                  Text('📍', style: TextStyle(fontSize: 40)),
                  SizedBox(height: 12),
                  Text('No tienes direcciones guardadas',
                      style: TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            )
          else
            ...List.generate(_direcciones.length, (i) {
              final d = _direcciones[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_outlined, color: AppColors.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (d['direccion_linea'] ?? d['direccion'])?.toString() ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if ([d['barrio'], d['ciudad']]
                              .where((v) => v != null && v.toString().isNotEmpty)
                              .isNotEmpty)
                            Text(
                              [d['barrio'], d['ciudad']]
                                  .where((v) => v != null && v.toString().isNotEmpty)
                                  .join(', '),
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          if ((d['referencia'] ?? '').toString().isNotEmpty)
                            Text(d['referencia'].toString(),
                                style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                      onPressed: () => _pedirConfirmacion(d),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Tab Puntos — antes era su propia pantalla con ítem propio en el bottom
// nav; ahora vive dentro de Perfil como una pestaña más, sin su propio
// Scaffold/AppBar (los provee PerfilScreen). El dato (puntos/saldo/loading)
// se recibe por parámetro desde _PerfilScreenState -- una sola llamada a
// GET /api/puntos/mis-puntos compartida con el banner del header, en vez de
// que cada uno la pida por su cuenta.
// ────────────────────────────────────────────────────────────────────────────

class _PuntosTab extends StatelessWidget {
  final int puntos;
  final double saldo;
  final bool loading;
  final double valorPunto;
  final Future<void> Function() onRefresh;
  // Solo admin: control para editar el valor del punto (movido aquí desde
  // Dashboard) -- null cuando el usuario no es admin.
  final Future<void> Function(double)? onGuardarValorPunto;
  const _PuntosTab({
    required this.puntos,
    required this.saldo,
    required this.loading,
    required this.valorPunto,
    required this.onRefresh,
    this.onGuardarValorPunto,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(AppSizes.md),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSizes.lg),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, Color(0xFF8B0000)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppSizes.radiusLg),
              boxShadow: [
                BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: loading
                ? const Center(
                    child: SizedBox(height: 40, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('MIS PUNTOS CHOCOFRESEO',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white70, letterSpacing: 1)),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('$puntos',
                                    style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white, height: 1)),
                                const Text('puntos disponibles', style: TextStyle(fontSize: 12, color: Colors.white70)),
                              ],
                            ),
                          ),
                          Container(width: 1, height: 50, color: Colors.white30),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_fmtMonedaPuntos.format(saldo),
                                      style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white, height: 1)),
                                  const Text('saldo disponible', style: TextStyle(fontSize: 12, color: Colors.white70)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                          '1 punto = \$${valorPunto == valorPunto.roundToDouble() ? valorPunto.toStringAsFixed(0) : valorPunto.toStringAsFixed(2)} · Se acumulan con cada compra',
                          style: const TextStyle(fontSize: 11, color: Colors.white60)),
                    ],
                  ),
          ),
          const SizedBox(height: AppSizes.md),
          Container(
            padding: const EdgeInsets.all(AppSizes.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: AppColors.textSecondary, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Usa tus puntos como descuento al hacer un pedido, en el paso de pago del carrito.',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          if (onGuardarValorPunto != null) ...[
            const SizedBox(height: AppSizes.md),
            _ValorPuntoCard(valorPunto: valorPunto, onSaved: onGuardarValorPunto!),
          ],
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Editor admin del valor del punto de fidelidad -- movido aquí (antes vivía
// en Dashboard, junto a horario/tiempo de espera). Widget/lógica sin tocar:
// misma tarjeta + bottom sheet, mismas validaciones y alerta de rango, solo
// cambia desde dónde se muestra la entrada para abrirlo.
// ────────────────────────────────────────────────────────────────────────────

// Rango habitual del negocio -- fuera de esto (pero dentro del tope
// absoluto) se pide confirmar antes de guardar, en vez de bloquear: puede
// ser una decisión real (ej. una promoción), no siempre un error de tecleo.
const _valorPuntoRangoUsualMin = 10.0;
const _valorPuntoRangoUsualMax = 25.0;
// Tope absoluto -- evita un error de tecleo tipo "99999" (mismo valor que
// valida el backend en configuracion/routes.js).
const _valorPuntoMax = 100.0;

class _ValorPuntoCard extends StatelessWidget {
  final double valorPunto;
  final Future<void> Function(double) onSaved;
  const _ValorPuntoCard({required this.valorPunto, required this.onSaved});

  // Mismo patrón que Tiempo estimado / Horario (Dashboard): editar abre un bottom sheet.
  void _abrirEditor(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EditarValorPuntoSheet(valorInicial: valorPunto, onSaved: onSaved),
    );
  }

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFCA8A04);
    final valorFmt = valorPunto == valorPunto.roundToDouble()
        ? valorPunto.toStringAsFixed(0)
        : valorPunto.toStringAsFixed(2);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      child: InkWell(
        onTap: () => _abrirEditor(context),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(AppSizes.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            boxShadow: const [BoxShadow(color: AppColors.shadow, blurRadius: 6, offset: Offset(0, 2))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: gold.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: const Icon(Icons.stars_rounded, size: 20, color: gold),
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Valor del punto de fidelidad', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                Text('\$$valorFmt por punto',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: gold)),
              ])),
            ]),
            const SizedBox(height: AppSizes.xs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(color: gold, borderRadius: BorderRadius.circular(6)),
              child: const Text('✏ Editar valor', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _EditarValorPuntoSheet extends StatefulWidget {
  final double valorInicial;
  final Future<void> Function(double) onSaved;
  const _EditarValorPuntoSheet({required this.valorInicial, required this.onSaved});

  @override
  State<_EditarValorPuntoSheet> createState() => _EditarValorPuntoSheetState();
}

class _EditarValorPuntoSheetState extends State<_EditarValorPuntoSheet> {
  late final _ctrl = TextEditingController(
    text: widget.valorInicial == widget.valorInicial.roundToDouble()
        ? widget.valorInicial.toStringAsFixed(0)
        : widget.valorInicial.toStringAsFixed(2),
  );
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // null = valor inválido (ya dejó el mensaje en _error)
  double? _validar() {
    final v = double.tryParse(_ctrl.text.replaceAll(',', '.'));
    if (v == null) { setState(() => _error = 'Ingresa un número válido'); return null; }
    if (v <= 0) { setState(() => _error = 'El valor debe ser mayor a 0'); return null; }
    if (v > _valorPuntoMax) { setState(() => _error = 'El valor no puede superar \$${_valorPuntoMax.toStringAsFixed(0)} por punto'); return null; }
    if (double.parse(v.toStringAsFixed(2)) != v) { setState(() => _error = 'Máximo 2 decimales'); return null; }
    return v;
  }

  Future<void> _confirmarFueraDeRango(double v) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Valor fuera de lo habitual?'),
        content: Text(
          '\$${v.toStringAsFixed(2)} por punto está fuera del rango habitual '
          '(\$${_valorPuntoRangoUsualMin.toStringAsFixed(0)}–\$${_valorPuntoRangoUsualMax.toStringAsFixed(0)}). '
          'Este cambio afecta de inmediato el saldo en pesos de TODOS los clientes. '
          '¿Confirmas que quieres guardar este valor?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, guardar'),
          ),
        ],
      ),
    );
    if (confirmar == true) await _guardar(v, confirmado: true);
  }

  Future<void> _guardar(double? valorConfirmado, {bool confirmado = false}) async {
    final v = valorConfirmado ?? _validar();
    if (v == null) return;

    if (!confirmado && (v < _valorPuntoRangoUsualMin || v > _valorPuntoRangoUsualMax)) {
      await _confirmarFueraDeRango(v);
      return;
    }

    setState(() { _guardando = true; _error = null; });
    try {
      await widget.onSaved(v);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _guardando = false;
          _error = e is ApiException ? e.message : 'Error al guardar el valor del punto';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Text('Valor del punto de fidelidad',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
            'No hay "valor histórico": cambiar esto actualiza de inmediato el saldo en pesos de todos los clientes. Las ventas ya cerradas no se tocan.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: AppSizes.md),
          TextField(
            controller: _ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: InputDecoration(labelText: 'Pesos por punto', prefixText: '\$ ', errorText: _error),
            onChanged: (_) { if (_error != null) setState(() => _error = null); },
          ),
          const SizedBox(height: AppSizes.lg),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _guardando ? null : () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: ElevatedButton(
                onPressed: _guardando ? null : () => _guardar(null),
                child: _guardando
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Guardar'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────

class _EstadoBadge extends StatelessWidget {
  final String estado;
  const _EstadoBadge({required this.estado});

  static const _labels = {
    'pendiente':  'Pendiente',
    'en_proceso': 'En cocina',
    'listo':      'En cocina',
    'despachado': 'En camino',
    'entregado':  'Entregado',
    'anulado':    'Cancelado',
  };

  String get _label => _labels[estado] ?? (estado.isNotEmpty ? estado[0].toUpperCase() + estado.substring(1) : estado);

  Color get _color {
    switch (estado) {
      case 'pendiente':   return const Color(0xFFCA8A04);
      case 'en_proceso':  return const Color(0xFFEA580C);
      case 'listo':       return const Color(0xFF3B82F6);
      case 'despachado':  return const Color(0xFF7C3AED);
      case 'entregado':   return const Color(0xFF16A34A);
      case 'anulado':     return const Color(0xFFCA0B0B);
      default:            return const Color(0xFF888888);
    }
  }

  Color get _bg {
    switch (estado) {
      case 'pendiente':   return const Color(0xFFFEFCE8);
      case 'en_proceso':  return const Color(0xFFFFF7ED);
      case 'listo':       return const Color(0xFFEFF6FF);
      case 'despachado':  return const Color(0xFFF5F3FF);
      case 'entregado':   return const Color(0xFFF0FDF4);
      case 'anulado':     return const Color(0xFFFFF5F5);
      default:            return const Color(0xFFF5F5F5);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _label,
        style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: _color),
      ),
    );
  }
}
