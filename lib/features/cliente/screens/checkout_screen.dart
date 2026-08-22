import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_config.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/services/api_service.dart';
import '../../../core/models/carrito_item.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/colombia_location_picker.dart';
import '../../../shared/widgets/double_back_to_exit.dart' show CheckoutBackController;
import '../providers/carrito_provider.dart';

// Pago mixto (igual React handleEfectivoMixto/handleTransferMixto): al
// escribir en un campo se recorta al rango [0,total] y el otro campo se
// autocompleta con el complemento, de forma que la suma siempre sea igual al
// total. Se aplica tanto al campo editado (para no dejar valores fuera de
// rango mientras se escribe) como al campo complementario.
void _aplicarMontoMixto({
  required String raw,
  required double total,
  required TextEditingController ctrlEditado,
  required TextEditingController ctrlComplemento,
  required void Function(double editado, double complemento) onCalculado,
}) {
  final editado = (double.tryParse(raw) ?? 0).clamp(0, total).toDouble();
  final complemento = (total - editado).clamp(0, total).toDouble();
  final editadoTexto = editado > 0 ? editado.round().toString() : '';
  if (ctrlEditado.text != editadoTexto) {
    ctrlEditado.value = TextEditingValue(
      text: editadoTexto,
      selection: TextSelection.collapsed(offset: editadoTexto.length),
    );
  }
  ctrlComplemento.text = complemento > 0 ? complemento.round().toString() : '';
  onCalculado(editado, complemento);
}

class CheckoutScreen extends StatefulWidget {
  final int initialPuntosUsados;
  const CheckoutScreen({super.key, this.initialPuntosUsados = 0});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  int _paso = 0;
  bool _enviando = false;
  String? _errorEnvio;

  // ── Paso 1: Datos de contacto ──────────────────────────────
  final _telefonoCtrl = TextEditingController();
  bool _guardandoTel  = false;
  String? _errorTelefono;
  final _form1Key = GlobalKey<FormState>();

  // ── Paso 2: Dirección ──────────────────────────────────────
  List<Map<String, dynamic>> _direccionesGuardadas = [];
  Map<String, dynamic>? _dirSeleccionada;
  bool _modoNueva = false;
  bool _cargandoDirs = false;
  String? _errorDireccion;
  // Estado de nueva dirección (idéntico a `nuevaDireccion` en React PasoDireccion)
  Map<String, dynamic> _nuevaDireccion = {};
  Map<String, String>  _errNuevaDireccion = {};

  // ── Paso 3: Método de pago ─────────────────────────────────
  String _metodoPago = 'efectivo';
  double? _montoEfectivo;
  double? _montoTransferencia;
  final _efectivoCtrl = TextEditingController();
  final _transferenciaCtrl = TextEditingController();
  // Comprobante de pago (transferencia / mixto)
  File? _comprobanteFile;
  String? _comprobanteUrl;
  bool _subiendoComprobante = false;
  String? _comprobanteError;

  // ── Puntos de fidelidad ────────────────────────────────────
  int _puntosUsados = 0;
  /// Cada punto equivale a $12.5 COP de descuento
  static const double _valorPorPunto = 12.5;

  // ── Costo domicilio ────────────────────────────────────
  static const double _costoDomicilioDefault = 5500.0;
  double _costoDomicilio = 5500.0;
  double _distanciaKm = 0;
  bool _calculandoCosto = false;

  // ── Observaciones ──────────────────────────────────────
  final _observacionesCtrl = TextEditingController();

  final _fmt = NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _puntosUsados = widget.initialPuntosUsados;
    // /checkout es una ruta plana (sin nada que popear -- se llega con
    // context.go(), no con push), así que el back del sistema no pasa por
    // PopScope/_handleBack acá abajo -- lo resuelve el dispatcher global en
    // main.dart, que no tiene forma de ver _paso. Este registro le da ese
    // puente mientras la pantalla esté montada.
    CheckoutBackController.registrar(_handleBack);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cargarPerfil();
    });
  }

  Future<void> _calcularCostoDomicilio(Map<String, dynamic> dir) async {
    // Igual que React: si la dirección tiene barrio del catálogo, su precio
    // real manda — nunca se debe depender de lat/lng (la mayoría de
    // direcciones ya no las tienen desde la migración a barrios).
    final barrioRel = dir['barrioRel'];
    final precioBarrio = barrioRel is Map ? barrioRel['precio_domicilio'] : null;
    final precio = precioBarrio ?? dir['costo_domicilio'];
    if (precio != null) {
      final costo = double.tryParse(precio.toString()) ?? _costoDomicilioDefault;
      setState(() { _costoDomicilio = costo; _distanciaKm = 0; });
      return;
    }

    final lat = dir['lat'];
    final lng = dir['lng'];
    if (lat == null || lng == null) {
      setState(() { _costoDomicilio = _costoDomicilioDefault; _distanciaKm = 0; });
      return;
    }
    setState(() => _calculandoCosto = true);
    try {
      final data = await ApiService.post('/api/domicilio/calcular', {
        'lat': lat,
        'lng': lng,
        'ciudad': dir['ciudad'] ?? '',
      });
      final costo = data is Map ? (data['data']?['costo_domicilio'] ?? data['costo_domicilio'] ?? _costoDomicilioDefault) : _costoDomicilioDefault;
      final dist = data is Map ? (data['data']?['distancia_km'] ?? data['distancia_km'] ?? 0) : 0;
      if (mounted) {
        setState(() {
          _costoDomicilio = (costo as num).toDouble();
          _distanciaKm = (dist as num).toDouble();
        });
      }
    } catch (_) {
      if (mounted) setState(() { _costoDomicilio = _costoDomicilioDefault; _distanciaKm = 0; });
    }
    if (mounted) setState(() => _calculandoCosto = false);
  }

  // ── Cloudinary upload ────────────────────────────────────────────────────────
  Future<void> _seleccionarYSubirComprobante() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (picked == null) return;

    final nombre = picked.name.toLowerCase();
    if (!nombre.endsWith('.jpg') && !nombre.endsWith('.jpeg') && !nombre.endsWith('.png')) {
      setState(() => _comprobanteError = 'Formato no permitido. Solo JPG o PNG');
      return;
    }
    if (await picked.length() > 5 * 1024 * 1024) {
      setState(() => _comprobanteError = 'El archivo supera el límite de 5 MB');
      return;
    }

    setState(() {
      _comprobanteFile = File(picked.path);
      _subiendoComprobante = true;
      _comprobanteError = null;
      _comprobanteUrl = null;
    });

    try {
      final uri = Uri.parse('https://api.cloudinary.com/v1_1/${AppConfig.cloudinaryCloudName}/image/upload');
      final req = http.MultipartRequest('POST', uri)
        ..fields['upload_preset'] = AppConfig.cloudinaryUploadPreset
        ..files.add(await http.MultipartFile.fromPath('file', picked.path));
      final response = await req.send();
      final body = await response.stream.bytesToString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        setState(() => _comprobanteUrl = json['secure_url']?.toString());
      } else {
        setState(() => _comprobanteError = json['error']?['message']?.toString() ?? 'Error al subir imagen');
      }
    } catch (e) {
      setState(() => _comprobanteError = 'Error al subir comprobante');
    }
    setState(() => _subiendoComprobante = false);
  }

  Future<void> _cargarPerfil() async {
    // Capturar referencias antes del gap asíncrono
    final authProvider = context.read<AuthProvider>();
    try {
      final data = await ApiService.get('/api/auth/perfil');
      final inner = data is Map && data['data'] is Map
          ? data['data'] as Map
          : data as Map;
      // Teléfono viene en cliente, no en usuario
      final tel = (inner['cliente'] as Map?)?['telefono']?.toString()
          ?? inner['telefono']?.toString()
          ?? '';
      if (mounted && tel.isNotEmpty) {
        _telefonoCtrl.text = tel;
      }
    } catch (_) {
      // best-effort — usar el del AuthProvider si falló
      final user = authProvider.user;
      if (mounted && user?.telefono != null && user!.telefono!.isNotEmpty) {
        _telefonoCtrl.text = user.telefono!;
      }
    }
  }

  @override
  void dispose() {
    CheckoutBackController.limpiar();
    _telefonoCtrl.dispose();
    _efectivoCtrl.dispose();
    _transferenciaCtrl.dispose();
    _observacionesCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarDirecciones() async {
    setState(() => _cargandoDirs = true);
    try {
      final data = await ApiService.get('/api/auth/mis-direcciones');
      List raw = data is List ? data : (data is Map && data['data'] is List ? data['data'] as List : []);
      final dirs = raw.where((d) => (d as Map)['estado'] != 0).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      setState(() {
        _direccionesGuardadas = dirs;
        _dirSeleccionada = null;
        _modoNueva = dirs.isEmpty;
      });
    } catch (_) {
      setState(() => _modoNueva = true);
    }
    setState(() => _cargandoDirs = false);
  }

  Future<void> _enviarPedido() async {
    // Guard explícito anti doble-tap (igual React: if (procesando) return;)
    if (_enviando) return;

    // Verificar comprobante obligatorio para transferencia/mixto
    if ((_metodoPago == 'transferencia' || _metodoPago == 'mixto') &&
        (_comprobanteUrl == null || _comprobanteUrl!.isEmpty)) {
      setState(() => _errorEnvio = 'Debes subir el comprobante de pago para continuar');
      return;
    }

    final carrito = context.read<CarritoProvider>();
    final descuentoSend = _puntosUsados * _valorPorPunto;
    final totalSend = (carrito.total - descuentoSend + _costoDomicilio).clamp(0.0, double.infinity);

    // pagoCompleto check para mixto (igual React: if (!pagoCompleto) setError)
    if (_metodoPago == 'mixto') {
      final ef = _montoEfectivo ?? 0;
      final tr = _montoTransferencia ?? 0;
      if ((ef + tr - totalSend).abs() >= 1) {
        setState(() => _errorEnvio = 'Falta ${_fmt.format(totalSend - ef - tr)} por cubrir');
        return;
      }
    }

    setState(() {
      _enviando = true;
      _errorEnvio = null;
    });

    // Montos según React handleConfirmar
    final int montoEf = _metodoPago == 'efectivo'
        ? totalSend.round()
        : (_metodoPago == 'mixto' ? (_montoEfectivo?.round() ?? 0) : 0);
    final int montoTr = _metodoPago == 'transferencia'
        ? totalSend.round()
        : (_metodoPago == 'mixto' ? (_montoTransferencia?.round() ?? 0) : 0);

    try {
      final items = carrito.items
          .map((item) => {
                'id_producto':  item.producto.id,
                'cantidad':     item.cantidad,
                'max_toppings': item.producto.maxToppings,
                'toppings': item.toppings.map((t) => {'id_topping': t.id, 'cantidad': 1}).toList(),
                'adiciones': item.adiciones.map((a) => {'id_adicion': a.id, 'cantidad': 1}).toList(),
                'salsas': item.salsas.map((s) => s['id'] ?? s['nombre']).toList(),
                'chocolate': item.tipoChocolate,
              })
          .toList();

      final body = <String, dynamic>{
        'costo_domicilio': _costoDomicilio.round(),
        'metodo_pago': _metodoPago,
        'monto_efectivo': montoEf,
        'monto_transferencia': montoTr,
        'puntos_a_usar': _puntosUsados,
        'items': items,
        if (_comprobanteUrl != null && _comprobanteUrl!.isNotEmpty)
          'comprobante_url': _comprobanteUrl,
        if (_observacionesCtrl.text.trim().isNotEmpty)
          'observaciones': _observacionesCtrl.text.trim(),
      };

      // Dirección: guardada o nueva
      if (!_modoNueva && _dirSeleccionada != null) {
        final idDir = _dirSeleccionada!['id_direccion'] ?? _dirSeleccionada!['id'];
        if (idDir != null) body['id_direccion'] = idDir;
      } else {
        String? sv(String? k) {
          final v = _nuevaDireccion[k]?.toString().trim() ?? '';
          return v.isNotEmpty ? v : null;
        }
        body['nueva_direccion'] = {
          'direccion_linea': _nuevaDireccion['direccion_linea'] ?? '',
          'barrio':          sv('barrio'),
          'ciudad':          sv('ciudad'),
          'departamento':    'Antioquia',
          'referencia':      sv('referencia'),
          'id_barrio':       _nuevaDireccion['id_barrio'],
        };
      }

      await ApiService.post('/api/ventas/mi-pedido', body);

      // Auto-guardar dirección nueva en perfil del cliente (igual React)
      if (_modoNueva && (_nuevaDireccion['direccion_linea'] ?? '').toString().isNotEmpty) {
        String? sv2(String? k) {
          final v = _nuevaDireccion[k]?.toString().trim() ?? '';
          return v.isNotEmpty ? v : null;
        }
        ApiService.post('/api/auth/mis-direcciones', {
          'direccion_linea': _nuevaDireccion['direccion_linea'],
          'barrio':          sv2('barrio'),
          'ciudad':          sv2('ciudad'),
          'departamento':    'Antioquia',
          'referencia':      sv2('referencia'),
          'id_barrio':       _nuevaDireccion['id_barrio'],
        }).catchError((_) {});
      }

      carrito.limpiar();

      if (mounted) {
        HapticFeedback.mediumImpact();
        context.go('/pedido-exitoso', extra: {
          'costoDomicilio': _costoDomicilio.round(),
          'distanciaKm': _distanciaKm,
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorEnvio = e.message);
    } catch (e) {
      if (mounted) setState(() => _errorEnvio = 'Error al enviar el pedido');
    }

    if (mounted) { setState(() => _enviando = false); }
  }

  void _handleBack() {
    if (_paso > 0) {
      setState(() => _paso--);
    } else {
      context.go('/catalogo');
    }
  }

  @override
  Widget build(BuildContext context) {
    final carrito = context.watch<CarritoProvider>();
    if (carrito.items.isEmpty && _paso == 0 && !_enviando) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => context.go('/catalogo'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🛒', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text('Tu carrito está vacío', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                const Text('Agrega productos antes de continuar.', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 24),
                AppButton(label: 'Ir al catálogo', onPressed: () => context.go('/catalogo')),
              ],
            ),
          ),
        ),
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Checkout'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: _handleBack,
        ),
      ),
      body: Column(
        children: [
          _buildIndicadorPasos(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSizes.screenPadding),
              child: [
                _buildPaso1(),
                _buildPaso2(),
                _buildPaso3(),
              ][_paso],
            ),
          ),
        ],
      ),
    ), // Scaffold
    ); // PopScope
  }

  Widget _buildIndicadorPasos() {
    const steps = ['Datos', 'Dirección', 'Pago'];
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.screenPadding,
        vertical: 12,
      ),
      child: Row(
        children: List.generate(steps.length, (i) {
          final activo = i == _paso;
          final completado = i < _paso;
          return Expanded(
            child: Row(
              children: [
                if (i > 0)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: completado ? AppColors.primary : AppColors.border,
                    ),
                  ),
                Column(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: activo || completado
                            ? AppColors.primary
                            : AppColors.surfaceVariant,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: completado
                            ? const Icon(Icons.check, color: Colors.white, size: 14)
                            : Text(
                                '${i + 1}',
                                style: TextStyle(
                                  color: activo ? Colors.white : AppColors.textHint,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      steps[i],
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: activo ? AppColors.primary : AppColors.textHint,
                      ),
                    ),
                  ],
                ),
                if (i < steps.length - 1) const Expanded(child: SizedBox()),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ── Paso 1: Datos de contacto ────────────────────────────────
  Widget _buildPaso1() {
    return Form(
      key: _form1Key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Datos de entrega',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('Confirma o actualiza tus datos de contacto',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 24),

          // User info card
          Consumer<AuthProvider>(
            builder: (context, auth, _) {
              final user = auth.user;
              if (user == null) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                      child: const Icon(Icons.person, color: AppColors.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.nombre, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        if (user.email.isNotEmpty)
                          Text(user.email, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),

          // Teléfono — se guarda en perfil al continuar
          AppTextField(
            controller: _telefonoCtrl,
            label: 'Teléfono de contacto',
            hint: '300 123 4567',
            keyboardType: TextInputType.phone,
            prefixIcon: Icons.phone_outlined,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Requerido';
              final digits = v.replaceAll(RegExp(r'\D'), '');
              if (!RegExp(r'^3[0-9]{9}$').hasMatch(digits)) return 'Número colombiano inválido (ej: 3001234567)';
              return null;
            },
          ),
          if (_errorTelefono != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              ),
              child: Text(_errorTelefono!, style: const TextStyle(color: AppColors.error)),
            ),
          ],
          const SizedBox(height: 28),

          AppButton(
            label: 'Continuar',
            isLoading: _guardandoTel,
            onPressed: () async {
              if (!_form1Key.currentState!.validate()) return;
              setState(() { _guardandoTel = true; _errorTelefono = null; });
              try {
                // Guardar teléfono en perfil — igual que React: si el backend
                // rechaza (ej. teléfono duplicado), no se avanza de paso.
                await ApiService.patch('/api/auth/perfil', {
                  'telefono': _telefonoCtrl.text.trim(),
                });
              } on ApiException catch (e) {
                if (mounted) setState(() { _guardandoTel = false; _errorTelefono = e.message; });
                return;
              } catch (_) {
                if (mounted) setState(() { _guardandoTel = false; _errorTelefono = 'Error al guardar el teléfono. Inténtalo de nuevo.'; });
                return;
              }
              await _cargarDirecciones();
              if (mounted) setState(() { _guardandoTel = false; _paso = 1; });
            },
          ),
        ],
      ),
    );
  }

  // ── Paso 2: Dirección de entrega ─────────────────────────────
  Widget _buildPaso2() {
    if (_cargandoDirs) {
      return Center(child: Padding(padding: const EdgeInsets.all(48), child: CircularProgressIndicator(color: AppColors.primary)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Dirección de entrega', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('¿A dónde enviamos tu pedido?',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 20),

        // Tabs (guardada / nueva) — igual que React
        if (_direccionesGuardadas.isNotEmpty) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
            child: Row(children: [
              Expanded(child: GestureDetector(
                onTap: () => setState(() { _modoNueva = false; _dirSeleccionada = null; }),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: !_modoNueva ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                  ),
                  child: Center(child: Text('Mis direcciones',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                          color: !_modoNueva ? Colors.white : AppColors.textSecondary))),
                ),
              )),
              Expanded(child: GestureDetector(
                onTap: () => setState(() { _modoNueva = true; _dirSeleccionada = null; }),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _modoNueva ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                  ),
                  child: Center(child: Text('Nueva dirección',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                          color: _modoNueva ? Colors.white : AppColors.textSecondary))),
                ),
              )),
            ]),
          ),
        ],

        // Lista de direcciones guardadas
        if (!_modoNueva && _direccionesGuardadas.isNotEmpty) ...[
          ..._direccionesGuardadas.map((dir) {
            final sel = _dirSeleccionada != null &&
                (_dirSeleccionada!['id_direccion'] ?? _dirSeleccionada!['id']) ==
                    (dir['id_direccion'] ?? dir['id']);
            return GestureDetector(
              onTap: () {
                setState(() { _dirSeleccionada = dir; _errorDireccion = null; });
                _calcularCostoDomicilio(dir);
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: sel ? AppColors.primary.withValues(alpha: 0.05) : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                  border: Border.all(color: sel ? AppColors.primary : AppColors.border, width: sel ? 1.5 : 1),
                ),
                child: Row(children: [
                  Icon(Icons.location_on_outlined, color: sel ? AppColors.primary : AppColors.textSecondary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dir['direccion_linea']?.toString() ?? dir['direccion']?.toString() ?? '',
                          style: TextStyle(fontWeight: FontWeight.w600,
                              color: sel ? AppColors.primary : AppColors.textPrimary)),
                      if ([dir['barrio'], dir['ciudad']].any((v) => v != null && v.toString().isNotEmpty))
                        Text([dir['barrio'], dir['ciudad']].where((v) => v != null && v.toString().isNotEmpty).join(', '),
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  )),
                  if (sel) const Icon(Icons.check_circle, color: AppColors.primary, size: 20),
                ]),
              ),
            );
          }),

          // Badge costo domicilio (igual React)
          if (_dirSeleccionada != null) ...[
            const SizedBox(height: 10),
            if (_calculandoCosto)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: const Color(0xFFEFF6FF), border: Border.all(color: const Color(0xFFBFDBFE)), borderRadius: BorderRadius.circular(8)),
                child: const Row(children: [
                  SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                  SizedBox(width: 8),
                  Text('⏳ Calculando costo de domicilio...', style: TextStyle(fontSize: 13, color: Color(0xFF1E40AF), fontWeight: FontWeight.w600)),
                ]),
              )
            else if (_dirSeleccionada!['lat'] == null &&
                (_dirSeleccionada!['barrioRel'] is! Map || (_dirSeleccionada!['barrioRel'] as Map)['precio_domicilio'] == null) &&
                _dirSeleccionada!['costo_domicilio'] == null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: const Color(0xFFFEF3C7), border: Border.all(color: const Color(0xFFFDE68A)), borderRadius: BorderRadius.circular(8)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFF92400E)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    'Esta dirección no tiene ubicación guardada. El costo base es \$${_fmt.format(_costoDomicilioDefault)}. Para un cálculo exacto usa "Nueva dirección".',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF92400E)))),
                ]),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: const Color(0xFFF0FDF4), border: Border.all(color: const Color(0xFFBBF7D0)), borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Row(children: [
                    Icon(Icons.delivery_dining_rounded, size: 14, color: Color(0xFF166534)),
                    SizedBox(width: 6),
                    Text('Costo de domicilio estimado', style: TextStyle(fontSize: 13, color: Color(0xFF166534), fontWeight: FontWeight.w700)),
                  ]),
                  Text(_fmt.format(_costoDomicilio), style: const TextStyle(fontSize: 16, color: Color(0xFF166534), fontWeight: FontWeight.w800)),
                ]),
              ),
          ],
        ],

        // Formulario nueva dirección — usa FormDireccion idéntico a React
        if (_modoNueva) ...[
          FormDireccion(
            value: _nuevaDireccion,
            onChange: (field, value) {
              setState(() {
                _nuevaDireccion = {..._nuevaDireccion, field: value};
                _errNuevaDireccion.remove(field);
              });
              // El costo ya viene directo del barrio elegido (igual que React
              // FormDireccion.handleBarrio) — no hace falta ningún cálculo async.
              if (field == 'costo_domicilio') {
                setState(() => _costoDomicilio = (value as num?)?.toDouble() ?? _costoDomicilioDefault);
              }
            },
            errors: _errNuevaDireccion,
            isClient: true,
          ),
        ],

        const SizedBox(height: 28),
        if (_errorDireccion != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(AppSizes.sm),
            decoration: BoxDecoration(color: AppColors.errorLight, borderRadius: BorderRadius.circular(AppSizes.radiusMd)),
            child: Row(children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 16),
              const SizedBox(width: 6),
              Text(_errorDireccion!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
            ]),
          ),

        // Botones: Atrás + Continuar (igual React)
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => setState(() => _paso = 0),
              child: const Text('← Atrás'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: AppButton(
              label: _calculandoCosto ? 'Calculando...' : 'Continuar',
              isLoading: _calculandoCosto,
              onPressed: () {
                if (_modoNueva) {
                  // Validación idéntica a React (sin lat/lng por falta de mapa)
                  final errs = <String, String>{};
                  if ((_nuevaDireccion['tipo_via']?.toString() ?? '').isEmpty)        errs['tipo_via']    = 'Selecciona el tipo de vía';
                  if ((_nuevaDireccion['numero']?.toString().trim() ?? '').isEmpty)   errs['numero']      = 'Ingresa el número de la vía';
                  if ((_nuevaDireccion['numeral']?.toString().trim() ?? '').isEmpty)  errs['numeral']     = 'Ingresa el numeral';
                  if ((_nuevaDireccion['complemento']?.toString().trim() ?? '').isEmpty) errs['complemento'] = 'Ingresa el complemento';
                  if ((_nuevaDireccion['barrio']?.toString().trim() ?? '').isEmpty)   errs['barrio']      = 'Ingresa el barrio';
                  if ((_nuevaDireccion['ciudad']?.toString().trim() ?? '').isEmpty)   errs['ciudad']      = 'Selecciona el municipio';
                  if (errs.isNotEmpty) { setState(() => _errNuevaDireccion = errs); return; }
                } else if (_dirSeleccionada == null) {
                  setState(() => _errorDireccion = 'Selecciona una dirección');
                  return;
                }
                setState(() { _paso = 2; _errorDireccion = null; _errNuevaDireccion = {}; });
              },
            ),
          ),
        ]),
      ],
    );
  }

  // ── Paso 3: Método de pago ───────────────────────────────────
  Widget _buildPaso3() {
    final carrito = context.watch<CarritoProvider>();
    final descuentoPuntos = _puntosUsados * _valorPorPunto;
    final totalConDescuento = (carrito.total - descuentoPuntos + _costoDomicilio).clamp(0.0, double.infinity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Método de pago', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('¿Cómo vas a pagar tu pedido?',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 20),

        // 1. Resumen del pedido (PRIMERO — igual React PasoPago)
        _buildResumenPedido(carrito.items, carrito.total, descuentoPuntos: descuentoPuntos),
        const SizedBox(height: 20),

        // 3. Opciones de pago en 2 filas
        _buildOpcionesPago(),

        // 4. Info bancaria para transferencia/mixto
        if (_metodoPago == 'transferencia' || _metodoPago == 'mixto') ...[
          const SizedBox(height: 16),
          const Text('Datos para transferencia',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.5)),
          const SizedBox(height: 10),
          _buildBankingInfo(),
        ],

        // 5. Monto pre-llenado efectivo (readonly, igual React)
        if (_metodoPago == 'efectivo') ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Expanded(child: Text('Monto en efectivo (total pre-llenado)',
                    style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 13))),
                const SizedBox(width: 12),
                Text(_fmt.format(totalConDescuento), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ],
            ),
          ),
        ],

        // 6. Transferencia: monto readonly + comprobante
        if (_metodoPago == 'transferencia') ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Expanded(child: Text('Monto por transferencia (total pre-llenado)',
                    style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 13))),
                const SizedBox(width: 12),
                Text(_fmt.format(totalConDescuento), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildComprobanteSection(),
        ],

        // 7. Mixto: dos campos editables con auto-fill cruzado + comprobante
        if (_metodoPago == 'mixto') ...[
          ..._buildCamposMixto(totalConDescuento),
          const SizedBox(height: 12),
          _buildComprobanteSection(),
        ],

        // 8. Observaciones
        const SizedBox(height: 16),
        AppTextField(
          controller: _observacionesCtrl,
          label: 'Observaciones (opcional)',
          hint: 'Ej: devuelta de \$50.000 (opcional)',
          prefixIcon: Icons.notes_outlined,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
        ),

        // 9. Error
        if (_errorEnvio != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.errorLight,
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
            child: Text(_errorEnvio!, style: const TextStyle(color: AppColors.error)),
          ),
        ],

        // 10. Botones: Atrás + Confirmar (igual React)
        const SizedBox(height: 28),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _enviando ? null : () => setState(() { _paso = 1; _errorEnvio = null; }),
              child: const Text('← Atrás'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: AppButton(
              label: _enviando ? 'Enviando pedido...' : 'Confirmar pedido',
              isLoading: _enviando,
              onPressed: _enviarPedido,
            ),
          ),
        ]),
        const SizedBox(height: 32),
      ],
    );
  }

  // 2 filas: [Efectivo | Transferencia] / [Ef. + Transfer. full width]
  Widget _buildOpcionesPago() {
    return Column(children: [
      Row(children: [
        Expanded(child: _pagoCard(
          value: 'efectivo',
          logo: const Icon(Icons.payments_outlined, size: 24, color: Color(0xFF16A34A)),
          label: 'Efectivo',
        )),
        const SizedBox(width: 8),
        Expanded(child: _pagoCard(
          value: 'transferencia',
          logo: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CachedNetworkImage(
                imageUrl: 'https://res.cloudinary.com/diqeuyoqo/image/upload/v1779736112/bancolombia_wiytke.png',
                width: 22, height: 22, fit: BoxFit.contain,
                placeholder: (_, __) => Container(width: 22, height: 22, decoration: const BoxDecoration(color: Color(0xFFFFCC00), shape: BoxShape.circle), alignment: Alignment.center, child: const Text('B', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFF1A3C5E)))),
                errorWidget: (_, __, ___) => Container(width: 22, height: 22, decoration: const BoxDecoration(color: Color(0xFFFFCC00), shape: BoxShape.circle), alignment: Alignment.center, child: const Text('B', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFF1A3C5E)))),
              ),
              const SizedBox(width: 4),
              CachedNetworkImage(
                imageUrl: 'https://res.cloudinary.com/diqeuyoqo/image/upload/v1779736049/nequi_pfgazy.png',
                width: 18, height: 18, fit: BoxFit.contain,
                placeholder: (_, __) => Container(width: 18, height: 18, decoration: const BoxDecoration(color: Color(0xFF3D1D89), shape: BoxShape.circle), alignment: Alignment.center, child: const Text('N', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white))),
                errorWidget: (_, __, ___) => Container(width: 18, height: 18, decoration: const BoxDecoration(color: Color(0xFF3D1D89), shape: BoxShape.circle), alignment: Alignment.center, child: const Text('N', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white))),
              ),
            ],
          ),
          label: 'Transferencia',
        )),
      ]),
      const SizedBox(height: 8),
      _pagoCard(
        value: 'mixto',
        logo: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.payments_outlined, size: 18, color: Color(0xFF16A34A)),
            const Text(' + ', style: TextStyle(fontSize: 9, color: Color(0xFFCCCCCC))),
            CachedNetworkImage(
              imageUrl: 'https://res.cloudinary.com/diqeuyoqo/image/upload/v1779736112/bancolombia_wiytke.png',
              width: 18, height: 18, fit: BoxFit.contain,
              placeholder: (_, __) => Container(width: 18, height: 18, decoration: const BoxDecoration(color: Color(0xFFFFCC00), shape: BoxShape.circle), alignment: Alignment.center, child: const Text('B', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Color(0xFF1A3C5E)))),
              errorWidget: (_, __, ___) => Container(width: 18, height: 18, decoration: const BoxDecoration(color: Color(0xFFFFCC00), shape: BoxShape.circle), alignment: Alignment.center, child: const Text('B', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Color(0xFF1A3C5E)))),
            ),
          ],
        ),
        label: 'Ef. + Transfer.',
      ),
    ]);
  }

  Widget _pagoCard({required String value, required Widget logo, required String label}) {
    final sel = _metodoPago == value;
    return GestureDetector(
        onTap: () => setState(() {
          _metodoPago = value;
          // cambiarMetodo: mixto limpia montos (igual React)
          if (value == 'mixto') {
            _montoEfectivo = null;
            _montoTransferencia = null;
            _efectivoCtrl.clear();
            _transferenciaCtrl.clear();
          }
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          decoration: BoxDecoration(
            color: sel ? AppColors.primary.withValues(alpha: 0.05) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: sel ? AppColors.primary : const Color(0xFFE5E7EB),
              width: sel ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              logo,
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: sel ? AppColors.primary : const Color(0xFF555555),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
    );
  }

  // Grid 1fr 1fr con auto-fill cruzado — igual React handleEfectivoMixto / handleTransferMixto
  List<Widget> _buildCamposMixto(double total) {
    const fieldDec = InputDecoration(
      prefixText: '\$ ',
      hintText: '0',
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: Color(0xFFE5E7EB))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: Color(0xFFE5E7EB))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
      filled: true,
      fillColor: Colors.white,
    );
    return [
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Efectivo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF555555))),
                const SizedBox(height: 4),
                TextField(
                  controller: _efectivoCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 13),
                  decoration: fieldDec,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (v) => _aplicarMontoMixto(
                    raw: v,
                    total: total,
                    ctrlEditado: _efectivoCtrl,
                    ctrlComplemento: _transferenciaCtrl,
                    onCalculado: (e, tr) => setState(() {
                      _montoEfectivo = e;
                      _montoTransferencia = tr;
                    }),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Transferencia', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF555555))),
                const SizedBox(height: 4),
                TextField(
                  controller: _transferenciaCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 13),
                  decoration: fieldDec,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (v) => _aplicarMontoMixto(
                    raw: v,
                    total: total,
                    ctrlEditado: _transferenciaCtrl,
                    ctrlComplemento: _efectivoCtrl,
                    onCalculado: (tr, e) => setState(() {
                      _montoTransferencia = tr;
                      _montoEfectivo = e;
                    }),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Builder(builder: (context) {
        final ef = _montoEfectivo ?? 0;
        final tr = _montoTransferencia ?? 0;
        final pagado = ef + tr;
        final pagoCompleto = (pagado - total).abs() < 1;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: pagoCompleto ? const Color(0xFFF0FDF4) : AppColors.surface,
            border: Border.all(color: pagoCompleto ? const Color(0xFFBBF7D0) : AppColors.border),
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total cubierto', style: TextStyle(fontSize: 13)),
                  Text(
                    '${_fmt.format(pagado)} / ${_fmt.format(total)}',
                    style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800,
                      color: pagoCompleto ? const Color(0xFF16A34A) : AppColors.primary,
                    ),
                  ),
                ],
              ),
              if (!pagoCompleto && pagado > 0) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Falta', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    Text(_fmt.format(total - pagado),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  ],
                ),
              ],
            ],
          ),
        );
      }),
    ];
  }

  Widget _buildBankingInfo() {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // QR Card
            Expanded(
              child: GestureDetector(
                onTap: () => _showQRLightbox(),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          'https://res.cloudinary.com/dnoxlv5kn/image/upload/v1778551977/Captura_de_pantalla_2026-05-11_210420_xc3wav.png',
                          height: 100,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text('QR Bancolombia', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      const Text('Toca para ampliar', style: TextStyle(fontSize: 10, color: AppColors.textHint)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Bancolombia + Nequi stacked
            Expanded(
              child: Column(
                children: [
                  // Bancolombia
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          CachedNetworkImage(
                            imageUrl: 'https://res.cloudinary.com/diqeuyoqo/image/upload/v1779736112/bancolombia_wiytke.png',
                            width: 32, height: 32, fit: BoxFit.contain,
                            placeholder: (_, __) => Container(width: 32, height: 32, decoration: const BoxDecoration(color: Color(0xFFFFCC00), shape: BoxShape.circle), alignment: Alignment.center, child: const Text('B', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF1A3C5E)))),
                            errorWidget: (_, __, ___) => Container(width: 32, height: 32, decoration: const BoxDecoration(color: Color(0xFFFFCC00), shape: BoxShape.circle), alignment: Alignment.center, child: const Text('B', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF1A3C5E)))),
                          ),
                          const SizedBox(width: 8),
                          const Text('Bancolombia', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                        ]),
                        const SizedBox(height: 8),
                        const Text('Cuenta Ahorros', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        const Text('00635734892', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        const Text('Gilberto Montoya', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () => _copiar('00635734892', 'Número copiado'),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: const Center(child: Text('Copiar número', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Nequi
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        CachedNetworkImage(
                          imageUrl: 'https://res.cloudinary.com/diqeuyoqo/image/upload/v1779736049/nequi_pfgazy.png',
                          width: 44, height: 44, fit: BoxFit.contain,
                          placeholder: (_, __) => Container(width: 44, height: 44, decoration: const BoxDecoration(color: Color(0xFF3D1D89), shape: BoxShape.circle), alignment: Alignment.center, child: const Text('N', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white))),
                          errorWidget: (_, __, ___) => Container(width: 44, height: 44, decoration: const BoxDecoration(color: Color(0xFF3D1D89), shape: BoxShape.circle), alignment: Alignment.center, child: const Text('N', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white))),
                        ),
                        const SizedBox(height: 6),
                        const Text('009181338', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
                        const Text('Llave Nequi', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () => _copiar('009181338', 'Llave copiada'),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: const Center(child: Text('Copiar llave', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _copiar(String texto, String mensaje) {
    Clipboard.setData(ClipboardData(text: texto));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(mensaje),
      duration: const Duration(seconds: 2),
    ));
  }

  void _showQRLightbox() {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: GestureDetector(
              onTap: () {},
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      'https://res.cloudinary.com/dnoxlv5kn/image/upload/v1778551977/Captura_de_pantalla_2026-05-11_210420_xc3wav.png',
                      width: MediaQuery.of(context).size.width * 0.85,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Toca fuera para cerrar', style: TextStyle(color: Colors.white, fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildComprobanteSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Comprobante de pago *',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        if (_comprobanteUrl != null) ...[
          // Comprobante subido exitosamente
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.successLight,
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: AppColors.success, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Comprobante subido correctamente',
                    style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                // Preview imagen
                if (_comprobanteFile != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(_comprobanteFile!, width: 44, height: 44, fit: BoxFit.cover),
                  ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _seleccionarYSubirComprobante,
                  child: const Text('Cambiar', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ] else ...[
          // Botón para subir comprobante
          GestureDetector(
            onTap: _subiendoComprobante ? null : _seleccionarYSubirComprobante,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                border: Border.all(
                  color: _comprobanteError != null ? AppColors.error : AppColors.border,
                  style: BorderStyle.solid,
                ),
              ),
              child: _subiendoComprobante
                  ? Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)))
                  : Column(
                      children: [
                        Icon(Icons.upload_file_rounded, color: AppColors.primary, size: 28),
                        const SizedBox(height: 6),
                        const Text(
                          'Subir comprobante de pago',
                          style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'JPG, PNG — máx 5 MB',
                          style: TextStyle(fontSize: 11, color: AppColors.textHint),
                        ),
                      ],
                    ),
            ),
          ),
          if (_comprobanteError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_comprobanteError!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ),
        ],
      ],
    );
  }

  Widget _buildResumenPedido(List<CarritoItem> items, double total, {double descuentoPuntos = 0}) {
    final totalFinal = (total - descuentoPuntos).clamp(0.0, double.infinity);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Resumen del pedido',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          const Divider(height: 1),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('${item.cantidad}x ${item.producto.nombre}',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                              if (item.tipoChocolate != null) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: item.tipoChocolate == 'Negro' ? const Color(0xFF1E3A5F) : const Color(0xFFF0F0F0),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    'Chocolate ${item.tipoChocolate}',
                                    style: TextStyle(
                                      fontSize: 10, fontWeight: FontWeight.w600,
                                      color: item.tipoChocolate == 'Negro' ? Colors.white : const Color(0xFF555555),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (item.producto.esBowl && item.salsas.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                border: Border.all(color: const Color(0xFFD97706)),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Cobertura: ${(item.salsas.first['nombre'] as String? ?? '').replaceAll('_', ' ')}',
                                style: const TextStyle(fontSize: 10, color: Color(0xFF92400E), fontWeight: FontWeight.w700),
                              ),
                            ),
                          ] else if (item.salsas.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Wrap(
                              spacing: 3, runSpacing: 3,
                              children: item.salsas.asMap().entries.map((e) {
                                final nombre = (e.value['nombre'] as String? ?? e.value['id']?.toString() ?? '').replaceAll('_', ' ');
                                final isExtra = e.key >= 2;
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF7ED),
                                    border: Border.all(color: const Color(0xFFEA580C)),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${nombre.substring(0, 1).toUpperCase()}${nombre.substring(1)}${isExtra ? ' +\$5k' : ''}',
                                    style: const TextStyle(fontSize: 10, color: Color(0xFFEA580C), fontWeight: FontWeight.w600),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                          if (item.toppings.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Wrap(
                              spacing: 3, runSpacing: 3,
                              children: item.toppings.map((t) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A1A1A),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(t.nombre,
                                    style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
                              )).toList(),
                            ),
                          ],
                          if (item.adiciones.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Wrap(
                              spacing: 3, runSpacing: 3,
                              children: item.adiciones.map((a) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFFBEB),
                                  border: Border.all(color: const Color(0xFFD97706)),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text('+${a.nombre}',
                                    style: const TextStyle(fontSize: 10, color: Color(0xFFD97706), fontWeight: FontWeight.w600)),
                              )).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _fmt.format(item.subtotal),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ],
                ),
              )),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Subtotal', style: Theme.of(context).textTheme.bodyMedium),
              Text(_fmt.format(total), style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
          if (descuentoPuntos > 0) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  const Icon(Icons.stars_rounded, size: 14, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text('Descuento puntos ($_puntosUsados pts)',
                      style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
                ]),
                Text('- ${_fmt.format(descuentoPuntos)}',
                    style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w700)),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(children: [
                Icon(Icons.delivery_dining_rounded, size: 14, color: AppColors.textSecondary),
                SizedBox(width: 4),
                Text('Domicilio', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ]),
              Text(_fmt.format(_costoDomicilio), style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ],
          ),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total',
                  style: Theme.of(context).textTheme.titleMedium),
              Text(
                _fmt.format(totalFinal + _costoDomicilio),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: AppColors.primary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
