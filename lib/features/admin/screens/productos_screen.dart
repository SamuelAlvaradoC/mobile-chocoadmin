import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/cloudinary_service.dart';
import '../../../shared/layouts/admin_layout.dart';

class ProductosScreen extends StatefulWidget {
  const ProductosScreen({super.key});
  @override
  State<ProductosScreen> createState() => _ProductosScreenState();
}

class _ProductosScreenState extends State<ProductosScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _productos = [];
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
    setState(() { _loading = true; _error = null; });
    // Cada request es independiente (como en React): si categorías falla,
    // no debe tumbar el listado de productos.
    try {
      final data = await ApiService.get('/api/productos');
      List rawP = data is List ? data : (data is Map && data['data'] is List ? data['data'] as List : []);
      setState(() {
        _productos = rawP.cast<Map<String, dynamic>>().map((p) {
          final img = p['imagen']?.toString().isNotEmpty == true
              ? p['imagen'].toString()
              : p['img']?.toString() ?? '';
          return {...p, 'img': img};
        }).toList();
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Error al cargar productos');
    }
    try {
      final data = await ApiService.get('/api/categorias');
      List rawC = data is List ? data : (data is Map && data['data'] is List ? data['data'] as List : []);
      setState(() => _categorias = rawC.cast<Map<String, dynamic>>());
    } catch (_) {}
    setState(() => _loading = false);
  }

  dynamic _filtroCategoria;

  List<Map<String, dynamic>> get _filtrados {
    final q = _busquedaCtrl.text.toLowerCase().trim();
    return _productos.where((p) {
      final coincideNombre = q.isEmpty || (p['nombre']?.toString().toLowerCase().contains(q) ?? false);
      final coincideCat = _filtroCategoria == null ||
          p['id_categoria'].toString() == _filtroCategoria.toString();
      return coincideNombre && coincideCat;
    }).toList();
  }

  String _catNombre(dynamic idCat) {
    final cat = _categorias.firstWhere(
      (c) => c['id_categoria'] == idCat || c['id'] == idCat,
      orElse: () => {},
    );
    return cat['nombre']?.toString() ?? '—';
  }

  Future<void> _toggleEstado(Map<String, dynamic> p) async {
    final id = p['id_producto'] ?? p['id'];
    final nuevoEstado = !(p['estado'] == true || p['estado'] == 1);
    try {
      await ApiService.patch('/api/productos/$id/estado', {'estado': nuevoEstado ? 1 : 0});
      await _cargar();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
      }
    }
  }

  Future<void> _eliminar(Map<String, dynamic> p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmarEliminarDialog(nombre: p['nombre'] ?? ''),
    );
    if (confirm != true) return;
    final id = p['id_producto'] ?? p['id'];
    try {
      await ApiService.delete('/api/productos/$id');
      await _cargar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Producto eliminado'), backgroundColor: AppColors.success));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
      }
    }
  }

  void _abrirCrear() {
    showDialog(context: context,
      builder: (_) => _ProductoFormDialog(categorias: _categorias, onGuardado: _cargar));
  }

  void _abrirEditar(Map<String, dynamic> p) {
    showDialog(context: context,
      builder: (_) => _ProductoFormDialog(categorias: _categorias, producto: p, onGuardado: _cargar));
  }

  void _abrirDetalle(Map<String, dynamic> p) {
    showDialog(context: context,
      builder: (_) => _ProductoDetalleDialog(
        producto: p,
        catNombre: _catNombre(p['id_categoria']),
        onEditar: _abrirEditar,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _filtrados;
    const porPagina = 5;
    final totalPaginas = filtrados.isEmpty ? 1 : ((filtrados.length + porPagina - 1) ~/ porPagina);
    final paginaActual = _pagina.clamp(1, totalPaginas);
    final paginados = filtrados.skip((paginaActual - 1) * porPagina).take(porPagina).toList();

    // Filter count text (matches React)
    String countText = '${filtrados.length} producto${filtrados.length != 1 ? 's' : ''}';
    if (_filtroCategoria != null) {
      final cat = _categorias.firstWhere(
        (c) => c['id_categoria'] == _filtroCategoria || c['id'] == _filtroCategoria,
        orElse: () => {},
      );
      final catName = (cat['nombre'] ?? '').toString();
      if (catName.isNotEmpty) countText += ' en $catName';
    }
    final q = _busquedaCtrl.text.trim();
    if (q.isNotEmpty) countText += ' con "$q"';

    return AdminLayout(
      currentRoute: '/admin/productos',
      body: Column(children: [
        // Header
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Productos', style: GoogleFonts.nunito(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF1a1a1a))),
              Text('${_productos.length} productos registrados',
                  style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFF888888))),
            ])),
            GestureDetector(
              onTap: _abrirCrear,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.add_rounded, color: Colors.white, size: 16),
                  const SizedBox(width: 4),
                  Text('+ Añadir producto', style: GoogleFonts.nunito(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ]),
        ),
        // Buscador + filtro categoría
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Column(children: [
            TextField(
              controller: _busquedaCtrl,
              onChanged: (_) => setState(() => _pagina = 1),
              style: GoogleFonts.nunito(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Buscar producto...',
                hintStyle: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFFAAAAAA)),
                prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF888888)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                filled: true, fillColor: const Color(0xFFF7F8FD),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(50), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(50), borderSide: const BorderSide(color: Color(0xFFE8E8E8))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(50), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
              ),
            ),
            if (_categorias.isNotEmpty) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<dynamic>(
                value: _filtroCategoria,
                isExpanded: true,
                style: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFF1a1a1a)),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  filled: true, fillColor: const Color(0xFFF7F8FD),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                ),
                items: [
                  DropdownMenuItem<dynamic>(value: null, child: Text('Todas las categorías', style: GoogleFonts.nunito(fontSize: 13))),
                  ..._categorias.map((c) => DropdownMenuItem<dynamic>(
                    value: c['id_categoria'] ?? c['id'],
                    child: Text(c['nombre'] ?? '', style: GoogleFonts.nunito(fontSize: 13)),
                  )),
                ],
                onChanged: (v) => setState(() { _filtroCategoria = v; _pagina = 1; }),
              ),
            ],
          ]),
        ),
        // Contador de resultados
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            countText,
            style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFFAAAAAA)),
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
              ? Center(child: Text('No se encontraron productos', style: GoogleFonts.nunito(color: AppColors.textSecondary)))
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
                          itemBuilder: (_, i) {
                            final p = paginados[i];
                            final activo = p['estado'] == true || p['estado'] == 1;
                            final toppings = p['permite_toppings'] == true || p['permite_toppings'] == 1;
                            final precio = (p['precio'] is num) ? (p['precio'] as num).toDouble() : double.tryParse(p['precio']?.toString() ?? '') ?? 0;
                            final imgUrl = (p['img'] ?? '').toString();
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1))],
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (imgUrl.isNotEmpty) ...[
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: CachedNetworkImage(
                                        imageUrl: imgUrl,
                                        width: 48, height: 48,
                                        fit: BoxFit.cover,
                                        placeholder: (_, __) => Container(width: 48, height: 48, color: const Color(0xFFF5F5F5)),
                                        errorWidget: (_, __, ___) => const SizedBox(width: 48, height: 48),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Row(children: [
                                      Expanded(
                                        child: Text(p['nombre'] ?? '-',
                                            style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1a1a1a))),
                                      ),
                                      const SizedBox(width: 8),
                                      GestureDetector(onTap: () => _toggleEstado(p), child: _ToggleWidget(activo: activo)),
                                    ]),
                                    const SizedBox(height: 4),
                                    Wrap(spacing: 6, runSpacing: 4, children: [
                                      _BadgeChip(label: _catNombre(p['id_categoria']), color: const Color(0xFF888888), bg: const Color(0xFFF5F5F5)),
                                      _BadgeChip(label: tamanoLabel(p['tamano']), color: const Color(0xFF888888), bg: const Color(0xFFF5F5F5)),
                                    ]),
                                    const SizedBox(height: 4),
                                    Row(children: [
                                      Text('\$${precio.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.')}',
                                          style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF1a1a1a))),
                                      if (toppings) ...[
                                        const SizedBox(width: 6),
                                        _BadgeChip(
                                          label: 'Toppings: máx. ${p['max_toppings'] ?? 0}',
                                          color: const Color(0xFF666666),
                                          bg: const Color(0xFFF0F0F0),
                                        ),
                                      ],
                                    ]),
                                    const SizedBox(height: 8),
                                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                                      _ActionBtn(icon: Icons.visibility_outlined, onTap: () => _abrirDetalle(p)),
                                      const SizedBox(width: 6),
                                      _ActionBtn(icon: Icons.edit_outlined, onTap: () => _abrirEditar(p)),
                                      const SizedBox(width: 6),
                                      _ActionBtn(icon: Icons.delete_outline, onTap: () => _eliminar(p), danger: true),
                                    ]),
                                  ])),
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
      ]),
    );
  }
}

// ─── Dialogs ──────────────────────────────────────────────────────────────────

class _ProductoFormDialog extends StatefulWidget {
  final Map<String, dynamic>? producto;
  final List<Map<String, dynamic>> categorias;
  final VoidCallback onGuardado;
  const _ProductoFormDialog({this.producto, required this.categorias, required this.onGuardado});
  @override
  State<_ProductoFormDialog> createState() => _ProductoFormDialogState();
}

class _ProductoFormDialogState extends State<_ProductoFormDialog> {
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _precioCtrl;
  dynamic _idCategoria;
  String _tamano = 'Mediano (12oz)';
  int _maxToppings = 1;
  bool _permiteToppings = false;
  bool _permiteChocolate = false;
  bool _permiteSalsas = false;
  bool _esBowl = false;
  bool _estado = true;
  String? _imgUrl;
  File? _imgFile;
  bool _subiendoImagen = false;
  bool _guardando = false;
  String? _error;
  Map<String, String> _errores = {};

  bool get _esEditar => widget.producto != null;

  @override
  void initState() {
    super.initState();
    final p = widget.producto;
    _nombreCtrl      = TextEditingController(text: p?['nombre'] ?? '');
    _descCtrl        = TextEditingController(text: p?['descripcion'] ?? '');
    _precioCtrl      = TextEditingController(text: p?['precio']?.toString() ?? '');
    _idCategoria     = p?['id_categoria'] ?? (widget.categorias.isNotEmpty ? widget.categorias[0]['id_categoria'] ?? widget.categorias[0]['id'] : null);
    _tamano          = _normTamano(p?['tamano'] ?? '');
    _permiteToppings  = p?['permite_toppings'] == true || p?['permite_toppings'] == 1;
    final mt = p?['max_toppings'];
    _maxToppings     = (mt == 2 || mt == '2') ? 2 : (mt == 3 || mt == '3') ? 3 : 1;
    _permiteChocolate = p?['permite_chocolate'] == true || p?['permite_chocolate'] == 1;
    _permiteSalsas   = p?['permite_salsas'] == true || p?['permite_salsas'] == 1;
    _esBowl          = p?['es_bowl'] == true || p?['es_bowl'] == 1;
    _estado          = _esEditar ? (p!['estado'] == true || p['estado'] == 1) : true;
    _imgUrl          = p?['img']?.toString();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose(); _descCtrl.dispose(); _precioCtrl.dispose();
    super.dispose();
  }

  bool _validar() {
    final e = <String, String>{};
    if (_nombreCtrl.text.trim().isEmpty) e['nombre'] = 'El nombre es requerido';
    if (_precioCtrl.text.trim().isEmpty) {
      e['precio'] = 'El precio es requerido';
    } else if ((double.tryParse(_precioCtrl.text) ?? 0) <= 0) {
      e['precio'] = 'El precio debe ser mayor a 0';
    }
    setState(() => _errores = e);
    return e.isEmpty;
  }

  Future<void> _seleccionarImagen() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1200);
    if (picked == null) return;
    final nombre = picked.name.toLowerCase();
    if (!nombre.endsWith('.jpg') && !nombre.endsWith('.jpeg') && !nombre.endsWith('.png')) {
      setState(() => _error = 'Formato no permitido. Solo JPG o PNG');
      return;
    }
    final tamano = await picked.length();
    if (tamano > 5 * 1024 * 1024) {
      setState(() => _error = 'El archivo supera el tamaño máximo de 5 MB');
      return;
    }
    setState(() { _subiendoImagen = true; _imgFile = File(picked.path); _error = null; });
    try {
      final url = await CloudinaryService.subirImagen(File(picked.path));
      if (mounted) setState(() { _imgUrl = url; _subiendoImagen = false; });
    } catch (_) {
      if (mounted) setState(() { _subiendoImagen = false; _error = 'Error al subir imagen'; });
    }
  }

  Future<void> _guardar() async {
    if (!_validar()) return;
    setState(() { _guardando = true; _error = null; });
    try {
      final body = {
        'nombre': _nombreCtrl.text.trim(),
        'descripcion': _descCtrl.text.trim(),
        'id_categoria': _idCategoria,
        'tamano': _tamano,
        'precio': double.tryParse(_precioCtrl.text) ?? 0,
        'permite_toppings': _permiteToppings ? 1 : 0,
        'max_toppings': _permiteToppings ? _maxToppings : 0,
        'permite_chocolate': _esBowl ? 0 : (_permiteChocolate ? 1 : 0),
        'permite_salsas': _esBowl ? false : _permiteSalsas,
        'es_bowl': _esBowl,
        if (_esEditar) 'estado': _estado,
        if (_imgUrl != null && _imgUrl!.isNotEmpty) 'img': _imgUrl,
      };
      if (_esEditar) {
        final id = widget.producto!['id_producto'] ?? widget.producto!['id'];
        await ApiService.put('/api/productos/$id', body);
      } else {
        await ApiService.post('/api/productos', body);
      }
      if (mounted) {
        Navigator.pop(context);
        widget.onGuardado();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_esEditar ? 'Producto actualizado' : 'Producto creado'),
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
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
            child: Row(children: [
              Expanded(child: Text(_esEditar ? 'Editar producto' : 'Nuevo producto',
                  style: GoogleFonts.nunito(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF1a1a1a)))),
              IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          const Divider(height: 16),
          // Form (scrollable)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Categoría
                Text('Categoría', style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF888888))),
                const SizedBox(height: 8),
                _DropdownField(
                  value: _idCategoria,
                  items: widget.categorias.map((c) => DropdownMenuItem(
                    value: c['id_categoria'] ?? c['id'],
                    child: Text(c['nombre'] ?? '', style: GoogleFonts.nunito(fontSize: 13)),
                  )).toList(),
                  onChanged: (v) => setState(() => _idCategoria = v),
                ),
                const SizedBox(height: 14),
                // Nombre
                _FormField(label: 'Nombre *', child: TextField(
                  controller: _nombreCtrl,
                  onChanged: (_) => setState(() => _errores.remove('nombre')),
                  style: GoogleFonts.nunito(fontSize: 14),
                  decoration: _inputDec('Nombre del producto', error: _errores['nombre']),
                )),
                if (_errores['nombre'] != null) _errMsg(_errores['nombre']!),
                const SizedBox(height: 14),
                // Descripción
                _FormField(label: 'Descripción', child: TextField(
                  controller: _descCtrl,
                  style: GoogleFonts.nunito(fontSize: 14),
                  decoration: _inputDec('Descripción'),
                )),
                const SizedBox(height: 14),
                // Tamaño
                Text('Tamaño', style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF888888))),
                const SizedBox(height: 8),
                _DropdownField(
                  value: _tamano,
                  items: ['', 'Pequeño (9oz)', 'Mediano (12oz)', 'Grande (16oz)'].map((t) => DropdownMenuItem(
                    value: t,
                    child: Text(t.isEmpty ? '(Sin tamaño)' : t, style: GoogleFonts.nunito(fontSize: 13)),
                  )).toList(),
                  onChanged: (v) => setState(() => _tamano = v ?? ''),
                ),
                const SizedBox(height: 14),
                // Precio
                Text('Precio', style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF888888))),
                const SizedBox(height: 8),
                TextField(
                  controller: _precioCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() => _errores.remove('precio')),
                  style: GoogleFonts.nunito(fontSize: 14),
                  decoration: _inputDec('0', prefix: '\$', error: _errores['precio']),
                ),
                if (_errores['precio'] != null) _errMsg(_errores['precio']!),
                const SizedBox(height: 14),
                // Toggles: toppings, chocolate, salsas
                _ToggleRow(
                  activo: _permiteToppings,
                  labelActivo: 'Permite toppings',
                  labelInactivo: 'Sin toppings',
                  onTap: () => setState(() => _permiteToppings = !_permiteToppings),
                ),
                if (_permiteToppings) ...[
                  const SizedBox(height: 12),
                  Text('¿Cuántos toppings van incluidos gratis?',
                      style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF555555))),
                  const SizedBox(height: 8),
                  Row(children: [1, 2, 3].map((n) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _maxToppings = n),
                      child: Container(
                        width: 42, height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _maxToppings == n ? const Color(0xFFFFF5F5) : Colors.white,
                          border: Border.all(
                            color: _maxToppings == n ? AppColors.primary : const Color(0xFFE5E7EB),
                            width: _maxToppings == n ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('$n', style: GoogleFonts.nunito(
                          fontSize: 16, fontWeight: FontWeight.w700,
                          color: _maxToppings == n ? AppColors.primary : const Color(0xFF555555),
                        )),
                      ),
                    ),
                  )).toList()),
                ],
                const SizedBox(height: 10),
                Opacity(
                  opacity: _esBowl ? 0.35 : 1,
                  child: IgnorePointer(
                    ignoring: _esBowl,
                    child: _ToggleRow(
                      activo: _permiteChocolate,
                      labelActivo: 'Con selección de chocolate',
                      labelInactivo: 'Sin elección de chocolate',
                      onTap: () => setState(() => _permiteChocolate = !_permiteChocolate),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Opacity(
                  opacity: _esBowl ? 0.35 : 1,
                  child: IgnorePointer(
                    ignoring: _esBowl,
                    child: _ToggleRow(
                      activo: _permiteSalsas,
                      labelActivo: 'Con salsas',
                      labelInactivo: 'Sin salsas',
                      onTap: () => setState(() => _permiteSalsas = !_permiteSalsas),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _ToggleRow(
                  activo: _esBowl,
                  labelActivo: '🥣 Bowl (elige cobertura)',
                  labelInactivo: 'Sin cobertura bowl',
                  onTap: () => setState(() {
                    _esBowl = !_esBowl;
                    if (_esBowl) { _permiteChocolate = false; _permiteSalsas = false; }
                  }),
                  activeTextColor: const Color(0xFFD97706),
                  toggleActiveColor: const Color(0xFFD97706),
                ),
                if (_esEditar) ...[
                  const SizedBox(height: 14),
                  Row(children: [
                    GestureDetector(onTap: () => setState(() => _estado = !_estado), child: _ToggleWidget(activo: _estado)),
                    const SizedBox(width: 10),
                    Text(
                      _estado ? 'Activo' : 'Inactivo',
                      style: GoogleFonts.nunito(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: _estado ? const Color(0xFF22c55e) : AppColors.primary,
                      ),
                    ),
                  ]),
                ],
                // Imagen
                const SizedBox(height: 14),
                Text('Imagen', style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF888888))),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _subiendoImagen ? null : _seleccionarImagen,
                  child: Container(
                    width: double.infinity,
                    height: 110,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FD),
                      border: Border.all(color: const Color(0xFFE0E0E0), width: 1.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _subiendoImagen
                        ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary)))
                        : (_imgUrl != null && _imgUrl!.isNotEmpty)
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(9),
                                child: CachedNetworkImage(
                                  imageUrl: _imgUrl!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  placeholder: (_, __) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                  errorWidget: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Color(0xFFBBBBBB), size: 32),
                                ),
                              )
                            : (_imgFile != null)
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(9),
                                    child: Image.file(_imgFile!, fit: BoxFit.cover, width: double.infinity),
                                  )
                                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                    const Icon(Icons.add_photo_alternate_outlined, color: Color(0xFFBBBBBB), size: 32),
                                    const SizedBox(height: 6),
                                    Text('Subir imagen', style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFF888888))),
                                  ]),
                  ),
                ),
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
          // Footer
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
                    : Text(_esEditar ? 'Guardar cambios' : 'Crear producto',
                        style: GoogleFonts.nunito(color: Colors.white, fontWeight: FontWeight.w700)),
              )),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _ProductoDetalleDialog extends StatelessWidget {
  final Map<String, dynamic> producto;
  final String catNombre;
  final void Function(Map<String, dynamic>)? onEditar;
  const _ProductoDetalleDialog({required this.producto, required this.catNombre, this.onEditar});

  @override
  Widget build(BuildContext context) {
    final activo = producto['estado'] == true || producto['estado'] == 1;
    final toppings = producto['permite_toppings'] == true || producto['permite_toppings'] == 1;
    final chocolate = producto['permite_chocolate'] == true || producto['permite_chocolate'] == 1;
    final salsas = producto['permite_salsas'] == true || producto['permite_salsas'] == 1;
    final esBowl = producto['es_bowl'] == true || producto['es_bowl'] == 1;
    final precio = (producto['precio'] is num) ? (producto['precio'] as num).toDouble() : 0.0;
    final imgUrl = producto['img']?.toString();
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
            child: Row(children: [
              Expanded(child: Text('Detalle del producto',
                  style: GoogleFonts.nunito(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF1a1a1a)))),
              IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          const Divider(height: 16),
          if (imgUrl != null && imgUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.zero),
              child: CachedNetworkImage(
                imageUrl: imgUrl,
                height: 140, width: double.infinity, fit: BoxFit.cover,
                placeholder: (_, __) => Container(height: 140, color: const Color(0xFFF5F5F5)),
                errorWidget: (_, __, ___) => Container(height: 0),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Column(children: [
              _DetalleRowFull(label: 'Nombre', value: producto['nombre'] ?? '-'),
              Row(children: [
                Expanded(child: _DetalleRow(label: 'Estado', value: activo ? '● Activo' : '● Inactivo',
                    valueColor: activo ? AppColors.success : AppColors.primary,
                    valueBg: activo ? const Color(0xFFF0FDF4) : const Color(0xFFFFF5F5))),
                const SizedBox(width: 12),
                Expanded(child: _DetalleRow(label: 'Categoría', value: catNombre)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _DetalleRow(label: 'Tamaño', value: tamanoLabel(producto['tamano']))),
                const SizedBox(width: 12),
                Expanded(child: _DetalleRow(label: 'Precio',
                    value: '\$${precio.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.')}',
                    valueBold: true)),
              ]),
              const SizedBox(height: 8),
              _DetalleRowFull(label: 'Descripción', value: (producto['descripcion'] ?? '').toString().isEmpty ? '—' : producto['descripcion'].toString()),
              Row(children: [
                Expanded(child: _DetalleRow(
                  label: 'Toppings',
                  value: toppings ? '✓ Sí (máx. ${producto['max_toppings'] ?? 0})' : '✗ No',
                  valueColor: toppings ? const Color(0xFF1a1a1a) : const Color(0xFF999999),
                  valueBg: const Color(0xFFF5F5F5),
                )),
                const SizedBox(width: 12),
                Expanded(child: _DetalleRow(
                  label: 'Chocolate',
                  value: chocolate ? '✓ Sí' : '✗ No',
                  valueColor: chocolate ? const Color(0xFF1a1a1a) : const Color(0xFF999999),
                  valueBg: const Color(0xFFF5F5F5),
                )),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _DetalleRow(
                  label: 'Salsas',
                  value: salsas ? '✓ Sí' : '✗ No',
                  valueColor: salsas ? const Color(0xFF1a1a1a) : const Color(0xFF999999),
                  valueBg: const Color(0xFFF5F5F5),
                )),
                const SizedBox(width: 12),
                Expanded(child: _DetalleRow(
                  label: 'Bowl',
                  value: esBowl ? '🥣 Sí' : '✗ No',
                  valueColor: esBowl ? const Color(0xFFD97706) : const Color(0xFF999999),
                  valueBg: esBowl ? const Color(0xFFFEF3C7) : const Color(0xFFF5F5F5),
                )),
              ]),
            ]),
          ),
          // Footer con Cerrar y Editar (igual que React)
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
            ),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Cerrar',
                      style: GoogleFonts.nunito(color: const Color(0xFF555555), fontSize: 13)),
                ),
              ),
              if (onEditar != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      onEditar!(producto);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    child: Text('Editar',
                        style: GoogleFonts.nunito(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
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
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.delete_outline, size: 48, color: AppColors.error),
          const SizedBox(height: 12),
          Text('¿Eliminar "$nombre"?',
              style: GoogleFonts.nunito(fontSize: 17, fontWeight: FontWeight.w800, color: const Color(0xFF1a1a1a)),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Esta acción no se puede deshacer.',
              style: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFF888888)), textAlign: TextAlign.center),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFE0E0E0)),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('Cancelar', style: GoogleFonts.nunito(color: const Color(0xFF666666), fontWeight: FontWeight.w600)),
            )),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              child: Text('Eliminar', style: GoogleFonts.nunito(color: Colors.white, fontWeight: FontWeight.w700)),
            )),
          ]),
        ]),
      ),
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _BadgeChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;
  const _BadgeChip({required this.label, required this.color, required this.bg});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4), border: Border.all(color: const Color(0xFFE0E0E0))),
    child: Text(label, style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
  );
}

class _ToggleWidget extends StatelessWidget {
  final bool activo;
  final Color activeColor;
  final Color inactiveColor;
  const _ToggleWidget({
    required this.activo,
    this.activeColor = const Color(0xFF22c55e),
    this.inactiveColor = const Color(0xFF9ca3af),
  });
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    width: 44, height: 24,
    decoration: BoxDecoration(
      color: activo ? activeColor : inactiveColor,
      borderRadius: BorderRadius.circular(12),
    ),
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

class _FormField extends StatelessWidget {
  final String label;
  final Widget child;
  const _FormField({required this.label, required this.child});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF555555))),
    const SizedBox(height: 6),
    child,
  ]);
}

class _DropdownField extends StatelessWidget {
  final dynamic value;
  final List<DropdownMenuItem> items;
  final ValueChanged onChanged;
  const _DropdownField({required this.value, required this.items, required this.onChanged});
  @override
  Widget build(BuildContext context) => DropdownButtonFormField(
    value: value,
    items: items,
    onChanged: onChanged,
    style: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFF1a1a1a)),
    decoration: InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      filled: true, fillColor: const Color(0xFFF7F8FD),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
    ),
  );
}

class _DetalleRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final Color? valueBg;
  final bool valueBold;
  const _DetalleRow({required this.label, required this.value, this.valueColor, this.valueBg, this.valueBold = false});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.nunito(fontSize: 11, color: const Color(0xFF888888), fontWeight: FontWeight.w600)),
      const SizedBox(height: 3),
      valueBg != null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: valueBg, borderRadius: BorderRadius.circular(20)),
              child: Text(value, style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: valueColor ?? const Color(0xFF1a1a1a))),
            )
          : Text(value, style: GoogleFonts.nunito(fontSize: 13, fontWeight: valueBold ? FontWeight.w700 : FontWeight.w600, color: valueColor ?? const Color(0xFF1a1a1a))),
    ]),
  );
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

String _normTamano(String t) {
  if (t == 'Pequeño') return 'Pequeño (9oz)';
  if (t == 'Mediano') return 'Mediano (12oz)';
  if (t == 'Grande')  return 'Grande (16oz)';
  return t;
}

// Igual que getTamanoLabel en Productos.jsx: normaliza valores legacy y
// muestra "(Sin tamaño)" cuando el producto no tiene tamaño asignado.
String tamanoLabel(dynamic raw) {
  final normalizado = _normTamano((raw ?? '').toString());
  return normalizado.isEmpty ? '(Sin tamaño)' : normalizado;
}

class _ToggleRow extends StatelessWidget {
  final bool activo;
  final String labelActivo;
  final String labelInactivo;
  final VoidCallback onTap;
  final Color activeTextColor;
  final Color toggleActiveColor;
  const _ToggleRow({
    required this.activo,
    required this.labelActivo,
    required this.labelInactivo,
    required this.onTap,
    this.activeTextColor = AppColors.primary,
    this.toggleActiveColor = AppColors.primary,
  });
  @override
  Widget build(BuildContext context) => Row(children: [
    GestureDetector(
      onTap: onTap,
      child: _ToggleWidget(
        activo: activo,
        activeColor: toggleActiveColor,
        inactiveColor: const Color(0xFFE5E7EB),
      ),
    ),
    const SizedBox(width: 10),
    Text(activo ? labelActivo : labelInactivo,
        style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600,
            color: activo ? activeTextColor : const Color(0xFF888888))),
  ]);
}

Widget _errMsg(String msg) => Padding(
  padding: const EdgeInsets.only(top: 4),
  child: Text(msg, style: GoogleFonts.nunito(fontSize: 11, color: AppColors.error, fontWeight: FontWeight.w600)),
);

InputDecoration _inputDec(String hint, {String? prefix, String? error}) => InputDecoration(
  hintText: hint,
  prefixText: prefix,
  prefixStyle: GoogleFonts.nunito(fontSize: 14, color: const Color(0xFF1a1a1a)),
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
          width: 32, height: 32,
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
              color: activo ? Colors.white : (enabled ? const Color(0xFF444444) : const Color(0xFFBBBBBB)),
            ),
          ),
        ),
      ),
    );
  }
}
