import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/layouts/admin_layout.dart';
import '../../auth/providers/auth_provider.dart';

// Réplica de src/pages/admin/barrios/Barrios.jsx
class BarriosScreen extends StatefulWidget {
  const BarriosScreen({super.key});

  @override
  State<BarriosScreen> createState() => _BarriosScreenState();
}

class _BarriosScreenState extends State<BarriosScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _barrios = [];
  List<Map<String, dynamic>> _ciudades = [];
  final _busquedaCtrl = TextEditingController();
  dynamic _filtroCiudad;
  int _pagina = 1;
  static const _porPagina = 10;
  static final _fmt = NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _cargar();
    _cargarCiudades();
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
      final data = await ApiService.get('/api/barrios');
      List raw = data is List ? data : (data is Map && data['data'] is List ? data['data'] as List : []);
      _barrios = raw.cast<Map<String, dynamic>>();
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Error al cargar barrios';
    }
    setState(() => _loading = false);
  }

  Future<void> _cargarCiudades() async {
    try {
      final data = await ApiService.get('/api/ciudades');
      List raw = data is List ? data : (data is Map && data['data'] is List ? data['data'] as List : []);
      if (mounted) setState(() => _ciudades = raw.cast<Map<String, dynamic>>());
    } catch (_) {}
  }

  String _ciudadNombre(Map<String, dynamic> b) {
    final ciudad = b['ciudad'];
    if (ciudad is Map && ciudad['nombre'] != null) return ciudad['nombre'].toString();
    return '—';
  }

  List<Map<String, dynamic>> get _filtrados {
    final q = _busquedaCtrl.text.toLowerCase().trim();
    return _barrios.where((b) {
      final matchNombre = q.isEmpty || (b['nombre']?.toString().toLowerCase().contains(q) ?? false);
      final matchCiudad = _filtroCiudad == null || (b['id_ciudad']?.toString() == _filtroCiudad.toString());
      return matchNombre && matchCiudad;
    }).toList();
  }

  Future<void> _toggleEstado(Map<String, dynamic> b) async {
    final id = b['id_barrio'] ?? b['id'];
    final nuevoEstado = !(b['estado'] == true || b['estado'] == 1);
    try {
      await ApiService.patch('/api/barrios/$id/estado', {'estado': nuevoEstado ? 1 : 0});
      await _cargar();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _eliminar(Map<String, dynamic> b) async {
    final id = b['id_barrio'] ?? b['id'];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmarEliminarDialog(titulo: '¿Eliminar el barrio "${b['nombre']}"?'),
    );
    if (confirm != true) return;
    try {
      await ApiService.delete('/api/barrios/$id');
      await _cargar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Barrio eliminado'), backgroundColor: AppColors.success),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _abrirCrear() {
    showDialog(context: context, builder: (_) => _BarrioFormDialog(ciudades: _ciudades, onGuardado: _cargar));
  }

  void _abrirEditar(Map<String, dynamic> b) {
    showDialog(context: context, builder: (_) => _BarrioFormDialog(barrio: b, ciudades: _ciudades, onGuardado: _cargar));
  }

  @override
  Widget build(BuildContext context) {
    final puedeGestionar = context.read<AuthProvider>().tienePermiso('gestionar_barrios');
    final filtrados = _filtrados;
    final totalPaginas = filtrados.isEmpty ? 1 : ((filtrados.length + _porPagina - 1) ~/ _porPagina);
    final paginaActual = _pagina.clamp(1, totalPaginas);
    final paginados = filtrados.skip((paginaActual - 1) * _porPagina).take(_porPagina).toList();

    return AdminLayout(
      currentRoute: '/admin/barrios',
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Barrios', style: GoogleFonts.nunito(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF1a1a1a))),
                      Text('${_barrios.length} barrios registrados', style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFF888888))),
                    ],
                  ),
                ),
                if (puedeGestionar)
                  GestureDetector(
                    onTap: _abrirCrear,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.add_rounded, color: Colors.white, size: 16),
                        const SizedBox(width: 4),
                        Text('+ Añadir barrio', style: GoogleFonts.nunito(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _busquedaCtrl,
                    onChanged: (_) => setState(() => _pagina = 1),
                    style: GoogleFonts.nunito(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Buscar barrio...',
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
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F8FD),
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(color: const Color(0xFFE8E8E8)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<dynamic>(
                      value: _filtroCiudad,
                      hint: Text('Ciudad', style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFF888888))),
                      style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFF333333)),
                      items: [
                        DropdownMenuItem(value: null, child: Text('Todas', style: GoogleFonts.nunito(fontSize: 12))),
                        ..._ciudades.map((c) => DropdownMenuItem(
                              value: c['id_ciudad'],
                              child: Text(c['nombre'] ?? '', style: GoogleFonts.nunito(fontSize: 12)),
                            )),
                      ],
                      onChanged: (v) => setState(() { _filtroCiudad = v; _pagina = 1; }),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _error != null
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.error_outline, color: AppColors.error, size: 48),
                          const SizedBox(height: 12),
                          Text(_error!, style: GoogleFonts.nunito(color: AppColors.error)),
                          const SizedBox(height: 12),
                          TextButton(onPressed: _cargar, child: const Text('Reintentar')),
                        ]),
                      )
                    : filtrados.isEmpty
                        ? Center(child: Text('No se encontraron barrios', style: GoogleFonts.nunito(color: AppColors.textSecondary)))
                        : Column(
                            children: [
                              Expanded(
                                child: RefreshIndicator(
                                  color: AppColors.primary,
                                  onRefresh: _cargar,
                                  child: ListView.separated(
                                    padding: const EdgeInsets.all(16),
                                    itemCount: paginados.length,
                                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                                    itemBuilder: (context, i) {
                                      final b = paginados[i];
                                      final activo = b['estado'] == true || b['estado'] == 1;
                                      final precio = double.tryParse(b['precio_domicilio']?.toString() ?? '0') ?? 0;
                                      return Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(10),
                                          boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1))],
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(b['nombre'] ?? '-',
                                                        style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1a1a1a))),
                                                    Text(_ciudadNombre(b), style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFF888888))),
                                                  ],
                                                ),
                                              ),
                                              Text(_fmt.format(precio),
                                                  style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF16A34A))),
                                              const SizedBox(width: 8),
                                              GestureDetector(
                                                onTap: puedeGestionar ? () => _toggleEstado(b) : null,
                                                child: _ToggleWidget(activo: activo),
                                              ),
                                            ]),
                                            if (puedeGestionar) ...[
                                              const SizedBox(height: 8),
                                              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                                                _ActionBtn(icon: Icons.edit_outlined, onTap: () => _abrirEditar(b)),
                                                const SizedBox(width: 6),
                                                _ActionBtn(icon: Icons.delete_outline, onTap: () => _eliminar(b), danger: true),
                                              ]),
                                            ],
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              if (totalPaginas > 1)
                                _PaginacionRow(pagina: paginaActual, totalPaginas: totalPaginas, onCambiar: (n) => setState(() => _pagina = n)),
                            ],
                          ),
          ),
        ],
      ),
    );
  }
}

class _BarrioFormDialog extends StatefulWidget {
  final Map<String, dynamic>? barrio;
  final List<Map<String, dynamic>> ciudades;
  final VoidCallback onGuardado;
  const _BarrioFormDialog({this.barrio, required this.ciudades, required this.onGuardado});

  @override
  State<_BarrioFormDialog> createState() => _BarrioFormDialogState();
}

class _BarrioFormDialogState extends State<_BarrioFormDialog> {
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _precioCtrl;
  dynamic _idCiudad;
  bool _guardando = false;
  String? _error;
  Map<String, String> _errores = {};

  bool get _esEditar => widget.barrio != null;

  @override
  void initState() {
    super.initState();
    _nombreCtrl = TextEditingController(text: widget.barrio?['nombre'] ?? '');
    final precioIni = widget.barrio?['precio_domicilio'];
    _precioCtrl = TextEditingController(text: precioIni != null ? precioIni.toString() : '');
    _idCiudad = widget.barrio?['id_ciudad'];
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _precioCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final errs = <String, String>{};
    if (_idCiudad == null) errs['ciudad'] = 'Selecciona una ciudad';
    if (_nombreCtrl.text.trim().isEmpty) errs['nombre'] = 'El nombre es requerido';
    final precio = double.tryParse(_precioCtrl.text.trim());
    if (_precioCtrl.text.trim().isEmpty || precio == null || precio <= 0) errs['precio'] = 'Precio inválido';
    if (errs.isNotEmpty) {
      setState(() => _errores = errs);
      return;
    }
    setState(() { _guardando = true; _error = null; _errores = {}; });
    try {
      final body = {
        'nombre': _nombreCtrl.text.trim(),
        'id_ciudad': _idCiudad,
        'precio_domicilio': precio,
      };
      if (_esEditar) {
        final id = widget.barrio!['id_barrio'] ?? widget.barrio!['id'];
        await ApiService.patch('/api/barrios/$id', body);
      } else {
        await ApiService.post('/api/barrios', body);
      }
      if (mounted) {
        Navigator.pop(context);
        widget.onGuardado();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_esEditar ? 'Barrio actualizado' : 'Barrio creado'), backgroundColor: AppColors.success),
        );
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Error al guardar');
    }
    setState(() => _guardando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
              child: Row(children: [
                Expanded(
                  child: Text(_esEditar ? 'Editar barrio' : 'Nuevo barrio',
                      style: GoogleFonts.nunito(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF1a1a1a))),
                ),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
              ]),
            ),
            const Divider(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ciudad / Municipio *',
                      style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF555555))),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _errores['ciudad'] != null ? AppColors.error : const Color(0xFFE0E0E0)),
                      color: const Color(0xFFF7F8FD),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<dynamic>(
                        isExpanded: true,
                        value: _idCiudad,
                        hint: Text('Seleccionar ciudad...', style: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFFAAAAAA))),
                        items: widget.ciudades
                            .map((c) => DropdownMenuItem(value: c['id_ciudad'], child: Text(c['nombre'] ?? '', style: GoogleFonts.nunito(fontSize: 13))))
                            .toList(),
                        onChanged: (v) => setState(() { _idCiudad = v; _errores.remove('ciudad'); }),
                      ),
                    ),
                  ),
                  if (_errores['ciudad'] != null) _errMsg(_errores['ciudad']!),
                  const SizedBox(height: 14),
                  Text('Nombre del barrio *',
                      style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF555555))),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _nombreCtrl,
                    onChanged: (_) => setState(() => _errores.remove('nombre')),
                    style: GoogleFonts.nunito(fontSize: 14),
                    decoration: _inputDec('Ej: Laureles, El Poblado...', error: _errores['nombre']),
                  ),
                  if (_errores['nombre'] != null) _errMsg(_errores['nombre']!),
                  const SizedBox(height: 14),
                  Text('Precio domicilio *',
                      style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF555555))),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _precioCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: false),
                    onChanged: (_) => setState(() => _errores.remove('precio')),
                    style: GoogleFonts.nunito(fontSize: 14),
                    decoration: _inputDec('Ej: 5000', error: _errores['precio']),
                  ),
                  if (_errores['precio'] != null) _errMsg(_errores['precio']!),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: AppColors.errorLight, borderRadius: BorderRadius.circular(8)),
                      child: Text(_error!, style: GoogleFonts.nunito(color: AppColors.error, fontSize: 13)),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE0E0E0)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text('Cancelar', style: GoogleFonts.nunito(color: const Color(0xFF666666), fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _guardando ? null : _guardar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    child: _guardando
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(_esEditar ? 'Guardar cambios' : 'Crear barrio', style: GoogleFonts.nunito(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmarEliminarDialog extends StatelessWidget {
  final String titulo;
  const _ConfirmarEliminarDialog({required this.titulo});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.delete_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(titulo,
                style: GoogleFonts.nunito(fontSize: 17, fontWeight: FontWeight.w800, color: const Color(0xFF1a1a1a)), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('Esta acción no se puede deshacer.', style: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFF888888)), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE0E0E0)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Cancelar', style: GoogleFonts.nunito(color: const Color(0xFF666666), fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: Text('Eliminar', style: GoogleFonts.nunito(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _ToggleWidget extends StatelessWidget {
  final bool activo;
  const _ToggleWidget({required this.activo});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 44,
      height: 24,
      decoration: BoxDecoration(color: activo ? const Color(0xFF22c55e) : const Color(0xFF9ca3af), borderRadius: BorderRadius.circular(12)),
      child: Stack(children: [
        AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          left: activo ? 22 : 2,
          top: 2,
          child: Container(width: 20, height: 20, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
        ),
      ]),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;
  const _ActionBtn({required this.icon, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(6)),
        alignment: Alignment.center,
        child: Icon(icon, size: 16, color: danger ? AppColors.error : const Color(0xFF666666)),
      ),
    );
  }
}

InputDecoration _inputDec(String hint, {String? error}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFFAAAAAA)),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    filled: true,
    fillColor: const Color(0xFFF7F8FD),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: error != null ? AppColors.error : const Color(0xFFE0E0E0))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: error != null ? AppColors.error : const Color(0xFFE0E0E0))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
  );
}

Widget _errMsg(String msg) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(msg, style: GoogleFonts.nunito(fontSize: 11, color: AppColors.error, fontWeight: FontWeight.w600)),
    );

class _PaginacionRow extends StatelessWidget {
  final int pagina;
  final int totalPaginas;
  final ValueChanged<int> onCambiar;
  const _PaginacionRow({required this.pagina, required this.totalPaginas, required this.onCambiar});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _PagBtn(label: '‹', activo: false, enabled: pagina > 1, onTap: () => onCambiar(pagina - 1)),
          ...List.generate(totalPaginas, (i) => i + 1).map((n) => _PagBtn(label: '$n', activo: n == pagina, onTap: () => onCambiar(n))),
          _PagBtn(label: '›', activo: false, enabled: pagina < totalPaginas, onTap: () => onCambiar(pagina + 1)),
        ],
      ),
    );
  }
}

class _PagBtn extends StatelessWidget {
  final String label;
  final bool activo;
  final bool enabled;
  final VoidCallback onTap;
  const _PagBtn({required this.label, required this.activo, required this.onTap, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: activo ? AppColors.primary : const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: activo ? AppColors.primary : const Color(0xFFE0E0E0)),
          ),
          child: Text(label,
              style: GoogleFonts.nunito(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: activo ? Colors.white : (enabled ? const Color(0xFF444444) : const Color(0xFFBBBBBB)),
              )),
        ),
      ),
    );
  }
}
