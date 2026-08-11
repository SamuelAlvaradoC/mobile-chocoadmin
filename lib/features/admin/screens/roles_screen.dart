import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/layouts/admin_layout.dart';

const int _kPorPagina = 5;

// Human-readable labels matching the 20 permissions in React
const Map<String, String> _kLabelPermiso = {
  'ver_dashboard':            'Ver dashboard y estadísticas',
  'ver_ventas':               'Ver ventas',
  'gestionar_ventas':         'Crear ventas',
  'cambiar_estado_venta':     'Cambiar estado de venta',
  'anular_venta':             'Anular ventas',
  'confirmar_domicilios':     'Confirmar/rechazar pedidos',
  'gestionar_productos':      'Gestionar productos',
  'gestionar_categorias':     'Gestionar categorías',
  'gestionar_toppings':       'Gestionar toppings',
  'gestionar_adiciones':      'Gestionar adiciones',
  'ver_clientes':             'Ver clientes',
  'gestionar_clientes':       'Gestionar clientes',
  'ver_empleados':            'Ver empleados',
  'gestionar_empleados':      'Gestionar empleados',
  'ver_usuarios':             'Ver usuarios',
  'gestionar_usuarios':       'Gestionar usuarios',
  'ver_roles':                'Ver roles',
  'gestionar_roles':          'Gestionar roles y permisos',
  'ver_pedidos_domiciliario': 'Ver pedidos (domiciliario)',
  'facturar_pedido':          'Facturar pedidos',
};

class RolesScreen extends StatefulWidget {
  const RolesScreen({super.key});
  @override
  State<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends State<RolesScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _roles               = [];
  List<Map<String, dynamic>> _permisosDisponibles = [];
  final _busquedaCtrl = TextEditingController();
  int _pagina = 1;

  @override
  void initState() { super.initState(); _cargar(); }

  @override
  void dispose() { _busquedaCtrl.dispose(); super.dispose(); }

  Future<void> _cargar() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        ApiService.get('/api/roles'),
        ApiService.get('/api/roles/permisos'),
      ]);
      List rawR = results[0] is List ? results[0] as List
          : (results[0] is Map && results[0]['data'] is List ? results[0]['data'] as List : []);
      List rawP = results[1] is List ? results[1] as List
          : (results[1] is Map && results[1]['data'] is List ? results[1]['data'] as List : []);
      setState(() {
        _roles               = rawR.cast<Map<String, dynamic>>();
        _permisosDisponibles = rawP.cast<Map<String, dynamic>>();
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Error al cargar roles');
    }
    setState(() => _loading = false);
  }

  // Extract permission IDs from role — mirrors React:
  // r.rolPermisos?.map((rp) => rp.id_permiso) || r.permisos || []
  List<int> _getPermisosIds(Map<String, dynamic> r) {
    final rolPermisos = r['rolPermisos'];
    if (rolPermisos is List && rolPermisos.isNotEmpty) {
      return rolPermisos
          .map((rp) => rp is Map ? (rp['id_permiso'] as int?) ?? 0 : 0)
          .where((id) => id != 0)
          .toList();
    }
    final p = r['permisos'];
    if (p is List) {
      return p
          .map((e) {
            if (e is int) return e;
            if (e is Map) return (e['id_permiso'] as int?) ?? 0;
            return 0;
          })
          .where((id) => id != 0)
          .toList();
    }
    return [];
  }

  List<Map<String, dynamic>> get _filtrados {
    final q = _busquedaCtrl.text.toLowerCase().trim();
    if (q.isEmpty) return _roles;
    return _roles.where((r) => (r['nombre']?.toString().toLowerCase().contains(q) ?? false)).toList();
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

  // Like React: actualizarRol(id, { estado }) then local state update
  Future<void> _toggleEstado(Map<String, dynamic> r) async {
    final id         = r['id_rol'] ?? r['id'];
    final activo     = r['estado'] == true || r['estado'] == 1;
    final nuevoEstado = activo ? 0 : 1;
    try {
      await ApiService.put('/api/roles/$id', {'estado': nuevoEstado});
      // Like React: setLista(p => p.map(r => r.id_rol === id ? {...r, estado: nuevoEstado} : r))
      if (mounted) {
        setState(() {
          _roles = _roles.map((item) {
            final itemId = item['id_rol'] ?? item['id'];
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

  Future<void> _eliminar(Map<String, dynamic> r) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmarEliminarDialog(nombre: r['nombre'] ?? ''),
    );
    if (confirm != true) return;
    final id = r['id_rol'] ?? r['id'];
    try {
      await ApiService.delete('/api/roles/$id');
      // Like React: setLista(p => p.filter(r => r.id_rol !== id))
      if (mounted) {
        setState(() {
          _roles = _roles.where((item) {
            final itemId = item['id_rol'] ?? item['id'];
            return itemId != id;
          }).toList();
        });
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Rol eliminado'), backgroundColor: AppColors.success));
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
      currentRoute: '/admin/roles',
      body: Column(children: [
        // ── Header ──────────────────────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Roles',
                  style: GoogleFonts.nunito(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF1a1a1a))),
              Text('${_roles.length} roles registrados',
                  style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFF888888))),
            ])),
            GestureDetector(
              onTap: () => showDialog(context: context,
                  builder: (_) => _RolFormDialog(onGuardado: _cargar)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.add_rounded, color: Colors.white, size: 16),
                  const SizedBox(width: 4),
                  Text('+ Añadir rol',
                      style: GoogleFonts.nunito(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ]),
        ),
        // ── Buscador ────────────────────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: TextField(
            controller: _busquedaCtrl,
            onChanged: (_) => setState(() => _pagina = 1),
            style: GoogleFonts.nunito(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Buscar rol...',
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
                    child: _wrapHScroll(paginados.isEmpty
                      ? Center(child: Text('No se encontraron roles',
                            style: GoogleFonts.nunito(color: AppColors.textSecondary)))
                      : RefreshIndicator(
                          color: AppColors.primary,
                          onRefresh: _cargar,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: paginados.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final r          = paginados[i];
                              final activo     = r['estado'] == true || r['estado'] == 1;
                              final permisosIds = _getPermisosIds(r);
                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1))],
                                ),
                                child: Row(children: [
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(r['nombre'] ?? '-',
                                        style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1a1a1a))),
                                    if ((r['descripcion'] ?? '').toString().isNotEmpty)
                                      Text(r['descripcion'].toString(),
                                          style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFF888888))),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                          color: const Color(0xFFF5F5F5),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFFE0E0E0))),
                                      child: Text('${permisosIds.length} permisos',
                                          style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF555555))),
                                    ),
                                  ])),
                                  GestureDetector(onTap: () => _toggleEstado(r), child: _ToggleWidget(activo: activo)),
                                  const SizedBox(width: 10),
                                  // Ver detalle
                                  _ActionBtn(
                                      icon: Icons.visibility_outlined,
                                      onTap: () => showDialog(context: context,
                                          builder: (_) => _RolDetalleDialog(
                                            rol: r,
                                            permisosIds: permisosIds,
                                            permisosDisponibles: _permisosDisponibles,
                                          ))),
                                  const SizedBox(width: 6),
                                  // Gestionar permisos
                                  _ActionBtn(
                                      icon: Icons.lock_outline,
                                      onTap: () => showDialog(context: context,
                                          builder: (_) => _ModalPermisos(
                                            rol: r,
                                            permisosActuales: permisosIds,
                                            permisosDisponibles: _permisosDisponibles,
                                            onGuardar: (nuevos) async {
                                              final id = r['id_rol'] ?? r['id'];
                                              final messenger = ScaffoldMessenger.of(context);
                                              try {
                                                // Like React: PATCH /roles/{id}/permisos
                                                await ApiService.patch(
                                                    '/api/roles/$id/permisos', {'permisos': nuevos});
                                                // Like React: setLista(prev => prev.map(r => r.id_rol === idRol ? {...r, permisos: [...nuevosPermisos]} : r))
                                                if (mounted) {
                                                  setState(() {
                                                    _roles = _roles.map((item) {
                                                      final itemId = item['id_rol'] ?? item['id'];
                                                      if (itemId == id) {
                                                        return <String, dynamic>{
                                                          ...item,
                                                          'rolPermisos': nuevos
                                                              .map((pid) => <String, dynamic>{'id_permiso': pid})
                                                              .toList(),
                                                          'permisos': nuevos,
                                                        };
                                                      }
                                                      return item;
                                                    }).toList();
                                                  });
                                                }
                                                messenger.showSnackBar(const SnackBar(
                                                    content: Text('Permisos guardados'),
                                                    backgroundColor: AppColors.success));
                                              } on ApiException catch (ex) {
                                                messenger.showSnackBar(SnackBar(
                                                    content: Text(ex.message),
                                                    backgroundColor: AppColors.error));
                                              }
                                            },
                                          ))),
                                  const SizedBox(width: 6),
                                  // Editar
                                  _ActionBtn(
                                      icon: Icons.edit_outlined,
                                      onTap: () => showDialog(context: context,
                                          builder: (_) => _RolFormDialog(rol: r, onGuardado: _cargar))),
                                  const SizedBox(width: 6),
                                  // Eliminar
                                  _ActionBtn(icon: Icons.delete_outline, onTap: () => _eliminar(r), danger: true),
                                ]),
                              );
                            },
                          ),
                        )),
                  ),
                  if (totalPaginas > 1) _buildPaginacion(totalPaginas),
                ]),
        ),
      ]),
    );
  }

  Widget _wrapHScroll(Widget child) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: SizedBox(
      width: MediaQuery.sizeOf(context).width,
      child: child,
    ),
  );

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

class _RolFormDialog extends StatefulWidget {
  final Map<String, dynamic>? rol;
  final VoidCallback onGuardado;
  const _RolFormDialog({this.rol, required this.onGuardado});
  @override
  State<_RolFormDialog> createState() => _RolFormDialogState();
}

class _RolFormDialogState extends State<_RolFormDialog> {
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _descCtrl;
  bool _estado    = true;
  bool _guardando = false;
  String? _error;
  Map<String, String> _errores = {};

  bool get _esEditar => widget.rol != null;

  @override
  void initState() {
    super.initState();
    _nombreCtrl = TextEditingController(text: widget.rol?['nombre']      ?? '');
    _descCtrl   = TextEditingController(text: widget.rol?['descripcion'] ?? '');
    _estado     = _esEditar ? (widget.rol!['estado'] == true || widget.rol!['estado'] == 1) : true;
  }

  @override
  void dispose() { _nombreCtrl.dispose(); _descCtrl.dispose(); super.dispose(); }

  Future<void> _guardar() async {
    if (_nombreCtrl.text.trim().isEmpty) {
      setState(() => _errores = {'nombre': 'El nombre es requerido'});
      return;
    }
    setState(() { _guardando = true; _error = null; _errores = {}; });
    try {
      final body = <String, dynamic>{
        'nombre':      _nombreCtrl.text.trim(),
        'descripcion': _descCtrl.text.trim(),
        if (_esEditar) 'estado': _estado ? 1 : 0,
      };
      if (_esEditar) {
        final id = widget.rol!['id_rol'] ?? widget.rol!['id'];
        await ApiService.put('/api/roles/$id', body);
      } else {
        await ApiService.post('/api/roles', body);
      }
      if (mounted) {
        Navigator.pop(context);
        widget.onGuardado();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_esEditar ? 'Rol actualizado' : 'Rol creado'),
          backgroundColor: AppColors.success,
        ));
      }
    } on ApiException catch (e) {
      setState(() {
        if (e.message.toLowerCase().contains('nombre')) {
          _errores = {..._errores, 'nombre': e.message};
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
        constraints: const BoxConstraints(maxWidth: 460),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
            child: Row(children: [
              Expanded(child: Text(_esEditar ? 'Editar rol' : 'Nuevo rol',
                  style: GoogleFonts.nunito(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF1a1a1a)))),
              IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          const Divider(height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                  controller: _nombreCtrl,
                  onChanged: (_) => setState(() { _error = null; _errores.remove('nombre'); }),
                  style: GoogleFonts.nunito(fontSize: 14),
                  decoration: _inputDec('Nombre del rol', error: _errores['nombre'])),
              if (_errores['nombre'] != null) _errMsg(_errores['nombre']!),
              const SizedBox(height: 12),
              TextField(
                  controller: _descCtrl,
                  style: GoogleFonts.nunito(fontSize: 14),
                  decoration: _inputDec('Descripción del rol')),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
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
                    : Text(_esEditar ? 'Guardar cambios' : 'Crear rol',
                        style: GoogleFonts.nunito(color: Colors.white, fontWeight: FontWeight.w700)),
              )),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _RolDetalleDialog extends StatelessWidget {
  final Map<String, dynamic> rol;
  final List<int> permisosIds;
  final List<Map<String, dynamic>> permisosDisponibles;
  const _RolDetalleDialog({
    required this.rol,
    required this.permisosIds,
    required this.permisosDisponibles,
  });

  @override
  Widget build(BuildContext context) {
    final activo = rol['estado'] == true || rol['estado'] == 1;
    // Filter to only assigned permissions, then resolve labels like React
    final permisosRol = permisosDisponibles
        .where((p) => permisosIds.contains(p['id_permiso']))
        .toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
            child: Row(children: [
              Expanded(child: Text('Detalle de rol',
                  style: GoogleFonts.nunito(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF1a1a1a)))),
              IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          const Divider(height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: _DetalleItem(label: 'Nombre', value: rol['nombre'] ?? '-')),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Estado', style: GoogleFonts.nunito(fontSize: 11, color: const Color(0xFF888888))),
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: activo ? const Color(0xFFF0FDF4) : const Color(0xFFFFF5F5),
                        borderRadius: BorderRadius.circular(20)),
                    child: Text(activo ? '● Activo' : '● Inactivo',
                        style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700,
                            color: activo ? AppColors.success : AppColors.primary)),
                  ),
                ])),
              ]),
              const SizedBox(height: 8),
              Text('Descripción',
                  style: GoogleFonts.nunito(fontSize: 11, color: const Color(0xFF888888))),
              const SizedBox(height: 3),
              Text(
                (rol['descripcion']?.toString().isEmpty ?? true) ? '—' : rol['descripcion'].toString(),
                style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1a1a1a)),
              ),
              const SizedBox(height: 12),
              Text('Permisos asignados (${permisosRol.length})',
                  style: GoogleFonts.nunito(fontSize: 11, color: const Color(0xFF888888))),
              const SizedBox(height: 6),
              permisosRol.isEmpty
                  ? Text('Sin permisos asignados',
                        style: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFF999999)))
                  : Wrap(
                      spacing: 6, runSpacing: 6,
                      children: permisosRol.map((p) {
                        final nombre = p['nombre']?.toString() ?? '';
                        final label  = _kLabelPermiso[nombre] ?? nombre;
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                              color: const Color(0xFFF5F5F5),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFE0E0E0))),
                          child: Text(label,
                              style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF555555))),
                        );
                      }).toList(),
                    ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
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

class _ModalPermisos extends StatefulWidget {
  final Map<String, dynamic> rol;
  final List<int> permisosActuales;
  final List<Map<String, dynamic>> permisosDisponibles;
  final Future<void> Function(List<int>) onGuardar;
  const _ModalPermisos({
    required this.rol,
    required this.permisosActuales,
    required this.permisosDisponibles,
    required this.onGuardar,
  });
  @override
  State<_ModalPermisos> createState() => _ModalPermisosState();
}

class _ModalPermisosState extends State<_ModalPermisos> {
  late List<int> _seleccionados;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _seleccionados = List.from(widget.permisosActuales);
  }

  void _togglePermiso(int id) {
    setState(() {
      if (_seleccionados.contains(id)) {
        _seleccionados.remove(id);
      } else {
        _seleccionados.add(id);
      }
    });
  }

  void _toggleTodos() {
    setState(() {
      if (_seleccionados.length == widget.permisosDisponibles.length) {
        _seleccionados.clear();
      } else {
        _seleccionados = widget.permisosDisponibles
            .map((p) => p['id_permiso'] as int? ?? 0)
            .where((id) => id != 0)
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // ── Header ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
            child: Row(children: [
              Expanded(child: Text('Permisos — ${widget.rol['nombre']}',
                  style: GoogleFonts.nunito(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF1a1a1a)))),
              IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          const Divider(height: 16),
          // ── Counter + toggle all ─────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFF0F0F0))),
              child: Row(children: [
                Text('${_seleccionados.length} de ${widget.permisosDisponibles.length} permisos seleccionados',
                    style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF666666))),
                const Spacer(),
                GestureDetector(
                  onTap: _toggleTodos,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFDDDDDD))),
                    child: Text(
                      _seleccionados.length == widget.permisosDisponibles.length
                          ? 'Quitar todos' : 'Seleccionar todos',
                      style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF666666)),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          // ── Permission list ──────────────────────────────────
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
            child: widget.permisosDisponibles.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: widget.permisosDisponibles.map((p) {
                        final idPermiso = p['id_permiso'] as int? ?? 0;
                        final nombre    = p['nombre']?.toString() ?? '';
                        final label     = _kLabelPermiso[nombre] ?? nombre;
                        final desc      = p['descripcion']?.toString() ?? '';
                        final activo    = _seleccionados.contains(idPermiso);
                        return GestureDetector(
                          onTap: () => _togglePermiso(idPermiso),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: activo ? const Color(0xFFF5F3FF) : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: activo ? const Color(0xFF7C3AED) : const Color(0xFFE8E8E8),
                                  width: 1.5),
                            ),
                            child: Row(children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 20, height: 20,
                                decoration: BoxDecoration(
                                  color: activo ? const Color(0xFF7C3AED) : Colors.white,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                      color: activo ? const Color(0xFF7C3AED) : const Color(0xFFDDDDDD),
                                      width: 2),
                                ),
                                alignment: Alignment.center,
                                child: activo
                                    ? const Icon(Icons.check, size: 13, color: Colors.white)
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(label,
                                    style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700,
                                        color: activo ? const Color(0xFF4C1D95) : const Color(0xFF333333))),
                                if (desc.isNotEmpty)
                                  Text(desc,
                                      style: GoogleFonts.nunito(fontSize: 11, color: const Color(0xFF999999))),
                              ])),
                            ]),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          // ── Footer ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
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
                onPressed: _guardando ? null : () async {
                  setState(() => _guardando = true);
                  final nav = Navigator.of(context);
                  await widget.onGuardar(List<int>.from(_seleccionados));
                  nav.pop();
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0),
                child: _guardando
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('Guardar permisos',
                        style: GoogleFonts.nunito(color: Colors.white, fontWeight: FontWeight.w700)),
              )),
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
        Text.rich(
          TextSpan(
            style: GoogleFonts.nunito(fontSize: 16),
            children: [
              const TextSpan(text: '¿Eliminar el rol '),
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

// NOTE: Roles toggle uses AppColors.primary (red) for inactive — matches React Roles.jsx
class _ToggleWidget extends StatelessWidget {
  final bool activo;
  const _ToggleWidget({required this.activo});
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    width: 44, height: 24,
    decoration: BoxDecoration(
        color: activo ? const Color(0xFF22c55e) : AppColors.primary,
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
  final String value;
  const _DetalleItem({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: GoogleFonts.nunito(fontSize: 11, color: const Color(0xFF888888))),
    const SizedBox(height: 3),
    Text(value, style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1a1a1a))),
  ]);
}

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

Widget _errMsg(String msg) => Padding(
  padding: const EdgeInsets.only(top: 4),
  child: Text(msg, style: GoogleFonts.nunito(fontSize: 11, color: AppColors.error, fontWeight: FontWeight.w600)),
);
