import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_config.dart';
import '../../../core/services/api_service.dart';

/// Cierre de caja del día — módulo independiente del dashboard de admin.
/// (No confundir con lib/features/domiciliario/screens/cierre_caja_screen.dart,
/// que es el resumen de entregas del domiciliario para rendir cuentas; esto es
/// la base inicial / gastos / saldo del negocio, igual a React Dashboard.jsx.)
class CierreCajaCard extends StatefulWidget {
  /// Fecha del filtro del dashboard (yyyy-MM-dd). Si es null o vacía, usa "hoy".
  final String? fecha;

  const CierreCajaCard({super.key, this.fecha});

  @override
  State<CierreCajaCard> createState() => _CierreCajaCardState();
}

class _CierreCajaCardState extends State<CierreCajaCard> {
  Map<String, dynamic>? _resumen;
  bool _cargando = true;
  bool _editandoBase = false;
  bool _guardandoBase = false;
  bool _guardandoGasto = false;
  dynamic _eliminandoGastoId;
  bool _imprimiendo = false;

  final _baseCtrl = TextEditingController();
  final _fmt = NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);
  final _fmtFecha = DateFormat('dd/MM/yyyy', 'es_CO');

  static const _tipoLabel = {
    'domiciliario': 'Domiciliario',
    'empleado': 'Empleado',
    'insumos': 'Insumos',
  };

  @override
  void initState() {
    super.initState();
    _cargarInicial();
  }

  @override
  void didUpdateWidget(CierreCajaCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // El filtro de fecha del dashboard cambió → recargar el cierre para esa fecha
    if (oldWidget.fecha != widget.fecha) {
      _cargarInicial();
    }
  }

  @override
  void dispose() {
    _baseCtrl.dispose();
    super.dispose();
  }

  Map<String, String>? get _queryFecha =>
      (widget.fecha != null && widget.fecha!.isNotEmpty) ? {'fecha': widget.fecha!} : null;

  // Solo se puede editar base/gastos del día de hoy (Colombia, UTC-5) — fechas
  // pasadas son solo lectura, igual que en el dashboard React.
  String get _hoyISO {
    final co = DateTime.now().toUtc().subtract(const Duration(hours: 5));
    return co.toIso8601String().substring(0, 10);
  }

  bool get _esFechaHoy => (widget.fecha == null || widget.fecha!.isEmpty) || widget.fecha == _hoyISO;

  // ── Helpers ──────────────────────────────────────────────────────────────

  Map<String, dynamic> _unwrap(dynamic raw) {
    if (raw is Map && raw['data'] is Map) return Map<String, dynamic>.from(raw['data'] as Map);
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  List<Map<String, dynamic>> _gastosDe(Map<String, dynamic> cierre) {
    final raw = cierre['gastos'];
    if (raw is! List) return [];
    return raw.map((g) => Map<String, dynamic>.from(g as Map)).toList();
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? AppColors.error : AppColors.success),
    );
  }

  // ── Carga ────────────────────────────────────────────────────────────────

  Future<void> _cargarInicial() async {
    // Resetear modo editar al cambiar fecha: si la nueva fecha tiene base
    // guardada se muestra modo lectura con ✏️, no el input de edición.
    setState(() { _cargando = true; _editandoBase = false; });
    try {
      final data = await ApiService.get('/api/cierre-caja/resumen', queryParams: _queryFecha);
      final cierre = _unwrap(data);
      if (mounted) {
        setState(() {
          _resumen = cierre;
          _baseCtrl.text = _toDouble(cierre['base_inicial']).toStringAsFixed(0);
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _cargando = false);
  }

  // Recarga en background para reconciliar con el servidor — SIN tocar
  // _cargando, así la card nunca se desmonta/parpadea
  Future<void> _cargarSilencioso() async {
    try {
      final data = await ApiService.get('/api/cierre-caja/resumen', queryParams: _queryFecha);
      final cierre = _unwrap(data);
      if (mounted) {
        setState(() {
          _resumen = cierre;
          if (!_editandoBase) _baseCtrl.text = _toDouble(cierre['base_inicial']).toStringAsFixed(0);
        });
      }
    } catch (_) {}
  }

  // ── Base inicial ─────────────────────────────────────────────────────────

  void _abrirEdicionBase() {
    _baseCtrl.text = _toDouble(_resumen?['base_inicial']).toStringAsFixed(0);
    setState(() => _editandoBase = true);
  }

  void _cancelarEdicionBase() => setState(() => _editandoBase = false);

  Future<void> _guardarBase() async {
    final valor = double.tryParse(_baseCtrl.text);
    if (valor == null || valor < 0) {
      _toast('Ingresa una base inicial válida', error: true);
      return;
    }
    final anterior = _resumen;
    // El saldo_final NO se recalcula aquí, se deja el valor anterior hasta
    // que _cargarSilencioso() traiga el real del backend.
    setState(() {
      _resumen = {...?_resumen, 'base_inicial': valor, 'base_registrada': true};
      _editandoBase = false;
      _guardandoBase = true;
    });
    try {
      await ApiService.patch('/api/cierre-caja/base', {'base_inicial': valor});
      _toast('Base inicial guardada');
      _cargarSilencioso();
    } on ApiException catch (e) {
      _toast(e.message, error: true);
      if (mounted) setState(() { _resumen = anterior; _editandoBase = true; });
    } catch (_) {
      _toast('No se pudo guardar la base inicial', error: true);
      if (mounted) setState(() { _resumen = anterior; _editandoBase = true; });
    } finally {
      if (mounted) setState(() => _guardandoBase = false);
    }
  }

  // ── Gastos ───────────────────────────────────────────────────────────────

  Future<void> _agregarGasto(String tipo, String descripcion, double valor) async {
    final anterior = _resumen;
    final tempId = 'temp-${DateTime.now().millisecondsSinceEpoch}';
    final gastoOptimista = {
      'id_gasto': tempId,
      'tipo': tipo,
      'descripcion': descripcion,
      'valor': valor,
      'fecha': DateTime.now().toIso8601String(),
    };

    setState(() {
      final gastos = [..._gastosDe(_resumen ?? {}), gastoOptimista];
      final totalGastos = gastos.fold(0.0, (s, g) => s + _toDouble(g['valor']));
      _resumen = {...?_resumen, 'gastos': gastos, 'total_gastos': totalGastos};
      _guardandoGasto = true;
    });
    try {
      await ApiService.post('/api/cierre-caja/gasto', {'tipo': tipo, 'descripcion': descripcion, 'valor': valor});
      _toast('Gasto agregado');
      _cargarSilencioso();
    } on ApiException catch (e) {
      _toast(e.message, error: true);
      if (mounted) setState(() => _resumen = anterior);
    } catch (_) {
      _toast('No se pudo agregar el gasto', error: true);
      if (mounted) setState(() => _resumen = anterior);
    } finally {
      if (mounted) setState(() => _guardandoGasto = false);
    }
  }

  Future<void> _eliminarGasto(dynamic idGasto) async {
    final anterior = _resumen;
    setState(() {
      final gastos = _gastosDe(_resumen ?? {}).where((g) => g['id_gasto'] != idGasto).toList();
      final totalGastos = gastos.fold(0.0, (s, g) => s + _toDouble(g['valor']));
      _resumen = {...?_resumen, 'gastos': gastos, 'total_gastos': totalGastos};
      _eliminandoGastoId = idGasto;
    });
    try {
      await ApiService.delete('/api/cierre-caja/gasto/$idGasto');
      _toast('Gasto eliminado');
      _cargarSilencioso();
    } catch (_) {
      _toast('No se pudo eliminar el gasto', error: true);
      if (mounted) setState(() => _resumen = anterior);
    } finally {
      if (mounted) setState(() => _eliminandoGastoId = null);
    }
  }

  Future<void> _abrirModalGasto() async {
    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _ModalGasto(),
    );
    if (resultado != null) {
      _agregarGasto(resultado['tipo'] as String, resultado['descripcion'] as String, resultado['valor'] as double);
    }
  }

  // ── Imprimir ─────────────────────────────────────────────────────────────

  Future<void> _imprimirCierre() async {
    setState(() => _imprimiendo = true);
    try {
      final data = await ApiService.get('/api/cierre-caja/resumen', queryParams: _queryFecha);
      final datos = _unwrap(data);

      final socketUrl = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/api$'), '');
      final socket = io.io(socketUrl, io.OptionBuilder().setTransports(['websocket']).build());

      socket.onConnect((_) {
        socket.emit('imprimir_cierre', {
          // El servidor recalcula los números reales a partir de fechaISO —
          // los demás campos ya no se usan para el cálculo, quedan por compatibilidad.
          'fechaISO': widget.fecha,
          'fecha': DateFormat('dd/MM/yyyy', 'es_CO').format(
              DateTime.tryParse('${widget.fecha}T12:00:00') ?? DateTime.now()),
          'base_inicial': datos['base_inicial'],
          'total_ventas': datos['total_ventas'],
          'total_efectivo': datos['total_efectivo'],
          'efectivo_sin_domicilios': datos['efectivo_sin_domicilios'],
          'total_transferencia': datos['total_transferencia'],
          'total_domicilios': datos['total_domicilios'],
          'gastos': datos['gastos'],
          'total_gastos': datos['total_gastos'],
          'efectivo_en_caja': datos['saldo_final'],
          'total_puntos_usados': datos['total_puntos_usados'],
        });
      });

      Future.delayed(const Duration(seconds: 2), () => socket.disconnect());
      _toast('Enviando cierre a imprimir...');
    } catch (_) {
      _toast('Error al imprimir cierre', error: true);
    } finally {
      if (mounted) setState(() => _imprimiendo = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    final resumen = _resumen;
    if (resumen == null) return const SizedBox.shrink();

    final baseRegistrada = resumen['base_registrada'] == true;
    final gastos = _gastosDe(resumen);
    final totalGastos = _toDouble(resumen['total_gastos']);
    final saldoFinal = _toDouble(resumen['saldo_final']);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: AppColors.shadow, blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.savings_rounded, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text('Cierre de Caja', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface)),
          ]),
          const SizedBox(height: 2),
          Text('${_esFechaHoy ? 'Hoy: ' : ''}${_fechaTexto(resumen['fecha'])}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),

          // ── Base inicial: modo ver / modo editar (solo editable/creable si es hoy) ──
          const Text('Base inicial del día', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          if (_esFechaHoy && (_editandoBase || !baseRegistrada)) ...[
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _baseCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixText: '\$ ',
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _guardandoBase ? null : _guardarBase,
                child: Container(
                  width: 38, height: 38, alignment: Alignment.center,
                  decoration: BoxDecoration(color: const Color(0xFF16A34A), borderRadius: BorderRadius.circular(8)),
                  child: _guardandoBase
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check, color: Colors.white, size: 18),
                ),
              ),
              if (baseRegistrada) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: _guardandoBase ? null : _cancelarEdicionBase,
                  child: Container(
                    width: 38, height: 38, alignment: Alignment.center,
                    decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                    child: const Icon(Icons.close, color: AppColors.textSecondary, size: 18),
                  ),
                ),
              ],
            ]),
          ] else ...[
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(_fmt.format(_toDouble(resumen['base_inicial'])), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
              if (_esFechaHoy)
                GestureDetector(
                  onTap: _abrirEdicionBase,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.edit_outlined, size: 15, color: AppColors.textSecondary),
                  ),
                ),
            ]),
          ],

          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 14),

          // ── Gastos del día (agregar/eliminar solo si es hoy) ──────────
          const Text('Gastos del día', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          if (gastos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(_esFechaHoy ? 'Sin gastos registrados hoy' : 'Sin gastos registrados', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            )
          else
            ...gastos.map((g) {
              final id = g['id_gasto'];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      '• ${g['descripcion']} (${_tipoLabel[g['tipo']] ?? g['tipo']})',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF444444)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(_fmt.format(_toDouble(g['valor'])), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.primary)),
                  if (_esFechaHoy) const SizedBox(width: 6),
                  if (_esFechaHoy)
                    GestureDetector(
                      onTap: _eliminandoGastoId == id ? null : () => _eliminarGasto(id),
                      child: _eliminandoGastoId == id
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                          : const Icon(Icons.delete_outline, size: 16, color: AppColors.primary),
                    ),
                ]),
              );
            }),

          if (_esFechaHoy) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _guardandoGasto ? null : _abrirModalGasto,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                alignment: Alignment.center,
                child: _guardandoGasto
                    ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                    : const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.add, size: 13, color: Color(0xFF333333)),
                        SizedBox(width: 4),
                        Text('Agregar gasto', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF333333))),
                      ]),
              ),
            ),
          ],
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 10),

          // ── Totales + imprimir ───────────────────────────────────────
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Total gastos', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            Text(_fmt.format(totalGastos), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          ]),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Efectivo en Caja', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            Text(_fmt.format(saldoFinal),
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: saldoFinal >= 0 ? const Color(0xFF15803D) : AppColors.primary)),
          ]),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _imprimiendo ? null : _imprimirCierre,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
              alignment: Alignment.center,
              child: _imprimiendo
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.print_outlined, size: 16, color: Colors.white),
                      SizedBox(width: 6),
                      Text('Imprimir cierre', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                    ]),
            ),
          ),
        ],
      ),
    );
  }

  String _fechaTexto(dynamic fecha) {
    if (fecha == null) return '';
    final dt = DateTime.tryParse('${fecha}T12:00:00');
    return dt != null ? _fmtFecha.format(dt) : fecha.toString();
  }
}

// ── Modal agregar gasto ──────────────────────────────────────────────────────

class _ModalGasto extends StatefulWidget {
  const _ModalGasto();

  @override
  State<_ModalGasto> createState() => _ModalGastoState();
}

class _ModalGastoState extends State<_ModalGasto> {
  String _tipo = 'empleado';
  final _descripcionCtrl = TextEditingController();
  final _valorCtrl = TextEditingController();

  @override
  void dispose() {
    _descripcionCtrl.dispose();
    _valorCtrl.dispose();
    super.dispose();
  }

  void _guardar() {
    final descripcion = _descripcionCtrl.text.trim();
    final valor = double.tryParse(_valorCtrl.text);
    if (descripcion.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingresa una descripción'), backgroundColor: AppColors.error));
      return;
    }
    if (valor == null || valor <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingresa un valor mayor a 0'), backgroundColor: AppColors.error));
      return;
    }
    Navigator.pop(context, {'tipo': _tipo, 'descripcion': descripcion, 'valor': valor});
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Agregar gasto', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(Icons.close, size: 20)),
            ]),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _tipo,
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
              items: const [
                DropdownMenuItem(value: 'empleado', child: Text('Empleado')),
                DropdownMenuItem(value: 'insumos', child: Text('Insumos')),
              ],
              onChanged: (v) => setState(() => _tipo = v ?? 'empleado'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descripcionCtrl,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Nombre del empleado/domi o descripción del insumo',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _valorCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Valor',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                  onPressed: _guardar,
                  child: const Text('Guardar'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
