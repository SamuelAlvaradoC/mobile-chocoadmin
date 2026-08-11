import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/layouts/admin_layout.dart';

const _kCargos = ['Domiciliario', 'Cocinero', 'Confirmador'];

// Helpers de parseo para campos anidados de la API
String _empNombre(Map<String, dynamic> e) {
  // usuario.nombre (relación anidada) → nombre_completo → nombre → '-'
  final usuario = e['usuario'];
  if (usuario is Map && usuario['nombre'] != null) {
    return usuario['nombre'].toString();
  }
  return (e['nombre_completo'] ?? e['nombre'] ?? '-').toString();
}

String _empCargo(Map<String, dynamic> e) {
  return (e['cargo'] ?? e['puesto'] ?? '—').toString();
}

String _empEmail(Map<String, dynamic> e) {
  final usuario = e['usuario'];
  if (usuario is Map && usuario['email'] != null) {
    return usuario['email'].toString();
  }
  return (e['email'] ?? '—').toString();
}

String _empFechaIngreso(Map<String, dynamic> e) {
  final raw = e['fecha_ingreso'];
  if (raw == null || raw.toString().isEmpty) { return '—'; }
  try {
    final dt = DateTime.parse(raw.toString());
    return DateFormat('dd/MM/yyyy', 'es_CO').format(dt);
  } catch (_) {
    return raw.toString();
  }
}

String _empRol(Map<String, dynamic> e) {
  final usuario = e['usuario'];
  if (usuario is Map && usuario['rol'] is Map && usuario['rol']['nombre'] != null) {
    return usuario['rol']['nombre'].toString();
  }
  return '—';
}

String _empFechaRegistro(Map<String, dynamic> e) {
  final usuario = e['usuario'];
  final raw = usuario is Map ? usuario['fecha_registro'] : null;
  if (raw == null || raw.toString().isEmpty) { return '—'; }
  try {
    final dt = DateTime.parse(raw.toString());
    return DateFormat('dd/MM/yyyy', 'es_CO').format(dt);
  } catch (_) {
    return raw.toString();
  }
}

class EmpleadosScreen extends StatefulWidget {
  const EmpleadosScreen({super.key});
  @override
  State<EmpleadosScreen> createState() => _EmpleadosScreenState();
}

class _EmpleadosScreenState extends State<EmpleadosScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _empleados = [];
  final _busquedaCtrl = TextEditingController();
  String _filtroCargo = 'todos'; // 'todos' | cargo | 'activos' | 'inactivos'
  int _pagina = 1;
  static const int _porPagina = 5;

  @override
  void initState() { super.initState(); _cargar(); }

  @override
  void dispose() { _busquedaCtrl.dispose(); super.dispose(); }

  Future<void> _cargar() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await ApiService.get('/api/empleados');
      List raw = data is List ? data : (data is Map && data['data'] is List ? data['data'] as List : []);
      setState(() => _empleados = raw.cast<Map<String, dynamic>>());
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Error al cargar empleados');
    }
    setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _filtrados {
    final q = _busquedaCtrl.text.toLowerCase().trim();
    final cargosUnicos = _empleados
        .map((e) => _empCargo(e))
        .where((c) => c != '—' && _kCargos.contains(c))
        .toSet()
        .toList();
    final usarFiltroEstado = cargosUnicos.isEmpty;
    return _empleados.where((e) {
      final matchQ = q.isEmpty ||
          _empNombre(e).toLowerCase().contains(q) ||
          _empEmail(e).toLowerCase().contains(q);
      final activo = e['estado'] == true || e['estado'] == 1;
      bool matchF;
      if (usarFiltroEstado) {
        matchF = _filtroCargo == 'todos' ||
            (_filtroCargo == 'activos' && activo) ||
            (_filtroCargo == 'inactivos' && !activo);
      } else {
        matchF = _filtroCargo == 'todos' || _empCargo(e) == _filtroCargo;
      }
      return matchQ && matchF;
    }).toList();
  }

  int get _totalPaginas => (_filtrados.length / _porPagina).ceil();

  List<Map<String, dynamic>> get _paginados {
    final f = _filtrados;
    final inicio = (_pagina - 1) * _porPagina;
    if (inicio >= f.length) return [];
    final fin = (inicio + _porPagina).clamp(0, f.length);
    return f.sublist(inicio, fin);
  }

  Future<void> _toggleEstado(Map<String, dynamic> emp) async {
    final id = emp['id_empleado'] ?? emp['id'];
    final activo = emp['estado'] == true || emp['estado'] == 1;
    try {
      await ApiService.patch('/api/empleados/$id/estado', {'estado': activo ? 0 : 1});
      await _cargar();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
      }
    }
  }

  Future<void> _eliminar(Map<String, dynamic> emp) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmarEliminarDialog(nombre: _empNombre(emp)),
    );
    if (confirm != true) return;
    final id = emp['id_empleado'] ?? emp['id'];
    try {
      await ApiService.delete('/api/empleados/$id');
      await _cargar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Empleado eliminado'), backgroundColor: AppColors.success));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _paginados;
    final totalPaginas = _totalPaginas;
    return AdminLayout(
      currentRoute: '/admin/empleados',
      body: Column(children: [
        // Header
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Empleados', style: GoogleFonts.nunito(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF1a1a1a))),
              Text('${_empleados.length} empleados registrados',
                  style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFF888888))),
            ])),
            GestureDetector(
              onTap: () => showDialog(context: context, builder: (_) => _EmpleadoFormDialog(onGuardado: _cargar)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.add_rounded, color: Colors.white, size: 16),
                  const SizedBox(width: 4),
                  Text('+ Añadir empleado', style: GoogleFonts.nunito(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ]),
        ),
        // Buscador
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: TextField(
            controller: _busquedaCtrl,
            onChanged: (_) => setState(() => _pagina = 1),
            style: GoogleFonts.nunito(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Buscar por nombre o email...',
              hintStyle: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFFAAAAAA)),
              prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF888888)),
              isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 10),
              filled: true, fillColor: const Color(0xFFF7F8FD),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(50), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(50), borderSide: const BorderSide(color: Color(0xFFE8E8E8))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(50), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
            ),
          ),
        ),
        // Filter chips: Todos / Activos / Inactivos  o  Todos / cargos
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: SizedBox(
            height: 30,
            child: Builder(builder: (context) {
              final cargosUnicos = _empleados
                  .map((e) => _empCargo(e))
                  .where((c) => c != '—' && _kCargos.contains(c))
                  .toSet()
                  .toList();
              final usarFiltroEstado = cargosUnicos.isEmpty;
              final chips = usarFiltroEstado
                  ? [('todos', 'Todos'), ('activos', 'Activos'), ('inactivos', 'Inactivos')]
                  : [('todos', 'Todos'), ...cargosUnicos.map((c) => (c, c))];
              return ListView(
                scrollDirection: Axis.horizontal,
                children: chips.map((f) => GestureDetector(
                  onTap: () => setState(() { _filtroCargo = f.$1; _pagina = 1; }),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: _filtroCargo == f.$1 ? AppColors.primary : const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(50),
                      border: _filtroCargo == f.$1 ? null : Border.all(color: const Color(0xFFE0E0E0)),
                    ),
                    child: Text(f.$2, style: GoogleFonts.nunito(
                      fontSize: 13,
                      fontWeight: _filtroCargo == f.$1 ? FontWeight.w700 : FontWeight.w400,
                      color: _filtroCargo == f.$1 ? Colors.white : const Color(0xFF555555),
                    )),
                  ),
                )).toList(),
              );
            }),
          ),
        ),
        const Divider(height: 1, color: Color(0xFFF0F0F0)),
        // Lista
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline, color: AppColors.error, size: 48),
                const SizedBox(height: 12),
                Text(_error!, style: GoogleFonts.nunito(color: AppColors.error)),
                const SizedBox(height: 12),
                TextButton(onPressed: _cargar, child: const Text('Reintentar')),
              ]))
            : filtrados.isEmpty
              ? Center(child: Text('No se encontraron empleados', style: GoogleFonts.nunito(color: AppColors.textSecondary)))
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _cargar,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtrados.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final emp = filtrados[i];
                      final activo = emp['estado'] == true || emp['estado'] == 1;
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
                              Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                                alignment: Alignment.center,
                                child: Text(
                                  _empNombre(emp).isNotEmpty ? _empNombre(emp)[0].toUpperCase() : '?',
                                  style: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(_empNombre(emp),
                                    style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1a1a1a))),
                                const SizedBox(height: 2),
                                Text(_empEmail(emp),
                                    style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFF888888))),
                                const SizedBox(height: 4),
                                Row(children: [
                                  Flexible(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF5F5),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFFF5C6C6)),
                                      ),
                                      child: Text(_empCargo(emp),
                                          style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary),
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(_empFechaIngreso(emp),
                                        style: GoogleFonts.nunito(fontSize: 11, color: const Color(0xFF888888)),
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                ]),
                              ])),
                              const SizedBox(width: 8),
                              GestureDetector(onTap: () => _toggleEstado(emp), child: _ToggleWidget(activo: activo)),
                            ]),
                            const SizedBox(height: 8),
                            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                              _ActionBtn(icon: Icons.visibility_outlined,
                                  onTap: () => showDialog(context: context, builder: (_) => _EmpleadoDetalleDialog(empleado: emp))),
                              const SizedBox(width: 6),
                              _ActionBtn(icon: Icons.edit_outlined,
                                  onTap: () => showDialog(context: context, builder: (_) => _EmpleadoFormDialog(empleado: emp, onGuardado: _cargar))),
                              const SizedBox(width: 6),
                              _ActionBtn(icon: Icons.delete_outline, onTap: () => _eliminar(emp), danger: true),
                            ]),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
        if (totalPaginas > 1)
          _PaginacionRow(
            pagina: _pagina,
            totalPaginas: totalPaginas,
            onCambiar: (p) => setState(() => _pagina = p),
          ),
      ]),
    );
  }
}

// ─── Dialogs ──────────────────────────────────────────────────────────────────

class _EmpleadoFormDialog extends StatefulWidget {
  final Map<String, dynamic>? empleado;
  final VoidCallback onGuardado;
  const _EmpleadoFormDialog({this.empleado, required this.onGuardado});
  @override
  State<_EmpleadoFormDialog> createState() => _EmpleadoFormDialogState();
}

class _EmpleadoFormDialogState extends State<_EmpleadoFormDialog> {
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _confPassCtrl;
  late final TextEditingController _fechaCtrl;
  String _cargo = 'Domiciliario';
  bool _estado = true;
  bool _obscurePass = true;
  bool _obscureConf = true;
  bool _guardando = false;
  String? _error;
  Map<String, String> _errores = {};

  bool get _esEditar => widget.empleado != null;

  @override
  void initState() {
    super.initState();
    final e = widget.empleado;
    _nombreCtrl   = TextEditingController(text: e != null ? _empNombre(e) : '');
    _emailCtrl    = TextEditingController(text: e != null ? _empEmail(e) : '');
    _passCtrl     = TextEditingController();
    _confPassCtrl = TextEditingController();
    _fechaCtrl    = TextEditingController(text: e?['fecha_ingreso']?.toString() ?? '');
    _cargo        = e != null ? _empCargo(e) : 'Domiciliario';
    if (!_kCargos.contains(_cargo)) _cargo = 'Domiciliario';
    _estado       = _esEditar ? (e!['estado'] == true || e['estado'] == 1) : true;
  }

  @override
  void dispose() {
    _nombreCtrl.dispose(); _emailCtrl.dispose();
    _passCtrl.dispose(); _confPassCtrl.dispose(); _fechaCtrl.dispose();
    super.dispose();
  }

  bool _validar() {
    final errs = <String, String>{};
    if (_nombreCtrl.text.trim().isEmpty) errs['nombre'] = 'El nombre es requerido';
    if (_emailCtrl.text.trim().isEmpty) {
      errs['email'] = 'El email es requerido';
    } else if (!RegExp(r'\S+@\S+\.\S+').hasMatch(_emailCtrl.text.trim())) {
      errs['email'] = 'Email no válido';
    }
    if (!_esEditar) {
      if (_passCtrl.text.isEmpty) {
        errs['pass'] = 'La contraseña es requerida';
      } else if (_passCtrl.text.length < 8) {
        errs['pass'] = 'Mínimo 8 caracteres';
      }
      if (_passCtrl.text != _confPassCtrl.text) errs['confPass'] = 'Las contraseñas no coinciden';
    }
    if (_fechaCtrl.text.trim().isEmpty) errs['fecha'] = 'La fecha de ingreso es requerida';
    setState(() => _errores = errs);
    return errs.isEmpty;
  }

  Future<void> _guardar() async {
    if (!_validar()) return;
    setState(() { _guardando = true; _error = null; });
    try {
      final body = <String, dynamic>{
        'nombre': _nombreCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'cargo': _cargo,
        'fecha_ingreso': _fechaCtrl.text.trim(),
        if (!_esEditar) 'contrasena': _passCtrl.text,
        if (_esEditar) 'estado': _estado ? 1 : 0,
      };
      if (_esEditar) {
        final id = widget.empleado!['id_empleado'] ?? widget.empleado!['id'];
        await ApiService.put('/api/empleados/$id', body);
      } else {
        await ApiService.post('/api/empleados', body);
      }
      if (mounted) {
        Navigator.pop(context);
        widget.onGuardado();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_esEditar ? 'Empleado actualizado' : 'Empleado creado'),
          backgroundColor: AppColors.success,
        ));
      }
    } on ApiException catch (e) {
      setState(() {
        if (e.message.toLowerCase().contains('email')) {
          _errores = {..._errores, 'email': e.message};
        } else {
          _error = e.message;
        }
      });
    } catch (_) {
      setState(() => _error = 'Error al guardar');
    }
    if (mounted) setState(() => _guardando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
            child: Row(children: [
              Expanded(child: Text(_esEditar ? 'Editar empleado' : 'Nuevo empleado',
                  style: GoogleFonts.nunito(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF1a1a1a)))),
              IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          const Divider(height: 16),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Cuenta
                Text('Cuenta', style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF888888))),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    TextField(controller: _nombreCtrl,
                        onChanged: (_) => setState(() => _errores.remove('nombre')),
                        style: GoogleFonts.nunito(fontSize: 14),
                        decoration: _inputDec('Nombre completo', error: _errores['nombre'])),
                    if (_errores['nombre'] != null) _errMsg(_errores['nombre']!),
                  ])),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    TextField(controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        onChanged: (_) => setState(() => _errores.remove('email')),
                        style: GoogleFonts.nunito(fontSize: 14),
                        decoration: _inputDec('Correo electrónico', error: _errores['email'])),
                    if (_errores['email'] != null) _errMsg(_errores['email']!),
                  ])),
                ]),
                // Contraseña solo al crear
                if (!_esEditar) ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      TextField(controller: _passCtrl,
                          obscureText: _obscurePass,
                          onChanged: (_) => setState(() => _errores.remove('pass')),
                          style: GoogleFonts.nunito(fontSize: 14),
                          decoration: _inputDec('Contraseña (mín. 8)', error: _errores['pass']).copyWith(
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: const Color(0xFF888888)),
                              onPressed: () => setState(() => _obscurePass = !_obscurePass),
                            ),
                          )),
                      if (_errores['pass'] != null) _errMsg(_errores['pass']!),
                    ])),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      TextField(controller: _confPassCtrl,
                          obscureText: _obscureConf,
                          onChanged: (_) => setState(() => _errores.remove('confPass')),
                          style: GoogleFonts.nunito(fontSize: 14),
                          decoration: _inputDec('Confirmar contraseña', error: _errores['confPass']).copyWith(
                            suffixIcon: IconButton(
                              icon: Icon(_obscureConf ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: const Color(0xFF888888)),
                              onPressed: () => setState(() => _obscureConf = !_obscureConf),
                            ),
                          )),
                      if (_errores['confPass'] != null) _errMsg(_errores['confPass']!),
                    ])),
                  ]),
                ],
                const SizedBox(height: 14),
                // Info laboral
                Text('Información laboral', style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF888888))),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: DropdownButtonFormField<String>(
                    value: _cargo,
                    items: _kCargos.map((c) => DropdownMenuItem(value: c, child: Text(c, style: GoogleFonts.nunito(fontSize: 13)))).toList(),
                    onChanged: (v) => setState(() => _cargo = v ?? _cargo),
                    style: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFF1a1a1a)),
                    decoration: _inputDec('Cargo'),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    TextField(controller: _fechaCtrl,
                        readOnly: true,
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime.tryParse(_fechaCtrl.text) ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() {
                              _fechaCtrl.text = picked.toIso8601String().split('T')[0];
                              _errores.remove('fecha');
                            });
                          }
                        },
                        style: GoogleFonts.nunito(fontSize: 14),
                        decoration: _inputDec('Fecha de ingreso', error: _errores['fecha']).copyWith(
                          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 16, color: Color(0xFF888888)),
                        )),
                    if (_errores['fecha'] != null) _errMsg(_errores['fecha']!),
                  ])),
                ]),
                if (_esEditar) ...[
                  const SizedBox(height: 14),
                  Row(children: [
                    GestureDetector(onTap: () => setState(() => _estado = !_estado), child: _ToggleWidget(activo: _estado)),
                    const SizedBox(width: 10),
                    Text(_estado ? 'Activo' : 'Inactivo',
                        style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600,
                            color: _estado ? const Color(0xFF22C55E) : AppColors.primary)),
                  ]),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AppColors.errorLight, borderRadius: BorderRadius.circular(8)),
                    child: Text(_error!, style: GoogleFonts.nunito(color: AppColors.error, fontSize: 13)),
                  ),
                ],
                const SizedBox(height: 8),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFE0E0E0)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text('Cancelar', style: GoogleFonts.nunito(color: const Color(0xFF666666), fontWeight: FontWeight.w600)),
              )),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton(
                onPressed: _guardando ? null : _guardar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                child: _guardando
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(_esEditar ? 'Guardar cambios' : 'Crear empleado',
                        style: GoogleFonts.nunito(color: Colors.white, fontWeight: FontWeight.w700)),
              )),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _EmpleadoDetalleDialog extends StatelessWidget {
  final Map<String, dynamic> empleado;
  const _EmpleadoDetalleDialog({required this.empleado});
  @override
  Widget build(BuildContext context) {
    final activo = empleado['estado'] == true || empleado['estado'] == 1;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
            child: Row(children: [
              Expanded(child: Text('Detalle de empleado',
                  style: GoogleFonts.nunito(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF1a1a1a)))),
              IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          const Divider(height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Column(children: [
              Row(children: [
                Expanded(child: _DetalleItem(label: 'Estado',
                    badge: activo ? '● Activo' : '● Inactivo',
                    badgeColor: activo ? AppColors.success : AppColors.primary,
                    badgeBg: activo ? const Color(0xFFF0FDF4) : const Color(0xFFFFF5F5))),
                const SizedBox(width: 12),
                Expanded(child: _CargoBadgeDetalle(cargo: _empCargo(empleado))),
              ]),
              const SizedBox(height: 8),
              _DetalleRowFull(label: 'Rol', value: _empRol(empleado)),
              _DetalleRowFull(label: 'Nombre', value: _empNombre(empleado)),
              _DetalleRowFull(label: 'Correo electrónico', value: _empEmail(empleado)),
              _DetalleRowFull(label: 'Fecha de ingreso', value: _empFechaIngreso(empleado)),
              _DetalleRowFull(label: 'Registrado desde', value: _empFechaRegistro(empleado)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFE0E0E0)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text('Cerrar', style: GoogleFonts.nunito(color: const Color(0xFF666666), fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _ConfirmarEliminarDialog extends StatelessWidget {
  final String nombre;
  const _ConfirmarEliminarDialog({required this.nombre});
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 440),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.delete_outline, size: 48, color: AppColors.error),
        const SizedBox(height: 12),
        Text('¿Eliminar "$nombre"?',
            style: GoogleFonts.nunito(fontSize: 17, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text('Esta acción no se puede deshacer.',
            style: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFF888888)), textAlign: TextAlign.center),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFE0E0E0)),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: Text('Cancelar', style: GoogleFonts.nunito(color: const Color(0xFF666666), fontWeight: FontWeight.w600)),
          )),
          const SizedBox(width: 10),
          Expanded(child: ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 0),
            child: Text('Eliminar', style: GoogleFonts.nunito(color: Colors.white, fontWeight: FontWeight.w700)),
          )),
        ]),
      ]),
    ),
  );
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _CargoBadgeDetalle extends StatelessWidget {
  final String cargo;
  const _CargoBadgeDetalle({required this.cargo});

  static _CargoBadgeStyle _style(String c) {
    final lower = c.toLowerCase();
    if (lower.contains('domiciliario')) return const _CargoBadgeStyle(bg: Color(0xFFEFF6FF), fg: Color(0xFF2563EB));
    if (lower.contains('cocinero'))    return const _CargoBadgeStyle(bg: Color(0xFFFFF7ED), fg: Color(0xFFF97316));
    if (lower.contains('confirmador')) return const _CargoBadgeStyle(bg: Color(0xFFF5F3FF), fg: Color(0xFF7C3AED));
    return const _CargoBadgeStyle(bg: Color(0xFFFFF5F5), fg: AppColors.primary);
  }

  @override
  Widget build(BuildContext context) {
    final s = _style(cargo);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: s.bg, borderRadius: BorderRadius.circular(6)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Cargo', style: GoogleFonts.nunito(fontSize: 11, color: const Color(0xFF888888))),
        Text(cargo, style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: s.fg)),
      ]),
    );
  }
}

class _CargoBadgeStyle {
  final Color bg;
  final Color fg;
  const _CargoBadgeStyle({required this.bg, required this.fg});
}

class _ToggleWidget extends StatelessWidget {
  final bool activo;
  const _ToggleWidget({required this.activo});
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    width: 44, height: 24,
    decoration: BoxDecoration(
        color: activo ? const Color(0xFF22c55e) : const Color(0xFF9ca3af),
        borderRadius: BorderRadius.circular(12)),
    child: Stack(children: [
      AnimatedPositioned(
        duration: const Duration(milliseconds: 200),
        left: activo ? 22 : 2, top: 2,
        child: Container(width: 20, height: 20,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
      ),
    ]),
  );
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;
  const _ActionBtn({required this.icon, required this.onTap, this.danger = false});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 32, height: 32,
      decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(6)),
      alignment: Alignment.center,
      child: Icon(icon, size: 16, color: danger ? AppColors.error : const Color(0xFF666666)),
    ),
  );
}

class _DetalleItem extends StatelessWidget {
  final String label;
  final String badge;
  final Color badgeColor;
  final Color badgeBg;
  const _DetalleItem({required this.label, required this.badge, required this.badgeColor, required this.badgeBg});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: GoogleFonts.nunito(fontSize: 11, color: const Color(0xFF888888))),
    const SizedBox(height: 3),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(20)),
      child: Text(badge, style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: badgeColor)),
    ),
  ]);
}

class _DetalleRowFull extends StatelessWidget {
  final String label;
  final String value;
  const _DetalleRowFull({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.nunito(fontSize: 11, color: const Color(0xFF888888), fontWeight: FontWeight.w600)),
      const SizedBox(height: 3),
      Text(value, style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1a1a1a))),
    ]),
  );
}

Widget _errMsg(String msg) => Padding(
  padding: const EdgeInsets.only(top: 4),
  child: Text(msg, style: GoogleFonts.nunito(fontSize: 11, color: AppColors.error, fontWeight: FontWeight.w600)),
);

InputDecoration _inputDec(String hint, {String? error}) => InputDecoration(
  hintText: hint,
  hintStyle: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFFAAAAAA)),
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
  filled: true, fillColor: const Color(0xFFF7F8FD),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: error != null ? AppColors.error : const Color(0xFFE0E0E0))),
  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: error != null ? AppColors.error : const Color(0xFFE0E0E0))),
  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
);

// ─── Pagination ───────────────────────────────────────────────────────────────

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
          ...List.generate(totalPaginas, (i) => i + 1).map(
            (n) => _PagBtn(label: '$n', activo: n == pagina, onTap: () => onCambiar(n)),
          ),
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
          child: Text(
            label,
            style: GoogleFonts.nunito(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: activo
                  ? Colors.white
                  : (enabled ? const Color(0xFF444444) : const Color(0xFFBBBBBB)),
            ),
          ),
        ),
      ),
    );
  }
}
