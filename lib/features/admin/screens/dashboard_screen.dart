import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/services/api_service.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/layouts/admin_layout.dart';
import '../widgets/cierre_caja_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  String? _error;

  // Datos dashboard
  double _totalDia  = 0;
  int    _ventasHoy = 0;
  List<Map<String, dynamic>> _productosMasVendidos = [];

  // Financial breakdown
  double _totalEfectivo      = 0;
  double _totalTransferencia = 0;
  double _totalDomicilios    = 0;
  int    _domiciliosActivos  = 0;

  // Tiempo estimado editable
  int _tiempoEspera = 30;

  // Horario editable
  int  _horaApertura      = 13;
  int  _horaCierre        = 20;

  // Domiciliarios del día
  List<Map<String, dynamic>> _domiciliariosDia = [];

  // Filtro de fecha (igual React)
  String _filtroFecha = '';

  final _fmt =
      NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);
  final _fmtFechaDisplay = DateFormat("EEEE d 'de' MMMM", 'es_CO');

  @override
  void initState() {
    super.initState();
    _filtroFecha = DateFormat('yyyy-MM-dd').format(DateTime.now().toUtc().subtract(const Duration(hours: 5)));
    _cargar();
    _cargarConfiguracion();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final qp = _filtroFecha.isNotEmpty ? {'fecha': _filtroFecha} : <String, String>{};
    try {
      final results = await Future.wait([
        ApiService.get('/api/dashboard/total-dia',            queryParams: qp.isNotEmpty ? qp : null).catchError((_) => null),
        ApiService.get('/api/dashboard/productos-mas-vendidos').catchError((_) => null),
        ApiService.get('/api/dashboard/domiciliarios-dia',    queryParams: qp.isNotEmpty ? qp : null).catchError((_) => null),
        // Igual que React: "domicilios activos" = ventas actualmente despachadas (en camino), no un campo de total-dia
        ApiService.get('/api/ventas', queryParams: {'estado': 'despachado', ...qp}).catchError((_) => null),
      ]);

      // Total día — { data: { total_ventas, monto_total, total_efectivo, total_transferencia, total_domicilios, domicilios_activos } }
      final td = results[0];
      if (td is Map) {
        final inner = td['data'] is Map ? td['data'] as Map : td;
        _totalDia           = _toDouble(inner['monto_total']         ?? inner['total']         ?? inner['ingresos_hoy'] ?? 0);
        _ventasHoy          = (inner['total_ventas'] ?? inner['ventas'] ?? inner['ventas_hoy'] ?? 0) is int
            ? inner['total_ventas'] ?? inner['ventas'] ?? inner['ventas_hoy'] ?? 0
            : int.tryParse((inner['total_ventas'] ?? inner['ventas'] ?? inner['ventas_hoy'] ?? 0).toString()) ?? 0;
        _totalEfectivo      = _toDouble(inner['total_efectivo']      ?? 0);
        _totalTransferencia = _toDouble(inner['total_transferencia'] ?? 0);
        _totalDomicilios    = _toDouble(inner['total_domicilios']    ?? 0);
      }

      // Domicilios activos = ventas actualmente despachadas (igual que React: api.js getDashboard)
      final desp = results[3];
      List rawDesp = desp is List ? desp : (desp is Map && desp['data'] is List ? desp['data'] as List : []);
      _domiciliosActivos = rawDesp.length;

      // Productos más vendidos
      final pm = results[1];
      List rawP = pm is List ? pm : (pm is Map && pm['data'] is List ? pm['data'] as List : []);
      _productosMasVendidos = rawP.map((e) {
        if (e is Map) {
          final prod = e['producto'];
          if (prod is Map) {
            return {'nombre': prod['nombre'] ?? '-', 'total_vendido': e['total_vendido'] ?? 0};
          }
          return Map<String, dynamic>.from(e);
        }
        return <String, dynamic>{};
      }).toList();

      // Domiciliarios del día
      final dom = results[2];
      List rawDom = dom is List ? dom : (dom is Map && dom['data'] is List ? dom['data'] as List : []);
      _domiciliariosDia = rawDom.cast<Map<String, dynamic>>();

      // Si las 4 llamadas fallaron (cada una atrapa su propio error con
      // catchError), no lo tratamos como "sin ventas hoy" sino como fallo real.
      if (results.every((r) => r == null)) {
        _error = 'No se pudo conectar con el servidor';
      }
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Error al cargar dashboard';
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _seleccionarFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_filtroFecha) ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      locale: const Locale('es', 'CO'),
    );
    if (picked != null) {
      setState(() => _filtroFecha = DateFormat('yyyy-MM-dd').format(picked));
      _cargar();
    }
  }

  Future<void> _cargarConfiguracion() async {
    try {
      final data = await ApiService.get('/api/configuracion/tiempo-espera');
      final inner = data is Map && data['data'] is Map ? data['data'] as Map : (data is Map ? data : <String, dynamic>{});
      final min = inner['minutos'];
      if (min != null && mounted) setState(() => _tiempoEspera = int.tryParse(min.toString()) ?? 30);
    } catch (_) {}
    try {
      final data = await ApiService.get('/api/configuracion/horario');
      final h = data is Map && data['data'] is Map ? data['data'] as Map : (data is Map ? data : <String, dynamic>{});
      if (mounted) {
        setState(() {
          _horaApertura = int.tryParse(h['hora_apertura']?.toString() ?? '') ?? 13;
          _horaCierre   = int.tryParse(h['hora_cierre']?.toString()   ?? '') ?? 20;
        });
      }
    } catch (_) {}
  }

  Future<void> _guardarTiempoEspera(int minutos) async {
    await ApiService.patch('/api/configuracion/tiempo-espera', {'minutos': minutos});
    if (mounted) setState(() => _tiempoEspera = minutos);
  }

  Future<void> _guardarHorario(int apertura, int cierre) async {
    await ApiService.patch('/api/configuracion/horario', {'hora_apertura': apertura, 'hora_cierre': cierre});
    if (mounted) setState(() { _horaApertura = apertura; _horaCierre = cierre; });
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      currentRoute: '/admin/dashboard',
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
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.all(AppSizes.screenPadding),
                    children: [
                      // ── Selector de fecha ──────────────────────────────────
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(children: [
                          const Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.primary),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _seleccionarFecha,
                            child: Text(
                              _filtroFecha.isNotEmpty
                                  ? _fmtFechaDisplay.format(DateTime.tryParse(_filtroFecha) ?? DateTime.now())
                                  : 'Hoy',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: _cargar,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: AppColors.successLight,
                                border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('Actualizar',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.success)),
                            ),
                          ),
                        ]),
                      ),

                      const SizedBox(height: AppSizes.md),

                      // ── 4 stat cards (igual React) ─────────────────────────
                      LayoutBuilder(builder: (_, bc) {
                        // On narrow screens reduce aspect ratio so value text has room
                        final ratio = bc.maxWidth < 340 ? 1.45 : 1.6;
                        return GridView.count(
                        crossAxisCount: 2,
                        crossAxisSpacing: AppSizes.sm,
                        mainAxisSpacing: AppSizes.sm,
                        childAspectRatio: ratio,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _StatCard(icono: Icons.payments_outlined,       titulo: 'Ingresos hoy',       valor: _fmt.format(_totalDia), sub: 'Efectivo neto + transferencia', color: AppColors.success),
                          _StatCard(icono: Icons.shopping_cart_outlined,   titulo: 'Ventas hoy',         valor: '$_ventasHoy',          sub: 'Pedidos del día',    color: const Color(0xFF3B82F6)),
                          _StatCard(icono: Icons.delivery_dining_rounded,  titulo: 'Domicilios activos', valor: '$_domiciliosActivos',  sub: 'En camino',          color: const Color(0xFF7C3AED)),
                          _TiempoEstimadoCard(tiempoInicial: _tiempoEspera, onSaved: _guardarTiempoEspera),
                        ],
                      ); }),

                      const SizedBox(height: AppSizes.sm),

                      // ── Cards financieras (mismo tamaño que KPIs) ──────────
                      LayoutBuilder(builder: (_, bc) {
                        final ratio = bc.maxWidth < 340 ? 1.45 : 1.6;
                        return GridView.count(
                          crossAxisCount: 2,
                          crossAxisSpacing: AppSizes.sm,
                          mainAxisSpacing: AppSizes.sm,
                          childAspectRatio: ratio,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _FinancialCard(icono: Icons.account_balance_wallet_outlined, titulo: 'Efectivo del día (neto)', valor: _fmt.format(_totalEfectivo),      color: const Color(0xFF065F46)),
                            _FinancialCard(icono: Icons.trending_up_rounded,              titulo: 'Transferencia del día',   valor: _fmt.format(_totalTransferencia), color: const Color(0xFF1E40AF)),
                            _FinancialCard(icono: Icons.delivery_dining_rounded,          titulo: 'Total domicilios',        valor: _fmt.format(_totalDomicilios),    color: const Color(0xFF5B21B6)),
                          ],
                        );
                      }),

                      const SizedBox(height: AppSizes.sm),

                      // ── Cierre de caja (módulo independiente) ──────────────
                      // Igual que React Dashboard.jsx:144 — solo con permiso ver_cierre_caja
                      if (context.watch<AuthProvider>().tienePermiso('ver_cierre_caja')) ...[
                        CierreCajaCard(fecha: _filtroFecha),
                        const SizedBox(height: AppSizes.lg),
                      ],

                      // ── Productos más vendidos ─────────────────────────────
                      Text(
                        'Productos más vendidos',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: AppSizes.sm),

                      if (_productosMasVendidos.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(AppSizes.lg),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                          ),
                          child: const Center(
                            child: Text('Sin datos aún',
                                style: TextStyle(color: AppColors.textSecondary)),
                          ),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                            boxShadow: const [BoxShadow(color: AppColors.shadow, blurRadius: 8, offset: Offset(0, 2))],
                          ),
                          child: Column(
                            children: List.generate(
                                _productosMasVendidos.length,
                                (i) {
                              final p = _productosMasVendidos[i];
                              final nombre = p['nombre'] ?? p['nombre_producto'] ?? '-';
                              final cantidad = p['total_vendido'] ?? p['cantidad'] ?? 0;
                              final isLast = i == _productosMasVendidos.length - 1;
                              return Container(
                                decoration: BoxDecoration(
                                  border: isLast ? null : const Border(bottom: BorderSide(color: AppColors.divider)),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.sm + 2),
                                child: Row(children: [
                                  Container(
                                    width: 28, height: 28,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                                  ),
                                  const SizedBox(width: AppSizes.sm),
                                  Expanded(child: Text(nombre.toString(), style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis)),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.successLight,
                                      borderRadius: BorderRadius.circular(AppSizes.radiusCircle),
                                    ),
                                    child: Text('$cantidad uds.', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.success)),
                                  ),
                                ]),
                              );
                            }),
                          ),
                        ),

                      const SizedBox(height: AppSizes.lg),

                      // ── Horario editable ───────────────────────────────────
                      _HorarioCard(
                        horaApertura: _horaApertura,
                        horaCierre: _horaCierre,
                        onSaved: _guardarHorario,
                      ),

                      const SizedBox(height: AppSizes.lg),

                      // ── Estado de la tienda ────────────────────────────────
                      _EstadoTiendaCard(),

                      const SizedBox(height: AppSizes.lg),

                      // ── Domiciliarios del día ──────────────────────────────
                      Text('Domiciliarios del día',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: AppSizes.sm),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                          boxShadow: const [BoxShadow(color: AppColors.shadow, blurRadius: 8, offset: Offset(0, 2))],
                        ),
                        child: _domiciliariosDia.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(AppSizes.lg),
                                child: Center(child: Text('Sin entregas registradas hoy', style: TextStyle(color: AppColors.textSecondary))),
                              )
                            : SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  headingRowColor: WidgetStateProperty.all(const Color(0xFFF9FAFB)),
                                  columns: const [
                                    DataColumn(label: Text('Domiciliario', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.textSecondary))),
                                    DataColumn(label: Text('Entregas',     style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.textSecondary))),
                                    DataColumn(label: Text('Efectivo',     style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.textSecondary))),
                                    DataColumn(label: Text('Transf.',      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.textSecondary))),
                                    DataColumn(label: Text('Total',        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.textSecondary))),
                                    DataColumn(label: Text('Total envíos', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.textSecondary))),
                                  ],
                                  rows: _domiciliariosDia.map((d) => DataRow(cells: [
                                    DataCell(Text(d['nombre']?.toString() ?? '-',                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                                    DataCell(Text(d['entregas']?.toString() ?? '0',              style: const TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.w700, fontSize: 13))),
                                    DataCell(Text(_fmt.format(_toDouble(d['efectivo']      ?? 0)), style: const TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.w700, fontSize: 13))),
                                    DataCell(Text(_fmt.format(_toDouble(d['transferencia'] ?? 0)), style: const TextStyle(color: Color(0xFF7C3AED), fontWeight: FontWeight.w700, fontSize: 13))),
                                    DataCell(Text(_fmt.format(_toDouble(d['total']         ?? 0)), style: const TextStyle(color: AppColors.primary,  fontWeight: FontWeight.w800, fontSize: 13))),
                                    DataCell(Text(_fmt.format(_toDouble(d['total_domicilios'] ?? 0)), style: const TextStyle(color: Color(0xFF0369A1), fontWeight: FontWeight.w700, fontSize: 13))),
                                  ])).toList(),
                                ),
                              ),
                      ),

                      const SizedBox(height: AppSizes.xl),
                    ],
                  ),
                ),
    );
  }

}

// ────────────────────────────────────────────────────────────────────────────
// Stat Card (4 KPI cards igual React)
// ────────────────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String valor;
  final String sub;
  final Color color;

  const _StatCard({required this.icono, required this.titulo, required this.valor,
      required this.sub, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        boxShadow: const [BoxShadow(color: AppColors.shadow, blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          alignment: Alignment.center,
          child: Icon(icono, size: 20, color: color),
        ),
        const SizedBox(width: AppSizes.sm),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(valor, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(titulo, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(sub, style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.8)), maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
      ]),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Estado de la tienda card
// ────────────────────────────────────────────────────────────────────────────

class _EstadoTiendaCard extends StatefulWidget {
  const _EstadoTiendaCard();

  @override
  State<_EstadoTiendaCard> createState() => _EstadoTiendaCardState();
}

class _EstadoTiendaCardState extends State<_EstadoTiendaCard> {
  String _estado = '';
  bool _loading = true;
  bool _guardando = false;

  // Claves reales que usa el backend (configuracion/routes.js): 'open' | 'schedule' | 'closed'
  static const _opciones = [
    {'key': 'open',     'label': 'Forzar abierta'},
    {'key': 'schedule', 'label': 'Por horario'},
    {'key': 'closed',   'label': 'Cerrar ahora'},
  ];

  // Texto de estado visible — igual que React Dashboard.jsx
  static const _estadoLabels = {
    'open':     'Abierta ahora',
    'schedule': 'Siguiendo horario',
    'closed':   'Cerrada temporalmente',
  };

  static const _colores = {
    'open':     Color(0xFF16A34A),
    'schedule': Color(0xFFF59E0B),
    'closed':   Color(0xFFCA0B0B),
  };

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final data = await ApiService.get('/api/configuracion/horario');
      final inner = data is Map && data['data'] is Map
          ? data['data'] as Map
          : (data is Map ? data : <String, dynamic>{});
      if (mounted) {
        setState(() {
          _estado  = inner['estado_tienda']?.toString() ?? 'schedule';
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _estado = 'schedule'; _loading = false; });
    }
  }

  Future<void> _cambiar(String nuevoEstado) async {
    setState(() => _guardando = true);
    try {
      await ApiService.patch('/api/configuracion/horario',
          {'estado_tienda': nuevoEstado});
      if (mounted) setState(() => _estado = nuevoEstado);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
      }
    } catch (_) {}
    if (mounted) setState(() => _guardando = false);
  }

  @override
  Widget build(BuildContext context) {
    final color = _colores[_estado] ?? const Color(0xFF3B82F6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Estado de la tienda',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSizes.sm),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSizes.radiusLg),
            boxShadow: const [
              BoxShadow(color: AppColors.shadow, blurRadius: 8, offset: Offset(0, 2)),
            ],
          ),
          padding: const EdgeInsets.all(AppSizes.md),
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : Column(
                  children: [
                    // Estado actual
                    Row(
                      children: [
                        Container(
                          width: 12, height: 12,
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _estadoLabels[_estado] ?? _estado,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: color,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSizes.md),
                    // Botones — Material+InkWell (ripple) y ConstrainedBox
                    // con minHeight 44 para cumplir el tap target minimo.
                    Row(
                      children: _opciones.map((op) {
                        final key     = op['key']!;
                        final label   = op['label']!;
                        final isActive = _estado == key;
                        final opColor  = _colores[key] ?? AppColors.primary;
                        final radius = BorderRadius.circular(8);
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 44),
                              child: Material(
                                color: isActive ? opColor : opColor.withValues(alpha: 0.08),
                                borderRadius: radius,
                                child: InkWell(
                                  onTap: _guardando || isActive ? null : () => _cambiar(key),
                                  borderRadius: radius,
                                  child: Ink(
                                    decoration: BoxDecoration(
                                      borderRadius: radius,
                                      border: Border.all(
                                        color: isActive ? opColor : opColor.withValues(alpha: 0.3),
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 9),
                                    child: Center(
                                      child: _guardando && !isActive
                                          ? SizedBox(
                                              width: 14, height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: opColor,
                                              ),
                                            )
                                          : Text(
                                              label,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: isActive ? Colors.white : opColor,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Financial card (3 small cards: efectivo / transferencia / domicilios)
// ────────────────────────────────────────────────────────────────────────────

class _FinancialCard extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String valor;
  final Color color;
  const _FinancialCard({required this.icono, required this.titulo, required this.valor, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        boxShadow: const [BoxShadow(color: AppColors.shadow, blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          alignment: Alignment.center,
          child: Icon(icono, size: 20, color: color),
        ),
        const SizedBox(width: AppSizes.sm),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(valor,  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(titulo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
        ])),
      ]),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Tiempo estimado card (editable inline)
// ────────────────────────────────────────────────────────────────────────────

class _TiempoEstimadoCard extends StatelessWidget {
  final int tiempoInicial;
  final Future<void> Function(int) onSaved;
  const _TiempoEstimadoCard({required this.tiempoInicial, required this.onSaved});

  // La edición vive en un bottom sheet en vez de campos+botones diminutos
  // dentro de la tarjeta (86px de ancho útil no alcanzan para un TextField +
  // dos botones de 44x44 sin desbordar) — mismo patrón que el resto de la
  // app usa para flujos cortos.
  void _abrirEditor(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EditarTiempoSheet(valorInicial: tiempoInicial, onSaved: onSaved),
    );
  }

  @override
  Widget build(BuildContext context) {
    const grey = Color(0xFF374151);
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
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              alignment: Alignment.center,
              child: const Icon(Icons.access_time_rounded, size: 20, color: grey),
            ),
            const SizedBox(width: AppSizes.sm),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('$tiempoInicial min',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: grey),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const Text('Tiempo estimado', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFF2563EB), borderRadius: BorderRadius.circular(6)),
                child: const Text('✏ Editar', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ])),
          ]),
        ),
      ),
    );
  }
}

class _EditarTiempoSheet extends StatefulWidget {
  final int valorInicial;
  final Future<void> Function(int) onSaved;
  const _EditarTiempoSheet({required this.valorInicial, required this.onSaved});

  @override
  State<_EditarTiempoSheet> createState() => _EditarTiempoSheetState();
}

class _EditarTiempoSheetState extends State<_EditarTiempoSheet> {
  late final _ctrl = TextEditingController(text: widget.valorInicial.toString());
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final v = int.tryParse(_ctrl.text);
    if (v == null || v <= 0) {
      setState(() => _error = 'Ingresa un número de minutos válido');
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
          _error = e is ApiException ? e.message : 'Error al guardar tiempo estimado';
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
          Text('Tiempo estimado de entrega',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSizes.md),
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(labelText: 'Minutos', suffixText: 'min', errorText: _error),
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
                onPressed: _guardando ? null : _guardar,
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
// Horario editable card
// ────────────────────────────────────────────────────────────────────────────

class _HorarioCard extends StatelessWidget {
  final int horaApertura;
  final int horaCierre;
  final Future<void> Function(int apertura, int cierre) onSaved;
  const _HorarioCard({required this.horaApertura, required this.horaCierre, required this.onSaved});

  // Mismo patron que Tiempo estimado: editar abre un bottom sheet en vez de
  // campos+botones diminutos inline.
  void _abrirEditor(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EditarHorarioSheet(apertura: horaApertura, cierre: horaCierre, onSaved: onSaved),
    );
  }

  @override
  Widget build(BuildContext context) {
    const darkBlue = Color(0xFF1E3A5F);
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
                decoration: BoxDecoration(color: darkBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: const Icon(Icons.schedule_rounded, size: 20, color: darkBlue),
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Horario de atención', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                Text('$horaApertura:00 – $horaCierre:00',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: darkBlue)),
              ])),
            ]),
            const SizedBox(height: AppSizes.xs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(color: darkBlue, borderRadius: BorderRadius.circular(6)),
              child: const Text('✏ Editar horario', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _EditarHorarioSheet extends StatefulWidget {
  final int apertura;
  final int cierre;
  final Future<void> Function(int apertura, int cierre) onSaved;
  const _EditarHorarioSheet({required this.apertura, required this.cierre, required this.onSaved});

  @override
  State<_EditarHorarioSheet> createState() => _EditarHorarioSheetState();
}

class _EditarHorarioSheetState extends State<_EditarHorarioSheet> {
  late int _apertura = widget.apertura;
  late int _cierre = widget.cierre;
  bool _guardando = false;
  String? _error;

  Future<void> _guardar() async {
    if (_cierre <= _apertura) {
      setState(() => _error = 'La hora de cierre debe ser mayor a la de apertura');
      return;
    }
    setState(() { _guardando = true; _error = null; });
    try {
      await widget.onSaved(_apertura, _cierre);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _guardando = false;
          _error = e is ApiException ? e.message : 'Error al guardar el horario';
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
          Text('Horario de atención',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSizes.md),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Abre', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                _HorarioInput(value: _apertura, onChanged: (v) => setState(() { _apertura = v; _error = null; })),
              ]),
            ),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Cierra', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                _HorarioInput(value: _cierre, onChanged: (v) => setState(() { _cierre = v; _error = null; })),
              ]),
            ),
          ]),
          if (_error != null) ...[
            const SizedBox(height: AppSizes.sm),
            Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ],
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
                onPressed: _guardando ? null : _guardar,
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

class _HorarioInput extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _HorarioInput({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value.toString(),
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF1E3A5F)),
      decoration: const InputDecoration(
        isDense: true,
        suffixText: ':00',
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF1E3A5F), width: 2)),
      ),
      onChanged: (v) { final n = int.tryParse(v); if (n != null) onChanged(n.clamp(0, 23)); },
    );
  }
}

