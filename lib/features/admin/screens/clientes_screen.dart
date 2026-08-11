import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/layouts/admin_layout.dart';

class ClientesScreen extends StatefulWidget {
  const ClientesScreen({super.key});

  @override
  State<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends State<ClientesScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _clientes = [];
  final _busquedaCtrl = TextEditingController();
  final _fmtFecha = DateFormat('dd/MM/yyyy', 'es_CO');
  String _filtroEstado = 'todos'; // 'todos' | 'activos' | 'inactivos'
  bool _procesando = false;
  int _pagina = 1;
  static const int _porPagina = 5;

  @override
  void initState() {
    super.initState();
    _cargar();
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
      final data = await ApiService.get('/api/clientes');
      List raw = [];
      if (data is List) {
        raw = data;
      } else if (data is Map && data['data'] is List) {
        raw = data['data'] as List;
      }
      _clientes = raw.cast<Map<String, dynamic>>();
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Error al cargar clientes';
    }
    setState(() => _loading = false);
  }

  // Helpers — API devuelve {id_cliente, usuario:{nombre,email,estado}, telefono}
  static String _cNombre(Map<String, dynamic> c) {
    final u = c['usuario'];
    if (u is Map) return u['nombre']?.toString() ?? '-';
    return c['nombre']?.toString() ?? '-';
  }

  static String _cEmail(Map<String, dynamic> c) {
    final u = c['usuario'];
    if (u is Map) return u['email']?.toString() ?? '-';
    return c['email']?.toString() ?? '-';
  }

  static bool _cActivo(Map<String, dynamic> c) {
    final u = c['usuario'];
    if (u is Map) return u['estado'] == true || u['estado'] == 1;
    return c['estado'] == true || c['estado'] == 1;
  }

  List<Map<String, dynamic>> get _filtrados {
    final q = _busquedaCtrl.text.toLowerCase().trim();
    return _clientes.where((c) {
      final matchQ = q.isEmpty ||
          _cNombre(c).toLowerCase().contains(q) ||
          _cEmail(c).toLowerCase().contains(q) ||
          (c['telefono']?.toString().contains(q) ?? false);
      final activo = _cActivo(c);
      final matchE = _filtroEstado == 'todos' ||
          (_filtroEstado == 'activos' && activo) ||
          (_filtroEstado == 'inactivos' && !activo);
      return matchQ && matchE;
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

  // ── CRUD ────────────────────────────────────────────────────────────────────

  Future<void> _toggleEstadoLista(Map<String, dynamic> c) async {
    final id = c['id_cliente'] ?? c['id'];
    if (id == null) return;
    final activo = _cActivo(c);
    final nuevoEstado = activo ? 0 : 1;
    try {
      await ApiService.patch('/api/clientes/$id/estado', {'estado': nuevoEstado});
      setState(() {
        _clientes = _clientes.map((x) {
          if ((x['id_cliente'] ?? x['id']) == id) {
            final u = x['usuario'];
            if (u is Map) return {...x, 'usuario': {...u, 'estado': nuevoEstado}};
            return {...x, 'estado': nuevoEstado};
          }
          return x;
        }).toList();
      });
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
      }
    } catch (_) {}
  }

  Future<void> _crear(Map<String, dynamic> fields) async {
    if (_procesando) return;
    setState(() => _procesando = true);
    try {
      final body = <String, dynamic>{
        'nombre': fields['nombre'],
        'email': fields['email'],
        'contrasena': fields['contrasena'],
      };
      final tel = fields['telefono']?.toString().trim();
      if (tel != null && tel.isNotEmpty) body['telefono'] = tel;
      await ApiService.post('/api/clientes', body);
      await _cargar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cliente creado'), backgroundColor: AppColors.success));
      }
    } on ApiException {
      rethrow;
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _editar(dynamic id, Map<String, dynamic> fields) async {
    if (_procesando) return;
    setState(() => _procesando = true);
    try {
      final body = <String, dynamic>{};
      final nombre = fields['nombre']?.toString().trim();
      final email  = fields['email']?.toString().trim();
      final tel    = fields['telefono']?.toString().trim();
      if (nombre != null && nombre.isNotEmpty) body['nombre'] = nombre;
      if (email  != null && email.isNotEmpty)  body['email']  = email;
      // Se envía como string vacío (no null): el schema del backend es .optional(),
      // no .nullable() — un JSON null ahí rompería la validación con un 422.
      if (tel    != null) body['telefono'] = tel;
      await ApiService.put('/api/clientes/$id', body);
      await _cargar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cliente actualizado'), backgroundColor: AppColors.success));
      }
    } on ApiException {
      rethrow;
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _confirmarEliminar(Map<String, dynamic> c) async {
    final id = c['id_cliente'] ?? c['id'];
    if (id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmarEliminarClienteDialog(nombre: _cNombre(c)),
    );
    if (confirm != true || _procesando) return;
    setState(() => _procesando = true);
    try {
      await ApiService.delete('/api/clientes/$id');
      setState(() => _clientes = _clientes.where((x) => (x['id_cliente'] ?? x['id']) != id).toList());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cliente eliminado'), backgroundColor: AppColors.success));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  void _abrirFormulario([Map<String, dynamic>? cliente]) {
    showDialog(
      context: context,
      builder: (_) => _ClienteFormDialog(
        cliente: cliente,
        onGuardado: (fields) async {
          final id = cliente?['id_cliente'] ?? cliente?['id'];
          if (id != null) {
            await _editar(id, fields);
          } else {
            await _crear(fields);
          }
          if (mounted) Navigator.of(context, rootNavigator: true).pop();
        },
      ),
    );
  }

  void _abrirDetalle(Map<String, dynamic> cliente) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ClienteDetalleDialog(
        cliente: cliente,
        fmtFecha: _fmtFecha,
        onToggle: _cargar,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _paginados;
    final totalPaginas = _totalPaginas;

    return AdminLayout(
      currentRoute: '/admin/clientes',
      body: Column(
        children: [
          // Header
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Clientes',
                          style: GoogleFonts.nunito(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1a1a1a))),
                      Text(
                        '${_clientes.length} cliente${_clientes.length != 1 ? 's' : ''} registrado${_clientes.length != 1 ? 's' : ''}',
                        style: GoogleFonts.nunito(
                            fontSize: 12, color: const Color(0xFF888888)),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _abrirFormulario(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.add_rounded, color: Colors.white, size: 16),
                      const SizedBox(width: 4),
                      Text('+ Añadir cliente',
                          style: GoogleFonts.nunito(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ],
            ),
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
                hintText: 'Buscar por nombre, email o teléfono...',
                hintStyle: GoogleFonts.nunito(
                    fontSize: 13, color: const Color(0xFFAAAAAA)),
                prefixIcon: const Icon(Icons.search_rounded,
                    size: 18, color: Color(0xFF888888)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                filled: true,
                fillColor: const Color(0xFFF7F8FD),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(50),
                    borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(50),
                    borderSide: const BorderSide(color: Color(0xFFE8E8E8))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(50),
                    borderSide:
                        const BorderSide(color: AppColors.primary, width: 1.5)),
              ),
            ),
          ),

          // Filter chips: Todos / Activos / Inactivos
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: SizedBox(
              height: 30,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final f in [
                    ('todos', 'Todos'),
                    ('activos', 'Activos'),
                    ('inactivos', 'Inactivos'),
                  ])
                    GestureDetector(
                      onTap: () => setState(() { _filtroEstado = f.$1; _pagina = 1; }),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: _filtroEstado == f.$1
                              ? AppColors.primary
                              : const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(50),
                          border: _filtroEstado == f.$1
                              ? null
                              : Border.all(color: const Color(0xFFE0E0E0)),
                        ),
                        child: Text(f.$2,
                            style: GoogleFonts.nunito(
                              fontSize: 13,
                              fontWeight: _filtroEstado == f.$1
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: _filtroEstado == f.$1
                                  ? Colors.white
                                  : const Color(0xFF555555),
                            )),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          // Lista
          Expanded(
            child: _loading
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
                                style: GoogleFonts.nunito(
                                    color: AppColors.error)),
                            const SizedBox(height: 12),
                            TextButton(
                                onPressed: _cargar,
                                child: const Text('Reintentar')),
                          ],
                        ),
                      )
                    : filtrados.isEmpty
                        ? Center(
                            child: Text('No se encontraron clientes',
                                style: GoogleFonts.nunito(
                                    color: AppColors.textSecondary)))
                        : RefreshIndicator(
                            color: AppColors.primary,
                            onRefresh: _cargar,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: filtrados.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                final c = filtrados[i];
                                final nombre = _cNombre(c);
                                final email = _cEmail(c);
                                final telefono =
                                    c['telefono']?.toString() ?? '-';
                                final activo = _cActivo(c);
                                return Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: const [
                                      BoxShadow(
                                          color: Color(0x0A000000),
                                          blurRadius: 4,
                                          offset: Offset(0, 1))
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color: AppColors.primary.withValues(alpha: 0.1),
                                              shape: BoxShape.circle,
                                            ),
                                            alignment: Alignment.center,
                                            child: Text(
                                              nombre.isNotEmpty ? nombre[0].toUpperCase() : '?',
                                              style: GoogleFonts.nunito(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w800,
                                                  color: AppColors.primary),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(nombre,
                                                    style: GoogleFonts.nunito(
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w700,
                                                        color: const Color(0xFF1a1a1a))),
                                                Text(email,
                                                    style: GoogleFonts.nunito(
                                                        fontSize: 12,
                                                        color: const Color(0xFF888888))),
                                                if (telefono != '-')
                                                  Text(telefono,
                                                      style: GoogleFonts.nunito(
                                                          fontSize: 12,
                                                          color: const Color(0xFF888888))),
                                                Text(
                                                  '${c['_count'] is Map ? (c['_count']['ventas'] ?? 0) : 0} pedidos · ${c['puntos'] is Map ? (c['puntos']['puntos'] ?? 0) : 0} pts',
                                                  style: GoogleFonts.nunito(
                                                      fontSize: 11,
                                                      color: const Color(0xFFAAAAAA)),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          GestureDetector(
                                            onTap: () => _toggleEstadoLista(c),
                                            child: _ToggleWidget(activo: activo),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          _ActionBtn(
                                              icon: Icons.visibility_outlined,
                                              onTap: () => _abrirDetalle(c)),
                                          const SizedBox(width: 6),
                                          _ActionBtn(
                                              icon: Icons.edit_outlined,
                                              onTap: () => _abrirFormulario(c)),
                                          const SizedBox(width: 6),
                                          _ActionBtn(
                                              icon: Icons.delete_outline,
                                              onTap: () => _confirmarEliminar(c),
                                              danger: true),
                                        ],
                                      ),
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
        ],
      ),
    );
  }
}

// ─── Dialog formulario cliente ────────────────────────────────────────────────

class _ClienteFormDialog extends StatefulWidget {
  final Map<String, dynamic>? cliente;
  final Future<void> Function(Map<String, dynamic>) onGuardado;
  const _ClienteFormDialog({this.cliente, required this.onGuardado});

  @override
  State<_ClienteFormDialog> createState() => _ClienteFormDialogState();
}

class _ClienteFormDialogState extends State<_ClienteFormDialog> {
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _confPassCtrl;
  late final TextEditingController _telefonoCtrl;
  bool _obscurePass = true;
  bool _obscureConf = true;
  bool _guardando = false;
  Map<String, String> _errores = {};
  String? _errorGeneral;

  bool get _esEditar => widget.cliente != null;

  @override
  void initState() {
    super.initState();
    final c = widget.cliente;
    _nombreCtrl = TextEditingController(text: c != null ? _getNombre(c) : '');
    _emailCtrl  = TextEditingController(text: c != null ? _getEmail(c)  : '');
    _passCtrl     = TextEditingController();
    _confPassCtrl = TextEditingController();
    _telefonoCtrl = TextEditingController(text: c?['telefono']?.toString() ?? '');
  }

  String _getNombre(Map<String, dynamic> c) {
    final u = c['usuario'];
    if (u is Map) return u['nombre']?.toString() ?? '';
    return c['nombre']?.toString() ?? '';
  }

  String _getEmail(Map<String, dynamic> c) {
    final u = c['usuario'];
    if (u is Map) return u['email']?.toString() ?? '';
    return c['email']?.toString() ?? '';
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confPassCtrl.dispose();
    _telefonoCtrl.dispose();
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
      if (_passCtrl.text != _confPassCtrl.text) {
        errs['confPass'] = 'Las contraseñas no coinciden';
      }
    }
    setState(() => _errores = errs);
    return errs.isEmpty;
  }

  Future<void> _guardar() async {
    if (!_validar()) return;
    setState(() { _guardando = true; _errorGeneral = null; });
    try {
      await widget.onGuardado({
        'nombre':    _nombreCtrl.text.trim(),
        'email':     _emailCtrl.text.trim(),
        if (!_esEditar) 'contrasena': _passCtrl.text,
        'telefono':  _telefonoCtrl.text.trim(),
      });
    } on ApiException catch (e) {
      setState(() {
        // El backend de clientes dice "correo electrónico", no "email" —
        // sin este segundo check el mensaje nunca resaltaba el campo.
        if (e.message.toLowerCase().contains('email') || e.message.toLowerCase().contains('correo')) {
          _errores = {..._errores, 'email': e.message};
        } else {
          _errorGeneral = e.message;
        }
      });
    } catch (_) {
      setState(() => _errorGeneral = 'Error al guardar. Inténtalo de nuevo.');
    }
    if (mounted) setState(() => _guardando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
            child: Row(children: [
              Expanded(
                  child: Text(
                      _esEditar ? 'Editar cliente' : 'Nuevo cliente',
                      style: GoogleFonts.nunito(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1a1a1a)))),
              IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context)),
            ]),
          ),
          const Divider(height: 16),

          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.65),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cuenta
                    Text('Cuenta',
                        style: GoogleFonts.nunito(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF888888))),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            TextField(
                              controller: _nombreCtrl,
                              onChanged: (_) =>
                                  setState(() => _errores.remove('nombre')),
                              style: GoogleFonts.nunito(fontSize: 14),
                              decoration: _cInputDec('Nombre completo',
                                  error: _errores['nombre']),
                            ),
                            if (_errores['nombre'] != null)
                              _cErrMsg(_errores['nombre']!),
                          ])),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            TextField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              onChanged: (_) =>
                                  setState(() => _errores.remove('email')),
                              style: GoogleFonts.nunito(fontSize: 14),
                              decoration: _cInputDec('Correo electrónico',
                                  error: _errores['email']),
                            ),
                            if (_errores['email'] != null)
                              _cErrMsg(_errores['email']!),
                          ])),
                    ]),

                    // Contraseña (solo al crear)
                    if (!_esEditar) ...[
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              TextField(
                                controller: _passCtrl,
                                obscureText: _obscurePass,
                                onChanged: (_) =>
                                    setState(() => _errores.remove('pass')),
                                style: GoogleFonts.nunito(fontSize: 14),
                                decoration: _cInputDec(
                                        'Contraseña (mín. 8 caracteres)',
                                        error: _errores['pass'])
                                    .copyWith(
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                        _obscurePass
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        size: 18,
                                        color: const Color(0xFF888888)),
                                    onPressed: () => setState(
                                        () => _obscurePass = !_obscurePass),
                                  ),
                                ),
                              ),
                              if (_errores['pass'] != null)
                                _cErrMsg(_errores['pass']!),
                            ])),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              TextField(
                                controller: _confPassCtrl,
                                obscureText: _obscureConf,
                                onChanged: (_) =>
                                    setState(() => _errores.remove('confPass')),
                                style: GoogleFonts.nunito(fontSize: 14),
                                decoration: _cInputDec('Confirmar contraseña',
                                        error: _errores['confPass'])
                                    .copyWith(
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                        _obscureConf
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        size: 18,
                                        color: const Color(0xFF888888)),
                                    onPressed: () => setState(
                                        () => _obscureConf = !_obscureConf),
                                  ),
                                ),
                              ),
                              if (_errores['confPass'] != null)
                                _cErrMsg(_errores['confPass']!),
                            ])),
                      ]),
                    ],

                    const SizedBox(height: 12),
                    TextField(
                      controller: _telefonoCtrl,
                      keyboardType: TextInputType.phone,
                      style: GoogleFonts.nunito(fontSize: 14),
                      decoration: _cInputDec('Teléfono (opcional)'),
                    ),

                    if (_errorGeneral != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: AppColors.errorLight,
                            borderRadius: BorderRadius.circular(8)),
                        child: Text(_errorGeneral!,
                            style: GoogleFonts.nunito(
                                color: AppColors.error, fontSize: 13)),
                      ),
                    ],
                    const SizedBox(height: 8),
                  ]),
            ),
          ),

          // Footer
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Row(children: [
              Expanded(
                  child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFE0E0E0)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text('Cancelar',
                    style: GoogleFonts.nunito(
                        color: const Color(0xFF666666),
                        fontWeight: FontWeight.w600)),
              )),
              const SizedBox(width: 10),
              Expanded(
                  child: ElevatedButton(
                onPressed: _guardando ? null : _guardar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                child: _guardando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text(
                        _esEditar ? 'Guardar cambios' : 'Crear cliente',
                        style: GoogleFonts.nunito(
                            color: Colors.white,
                            fontWeight: FontWeight.w700)),
              )),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ─── Confirmar eliminar cliente ───────────────────────────────────────────────

class _ConfirmarEliminarClienteDialog extends StatelessWidget {
  final String nombre;
  const _ConfirmarEliminarClienteDialog({required this.nombre});

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.delete_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text('¿Eliminar al cliente "$nombre"?',
                style: GoogleFonts.nunito(
                    fontSize: 17, fontWeight: FontWeight.w800),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('Esta acción no se puede deshacer.',
                style: GoogleFonts.nunito(
                    fontSize: 13, color: const Color(0xFF888888)),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                  child: OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFE0E0E0)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text('Cancelar',
                    style: GoogleFonts.nunito(
                        color: const Color(0xFF666666),
                        fontWeight: FontWeight.w600)),
              )),
              const SizedBox(width: 10),
              Expanded(
                  child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                child: Text('Sí, eliminar',
                    style: GoogleFonts.nunito(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              )),
            ]),
          ]),
        ),
      );
}

// ─── Dialog detalle cliente ───────────────────────────────────────────────────

class _ClienteDetalleDialog extends StatefulWidget {
  final Map<String, dynamic> cliente;
  final DateFormat fmtFecha;
  final VoidCallback onToggle;

  const _ClienteDetalleDialog({
    required this.cliente,
    required this.fmtFecha,
    required this.onToggle,
  });

  @override
  State<_ClienteDetalleDialog> createState() => _ClienteDetalleDialogState();
}

class _ClienteDetalleDialogState extends State<_ClienteDetalleDialog> {
  bool _cargando = true;
  Map<String, dynamic>? _detalle;
  late bool _activo;

  final _fmtMoneda =
      NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    final u = widget.cliente['usuario'];
    _activo = u is Map
        ? (u['estado'] == true || u['estado'] == 1)
        : (widget.cliente['estado'] == true || widget.cliente['estado'] == 1);
    _cargarDetalle();
  }

  Future<void> _cargarDetalle() async {
    final id = widget.cliente['id_cliente'] ?? widget.cliente['id'];
    if (id == null) {
      setState(() => _cargando = false);
      return;
    }
    try {
      final data = await ApiService.get('/api/clientes/$id/detalle');
      final d = data is Map && data['data'] is Map
          ? data['data'] as Map<String, dynamic>
          : (data is Map ? Map<String, dynamic>.from(data) : null);
      if (mounted) setState(() { _detalle = d; _cargando = false; });
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _detalle ?? widget.cliente;
    final u = d['usuario'];
    final nombre =
        u is Map ? (u['nombre'] ?? '-').toString() : (d['nombre'] ?? '-').toString();
    final email =
        u is Map ? (u['email'] ?? '-').toString() : (d['email'] ?? '-').toString();
    final telefono = (d['telefono'] ?? '-').toString();
    final puntosRaw = d['puntos'];
    final int puntos = puntosRaw is Map
        ? (puntosRaw['puntos'] as num?)?.toInt() ?? 0
        : (puntosRaw as num?)?.toInt() ?? 0;
    final double saldo = puntos * 12.5;
    final fechaRaw =
        u is Map ? (u['fecha_registro'] ?? u['created_at']) : null;
    String fechaStr = '-';
    if (fechaRaw != null) {
      try {
        fechaStr = widget.fmtFecha.format(DateTime.parse(fechaRaw.toString()));
      } catch (_) {}
    }
    final dirs =
        (d['direcciones'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final ventas =
        (d['ventas'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
              child: Row(
                children: [
                  Expanded(
                      child: Text('Detalle de cliente',
                          style: GoogleFonts.nunito(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1a1a1a)))),
                  IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const Divider(height: 1),

            Flexible(
              child: _cargando
                  ? const Center(
                      child: Padding(
                          padding: EdgeInsets.all(40),
                          child: CircularProgressIndicator(
                              color: AppColors.primary)))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Info personal + Puntos en 2 columnas
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                      color: const Color(0xFFF9FAFB),
                                      borderRadius: BorderRadius.circular(10)),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('INFO PERSONAL',
                                            style: GoogleFonts.nunito(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: const Color(0xFF999999),
                                                letterSpacing: 1)),
                                        const SizedBox(height: 10),
                                        Text(nombre,
                                            style: GoogleFonts.nunito(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w800,
                                                color:
                                                    const Color(0xFF1a1a1a))),
                                        const SizedBox(height: 4),
                                        Text(email,
                                            style: GoogleFonts.nunito(
                                                fontSize: 12,
                                                color: const Color(0xFF555555))),
                                        Text('📞 $telefono',
                                            style: GoogleFonts.nunito(
                                                fontSize: 12,
                                                color: const Color(0xFF555555))),
                                        if (fechaStr != '-') ...[
                                          const SizedBox(height: 4),
                                          Text('Desde $fechaStr',
                                              style: GoogleFonts.nunito(
                                                  fontSize: 11,
                                                  color: const Color(
                                                      0xFFAAAAAA))),
                                        ],
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: _activo
                                                ? const Color(0xFFF0FDF4)
                                                : const Color(0xFFFFF5F5),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                              _activo
                                                  ? '● Activo'
                                                  : '● Inactivo',
                                              style: GoogleFonts.nunito(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: _activo
                                                      ? const Color(0xFF16A34A)
                                                      : AppColors.primary)),
                                        ),
                                      ]),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                width: 130,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                    color: const Color(0xFFFFF5F5),
                                    borderRadius: BorderRadius.circular(10)),
                                child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('PUNTOS CHOCOFRESEO',
                                          style: GoogleFonts.nunito(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFF999999),
                                              letterSpacing: 1)),
                                      const SizedBox(height: 10),
                                      Text('$puntos',
                                          style: GoogleFonts.nunito(
                                              fontSize: 28,
                                              fontWeight: FontWeight.w900,
                                              color: AppColors.primary,
                                              height: 1)),
                                      Text('puntos',
                                          style: GoogleFonts.nunito(
                                              fontSize: 11,
                                              color: const Color(0xFF888888))),
                                      const SizedBox(height: 8),
                                      Text(_fmtMoneda.format(saldo),
                                          style: GoogleFonts.nunito(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w900,
                                              color: const Color(0xFF16A34A),
                                              height: 1)),
                                      Text('saldo disponible',
                                          style: GoogleFonts.nunito(
                                              fontSize: 11,
                                              color: const Color(0xFF888888))),
                                    ]),
                              ),
                            ],
                          ),

                          const SizedBox(height: 14),

                          // Direcciones
                          Text('DIRECCIONES',
                              style: GoogleFonts.nunito(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF999999),
                                  letterSpacing: 1)),
                          const SizedBox(height: 8),
                          if (dirs.isEmpty)
                            Text('Sin direcciones registradas',
                                style: GoogleFonts.nunito(
                                    fontSize: 13,
                                    color: const Color(0xFFAAAAAA)))
                          else
                            ...dirs.map((dir) => Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                      color: const Color(0xFFF9FAFB),
                                      borderRadius: BorderRadius.circular(8)),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            dir['direccion_linea']
                                                    ?.toString() ??
                                                '—',
                                            style: GoogleFonts.nunito(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: const Color(0xFF1a1a1a))),
                                        if ([
                                          dir['barrio'],
                                          dir['ciudad'],
                                          dir['departamento']
                                        ].any((v) =>
                                            v != null &&
                                            v.toString().isNotEmpty))
                                          Text(
                                              [
                                                dir['barrio'],
                                                dir['ciudad'],
                                                dir['departamento']
                                              ]
                                                  .where((v) =>
                                                      v != null &&
                                                      v.toString().isNotEmpty)
                                                  .join(', '),
                                              style: GoogleFonts.nunito(
                                                  fontSize: 12,
                                                  color: const Color(
                                                      0xFF888888))),
                                        if (dir['referencia'] != null &&
                                            dir['referencia']
                                                .toString()
                                                .isNotEmpty)
                                          Text(
                                              'Ref: ${dir['referencia']}',
                                              style: GoogleFonts.nunito(
                                                  fontSize: 11,
                                                  color: const Color(
                                                      0xFFAAAAAA))),
                                      ]),
                                )),

                          const SizedBox(height: 14),

                          // Historial pedidos
                          Text('ÚLTIMOS PEDIDOS',
                              style: GoogleFonts.nunito(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF999999),
                                  letterSpacing: 1)),
                          const SizedBox(height: 8),
                          if (ventas.isEmpty)
                            Text('Sin pedidos registrados',
                                style: GoogleFonts.nunito(
                                    fontSize: 13,
                                    color: const Color(0xFFAAAAAA)))
                          else
                            ...ventas.map((v) {
                              final est = (v['estado'] is Map
                                          ? v['estado']['nombre_estado']
                                          : v['estado'])
                                      ?.toString() ??
                                  '—';
                              final total =
                                  double.tryParse((v['total'] ?? 0).toString()) ??
                                      0;
                              final fechaV =
                                  v['fecha'] ?? v['createdAt'] ?? v['created_at'];
                              String fechaVStr = '-';
                              if (fechaV != null) {
                                try {
                                  fechaVStr = widget.fmtFecha.format(
                                      DateTime.parse(fechaV.toString()));
                                } catch (_) {}
                              }
                              final motivo =
                                  v['motivo_anulacion']?.toString();
                              final Color estBg = est == 'entregado'
                                  ? const Color(0xFFDCFCE7)
                                  : est == 'anulado'
                                      ? const Color(0xFFFEE2E2)
                                      : const Color(0xFFF0F0F0);
                              final Color estFg = est == 'entregado'
                                  ? const Color(0xFF166534)
                                  : est == 'anulado'
                                      ? AppColors.primary
                                      : const Color(0xFF555555);
                              return Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                decoration: const BoxDecoration(
                                    border: Border(
                                        bottom: BorderSide(
                                            color: Color(0xFFF0F0F0)))),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(children: [
                                              Text(
                                                  '#${v['id_venta'] ?? '?'}',
                                                  style: GoogleFonts.nunito(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: const Color(
                                                          0xFF1a1a1a))),
                                              const SizedBox(width: 8),
                                              Text(fechaVStr,
                                                  style: GoogleFonts.nunito(
                                                      fontSize: 11,
                                                      color: const Color(
                                                          0xFF888888))),
                                            ]),
                                            if (est == 'anulado' &&
                                                motivo != null)
                                              Text('Motivo: $motivo',
                                                  style: GoogleFonts.nunito(
                                                      fontSize: 11,
                                                      color: AppColors.primary,
                                                      fontStyle:
                                                          FontStyle.italic)),
                                          ]),
                                    ),
                                    const SizedBox(width: 8),
                                    Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                                color: estBg,
                                                borderRadius:
                                                    BorderRadius.circular(20)),
                                            child: Text(est,
                                                style: GoogleFonts.nunito(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: estFg)),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(_fmtMoneda.format(total),
                                              style: GoogleFonts.nunito(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.primary)),
                                        ]),
                                  ],
                                ),
                              );
                            }),

                        ],
                      ),
                    ),
            ),
            // Footer
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE0E0E0)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Cerrar', style: GoogleFonts.nunito(color: const Color(0xFF666666), fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _ToggleWidget extends StatelessWidget {
  final bool activo;
  const _ToggleWidget({required this.activo});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 24,
        decoration: BoxDecoration(
            color: activo
                ? const Color(0xFF22c55e)
                : const Color(0xFF9ca3af),
            borderRadius: BorderRadius.circular(12)),
        child: Stack(children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            left: activo ? 22 : 2,
            top: 2,
            child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle)),
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
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(6)),
        alignment: Alignment.center,
        child: Icon(icon,
            size: 16,
            color: danger ? AppColors.error : const Color(0xFF666666)),
      ),
    );
  }
}

// ─── Helpers de formulario ────────────────────────────────────────────────────

Widget _cErrMsg(String msg) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(msg,
          style: GoogleFonts.nunito(
              fontSize: 11,
              color: AppColors.error,
              fontWeight: FontWeight.w600)),
    );

InputDecoration _cInputDec(String hint, {String? error}) => InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFFAAAAAA)),
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      filled: true,
      fillColor: const Color(0xFFF7F8FD),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
              color: error != null
                  ? AppColors.error
                  : const Color(0xFFE0E0E0))),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
              color: error != null
                  ? AppColors.error
                  : const Color(0xFFE0E0E0))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: AppColors.primary, width: 1.5)),
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
