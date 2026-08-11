import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/cloudinary_service.dart';
import '../../../shared/layouts/admin_layout.dart';

const _porPagina = 5;

class ToppingsScreen extends StatefulWidget {
  const ToppingsScreen({super.key});

  @override
  State<ToppingsScreen> createState() => _ToppingsScreenState();
}

class _ToppingsScreenState extends State<ToppingsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
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
      final data = await ApiService.get('/api/toppings');
      List raw = data is List
          ? data
          : (data is Map && data['data'] is List ? data['data'] as List : []);
      setState(() => _items = raw.cast<Map<String, dynamic>>());
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Error al cargar toppings');
    }
    setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _filtrados {
    final q = _busquedaCtrl.text.toLowerCase().trim();
    if (q.isEmpty) return _items;
    return _items
        .where((t) => (t['nombre']?.toString().toLowerCase().contains(q) ?? false))
        .toList();
  }

  Future<void> _toggleEstado(Map<String, dynamic> item) async {
    final id = item['id_topping'] ?? item['id'];
    final nuevoEstado = (item['estado'] == true || item['estado'] == 1) ? 0 : 1;
    try {
      await ApiService.patch('/api/toppings/$id/estado', {'estado': nuevoEstado});
      setState(() {
        final idx = _items.indexWhere((t) => (t['id_topping'] ?? t['id']) == id);
        if (idx != -1) _items[idx] = {..._items[idx], 'estado': nuevoEstado};
      });
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _eliminar(Map<String, dynamic> item) async {
    final id = item['id_topping'] ?? item['id'];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmarEliminarDialog(nombre: item['nombre'] ?? ''),
    );
    if (confirm != true) return;
    try {
      await ApiService.delete('/api/toppings/$id');
      setState(() => _items.removeWhere((t) => (t['id_topping'] ?? t['id']) == id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Topping eliminado'),
              backgroundColor: AppColors.success),
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
      builder: (_) => _ToppingFormDialog(onGuardado: _cargar),
    );
  }

  void _abrirEditar(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (_) => _ToppingFormDialog(item: item, onGuardado: _cargar),
    );
  }

  void _abrirDetalle(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (_) => _ToppingDetalleDialog(item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _filtrados;
    final totalPaginas =
        filtrados.isEmpty ? 1 : ((filtrados.length + _porPagina - 1) ~/ _porPagina);
    final paginaActual = _pagina.clamp(1, totalPaginas);
    final paginados =
        filtrados.skip((paginaActual - 1) * _porPagina).take(_porPagina).toList();

    return AdminLayout(
      currentRoute: '/admin/toppings',
      body: Column(
        children: [
          // ── Header ────────────────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Toppings',
                          style: GoogleFonts.nunito(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1a1a1a))),
                      Text(
                        '${_items.length} toppings registrados',
                        style: GoogleFonts.nunito(
                            fontSize: 12, color: const Color(0xFF888888)),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _abrirCrear,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_rounded,
                            color: Colors.white, size: 16),
                        const SizedBox(width: 4),
                        Text('+ Añadir topping',
                            style: GoogleFonts.nunito(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Buscador ──────────────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: TextField(
              controller: _busquedaCtrl,
              onChanged: (_) => setState(() => _pagina = 1),
              style: GoogleFonts.nunito(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Buscar topping...',
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

          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          // ── Lista ─────────────────────────────────────────────────────────────
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
                                style:
                                    GoogleFonts.nunito(color: AppColors.error)),
                            const SizedBox(height: 12),
                            TextButton(
                                onPressed: _cargar,
                                child: const Text('Reintentar')),
                          ],
                        ),
                      )
                    : filtrados.isEmpty
                        ? Center(
                            child: Text('No se encontraron toppings',
                                style: GoogleFonts.nunito(
                                    color: AppColors.textSecondary)),
                          )
                        : Column(
                            children: [
                              Expanded(
                                child: RefreshIndicator(
                                  color: AppColors.primary,
                                  onRefresh: _cargar,
                                  child: ListView.separated(
                                    padding: const EdgeInsets.all(16),
                                    itemCount: paginados.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 8),
                                    itemBuilder: (context, i) {
                                      final item = paginados[i];
                                      final activo = item['estado'] == true ||
                                          item['estado'] == 1;
                                      final img =
                                          item['img']?.toString() ?? '';
                                      return Opacity(
                                        opacity: activo ? 1.0 : 0.6,
                                        child: Container(
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            boxShadow: const [
                                              BoxShadow(
                                                  color: Color(0x0A000000),
                                                  blurRadius: 4,
                                                  offset: Offset(0, 1))
                                            ],
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              if (img.isNotEmpty) ...[
                                                ClipRRect(
                                                  borderRadius: BorderRadius.circular(8),
                                                  child: Image.network(
                                                    img,
                                                    width: 48,
                                                    height: 48,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (_, __, ___) =>
                                                        const SizedBox(width: 48, height: 48),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                              ],
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(children: [
                                                      Expanded(
                                                        child: Text(
                                                          item['nombre'] ?? '-',
                                                          style: GoogleFonts.nunito(
                                                              fontSize: 14,
                                                              fontWeight: FontWeight.w700,
                                                              color: const Color(0xFF1a1a1a)),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      GestureDetector(
                                                        onTap: () => _toggleEstado(item),
                                                        child: _ToggleWidget(activo: activo),
                                                      ),
                                                    ]),
                                                    if ((item['descripcion'] ?? '').toString().isNotEmpty) ...[
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        item['descripcion'].toString(),
                                                        style: GoogleFonts.nunito(
                                                            fontSize: 12,
                                                            color: const Color(0xFF888888)),
                                                        maxLines: 2,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ],
                                                    const SizedBox(height: 8),
                                                    Row(
                                                      mainAxisAlignment: MainAxisAlignment.end,
                                                      children: [
                                                        _ActionBtn(
                                                            icon: Icons.visibility_outlined,
                                                            onTap: () => _abrirDetalle(item)),
                                                        const SizedBox(width: 6),
                                                        _ActionBtn(
                                                            icon: Icons.edit_outlined,
                                                            onTap: () => _abrirEditar(item)),
                                                        const SizedBox(width: 6),
                                                        _ActionBtn(
                                                            icon: Icons.delete_outline,
                                                            onTap: () => _eliminar(item),
                                                            danger: true),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              if (totalPaginas > 1)
                                _PaginationBar(
                                  pagina: paginaActual,
                                  totalPaginas: totalPaginas,
                                  onCambiar: (p) =>
                                      setState(() => _pagina = p),
                                ),
                            ],
                          ),
          ),
        ],
      ),
    );
  }
}

// ─── Form Dialog ──────────────────────────────────────────────────────────────

class _ToppingFormDialog extends StatefulWidget {
  final Map<String, dynamic>? item;
  final VoidCallback onGuardado;
  const _ToppingFormDialog({this.item, required this.onGuardado});

  @override
  State<_ToppingFormDialog> createState() => _ToppingFormDialogState();
}

class _ToppingFormDialogState extends State<_ToppingFormDialog> {
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _gramajeCtrl;
  late final TextEditingController _descCtrl;
  bool _estado = true;
  bool _guardando = false;
  String? _error;
  Map<String, String> _errores = {};
  String? _img;

  bool get _esEditar => widget.item != null;

  @override
  void initState() {
    super.initState();
    _nombreCtrl  = TextEditingController(text: widget.item?['nombre']      ?? '');
    _gramajeCtrl = TextEditingController(text: widget.item?['gramaje']     ?? '');
    _descCtrl    = TextEditingController(text: widget.item?['descripcion'] ?? '');
    _img = widget.item?['img']?.toString();
    if (_esEditar) {
      _estado = widget.item!['estado'] == true || widget.item!['estado'] == 1;
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _gramajeCtrl.dispose();
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
      final body = <String, dynamic>{
        'nombre':      _nombreCtrl.text.trim(),
        'descripcion': _descCtrl.text.trim(),
        'gramaje':     _gramajeCtrl.text.trim().isEmpty
                           ? null
                           : _gramajeCtrl.text.trim(),
        'img':         _img ?? '',
        'estado':      _esEditar ? _estado : true,
      };
      if (_esEditar) {
        final id = widget.item!['id_topping'] ?? widget.item!['id'];
        await ApiService.put('/api/toppings/$id', body);
      } else {
        await ApiService.post('/api/toppings', body);
      }
      if (mounted) {
        Navigator.pop(context);
        widget.onGuardado();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_esEditar ? 'Topping actualizado' : 'Topping creado'),
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
      setState(() => _error = 'Error al guardar. Inténtalo de nuevo.');
    }
    setState(() => _guardando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        decoration:
            BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ───────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _esEditar ? 'Editar topping' : 'Nuevo topping',
                        style: GoogleFonts.nunito(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1a1a1a)),
                      ),
                    ),
                    IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(context)),
                  ],
                ),
              ),
              const Divider(height: 16),

              // ── Fields ───────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nombre
                    _FormField(
                      label: 'Nombre *',
                      child: TextField(
                        controller: _nombreCtrl,
                        onChanged: (_) =>
                            setState(() => _errores.remove('nombre')),
                        style: GoogleFonts.nunito(fontSize: 14),
                        decoration:
                            _inputDec('Nombre del topping', error: _errores['nombre']),
                      ),
                    ),
                    if (_errores['nombre'] != null)
                      _errMsg(_errores['nombre']!),
                    const SizedBox(height: 14),

                    // Gramaje
                    _FormField(
                      label: 'Gramaje (opcional)',
                      child: TextField(
                        controller: _gramajeCtrl,
                        style: GoogleFonts.nunito(fontSize: 14),
                        decoration: _inputDec('Ej: 100g, 150ml...'),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Descripción
                    _FormField(
                      label: 'Descripción',
                      child: TextField(
                        controller: _descCtrl,
                        style: GoogleFonts.nunito(fontSize: 14),
                        decoration: _inputDec('Descripción'),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Estado — solo al editar
                    if (_esEditar) ...[
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
                              color: _estado
                                  ? const Color(0xFF22c55e)
                                  : AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Imagen
                    _FormField(
                      label: 'Imagen',
                      child: _ImageUploadWidget(
                        imageUrl: _img,
                        onChanged: (url) => setState(() => _img = url),
                      ),
                    ),

                    // Error general
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: AppColors.errorLight,
                            borderRadius: BorderRadius.circular(8)),
                        child: Text(_error!,
                            style: GoogleFonts.nunito(
                                color: AppColors.error, fontSize: 13)),
                      ),
                    ],
                  ],
                ),
              ),

              // ── Buttons ──────────────────────────────────────────────────────
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
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text('Cancelar',
                            style: GoogleFonts.nunito(
                                color: const Color(0xFF666666),
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
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
                                _esEditar
                                    ? 'Guardar cambios'
                                    : 'Crear topping',
                                style: GoogleFonts.nunito(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Detail Dialog ────────────────────────────────────────────────────────────

class _ToppingDetalleDialog extends StatelessWidget {
  final Map<String, dynamic> item;
  const _ToppingDetalleDialog({required this.item});

  @override
  Widget build(BuildContext context) {
    final activo = item['estado'] == true || item['estado'] == 1;
    final img = item['img']?.toString() ?? '';

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        decoration:
            BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Detalle de topping',
                        style: GoogleFonts.nunito(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1a1a1a))),
                  ),
                  IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const Divider(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Imagen
                  if (img.isNotEmpty) ...[
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          img,
                          height: 120,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Estado badge (primero, como en React)
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: activo
                                ? const Color(0xFFf0fdf4)
                                : const Color(0xFFfff5f5),
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: Text(
                            activo ? '● Activo' : '● Inactivo',
                            style: GoogleFonts.nunito(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: activo
                                  ? const Color(0xFF22c55e)
                                  : AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Nombre
                  _DetalleRow(label: 'Nombre', value: item['nombre'] ?? '-'),
                  // Gramaje (si existe)
                  if ((item['gramaje'] ?? '').toString().isNotEmpty)
                    _DetalleRow(
                        label: 'Gramaje',
                        value: item['gramaje'].toString()),
                  // Descripción
                  _DetalleRow(
                    label: 'Descripción',
                    value: (item['descripcion'] ?? '').toString().isEmpty
                        ? '—'
                        : item['descripcion'].toString(),
                  ),
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
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Cerrar',
                      style: GoogleFonts.nunito(
                          color: const Color(0xFF666666),
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Confirm Delete Dialog ────────────────────────────────────────────────────

class _ConfirmarEliminarDialog extends StatelessWidget {
  final String nombre;
  const _ConfirmarEliminarDialog({required this.nombre});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        decoration:
            BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.delete_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: GoogleFonts.nunito(
                    fontSize: 15, color: const Color(0xFF1a1a1a)),
                children: [
                  const TextSpan(text: '¿Eliminar el topping '),
                  TextSpan(
                      text: '"$nombre"',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const TextSpan(
                      text: '?\nEsta acción no se puede deshacer.'),
                ],
              ),
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
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text('Cancelar',
                        style: GoogleFonts.nunito(
                            color: const Color(0xFF666666),
                            fontWeight: FontWeight.w600)),
                  ),
                ),
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
                            color: Colors.white,
                            fontWeight: FontWeight.w700)),
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

// ─── Image Upload Widget ──────────────────────────────────────────────────────

class _ImageUploadWidget extends StatefulWidget {
  final String? imageUrl;
  final void Function(String?) onChanged;
  const _ImageUploadWidget({this.imageUrl, required this.onChanged});

  @override
  State<_ImageUploadWidget> createState() => _ImageUploadWidgetState();
}

class _ImageUploadWidgetState extends State<_ImageUploadWidget> {
  bool _subiendo = false;
  String? _errorImg;

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final nombre = picked.name.toLowerCase();
    if (!nombre.endsWith('.jpg') && !nombre.endsWith('.jpeg') && !nombre.endsWith('.png')) {
      setState(() => _errorImg = 'Formato no permitido. Solo JPG o PNG');
      return;
    }
    if (await picked.length() > 5 * 1024 * 1024) {
      setState(() => _errorImg = 'El archivo supera el tamaño máximo de 5 MB');
      return;
    }
    setState(() {
      _subiendo = true;
      _errorImg = null;
    });
    try {
      final url = await CloudinaryService.subirImagen(File(picked.path));
      if (url != null) {
        widget.onChanged(url);
      } else {
        setState(() => _errorImg = 'Error al subir imagen');
      }
    } catch (_) {
      setState(() => _errorImg = 'Error al subir imagen');
    }
    setState(() => _subiendo = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _subiendo ? null : _pickAndUpload,
          child: Container(
            height: 90,
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FD),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            clipBehavior: Clip.antiAlias,
            child: _subiendo
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primary, strokeWidth: 2))
                : (widget.imageUrl != null && widget.imageUrl!.isNotEmpty)
                    ? Image.network(
                        widget.imageUrl!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (_, __, ___) => _placeholder(),
                      )
                    : _placeholder(),
          ),
        ),
        if (_errorImg != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_errorImg!,
                style: GoogleFonts.nunito(
                    fontSize: 11,
                    color: AppColors.error,
                    fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }

  Widget _placeholder() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.image_outlined,
                size: 28, color: Color(0xFFBBBBBB)),
            const SizedBox(height: 4),
            Text('Subir imagen',
                style: GoogleFonts.nunito(
                    fontSize: 12, color: const Color(0xFFAAAAAA))),
          ],
        ),
      );
}

// ─── Pagination Bar ───────────────────────────────────────────────────────────

class _PaginationBar extends StatelessWidget {
  final int pagina;
  final int totalPaginas;
  final void Function(int) onCambiar;
  const _PaginationBar(
      {required this.pagina,
      required this.totalPaginas,
      required this.onCambiar});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _PageBtn(
              label: '‹',
              enabled: pagina > 1,
              onTap: () => onCambiar(pagina - 1)),
          for (int n = 1; n <= totalPaginas; n++)
            _PageBtn(
                label: '$n',
                active: pagina == n,
                onTap: () => onCambiar(n)),
          _PageBtn(
              label: '›',
              enabled: pagina < totalPaginas,
              onTap: () => onCambiar(pagina + 1)),
        ],
      ),
    );
  }
}

class _PageBtn extends StatelessWidget {
  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;
  const _PageBtn(
      {required this.label,
      this.active = false,
      this.enabled = true,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.transparent,
          border: Border.all(
              color: active ? AppColors.primary : const Color(0xFFE0E0E0)),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.nunito(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: active
                ? Colors.white
                : enabled
                    ? const Color(0xFF666666)
                    : const Color(0xFFBBBBBB),
          ),
        ),
      ),
    );
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

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
                  color: Colors.white, shape: BoxShape.circle),
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
  const _ActionBtn(
      {required this.icon, required this.onTap, this.danger = false});

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

InputDecoration _inputDec(String hint, {String? error}) => InputDecoration(
      hintText: hint,
      hintStyle:
          GoogleFonts.nunito(fontSize: 13, color: const Color(0xFFAAAAAA)),
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

Widget _errMsg(String msg) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(msg,
          style: GoogleFonts.nunito(
              fontSize: 11,
              color: AppColors.error,
              fontWeight: FontWeight.w600)),
    );
