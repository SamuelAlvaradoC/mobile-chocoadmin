import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/layouts/domiciliario_layout.dart';

class CierreCajaScreen extends StatefulWidget {
  const CierreCajaScreen({super.key});
  @override
  State<CierreCajaScreen> createState() => _CierreCajaScreenState();
}

class _CierreCajaScreenState extends State<CierreCajaScreen> {
  bool _loading = true;
  // Fecha en formato yyyy-MM-dd
  late String _fecha;
  List<Map<String, dynamic>> _ventas = [];

  final _fmt      = NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);
  final _fmtFecha = DateFormat("EEEE d 'de' MMMM", 'es_CO');

  @override
  void initState() {
    super.initState();
    // Fecha de hoy en Colombia (UTC-5), igual que React (hoyISO)
    _fecha = DateFormat('yyyy-MM-dd').format(DateTime.now().toUtc().subtract(const Duration(hours: 5)));
    _cargar(_fecha);
  }

  // ── Parseo de una venta de la API ────────────────────────────────────────────
  Map<String, dynamic> _mapVenta(dynamic v) {
    if (v is! Map) return {};
    // id_venta
    final id = v['id_venta'] ?? v['id'] ?? 0;
    // hora
    final fechaStr = v['fecha']?.toString() ?? '';
    String hora = '—';
    if (fechaStr.isNotEmpty) {
      final dt = DateTime.tryParse(fechaStr);
      if (dt != null) {
        hora = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
    }
    // cliente
    final clienteMap = v['cliente'];
    String cliente = '—';
    if (clienteMap is Map) {
      final usuMap = clienteMap['usuario'];
      if (usuMap is Map) {
        cliente = usuMap['nombre']?.toString() ?? '—';
      }
    }
    // total
    final total = double.tryParse(v['total']?.toString() ?? '0') ?? 0.0;
    // costo domicilio (React usa 0 como default)
    final costoDomicilio = double.tryParse(v['costo_domicilio']?.toString() ?? '0') ?? 0.0;
    // forma pago + montos parciales (igual React CierreCaja.jsx)
    final pagos = v['pagos'];
    List detallePagos = [];
    if (pagos is List && pagos.isNotEmpty && pagos[0] is Map) {
      final dp = (pagos[0] as Map)['detallePagos'];
      if (dp is List) detallePagos = dp;
    }
    final tieneEf = detallePagos.any((d) => d is Map && (d['metodoPago'] as Map?)?['nombre'] == 'efectivo');
    final tieneT  = detallePagos.any((d) => d is Map && (d['metodoPago'] as Map?)?['nombre'] == 'transferencia');

    String formaPago = v['metodo_pago']?.toString() ?? '';
    if (formaPago.isEmpty) {
      if (tieneEf && tieneT) {
        formaPago = 'mixto';
      } else if (tieneT) {
        formaPago = 'transferencia';
      } else {
        formaPago = 'efectivo';
      }
    }

    // React: suma monto del detallePago si existe, si no usa monto_efectivo/monto_transferencia
    double montoEf;
    double montoT;
    if (tieneEf) {
      montoEf = detallePagos
          .where((d) => d is Map && (d['metodoPago'] as Map?)?['nombre'] == 'efectivo')
          .fold(0.0, (s, d) => s + (double.tryParse((d as Map)['monto']?.toString() ?? '0') ?? 0));
    } else {
      montoEf = formaPago == 'efectivo' ? total : (double.tryParse(v['monto_efectivo']?.toString() ?? '0') ?? 0);
    }
    if (tieneT) {
      montoT = detallePagos
          .where((d) => d is Map && (d['metodoPago'] as Map?)?['nombre'] == 'transferencia')
          .fold(0.0, (s, d) => s + (double.tryParse((d as Map)['monto']?.toString() ?? '0') ?? 0));
    } else {
      montoT = formaPago == 'transferencia' ? total : (double.tryParse(v['monto_transferencia']?.toString() ?? '0') ?? 0);
    }

    return {
      'id':              id,
      'hora':            hora,
      'cliente':         cliente,
      'total':           total,
      'costo_domicilio': costoDomicilio,
      'forma_pago':      formaPago,
      'monto_efectivo':  montoEf,
      'monto_transf':    montoT,
    };
  }

  Future<void> _cargar(String fecha) async {
    setState(() => _loading = true);
    try {
      // React: GET /ventas/mis-despachos?estado=entregado&fecha=<fecha>
      // (filtra automáticamente por el domiciliario logueado, no todas las ventas)
      final data = await ApiService.get('/api/ventas/mis-despachos', queryParams: {'estado': 'entregado', if (fecha.isNotEmpty) 'fecha': fecha});
      List raw = data is List ? data : (data is Map && data['data'] is List ? data['data'] as List : []);
      if (mounted) setState(() => _ventas = raw.map(_mapVenta).where((v) => v.isNotEmpty).toList());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.message : 'Error al cargar el cierre de caja')));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  // ── Totales ──────────────────────────────────────────────────────────────────
  double get _totalDia      => _ventas.fold(0, (a, v) => a + (v['total'] as double));
  double get _totalEfectivo => _ventas.fold(0, (a, v) => a + (v['monto_efectivo'] as double));
  double get _totalTransf   => _ventas.fold(0, (a, v) => a + (v['monto_transf'] as double));
  double get _totalDomicilios => _ventas.fold(0, (a, v) => a + (v['costo_domicilio'] as double));
  double get _totalEntregar  => _totalEfectivo - _totalDomicilios;

  Future<void> _seleccionarFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_fecha) ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      locale: const Locale('es', 'CO'),
    );
    if (picked != null) {
      final f = DateFormat('yyyy-MM-dd').format(picked);
      setState(() => _fecha = f);
      _cargar(f);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tarjetas = [
      _Tarjeta(titulo: 'Total día',                   valor: _totalDia,        border: const Color(0xFF22C55E), bg: const Color(0xFFF0FDF4), iconData: Icons.payments_outlined),
      _Tarjeta(titulo: 'Total ventas en efectivo',    valor: _totalEfectivo,   border: const Color(0xFF3B82F6), bg: const Color(0xFFEFF6FF), iconData: Icons.account_balance_wallet_outlined),
      _Tarjeta(titulo: 'Total ventas transferencia',  valor: _totalTransf,     border: const Color(0xFFF97316), bg: const Color(0xFFFFF7ED), iconData: Icons.smartphone_outlined),
      _Tarjeta(titulo: 'Total en domicilios',         valor: _totalDomicilios, border: const Color(0xFF6B7280), bg: const Color(0xFFF9FAFB), iconData: Icons.delivery_dining_rounded),
      _Tarjeta(titulo: 'Total efectivo a entregar',   valor: _totalEntregar,   border: AppColors.primary,      bg: const Color(0xFFFFF5F5), iconData: Icons.check_circle_outlined),
    ];

    return DomiciliarioLayout(
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => _cargar(_fecha),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [

            // ── Header + date picker ────────────────────────────────────────
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('Total del día', style: GoogleFonts.nunito(fontSize: 20, fontWeight: FontWeight.w900, color: const Color(0xFF1a1a1a))),
                ),
                const SizedBox(height: 2),
                Text(
                  _fmtFecha.format(DateTime.tryParse('${_fecha}T12:00:00') ?? DateTime.now()),
                  style: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFF888888)),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                // Date picker widget — full width en pantallas pequeñas
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F8FD),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: GestureDetector(
                        onTap: _seleccionarFecha,
                        child: Text(
                          _fmtFecha.format(DateTime.tryParse('${_fecha}T12:00:00') ?? DateTime.now()),
                          style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF333333)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _cargar(_fecha),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          border: Border.all(color: const Color(0xFFBBF7D0)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('Actualizar', style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF16A34A))),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Tarjetas de resumen ───────────────────────────────────���────
            if (_loading)
              const Center(child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(color: AppColors.primary),
              ))
            else ...[
              ...tarjetas.map((t) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: t.bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.border.withValues(alpha: 0.4), width: 1.5),
                ),
                child: Row(children: [
                  Icon(t.iconData, size: 28, color: t.border),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(_fmt.format(t.valor),
                          style: GoogleFonts.nunito(fontSize: 22, fontWeight: FontWeight.w900, color: const Color(0xFF1a1a1a))),
                    ),
                    Text(t.titulo,
                        style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF666666)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ])),
                ]),
              )),

              const SizedBox(height: 16),

              // ── Listado de ventas ────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Listado de ventas', style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w800)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: const Color(0xFFF0F0F5), borderRadius: BorderRadius.circular(20)),
                            child: Text('${_ventas.length} entregas',
                                style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF666666))),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFF0F0F0)),

                    if (_ventas.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(child: Text('No se encontraron ventas',
                            style: GoogleFonts.nunito(color: const Color(0xFF888888)))),
                      )
                    else
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowHeight: 40,
                          dataRowMinHeight: 44,
                          dataRowMaxHeight: 60,
                          columnSpacing: 16,
                          headingTextStyle: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF888888)),
                          dataTextStyle: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFF1a1a1a)),
                          columns: const [
                            DataColumn(label: Text('No. Venta')),
                            DataColumn(label: Text('Hora')),
                            DataColumn(label: Text('Cliente')),
                            DataColumn(label: Text('Forma pago')),
                            DataColumn(label: Text('Domicilio'), numeric: true),
                            DataColumn(label: Text('Valor'), numeric: true),
                            DataColumn(label: Text('Estado')),
                          ],
                          rows: _ventas.map((v) {
                            final fp = v['forma_pago'] as String;
                            return DataRow(cells: [
                              DataCell(Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(5)),
                                child: Text('V-${(v['id']).toString().padLeft(4, '0')}',
                                    style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF666666))),
                              )),
                              DataCell(Text(v['hora'] as String,
                                  style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFF888888)))),
                              DataCell(Text(v['cliente'] as String,
                                  style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700))),
                              DataCell(_PagoBadgeCaja(formaPago: fp)),
                              DataCell(Text(_fmt.format(v['costo_domicilio']),
                                  style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFF888888)))),
                              DataCell(Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(_fmt.format(v['total']),
                                      style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w800)),
                                  if (fp == 'mixto')
                                    Text(
                                      'Ef. ${_fmt.format(v['monto_efectivo'])} + Tr. ${_fmt.format(v['monto_transf'])}',
                                      style: GoogleFonts.nunito(fontSize: 9, color: const Color(0xFF888888)),
                                    ),
                                ],
                              )),
                              DataCell(Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(20)),
                                child: Text('✓ Facturado', style: GoogleFonts.nunito(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF16A34A))),
                              )),
                            ]);
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Resumen final ─────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1))],
                ),
                child: Column(children: [
                  _ResumenFila2(label: 'Total recaudado en efectivo', valor: _fmt.format(_totalEfectivo)),
                  _ResumenFila2(label: 'Menos costo domicilios',      valor: '− ${_fmt.format(_totalDomicilios)}', rojo: true),
                  const Divider(color: Color(0xFFE0E0E0), height: 20),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Efectivo a entregar', style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w800)),
                    Text(_fmt.format(_totalEntregar),
                        style: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.primary)),
                  ]),
                ]),
              ),

              const SizedBox(height: 40),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Datos de tarjeta ──────────────────────────────────────────────────────────

class _Tarjeta {
  final String titulo;
  final double valor;
  final Color border;
  final Color bg;
  final IconData iconData;
  const _Tarjeta({required this.titulo, required this.valor, required this.border, required this.bg, required this.iconData});
}

// ── Badge forma de pago ───────────────────────────────────────────────────────

class _PagoBadgeCaja extends StatelessWidget {
  final String formaPago;
  const _PagoBadgeCaja({required this.formaPago});

  @override
  Widget build(BuildContext context) {
    final isEf    = formaPago == 'efectivo';
    final isTr    = formaPago == 'transferencia';
    final color   = isEf ? const Color(0xFFCA8A04) : isTr ? const Color(0xFF3B82F6) : const Color(0xFF7C3AED);
    final bg      = isEf ? const Color(0xFFFEFCE8) : isTr ? const Color(0xFFEFF6FF) : const Color(0xFFF5F3FF);
    final label   = isEf ? 'Efectivo' : isTr ? 'Transf.' : 'Mixto';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: GoogleFonts.nunito(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

// ── Fila resumen ──────────────────────────────────────────────────────────────

class _ResumenFila2 extends StatelessWidget {
  final String label;
  final String valor;
  final bool rojo;
  const _ResumenFila2({required this.label, required this.valor, this.rojo = false});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFF666666))),
      Text(valor, style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700,
          color: rojo ? AppColors.primary : const Color(0xFF1a1a1a))),
    ]),
  );
}
