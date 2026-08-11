import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/layouts/admin_layout.dart';

const int _kPorPagina = 5;

const List<Map<String, String>> _kFiltroRoles = [
  {'key': 'todos',                 'label': 'Todos'},
  {'key': 'admin',                 'label': 'Admin'},
  {'key': 'domiciliario',          'label': 'Domiciliario'},
  {'key': 'cocinero',              'label': 'Cocinero'},
  {'key': 'confirmador_domicilio', 'label': 'Confirmador'},
  {'key': 'cliente',               'label': 'Cliente'},
];

String _fmtFecha(dynamic f) {
  if (f == null) return '—';
  try {
    final dt = DateTime.parse(f.toString());
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  } catch (_) {
    return f.toString();
  }
}

class UsuariosScreen extends StatefulWidget {
  const UsuariosScreen({super.key});
  @override
  State<UsuariosScreen> createState() => _UsuariosScreenState();
}

class _UsuariosScreenState extends State<UsuariosScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _usuarios = [];
  List<Map<String, dynamic>> _roles    = [];
  final _busquedaCtrl = TextEditingController();
  String _filtroRol = 'todos';
  int    _pagina    = 1;

  @override
  void initState() { super.initState(); _cargar(); }

  @override
  void dispose() { _busquedaCtrl.dispose(); super.dispose(); }

  Future<void> _cargar() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        ApiService.get('/api/usuarios'),
        ApiService.get('/api/roles'),
      ]);
      List rawU = results[0] is List ? results[0] as List
          : (results[0] is Map && results[0]['data'] is List ? results[0]['data'] as List : []);
      List rawR = results[1] is List ? results[1] as List
          : (results[1] is Map && results[1]['data'] is List ? results[1]['data'] as List : []);
      setState(() {
        _usuarios = rawU.cast<Map<String, dynamic>>();
        _roles    = rawR.cast<Map<String, dynamic>>();
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Error al cargar usuarios');
    }
    setState(() => _loading = false);
  }

  // Like React: u.rol?.nombre || getRol(u.id_rol)
  String _rolNombre(Map<String, dynamic> u) {
    if (u['rol'] is Map && u['rol']['nombre'] != null) {
      return u['rol']['nombre'].toString();
    }
    final idRol = u['id_rol'];
    final r = _roles.firstWhere(
      (r) => r['id_rol'] == idRol || r['id'] == idRol,
      orElse: () => <String, dynamic>{},
    );
    return r['nombre']?.toString() ?? '—';
  }

  List<Map<String, dynamic>> get _filtrados {
    final q = _busquedaCtrl.text.toLowerCase().trim();
    return _usuarios.where((u) {
      final rolNm = (u['rol'] is Map ? u['rol']['nombre'] : null)?.toString().toLowerCase() ?? '';
      final coincideBusqueda = q.isEmpty ||
          (u['nombre']?.toString().toLowerCase().contains(q) ?? false) ||
          (u['email']?.toString().toLowerCase().contains(q)  ?? false) ||
          rolNm.contains(q);
      final coincideRol = _filtroRol == 'todos' || rolNm == _filtroRol.toLowerCase();
      return coincideBusqueda && coincideRol;
    }).toList();
  }

  int get _totalPaginas {
    final n = (_filtrados.length / _kPorPagina).ceil();
    return n < 1 ? 1 : n;
  }

  List<Map<String, dynamic>> get _paginados {
    final f = _filtrados;
    final start = (_pagina - 1) * _kPorPagina;
    if (start >= f.length) return [];
    final end = (start + _kPorPagina).clamp(0, f.length);
    return f.sublist(start, end);
  }

  // Like React: PATCH /api/usuarios/{id}/activar-desactivar then update local state
  Future<void> _toggleEstado(Map<String, dynamic> u) async {
    final id      = u['id_usuario'] ?? u['id'];
    final activo  = u['estado'] == true || u['estado'] == 1;
    final nuevoEstado = activo ? 0 : 1;
    try {
      await ApiService.patch('/api/usuarios/$id/activar-desactivar', {'estado': nuevoEstado});
      // Like React: setLista(p => p.map(u => u.id_usuario === id ? {...u, estado: nuevoEstado} : u))
      if (mounted) {
        setState(() {
          _usuarios = _usuarios.map((item) {
            final itemId = item['id_usuario'] ?? item['id'];
            if (itemId == id) return <String, dynamic>{...item, 'estado': nuevoEstado};
            return item;
          }).toList();
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
      }
    }
  }

  Future<void> _eliminar(Map<String, dynamic> u) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmarEliminarDialog(nombre: u['nombre'] ?? ''),
    );
    if (confirm != true) return;
    final id = u['id_usuario'] ?? u['id'];
    try {
      await ApiService.delete('/api/usuarios/$id');
      // Like React: setLista(p => p.filter(u => u.id_usuario !== id))
      if (mounted) {
        setState(() {
          _usuarios = _usuarios.where((item) {
            final itemId = item['id_usuario'] ?? item['id'];
            return itemId != id;
          }).toList();
        });
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Usuario eliminado'), backgroundColor: AppColors.success));
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
    final paginados    = _paginados;
    final totalPaginas = _totalPaginas;
    return AdminLayout(
      currentRoute: '/admin/usuarios',
      body: Column(children: [
        // ── Header ──────────────────────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Usuarios',
                  style: GoogleFonts.nunito(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF1a1a1a))),
              Text('${_usuarios.length} usuarios registrados',
                  style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFF888888))),
            ])),
            GestureDetector(
              onTap: () => showDialog(
                  context: context,
                  builder: (_) => _UsuarioFormDialog(roles: _roles, onGuardado: _cargar)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.add_rounded, color: Colors.white, size: 16),
                  const SizedBox(width: 4),
                  Text('+ Añadir usuario',
                      style: GoogleFonts.nunito(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ]),
        ),
        // ── Buscador ────────────────────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: TextField(
            controller: _busquedaCtrl,
            onChanged: (_) => setState(() => _pagina = 1),
            style: GoogleFonts.nunito(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Buscar usuario...',
              hintStyle: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFFAAAAAA)),
              prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF888888)),
              isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 10),
              filled: true, fillColor: const Color(0xFFF7F8FD),
              border:        OutlineInputBorder(borderRadius: BorderRadius.circular(50), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(50), borderSide: const BorderSide(color: Color(0xFFE8E8E8))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(50), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
            ),
          ),
        ),
        // ── Role filter pills ────────────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _kFiltroRoles.map((f) {
                final sel = _filtroRol == f['key'];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() { _filtroRol = f['key']!; _pagina = 1; }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: sel ? AppColors.primary : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: sel ? AppColors.primary : const Color(0xFFE0E0E0)),
                      ),
                      child: Text(f['label']!,
                          style: GoogleFonts.nunito(
                            fontSize: 13,
                            fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                            color: sel ? Colors.white : const Color(0xFF555555),
                          )),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const Divider(height: 1, color: Color(0xFFF0F0F0)),
        // ── Lista ───────────────────────────────────────────────
        Expanded(
          child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, color: AppColors.error, size: 48),
                  const SizedBox(height: 12),
                  Text(_error!, style: GoogleFonts.nunito(color: AppColors.error)),
                  const SizedBox(height: 12),
                  TextButton(onPressed: _cargar, child: const Text('Reintentar')),
                ]))
              : Column(children: [
                  Expanded(
                    child: paginados.isEmpty
                      ? Center(child: Text('No se encontraron usuarios',
                            style: GoogleFonts.nunito(color: AppColors.textSecondary)))
                      : RefreshIndicator(
                          color: AppColors.primary,
                          onRefresh: _cargar,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: paginados.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final u      = paginados[i];
                              final activo = u['estado'] == true || u['estado'] == 1;
                              final rolNm  = _rolNombre(u);
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
                                        decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(alpha: 0.1),
                                            shape: BoxShape.circle),
                                        alignment: Alignment.center,
                                        child: Text(
                                          (u['nombre'] ?? '?').toString().isNotEmpty
                                              ? (u['nombre'] as String)[0].toUpperCase()
                                              : '?',
                                          style: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text(u['nombre'] ?? '-',
                                            style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1a1a1a))),
                                        const SizedBox(height: 2),
                                        Text(u['email'] ?? '',
                                            style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFF888888))),
                                        const SizedBox(height: 4),
                                        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                                color: const Color(0xFFF5F5F5),
                                                borderRadius: BorderRadius.circular(20),
                                                border: Border.all(color: const Color(0xFFE0E0E0))),
                                            child: Text(rolNm,
                                                style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF555555))),
                                          ),
                                          if (u['empleado'] is Map && u['empleado']['cargo'] != null) ...[
                                            const SizedBox(width: 6),
                                            Text(u['empleado']['cargo'].toString(),
                                                style: GoogleFonts.nunito(fontSize: 11, color: const Color(0xFF888888))),
                                          ],
                                        ]),
                                      ])),
                                      const SizedBox(width: 8),
                                      // Super Admin (id=1) protegido — igual que React: toggle deshabilitado con tooltip.
                                      (u['id_usuario'] ?? u['id']) == 1
                                          ? Tooltip(
                                              message: 'Super Admin protegido',
                                              child: Opacity(opacity: 0.5, child: _ToggleWidget(activo: true)),
                                            )
                                          : GestureDetector(onTap: () => _toggleEstado(u), child: _ToggleWidget(activo: activo)),
                                    ]),
                                    const SizedBox(height: 8),
                                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                                      _ActionBtn(
                                          icon: Icons.visibility_outlined,
                                          onTap: () => showDialog(context: context,
                                              builder: (_) => _UsuarioDetalleDialog(usuario: u, rolNombre: rolNm))),
                                      const SizedBox(width: 6),
                                      _ActionBtn(
                                          icon: Icons.edit_outlined,
                                          onTap: () => showDialog(context: context,
                                              builder: (_) => _UsuarioFormDialog(roles: _roles, usuario: u, onGuardado: _cargar))),
                                      // Super Admin (id=1) protegido — igual que React: sin botón de eliminar.
                                      if ((u['id_usuario'] ?? u['id']) != 1) ...[
                                        const SizedBox(width: 6),
                                        _ActionBtn(icon: Icons.delete_outline, onTap: () => _eliminar(u), danger: true),
                                      ],
                                    ]),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                  ),
                  if (totalPaginas > 1) _buildPaginacion(totalPaginas),
                ]),
        ),
      ]),
    );
  }

  Widget _buildPaginacion(int total) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _PageBtn(label: '‹', enabled: _pagina > 1, active: false,
              onTap: () => setState(() => _pagina--)),
          ...List.generate(total, (i) => _PageBtn(
            label: '${i + 1}', enabled: true, active: _pagina == i + 1,
            onTap: () => setState(() => _pagina = i + 1),
          )),
          _PageBtn(label: '›', enabled: _pagina < total, active: false,
              onTap: () => setState(() => _pagina++)),
        ],
      ),
    );
  }
}

// ─── Dialogs ──────────────────────────────────────────────────────────────────

class _UsuarioFormDialog extends StatefulWidget {
  final Map<String, dynamic>? usuario;
  final List<Map<String, dynamic>> roles;
  final VoidCallback onGuardado;
  const _UsuarioFormDialog({this.usuario, required this.roles, required this.onGuardado});
  @override
  State<_UsuarioFormDialog> createState() => _UsuarioFormDialogState();
}

class _UsuarioFormDialogState extends State<_UsuarioFormDialog> {
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _confPassCtrl;
  dynamic _idRol;
  bool _estado       = true;
  bool _obscurePass  = true;
  bool _obscureConf  = true;
  bool _guardando    = false;
  String? _error;
  Map<String, String> _errores = {};

  bool get _esEditar => widget.usuario != null;

  List<Map<String, dynamic>> get _activeRoles =>
      widget.roles.where((r) => r['estado'] != 0 && r['estado'] != false).toList();

  // Si el rol actual del usuario fue desactivado, se incluye igual para que el
  // Dropdown no reciba un value ausente de items (evita crash de Flutter).
  List<Map<String, dynamic>> get _rolesParaDropdown {
    final activos = _activeRoles;
    if (_idRol == null || activos.any((r) => (r['id_rol'] ?? r['id']) == _idRol)) {
      return activos;
    }
    final actual = widget.roles.where((r) => (r['id_rol'] ?? r['id']) == _idRol);
    return [...activos, ...actual];
  }

  @override
  void initState() {
    super.initState();
    final u       = widget.usuario;
    _nombreCtrl   = TextEditingController(text: u?['nombre'] ?? '');
    _emailCtrl    = TextEditingController(text: u?['email']  ?? '');
    _passCtrl     = TextEditingController();
    _confPassCtrl = TextEditingController();
    final active  = _activeRoles;
    _idRol  = u?['id_rol'] ?? (active.isNotEmpty ? (active[0]['id_rol'] ?? active[0]['id']) : null);
    _estado = _esEditar ? (u!['estado'] == true || u['estado'] == 1) : true;
  }

  @override
  void dispose() {
    _nombreCtrl.dispose(); _emailCtrl.dispose();
    _passCtrl.dispose(); _confPassCtrl.dispose();
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
    setState(() => _errores = errs);
    return errs.isEmpty;
  }

  Future<void> _guardar() async {
    if (!_validar()) return;
    setState(() { _guardando = true; _error = null; });
    try {
      final body = <String, dynamic>{
        'nombre':  _nombreCtrl.text.trim(),
        'email':   _emailCtrl.text.trim(),
        'id_rol':  _idRol,
        if (!_esEditar) 'contrasena': _passCtrl.text,
        if (_esEditar)  'estado': _estado ? 1 : 0,
      };
      if (_esEditar) {
        final id = widget.usuario!['id_usuario'] ?? widget.usuario!['id'];
        await ApiService.put('/api/usuarios/$id', body);
      } else {
        await ApiService.post('/api/usuarios', body);
      }
      if (mounted) {
        Navigator.pop(context);
        widget.onGuardado();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_esEditar ? 'Usuario actualizado' : 'Usuario creado'),
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
        constraints: const BoxConstraints(maxWidth: 480),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
            child: Row(children: [
              Expanded(child: Text(_esEditar ? 'Editar usuario' : 'Nuevo usuario',
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
                TextField(
                    controller: _nombreCtrl,
                    onChanged: (_) => setState(() => _errores.remove('nombre')),
                    style: GoogleFonts.nunito(fontSize: 14),
                    decoration: _inputDec('Nombre completo', error: _errores['nombre'])),
                if (_errores['nombre'] != null) _errMsg(_errores['nombre']!),
                const SizedBox(height: 12),
                TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) => setState(() => _errores.remove('email')),
                    style: GoogleFonts.nunito(fontSize: 14),
                    decoration: _inputDec('Correo electrónico', error: _errores['email'])),
                if (_errores['email'] != null) _errMsg(_errores['email']!),
                if (!_esEditar) ...[
                  const SizedBox(height: 12),
                  TextField(
                      controller: _passCtrl,
                      obscureText: _obscurePass,
                      onChanged: (_) => setState(() => _errores.remove('pass')),
                      style: GoogleFonts.nunito(fontSize: 14),
                      decoration: _inputDec('Contraseña (mín. 8 caracteres)', error: _errores['pass']).copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              size: 18, color: const Color(0xFF888888)),
                          onPressed: () => setState(() => _obscurePass = !_obscurePass),
                        ),
                      )),
                  if (_errores['pass'] != null) _errMsg(_errores['pass']!),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _confPassCtrl,
                      obscureText: _obscureConf,
                      onChanged: (_) => setState(() => _errores.remove('confPass')),
                      style: GoogleFonts.nunito(fontSize: 14),
                      decoration: _inputDec('Confirmar contraseña', error: _errores['confPass']).copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConf ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              size: 18, color: const Color(0xFF888888)),
                          onPressed: () => setState(() => _obscureConf = !_obscureConf),
                        ),
                      )),
                  if (_errores['confPass'] != null) _errMsg(_errores['confPass']!),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField(
                  value: _idRol,
                  items: _rolesParaDropdown.map((r) => DropdownMenuItem(
                    value: r['id_rol'] ?? r['id'],
                    child: Text(r['nombre'] ?? '', style: GoogleFonts.nunito(fontSize: 13)),
                  )).toList(),
                  onChanged: (v) => setState(() => _idRol = v),
                  style: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFF1a1a1a)),
                  decoration: _inputDec('Rol'),
                ),
                if (_esEditar) ...[
                  const SizedBox(height: 14),
                  Row(children: [
                    GestureDetector(
                        onTap: () => setState(() => _estado = !_estado),
                        child: _ToggleWidget(activo: _estado)),
                    const SizedBox(width: 10),
                    Text(_estado ? 'Activo' : 'Inactivo',
                        style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600,
                            color: _estado ? AppColors.success : AppColors.primary)),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: Text('Cancelar',
                    style: GoogleFonts.nunito(color: const Color(0xFF666666), fontWeight: FontWeight.w600)),
              )),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton(
                onPressed: _guardando ? null : _guardar,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0),
                child: _guardando
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(_esEditar ? 'Guardar cambios' : 'Crear usuario',
                        style: GoogleFonts.nunito(color: Colors.white, fontWeight: FontWeight.w700)),
              )),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _UsuarioDetalleDialog extends StatelessWidget {
  final Map<String, dynamic> usuario;
  final String rolNombre;
  const _UsuarioDetalleDialog({required this.usuario, required this.rolNombre});

  @override
  Widget build(BuildContext context) {
    final activo   = usuario['estado'] == true || usuario['estado'] == 1;
    final empleado = usuario['empleado'];
    final cliente  = usuario['cliente'];

    String perfilLabel;
    Color  perfilColor;
    Color  perfilBg;
    if (empleado is Map) {
      perfilLabel = 'Empleado · ${empleado['cargo'] ?? ''}';
      perfilColor = const Color(0xFF2563EB);
      perfilBg    = const Color(0xFFEFF6FF);
    } else if (cliente != null) {
      perfilLabel = 'Cliente';
      perfilColor = const Color(0xFF16A34A);
      perfilBg    = const Color(0xFFF0FDF4);
    } else {
      perfilLabel = 'Sin perfil';
      perfilColor = const Color(0xFF999999);
      perfilBg    = const Color(0xFFFAFAFA);
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
            child: Row(children: [
              Expanded(child: Text('Detalle de usuario',
                  style: GoogleFonts.nunito(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF1a1a1a)))),
              IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          const Divider(height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
            child: Column(children: [
              Row(children: [
                Expanded(child: _DetalleItem(
                    label: 'Estado',
                    badge: activo ? '● Activo' : '● Inactivo',
                    badgeColor: activo ? AppColors.success : AppColors.primary,
                    badgeBg:    activo ? const Color(0xFFF0FDF4) : const Color(0xFFFFF5F5))),
                const SizedBox(width: 12),
                Expanded(child: _DetalleItem(label: 'Rol', value: rolNombre)),
              ]),
              const SizedBox(height: 8),
              _DetalleRowFull(label: 'Nombre',             value: usuario['nombre'] ?? '-'),
              _DetalleRowFull(label: 'Correo electrónico', value: usuario['email']  ?? '-'),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: _DetalleItem(
                    label:      'Perfil vinculado',
                    badge:      perfilLabel,
                    badgeColor: perfilColor,
                    badgeBg:    perfilBg)),
                const SizedBox(width: 12),
                Expanded(child: _DetalleItem(
                    label: 'Fecha de registro',
                    value: _fmtFecha(usuario['fecha_registro']))),
              ]),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE0E0E0)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: Text('Cerrar',
                    style: GoogleFonts.nunito(color: const Color(0xFF666666), fontWeight: FontWeight.w600)),
              ),
            ),
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
        Text.rich(
          TextSpan(
            style: GoogleFonts.nunito(fontSize: 16),
            children: [
              const TextSpan(text: '¿Eliminar al usuario '),
              TextSpan(text: '"$nombre"', style: const TextStyle(fontWeight: FontWeight.w800)),
              const TextSpan(text: '?'),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text('Esta acción no se puede deshacer.',
            style: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFF888888)),
            textAlign: TextAlign.center),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFE0E0E0)),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: Text('Cancelar',
                style: GoogleFonts.nunito(color: const Color(0xFF666666), fontWeight: FontWeight.w600)),
          )),
          const SizedBox(width: 10),
          Expanded(child: ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0),
            child: Text('Sí, eliminar',
                style: GoogleFonts.nunito(color: Colors.white, fontWeight: FontWeight.w700)),
          )),
        ]),
      ]),
    ),
  );
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

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

class _PageBtn extends StatelessWidget {
  final String label;
  final bool enabled;
  final bool active;
  final VoidCallback onTap;
  const _PageBtn({required this.label, required this.enabled, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        constraints: const BoxConstraints(minWidth: 32),
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color:  active ? AppColors.primary : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? AppColors.primary : const Color(0xFFE0E0E0)),
        ),
        child: Text(label,
            style: GoogleFonts.nunito(
              fontSize: 13, fontWeight: FontWeight.w700,
              color: active ? Colors.white : (enabled ? const Color(0xFF555555) : const Color(0xFFCCCCCC)),
            )),
      ),
    ),
  );
}

class _DetalleItem extends StatelessWidget {
  final String label;
  final String? badge;
  final String? value;
  final Color? badgeColor;
  final Color? badgeBg;
  const _DetalleItem({required this.label, this.badge, this.value, this.badgeColor, this.badgeBg});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: GoogleFonts.nunito(fontSize: 11, color: const Color(0xFF888888))),
    const SizedBox(height: 3),
    if (badge != null)
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(20)),
        child: Text(badge!, style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: badgeColor)),
      )
    else
      Text(value ?? '—',
          style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1a1a1a))),
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
