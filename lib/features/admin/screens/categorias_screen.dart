import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/layouts/admin_layout.dart';

class CategoriasScreen extends StatefulWidget {
  const CategoriasScreen({super.key});

  @override
  State<CategoriasScreen> createState() => _CategoriasScreenState();
}

class _CategoriasScreenState extends State<CategoriasScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _categorias = [];
  final _busquedaCtrl = TextEditingController();
  int _pagina = 1;

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
      final data = await ApiService.get('/api/categorias');
      List raw = [];
      if (data is List) {
        raw = data;
      } else if (data is Map && data['data'] is List) {
        raw = data['data'] as List;
      }
      _categorias = raw.cast<Map<String, dynamic>>();
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Error al cargar categorías';
    }
    setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _filtradas {
    final q = _busquedaCtrl.text.toLowerCase().trim();
    if (q.isEmpty) return _categorias;
    return _categorias.where((c) {
      return c['nombre']?.toString().toLowerCase().contains(q) ?? false;
    }).toList();
  }

  Future<void> _toggleEstado(Map<String, dynamic> cat) async {
    final id = cat['id_categoria'] ?? cat['id'];
    final nuevoEstado = !(cat['estado'] == true || cat['estado'] == 1);
    try {
      await ApiService.patch('/api/categorias/$id/estado', {
        'estado': nuevoEstado ? 1 : 0,
      });
      await _cargar();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _eliminar(Map<String, dynamic> cat) async {
    final id = cat['id_categoria'] ?? cat['id'];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmarEliminarDialog(nombre: cat['nombre'] ?? ''),
    );
    if (confirm != true) return;
    try {
      await ApiService.delete('/api/categorias/$id');
      await _cargar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Categoría eliminada'),
            backgroundColor: AppColors.success,
          ),
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
    showDialog(
      context: context,
      builder: (_) => _CategoriaFormDialog(
        onGuardado: _cargar,
      ),
    );
  }

  void _abrirEditar(Map<String, dynamic> cat) {
    showDialog(
      context: context,
      builder: (_) => _CategoriaFormDialog(
        categoria: cat,
        onGuardado: _cargar,
      ),
    );
  }

  void _abrirDetalle(Map<String, dynamic> cat) {
    showDialog(
      context: context,
      builder: (_) => _CategoriaDetalleDialog(categoria: cat),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtradas = _filtradas;
    const porPagina = 5;
    final totalPaginas = filtradas.isEmpty ? 1 : ((filtradas.length + porPagina - 1) ~/ porPagina);
    final paginaActual = _pagina.clamp(1, totalPaginas);
    final paginadas = filtradas.skip((paginaActual - 1) * porPagina).take(porPagina).toList();

    return AdminLayout(
      currentRoute: '/admin/categorias',
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
                      Text(
                        'Categorías',
                        style: GoogleFonts.nunito(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1a1a1a),
                        ),
                      ),
                      Text(
                        '${_categorias.length} categorías registradas',
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          color: const Color(0xFF888888),
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _abrirCrear,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_rounded, color: Colors.white, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          '+ Añadir categoría',
                          style: GoogleFonts.nunito(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
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
                hintText: 'Buscar categoría...',
                hintStyle: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFFAAAAAA)),
                prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF888888)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                filled: true,
                fillColor: const Color(0xFFF7F8FD),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(50),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(50),
                  borderSide: const BorderSide(color: Color(0xFFE8E8E8)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(50),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
          ),

          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          // Lista
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, color: AppColors.error, size: 48),
                            const SizedBox(height: 12),
                            Text(_error!, style: GoogleFonts.nunito(color: AppColors.error)),
                            const SizedBox(height: 12),
                            TextButton(onPressed: _cargar, child: const Text('Reintentar')),
                          ],
                        ),
                      )
                    : filtradas.isEmpty
                        ? Center(
                            child: Text(
                              'No se encontraron categorías',
                              style: GoogleFonts.nunito(color: AppColors.textSecondary),
                            ),
                          )
                        : Column(
                            children: [
                              Expanded(
                                child: RefreshIndicator(
                                  color: AppColors.primary,
                                  onRefresh: _cargar,
                                  child: ListView.separated(
                                    padding: const EdgeInsets.all(16),
                                    itemCount: paginadas.length,
                                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                                    itemBuilder: (context, i) {
                                      final cat = paginadas[i];
                                      final activo = cat['estado'] == true || cat['estado'] == 1;
                                      return Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(10),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Color(0x0A000000),
                                              blurRadius: 4,
                                              offset: Offset(0, 1),
                                            ),
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
                                                    (cat['nombre'] ?? '').toString().isNotEmpty
                                                        ? (cat['nombre'] as String)[0].toUpperCase()
                                                        : '?',
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
                                                      Text(
                                                        cat['nombre'] ?? '-',
                                                        style: GoogleFonts.nunito(
                                                          fontSize: 14,
                                                          fontWeight: FontWeight.w700,
                                                          color: const Color(0xFF1a1a1a),
                                                        ),
                                                      ),
                                                      if ((cat['descripcion'] ?? '').toString().isNotEmpty)
                                                        Text(
                                                          cat['descripcion'].toString(),
                                                          style: GoogleFonts.nunito(
                                                            fontSize: 12,
                                                            color: const Color(0xFF888888),
                                                          ),
                                                          maxLines: 2,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                GestureDetector(
                                                  onTap: () => _toggleEstado(cat),
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
                                                  onTap: () => _abrirDetalle(cat),
                                                ),
                                                const SizedBox(width: 6),
                                                _ActionBtn(
                                                  icon: Icons.edit_outlined,
                                                  onTap: () => _abrirEditar(cat),
                                                ),
                                                const SizedBox(width: 6),
                                                _ActionBtn(
                                                  icon: Icons.delete_outline,
                                                  onTap: () => _eliminar(cat),
                                                  danger: true,
                                                ),
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
                                  pagina: paginaActual,
                                  totalPaginas: totalPaginas,
                                  onCambiar: (n) => setState(() => _pagina = n),
                                ),
                            ],
                          ),
          ),
        ],
      ),
    );
  }
}

// ─── Dialogs ──────────────────────────────────────────────────────────────────

class _CategoriaFormDialog extends StatefulWidget {
  final Map<String, dynamic>? categoria;
  final VoidCallback onGuardado;

  const _CategoriaFormDialog({this.categoria, required this.onGuardado});

  @override
  State<_CategoriaFormDialog> createState() => _CategoriaFormDialogState();
}

class _CategoriaFormDialogState extends State<_CategoriaFormDialog> {
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _descCtrl;
  bool _estado = true;
  late final bool _estadoOriginal;
  bool _guardando = false;
  String? _error;
  Map<String, String> _errores = {};

  bool get _esEditar => widget.categoria != null;

  @override
  void initState() {
    super.initState();
    _nombreCtrl = TextEditingController(text: widget.categoria?['nombre'] ?? '');
    _descCtrl = TextEditingController(text: widget.categoria?['descripcion'] ?? '');
    if (_esEditar) {
      _estado = widget.categoria!['estado'] == true || widget.categoria!['estado'] == 1;
    }
    _estadoOriginal = _estado;
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_nombreCtrl.text.trim().isEmpty) {
      setState(() => _errores = {'nombre': 'El nombre es requerido'});
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
      _errores = {};
    });
    try {
      final body = {
        'nombre': _nombreCtrl.text.trim(),
        'descripcion': _descCtrl.text.trim(),
      };
      String? errorEstado;
      if (_esEditar) {
        final id = widget.categoria!['id_categoria'] ?? widget.categoria!['id'];
        await ApiService.put('/api/categorias/$id', body);
        if (_estado != _estadoOriginal) {
          try {
            await ApiService.patch('/api/categorias/$id/estado', {'estado': _estado ? 1 : 0});
          } on ApiException catch (e) {
            errorEstado = e.message;
          } catch (_) {
            errorEstado = 'Error al cambiar el estado';
          }
        }
      } else {
        await ApiService.post('/api/categorias', body);
      }
      if (mounted) {
        Navigator.pop(context);
        widget.onGuardado();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorEstado != null
                ? '${_esEditar ? 'Categoría actualizada' : 'Categoría creada'}, pero no se pudo cambiar el estado: $errorEstado'
                : (_esEditar ? 'Categoría actualizada' : 'Categoría creada')),
            backgroundColor: errorEstado != null ? AppColors.error : AppColors.success,
          ),
        );
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
        constraints: const BoxConstraints(maxWidth: 500),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _esEditar ? 'Editar categoría' : 'Nueva categoría',
                      style: GoogleFonts.nunito(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1a1a1a),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 16),

            // Form
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FormField(label: 'Nombre *', child: TextField(
                    controller: _nombreCtrl,
                    onChanged: (_) => setState(() => _errores.remove('nombre')),
                    style: GoogleFonts.nunito(fontSize: 14),
                    decoration: _inputDec('Nombre de la categoría', error: _errores['nombre']),
                  )),
                  if (_errores['nombre'] != null) _errMsg(_errores['nombre']!),
                  const SizedBox(height: 14),
                  _FormField(label: 'Descripción', child: TextField(
                    controller: _descCtrl,
                    style: GoogleFonts.nunito(fontSize: 14),
                    decoration: _inputDec('Descripción'),
                  )),
                  if (_esEditar) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => setState(() => _estado = !_estado),
                          child: _ToggleWidget(activo: _estado),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _estado ? 'Activo' : 'Inactivo',
                          style: GoogleFonts.nunito(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _estado ? const Color(0xFF22c55e) : AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.errorLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_error!,
                          style: GoogleFonts.nunito(color: AppColors.error, fontSize: 13)),
                    ),
                  ],
                ],
              ),
            ),

            // Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE0E0E0)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text('Cancelar',
                          style: GoogleFonts.nunito(
                              color: const Color(0xFF666666), fontWeight: FontWeight.w600)),
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
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : Text(
                              _esEditar ? 'Guardar cambios' : 'Crear categoría',
                              style: GoogleFonts.nunito(
                                  color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoriaDetalleDialog extends StatelessWidget {
  final Map<String, dynamic> categoria;

  const _CategoriaDetalleDialog({required this.categoria});

  @override
  Widget build(BuildContext context) {
    final activo = categoria['estado'] == true || categoria['estado'] == 1;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Detalle de categoría',
                      style: GoogleFonts.nunito(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1a1a1a)),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 16),
            if ((categoria['img'] ?? '').toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: categoria['img'].toString(),
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(height: 120, color: const Color(0xFFF5F5F5)),
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                children: [
                  _DetalleRow(label: 'Nombre', value: categoria['nombre'] ?? '-'),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Text('Estado',
                            style: GoogleFonts.nunito(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF888888))),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: activo ? const Color(0xFFF0FDF4) : const Color(0xFFFFF5F5),
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: Text(
                            activo ? '● Activo' : '● Inactivo',
                            style: GoogleFonts.nunito(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: activo ? AppColors.success : AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _DetalleRow(
                      label: 'Descripción',
                      value: (categoria['descripcion'] ?? '').toString().isEmpty
                          ? '—'
                          : categoria['descripcion'].toString()),
                ],
              ),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Cerrar',
                      style: GoogleFonts.nunito(
                          color: const Color(0xFF666666), fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmarEliminarDialog extends StatelessWidget {
  final String nombre;

  const _ConfirmarEliminarDialog({required this.nombre});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.delete_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(
              '¿Eliminar la categoría "$nombre"?',
              style: GoogleFonts.nunito(
                  fontSize: 17, fontWeight: FontWeight.w800, color: const Color(0xFF1a1a1a)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Esta acción no se puede deshacer.',
              style: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFF888888)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE0E0E0)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text('Cancelar',
                        style: GoogleFonts.nunito(
                            color: const Color(0xFF666666), fontWeight: FontWeight.w600)),
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
                    child: Text('Sí, eliminar',
                        style: GoogleFonts.nunito(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
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
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 44,
      height: 24,
      decoration: BoxDecoration(
        color: activo ? const Color(0xFF22c55e) : const Color(0xFF9ca3af),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            left: activo ? 22 : 2,
            top: 2,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
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
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 16,
          color: danger ? AppColors.error : const Color(0xFF666666),
        ),
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  final String label;
  final Widget child;

  const _FormField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.nunito(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF555555))),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _DetalleRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetalleRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF888888))),
          ),
          Expanded(
            child: Text(value,
                style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1a1a1a))),
          ),
        ],
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
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: error != null ? AppColors.error : const Color(0xFFE0E0E0)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: error != null ? AppColors.error : const Color(0xFFE0E0E0)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
    ),
  );
}

Widget _errMsg(String msg) => Padding(
  padding: const EdgeInsets.only(top: 4),
  child: Text(msg, style: GoogleFonts.nunito(fontSize: 11, color: AppColors.error, fontWeight: FontWeight.w600)),
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
