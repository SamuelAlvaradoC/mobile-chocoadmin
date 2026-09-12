import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/models/pedido.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/auth_service.dart' show UserRole;
import '../../../core/utils/validar_sin_html.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/layouts/admin_bottom_nav.dart';
import '../../../shared/widgets/brand_icons.dart';

class DomiciliosScreen extends StatefulWidget {
  const DomiciliosScreen({super.key});

  @override
  State<DomiciliosScreen> createState() => _DomiciliosScreenState();
}

class _DomiciliosScreenState extends State<DomiciliosScreen> {
  bool _loading = true;
  String? _error;
  List<Pedido> _pedidos = [];
  int? _procesandoId;
  // Bloqueo global mientras CUALQUIER confirmación/rechazo está en curso
  // (quick-confirm, quick-reject o el modal de detalle) -- igual que React
  // (Domicilios.jsx: un solo estado `procesando` compartido por confirmar()
  // y rechazar(), que deshabilita los botones rápidos de TODAS las
  // tarjetas). Antes cada tarjeta solo se bloqueaba a sí misma
  // (_procesandoId por-tarjeta), así que se podían confirmar/rechazar dos
  // pedidos distintos en simultáneo.
  bool _bloqueado = false;
  final _busquedaCtrl = TextEditingController();
  String _busqueda = '';
  Timer? _timer;

  final _fmt =
      NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);

  @override
  void dispose() {
    _timer?.cancel();
    _busquedaCtrl.dispose();
    super.dispose();
  }

  List<Pedido> get _filtrados {
    if (_busqueda.isEmpty) return _pedidos;
    final q = _busqueda.toLowerCase();
    return _pedidos.where((p) {
      return (p.clienteNombre?.toLowerCase().contains(q) ?? false) ||
          p.id.toString().contains(q);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _cargar();
    _timer = Timer.periodic(
        const Duration(seconds: 8), (_) => _cargar(silencioso: true));
  }

  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await ApiService.get('/api/ventas',
          queryParams: {'estado': 'pendiente'});
      List raw = [];
      if (data is List) {
        raw = data;
      } else if (data is Map && data['data'] is List) {
        raw = data['data'] as List;
      }
      _pedidos = raw
          .map((e) => Pedido.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));
    } on ApiException catch (e) {
      // El refresco automático silencioso no debe tapar la lista visible con
      // una pantalla de error por un fallo de red pasajero -- se ignora,
      // igual que hace React (Domicilios.jsx: .catch(() => {})). Solo la
      // carga inicial o el botón "Actualizar pedidos" (silencioso: false)
      // muestran el error.
      if (silencioso) return;
      _error = e.message;
    } catch (e) {
      if (silencioso) return;
      _error = 'Error al cargar domicilios: ${e.toString()}';
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  // Solo la llamada de red — sin tocar setState/list/snackbar. Se usa desde
  // diálogos/modales, que la esperan ANTES de cerrarse. El refresh completo
  // (_despuesDeConfirmar) se dispara DESPUÉS de que el diálogo/modal ya
  // terminó de cerrarse, nunca mientras sigue en el árbol — evitar mezclar
  // el cierre de una ruta con un setState de pantalla completa es lo que
  // corrige el crash "_dependents.isEmpty" / "Duplicate GlobalKeys".
  Future<void> _confirmarApi(int id) async {
    await ApiService.patch('/api/ventas/$id/estado', {'nombre_estado': 'en_proceso'});
  }

  Future<void> _anularApi(int id, String motivo) async {
    await ApiService.patch('/api/ventas/$id/anular',
        {'motivo_anulacion': motivo.isNotEmpty ? motivo : 'Rechazado por admin'});
  }

  Future<void> _despuesDeConfirmar() async {
    await _cargar();
    if (mounted) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Pedido confirmado y enviado a cocina'),
        backgroundColor: Color(0xFF16A34A),
      ));
    }
  }

  Future<void> _despuesDeAnular() async {
    await _cargar();
    if (mounted) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Pedido rechazado'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  // Wrapper legado (mismo comportamiento visible que antes) usado solo
  // fuera de diálogos/modales, donde no hay riesgo de mezclar el pop de una
  // ruta con este setState de pantalla completa.
  Future<void> _confirmar(Pedido pedido) async {
    setState(() { _procesandoId = pedido.id; _bloqueado = true; });
    try {
      await _confirmarApi(pedido.id);
      await _despuesDeConfirmar();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error al confirmar pedido')));
      }
    }
    if (mounted) setState(() { _procesandoId = null; _bloqueado = false; });
  }

  String _wppUrl(Pedido p) {
    final digits = (p.clienteTelefono ?? '').replaceAll(RegExp(r'\D'), '');
    final number = digits.startsWith('57') ? digits : '57$digits';
    final msg = Uri.encodeComponent(
      'Hola ${p.clienteNombre ?? ''}, tu pedido #${p.id} de ChocoFreseo ya está confirmado y en preparación, en breves minutos será despachado hacia tu ubicación, por favor esté pendiente.\n\nCuando recibas tus productos, te invitamos a llenar este pequeño formulario, tu opinión es muy importante para nosotros:\nchocofreseo.com/#resenas',
    );
    return 'https://wa.me/$number?text=$msg';
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo abrir el enlace')));
      }
    }
  }

  // El modal solo ejecuta la llamada API y se cierra devolviendo un
  // resultado; el refresh de la lista + snackbar corren DESPUÉS, cuando el
  // modal ya salió por completo del árbol (ver comentario en _confirmarApi).
  void _mostrarDetalle(Pedido pedido) async {
    final resultado = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DetalleAdminModal(
        pedido: pedido,
        fmt: _fmt,
        onConfirmar: () async {
          setState(() => _bloqueado = true);
          try {
            await _confirmarApi(pedido.id);
          } finally {
            if (mounted) setState(() => _bloqueado = false);
          }
        },
        onRechazar: (motivo) async {
          setState(() => _bloqueado = true);
          try {
            await _anularApi(pedido.id, motivo);
          } finally {
            if (mounted) setState(() => _bloqueado = false);
          }
        },
      ),
    );
    if (!mounted || resultado == null) return;
    if (resultado == 'confirmado') {
      await _despuesDeConfirmar();
    } else if (resultado == 'rechazado') {
      await _despuesDeAnular();
    }
  }

  // Quick reject from card X button — requires non-empty motivo.
  // Mismo patrón de dos fases que _mostrarDetalle: el diálogo solo hace la
  // llamada API y se cierra; el refresh de la lista + snackbar corren
  // DESPUÉS de que el diálogo ya salió del árbol por completo.
  void _confirmarRechazo(Pedido pedido) async {
    final motivoCtrl = TextEditingController();
    bool procesando = false;
    String? error;
    final rechazado = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Rechazar pedido'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('¿Rechazar el pedido #${pedido.id}?'),
              const SizedBox(height: 12),
              TextField(
                controller: motivoCtrl,
                onChanged: (_) => setSt(() {}),
                decoration: const InputDecoration(
                  hintText: 'Motivo del rechazo...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
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
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white),
              // Disabled when motivo is empty (matches React)
              onPressed: (motivoCtrl.text.trim().isEmpty || procesando)
                  ? null
                  : () async {
                      final motivo = motivoCtrl.text.trim();
                      if (contieneEtiquetaHtml(motivo)) {
                        setSt(() => error = mensajeHtml);
                        return;
                      }
                      setSt(() { procesando = true; error = null; });
                      setState(() => _bloqueado = true);
                      try {
                        await _anularApi(pedido.id, motivo);
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } on ApiException catch (e) {
                        setSt(() { procesando = false; error = e.message; });
                      } catch (_) {
                        setSt(() { procesando = false; error = 'Error al rechazar pedido'; });
                      } finally {
                        if (mounted) setState(() => _bloqueado = false);
                      }
                    },
              child: procesando
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Confirmar rechazo'),
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
    if (mounted && rechazado == true) await _despuesDeAnular();
  }

  @override
  Widget build(BuildContext context) {
    // Rol de una sola pantalla (confirmador): AppBar simple, sin drawer.
    // Si quien mira esta pantalla es el admin (llegó desde su tab
    // "Confirmar"), sí necesita el bottom nav para salir a otra sección — el
    // rol confirmador en cambio no tiene a dónde más navegar.
    // El back del sistema (ir al Dashboard si es admin / doble-back-para-
    // salir si es confirmador) se maneja en el flatRouteHandler de
    // '/admin/domicilios' dentro de ShellAwareBackButtonDispatcher, conectado
    // en main.dart -- no aquí con PopScope, que no se dispara en la raíz de
    // una ruta sin nada que popear (ver double_back_to_exit.dart).
    final esAdmin = context.watch<AuthProvider>().user?.role == UserRole.admin;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Confirmar pedidos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppColors.error),
            tooltip: 'Cerrar sesión',
            onPressed: () => context.read<AuthProvider>().logout(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      bottomNavigationBar: esAdmin ? const AdminBottomNav.flat(currentRoute: '/admin/domicilios') : null,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.error, size: 48),
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: const TextStyle(color: AppColors.error)),
                      const SizedBox(height: 12),
                      TextButton(
                          onPressed: _cargar,
                          child: const Text('Reintentar')),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header: título + subtítulo + botón actualizar ─────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSizes.screenPadding,
                          AppSizes.screenPadding,
                          AppSizes.screenPadding,
                          0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '${_pedidos.length} pedidos esperando confirmación',
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _cargar,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.successLight,
                                border: Border.all(
                                    color: AppColors.success
                                        .withValues(alpha: 0.3)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.refresh_rounded,
                                        size: 14, color: AppColors.success),
                                    SizedBox(width: 4),
                                    Text('Actualizar pedidos',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.success)),
                                  ]),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Contenido: vacío o buscador + lista ───────────────────
                    if (_pedidos.isEmpty)
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.delivery_dining_rounded,
                                  size: 40, color: AppColors.primary),
                              SizedBox(height: 12),
                              Text(
                                'No hay pedidos pendientes por confirmar',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Cuando lleguen nuevos pedidos aparecerán aquí',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      // ── Buscador (solo cuando hay pedidos) ──────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            AppSizes.screenPadding,
                            AppSizes.sm,
                            AppSizes.screenPadding,
                            0),
                        child: TextField(
                          controller: _busquedaCtrl,
                          onChanged: (v) => setState(() => _busqueda = v),
                          style: const TextStyle(fontSize: 12, height: 1.0),
                          decoration: InputDecoration(
                            hintText: 'Buscar por cliente o número...',
                            hintStyle: const TextStyle(fontSize: 12),
                            prefixIcon: const Icon(Icons.search_rounded,
                                size: 16, color: AppColors.textSecondary),
                            suffixIcon: _busqueda.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close_rounded,
                                        size: 16),
                                    onPressed: () {
                                      _busquedaCtrl.clear();
                                      setState(() => _busqueda = '');
                                    },
                                  )
                                : null,
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 6),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                  color: AppColors.border, width: 1.5),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                  color: AppColors.border, width: 1.5),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                  color: AppColors.primary, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                      // ── Lista ───────────────────────────────────────────
                      Expanded(
                        child: RefreshIndicator(
                          color: AppColors.primary,
                          onRefresh: _cargar,
                          child: _filtrados.isEmpty
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.only(top: 80),
                                    child: Text(
                                      'Sin resultados para esa búsqueda',
                                      style: TextStyle(
                                          color: AppColors.textSecondary),
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.all(
                                      AppSizes.screenPadding),
                                  itemCount: _filtrados.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: AppSizes.sm),
                                  itemBuilder: (context, i) {
                                    final p = _filtrados[i];
                                    // Igual que React Domicilios.jsx:378-387 — tienePermiso('confirmar_domicilios')
                                    final puedeConfirmar = context.read<AuthProvider>().tienePermiso('confirmar_domicilios');
                                    return _DomicilioCard(
                                      pedido: p,
                                      procesando: _procesandoId == p.id,
                                      fmt: _fmt,
                                      onWhatsApp: p.clienteTelefono != null
                                          ? () => _launchUrl(_wppUrl(p))
                                          : null,
                                      onRechazar: (p.estado == 'pendiente' && puedeConfirmar && !_bloqueado)
                                          ? () => _confirmarRechazo(p)
                                          : null,
                                      onConfirmar: (p.estado == 'pendiente' && puedeConfirmar && !_bloqueado)
                                          ? () => _confirmar(p)
                                          : null,
                                      onDetalle: () => _mostrarDetalle(p),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────

class _DomicilioCard extends StatelessWidget {
  final Pedido pedido;
  final bool procesando;
  final NumberFormat fmt;
  final VoidCallback? onWhatsApp;
  final VoidCallback? onRechazar;
  final VoidCallback? onConfirmar;
  final VoidCallback onDetalle;

  const _DomicilioCard({
    required this.pedido,
    required this.procesando,
    required this.fmt,
    this.onWhatsApp,
    this.onRechazar,
    this.onConfirmar,
    required this.onDetalle,
  });

  @override
  Widget build(BuildContext context) {
    final fmtHora = DateFormat('d/MM/yyyy HH:mm', 'es_CO');
    // React: {d.direccion}, {d.barrio} — no incluye ciudad
    final dirCard = [pedido.direccion, pedido.barrio]
        .whereType<String>().where((s) => s.isNotEmpty).join(', ');

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header: id + fecha + pago badge ─────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '#${pedido.id}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (pedido.creadoEn != null)
                        Text(
                          fmtHora.format(pedido.creadoEn!),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (pedido.metodoPago != null)
                  _PagoBadgeAdmin(formaPago: pedido.metodoPago!),
              ],
            ),
            const SizedBox(height: AppSizes.xs),

            if (pedido.clienteNombre != null)
              _Row(Icons.person_outline_rounded, pedido.clienteNombre!),
            if (pedido.clienteTelefono != null)
              _Row(Icons.phone_outlined, pedido.clienteTelefono!),
            if (dirCard.isNotEmpty)
              _Row(Icons.location_on_outlined, dirCard),

            // Chips de productos
            if (pedido.lineas.isNotEmpty) ...[
              const SizedBox(height: AppSizes.xs),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: pedido.lineas
                    .map((l) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(
                                AppSizes.radiusCircle),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            '${l.cantidad}x ${l.nombreProducto}',
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary),
                          ),
                        ))
                    .toList(),
              ),
            ],

            // ⚠ Sin comprobante — solo transferencia/mixto sin comprobante (React: después de productos)
            if ((pedido.metodoPago == 'transferencia' ||
                    pedido.metodoPago == 'mixto') &&
                (pedido.comprobanteUrl ?? pedido.comprobante ?? '').isEmpty)
              Container(
                margin: const EdgeInsets.only(top: 6, bottom: 2),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF5F5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: const Text(
                  '⚠ Sin comprobante — verificar por WhatsApp antes de confirmar',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600),
                ),
              ),

            const SizedBox(height: AppSizes.sm),

            if (procesando)
              const Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.primary),
              )
            else
              // ── Acciones: total + wpp → X → ✓ → ojo ────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    fmt.format(pedido.total),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Row(
                    children: [
                      // WhatsApp
                      if (onWhatsApp != null) ...[
                        _IconBtn(
                          color: const Color(0xFF25D366),
                          solid: true,
                          onTap: onWhatsApp!,
                          child: const LogoWhatsApp(
                              size: 18, color: Colors.white),
                        ),
                        const SizedBox(width: 6),
                      ],
                      // Rechazar (X)
                      if (onRechazar != null) ...[
                        _IconBtn(
                          icon: Icons.close_rounded,
                          color: AppColors.error,
                          onTap: onRechazar!,
                        ),
                        const SizedBox(width: 6),
                      ],
                      // Confirmar (✓)
                      if (onConfirmar != null) ...[
                        _IconBtn(
                          icon: Icons.check_rounded,
                          color: AppColors.success,
                          onTap: onConfirmar!,
                        ),
                        const SizedBox(width: 6),
                      ],
                      // Ver detalle (ojo)
                      _IconBtn(
                        icon: Icons.remove_red_eye_outlined,
                        color: AppColors.textSecondary,
                        onTap: onDetalle,
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Row(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData? icon;
  final Widget? child;
  final Color color;
  final VoidCallback onTap;
  final bool solid;
  const _IconBtn(
      {this.icon, this.child, required this.color, required this.onTap, this.solid = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: solid ? color : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppSizes.radiusSm),
          border: solid ? null : Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: child ?? Icon(icon, color: solid ? Colors.white : color, size: 18),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Modal detalle admin — StatefulWidget para soportar sub-vista de rechazo
// Equivalente a React <ModalRevision> con vista 'revision' | 'rechazar'
// ────────────────────────────────────────────────────────────────────────────

class _DetalleAdminModal extends StatefulWidget {
  final Pedido pedido;
  final NumberFormat fmt;
  final Future<void> Function() onConfirmar;
  final Future<void> Function(String motivo) onRechazar;

  const _DetalleAdminModal({
    required this.pedido,
    required this.fmt,
    required this.onConfirmar,
    required this.onRechazar,
  });

  @override
  State<_DetalleAdminModal> createState() => _DetalleAdminModalState();
}

class _DetalleAdminModalState extends State<_DetalleAdminModal> {
  /// 'revision' | 'rechazar'  — igual que React vista state
  String _vista = 'revision';
  final _motivoCtrl = TextEditingController();
  // Evita el crash "_dependents.isEmpty": primero se completa la
  // actualización (llamada API + setState del padre) y solo después se
  // cierra este modal — nunca al revés.
  bool _procesando = false;
  String? _error;

  @override
  void dispose() {
    _motivoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_vista == 'rechazar') return _buildRechazarView(context);
    return _buildRevisionView(context);
  }

  // ── Sub-vista rechazar (igual a React vista==='rechazar') ─────────────────
  Widget _buildRechazarView(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: AppSizes.screenPadding,
        right: AppSizes.screenPadding,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Rechazar pedido',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 16),
          // Icono advertencia
          const Icon(Icons.warning_amber_rounded,
              size: 40, color: Color(0xFFF59E0B)),
          const SizedBox(height: 12),
          Text(
            '¿Rechazar el pedido #${widget.pedido.id}?',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 12),
          // Textarea motivo
          TextField(
            controller: _motivoCtrl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Motivo del rechazo...',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          // Botones: ← Volver | Confirmar rechazo
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      setState(() {
                        _motivoCtrl.clear();
                        _vista = 'revision';
                      }),
                  child: const Text('← Volver'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                  ),
                  // Disabled cuando motivo vacío (igual a React)
                  onPressed: (_motivoCtrl.text.trim().isEmpty || _procesando)
                      ? null
                      : () async {
                          final motivo = _motivoCtrl.text.trim();
                          if (contieneEtiquetaHtml(motivo)) {
                            setState(() => _error = mensajeHtml);
                            return;
                          }
                          setState(() { _procesando = true; _error = null; });
                          try {
                            await widget.onRechazar(motivo);
                            if (context.mounted) Navigator.pop(context, 'rechazado');
                          } on ApiException catch (e) {
                            if (mounted) setState(() { _procesando = false; _error = e.message; });
                          } catch (_) {
                            if (mounted) {
                              setState(() { _procesando = false; _error = 'Error al rechazar pedido'; });
                            }
                          }
                        },
                  child: _procesando
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Confirmar rechazo'),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  // ── Vista principal de revisión (igual a React vista==='revision') ─────────
  Widget _buildRevisionView(BuildContext context) {
    final pedido = widget.pedido;
    final fmt = widget.fmt;
    final tieneComprobante =
        (pedido.comprobanteUrl ?? pedido.comprobante ?? '').isNotEmpty;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Header: "Revisar pedido #id"
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.screenPadding),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Revisar pedido #${pedido.id}',
                    style: Theme.of(context).textTheme.headlineSmall),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Contenido scrollable
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSizes.screenPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Información del cliente ──────────────────────────
                  const Text('Información del cliente',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  _InfoSection(label: 'Cliente', value: pedido.clienteNombre),
                  _InfoSection(
                      label: 'Teléfono', value: pedido.clienteTelefono),
                  _InfoSection(label: 'Barrio', value: pedido.barrio),
                  _InfoSection(label: 'Ciudad', value: pedido.ciudad),
                  _InfoSection(
                      label: 'Dirección',
                      value: pedido.direccion?.isNotEmpty == true
                          ? pedido.direccion
                          : null),
                  _InfoSection(
                      label: 'Referencia',
                      value: pedido.referencia?.isNotEmpty == true
                          ? pedido.referencia
                          : null),
                  // Observaciones en info cliente
                  if (pedido.observaciones != null &&
                      pedido.observaciones!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        border:
                            Border.all(color: const Color(0xFFFDE68A)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(children: [
                        const Icon(Icons.warning_amber_rounded,
                            size: 13, color: Color(0xFFB45309)),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(pedido.observaciones!,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF92400E),
                                    fontWeight: FontWeight.w600))),
                      ]),
                    ),
                  ],

                  // ── Productos del pedido ─────────────────────────────
                  if (pedido.lineas.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Productos del pedido',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 8),
                    ...pedido.lineas.asMap().entries.map((entry) {
                      final l = entry.value;
                      final i = entry.key;
                      return Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 10),
                        decoration: i < pedido.lineas.length - 1
                            ? const BoxDecoration(
                                border: Border(
                                    bottom: BorderSide(
                                        color: Color(0xFFF0F0F0))))
                            : null,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                      child: Text(
                                          '${l.cantidad}x ${l.nombreProducto}',
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight:
                                                  FontWeight.w700))),
                                  Text(fmt.format(l.subtotal),
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.primary)),
                                ],
                              ),
                              if (l.chocolate != null ||
                                  l.salsas.isNotEmpty ||
                                  l.toppings.isNotEmpty ||
                                  l.adiciones.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: [
                                      if (l.chocolate != null)
                                        _ChipModal(
                                          label:
                                              'Chocolate ${l.chocolate!}',
                                          bg: l.chocolate!
                                                  .toLowerCase()
                                                  .contains('negro')
                                              ? const Color(0xFF1E3A5F)
                                              : const Color(0xFFF0F0F0),
                                          fg: l.chocolate!
                                                  .toLowerCase()
                                                  .contains('negro')
                                              ? Colors.white
                                              : const Color(0xFF555555),
                                        ),
                                      ...l.salsas.map((s) => _ChipModal(
                                            label: _nombreSalsa(s),
                                            outlined: true,
                                            outlineColor:
                                                const Color(0xFFEA580C),
                                            fg: const Color(0xFFEA580C),
                                            bg: const Color(0xFFFFF7ED),
                                          )),
                                      ...l.toppings.map((t) => _ChipModal(
                                            label: t,
                                            bg: const Color(0xFF1A1A1A),
                                            fg: Colors.white,
                                          )),
                                      ...l.adiciones.map((a) => _ChipModal(
                                            label: '+$a',
                                            bg: const Color(0xFFD97706),
                                            fg: Colors.white,
                                          )),
                                    ]),
                              ],
                            ]),
                      );
                    }),
                    const Divider(),
                    // Totales
                    _TotalRowAdmin(
                        label: 'Subtotal productos',
                        valor: fmt.format(pedido.subtotal)),
                    if (pedido.descuentoPuntos > 0)
                      _TotalRowAdmin(
                          label:
                              'Descuento puntos (${pedido.puntosUsados} pts)',
                          valor: '- ${fmt.format(pedido.descuentoPuntos)}',
                          green: true),
                    _TotalRowAdmin(
                        label: 'Domicilio',
                        valor: fmt.format(pedido.costoDomicilio)),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('TOTAL',
                            style:
                                TextStyle(fontWeight: FontWeight.w700)),
                        Text(fmt.format(pedido.total),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                                fontSize: 16)),
                      ],
                    ),
                  ],

                  // ── Método de pago ───────────────────────────────────
                  const SizedBox(height: 16),
                  const Text('Método de pago',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          if (pedido.metodoPago == 'efectivo')
                            const Icon(Icons.payments_outlined,
                                size: 18, color: Color(0xFF856404)),
                          if (pedido.metodoPago == 'transferencia') ...[
                            const Icon(Icons.phone_android_rounded,
                                size: 18, color: Color(0xFF0C5460)),
                          ],
                          if (pedido.metodoPago == 'mixto') ...[
                            const Icon(Icons.payments_outlined,
                                size: 16, color: Color(0xFF7C3AED)),
                            const SizedBox(width: 4),
                            const Icon(Icons.phone_android_rounded,
                                size: 16, color: Color(0xFF7C3AED)),
                          ],
                          const SizedBox(width: 8),
                          Text(
                            pedido.metodoPago == 'efectivo'
                                ? 'Pago en efectivo'
                                : pedido.metodoPago == 'mixto'
                                    ? 'Efectivo + Transferencia'
                                    : 'Transferencia bancaria',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13),
                          ),
                        ]),
                        if (pedido.metodoPago == 'mixto') ...[
                          const SizedBox(height: 6),
                          if (pedido.montoEfectivo != null)
                            Text(
                                'Efectivo: ${fmt.format(pedido.montoEfectivo!)}',
                                style: const TextStyle(fontSize: 13)),
                          if (pedido.montoTransferencia != null)
                            Text(
                                'Transferencia: ${fmt.format(pedido.montoTransferencia!)}',
                                style: const TextStyle(fontSize: 13)),
                        ],
                        if (pedido.metodoPago == 'transferencia' ||
                            pedido.metodoPago == 'mixto') ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: tieneComprobante
                                  ? const Color(0xFFF0FDF4)
                                  : const Color(0xFFFEFCE8),
                              border: Border.all(
                                  color: tieneComprobante
                                      ? const Color(0xFFBBF7D0)
                                      : const Color(0xFFFDE68A)),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                      tieneComprobante
                                          ? Icons.check_circle_rounded
                                          : Icons.warning_amber_rounded,
                                      size: 14,
                                      color: tieneComprobante
                                          ? const Color(0xFF16A34A)
                                          : const Color(0xFF92400E)),
                                  const SizedBox(width: 6),
                                  Text(
                                    tieneComprobante
                                        ? 'Comprobante recibido'
                                        : 'Sin comprobante — verificar por WhatsApp',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: tieneComprobante
                                            ? const Color(0xFF16A34A)
                                            : const Color(0xFF92400E)),
                                  ),
                                ]),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // ── Comprobante de pago ──────────────────────────────
                  if (pedido.metodoPago == 'transferencia' ||
                      pedido.metodoPago == 'mixto') ...[
                    const SizedBox(height: 16),
                    const Text('Comprobante de pago',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 8),
                    if (tieneComprobante)
                      GestureDetector(
                        onTap: () => showDialog(
                          context: context,
                          builder: (_) => Dialog(
                            backgroundColor: Colors.black,
                            insetPadding: const EdgeInsets.all(8),
                            child: Stack(
                              children: [
                                InteractiveViewer(
                                  child: CachedNetworkImage(
                                    imageUrl: (pedido.comprobanteUrl ??
                                        pedido.comprobante)!,
                                    fit: BoxFit.contain,
                                    placeholder: (_, __) => const Center(
                                        child: CircularProgressIndicator(
                                            color: Colors.white)),
                                    errorWidget: (_, __, ___) => const Icon(
                                        Icons.broken_image,
                                        color: Colors.white,
                                        size: 48),
                                  ),
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: GestureDetector(
                                    onTap: () =>
                                        Navigator.pop(context),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                          color: Colors.white24,
                                          shape: BoxShape.circle),
                                      child: const Icon(Icons.close,
                                          color: Colors.white, size: 20),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: CachedNetworkImage(
                            imageUrl: (pedido.comprobanteUrl ??
                                pedido.comprobante)!,
                            height: 200,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              height: 200,
                              color: AppColors.surfaceVariant,
                              child: const Center(
                                  child: CircularProgressIndicator(
                                      color: AppColors.primary)),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              height: 100,
                              color: AppColors.surfaceVariant,
                              child: const Center(
                                  child: Icon(Icons.broken_image,
                                      size: 40,
                                      color: AppColors.textHint)),
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEFCE8),
                          border: Border.all(
                              color: const Color(0xFFFDE68A)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 18, color: Color(0xFF92400E)),
                          SizedBox(width: 10),
                          Expanded(
                              child: Text(
                            'Sin comprobante — verificar por WhatsApp antes de confirmar',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF92400E)),
                          )),
                        ]),
                      ),
                    if (tieneComprobante) ...[
                      const SizedBox(height: 4),
                      const Text('Toca para ver en pantalla completa',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textHint)),
                    ],
                  ],

                  const SizedBox(height: AppSizes.md),
                ],
              ),
            ),
          ),

          // ── Botones de acción: Rechazar | Confirmar ──────────────────
          Padding(
            padding: EdgeInsets.only(
              left: AppSizes.screenPadding,
              right: AppSizes.screenPadding,
              top: 8,
              bottom:
                  MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () =>
                        setState(() => _vista = 'rechazar'),
                    child: const Text('Rechazar pedido',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: _procesando
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.check_rounded, size: 14),
                    label: const Text('Confirmar — enviar a cocina',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700)),
                    onPressed: _procesando
                        ? null
                        : () async {
                            setState(() { _procesando = true; _error = null; });
                            try {
                              await widget.onConfirmar();
                              if (context.mounted) Navigator.pop(context, 'confirmado');
                            } on ApiException catch (e) {
                              if (mounted) setState(() { _procesando = false; _error = e.message; });
                            } catch (_) {
                              if (mounted) {
                                setState(() { _procesando = false; _error = 'Error al confirmar pedido'; });
                              }
                            }
                          },
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Capitaliza nombre de salsa reemplazando guiones bajos por espacios
String _nombreSalsa(String s) =>
    s.replaceAll('_', ' ').replaceAllMapped(
        RegExp(r'\b\w'), (m) => m.group(0)!.toUpperCase());

class _InfoSection extends StatelessWidget {
  final String label;
  final String? value;
  const _InfoSection({required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ),
          Expanded(
              child: Text(value!, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _ChipModal extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final bool outlined;
  final Color? outlineColor;
  const _ChipModal(
      {required this.label,
      required this.bg,
      required this.fg,
      this.outlined = false,
      this.outlineColor});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: outlined ? Border.all(color: outlineColor ?? fg) : null,
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
      );
}

class _TotalRowAdmin extends StatelessWidget {
  final String label;
  final String valor;
  final bool green;
  const _TotalRowAdmin(
      {required this.label, required this.valor, this.green = false});
  @override
  Widget build(BuildContext context) {
    final color =
        green ? const Color(0xFF16A34A) : const Color(0xFF666666);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight:
                      green ? FontWeight.w700 : FontWeight.w400)),
          Text(valor,
              style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ── Badge método de pago ──────────────────────────────────────────────────────
class _PagoBadgeAdmin extends StatelessWidget {
  final String formaPago;
  const _PagoBadgeAdmin({required this.formaPago});

  @override
  Widget build(BuildContext context) {
    final isEf = formaPago == 'efectivo';
    final isMx = formaPago == 'mixto';
    final Color bg = isEf
        ? const Color(0xFFFFF3CD)
        : isMx
            ? const Color(0xFFF5F3FF)
            : const Color(0xFFD1ECF1);
    final Color color = isEf
        ? const Color(0xFF856404)
        : isMx
            ? const Color(0xFF7C3AED)
            : const Color(0xFF0C5460);
    final String label =
        isEf ? 'Efectivo' : isMx ? 'Mixto' : 'Transferencia';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}
