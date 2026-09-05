import 'dart:convert';

/// Una línea del pedido tal como llega de la API en el detalle (nombres ya resueltos)
class LineaDetalle {
  final int idProducto;
  final String nombreProducto;
  final int cantidad;
  final double precioUnitario;
  final List<String> toppings;
  final List<String> adiciones;
  final List<String> salsas;    // salsa names (o cobertura de bowl, ver esBowl)
  final String? chocolate;       // 'Negro' or 'Blanco' or null
  final bool esBowl;             // true si el producto es bowl (entonces 'salsas' es realmente la cobertura)
  final List<Map<String, dynamic>> rawToppings;  // [{id_topping, cantidad}] para edición
  final List<Map<String, dynamic>> rawAdiciones; // [{id_adicion, cantidad}] para edición
  final int maxToppings;
  final double costoAdiciones; // suma de (precio × cantidad_adicion) por CADA unidad del producto — falta multiplicar por `cantidad` (ver subtotal)

  const LineaDetalle({
    required this.idProducto,
    required this.nombreProducto,
    required this.cantidad,
    required this.precioUnitario,
    required this.toppings,
    required this.adiciones,
    this.salsas = const [],
    this.chocolate,
    this.esBowl = false,
    this.rawToppings = const [],
    this.rawAdiciones = const [],
    this.maxToppings = 0,
    this.costoAdiciones = 0,
  });

  factory LineaDetalle.fromJson(Map<String, dynamic> json) {
    List<String> parseStringList(dynamic raw) {
      if (raw == null) return [];
      if (raw is List) {
        return raw.map((e) {
          if (e is String) return e;
          if (e is Map) return (e['nombre'] ?? '').toString();
          return e.toString();
        }).toList();
      }
      return [];
    }

    // En detalleVentas: producto es {nombre_producto} o {producto:{nombre}}
    String nombreProducto = '';
    final prodRaw = json['producto'];
    if (prodRaw is Map) {
      nombreProducto = prodRaw['nombre']?.toString() ?? '';
    }
    if (nombreProducto.isEmpty) {
      nombreProducto = json['nombre_producto']?.toString() ?? json['nombre']?.toString() ?? '';
    }

    // Toppings en detalleVentas: detalleToppings: [{topping:{nombre}, cantidad:n}]
    // Like React: {t.nombre}{t.cantidad > 1 ? ` ×${t.cantidad}` : ''}
    List<String> toppings = parseStringList(json['toppings']);
    if (toppings.isEmpty) {
      final dt = json['detalleToppings'];
      if (dt is List) {
        toppings = dt.map<String>((e) {
          if (e is Map) {
            final t = e['topping'];
            final nombre = ((t is Map ? t['nombre'] : e['nombre']) ?? '').toString();
            final cantidad = (e['cantidad'] as num?)?.toInt() ?? 1;
            return cantidad > 1 ? '$nombre ×$cantidad' : nombre;
          }
          return e.toString();
        }).where((s) => s.isNotEmpty).toList();
      }
    }

    // Adiciones en detalleVentas: detalleAdiciones: [{adicion:{nombre,precio}, precio_unitario, cantidad}]
    // Like React: +{a.nombre}{a.cantidad > 1 ? ` ×n` : ''}{a.precio > 0 ? ` $price` : ''}
    List<String> adiciones = parseStringList(json['adiciones']);
    if (adiciones.isEmpty) {
      final da = json['detalleAdiciones'];
      if (da is List) {
        adiciones = da.map<String>((e) {
          if (e is Map) {
            final a = e['adicion'];
            final nombre = ((a is Map ? a['nombre'] : e['nombre']) ?? '').toString();
            final cantidad = (e['cantidad'] as num?)?.toInt() ?? 1;
            final precio = double.tryParse(
              (e['precio_unitario'] ?? (a is Map ? a['precio'] : null) ?? 0).toString(),
            ) ?? 0.0;
            String label = nombre;
            if (cantidad > 1) label += ' ×$cantidad';
            if (precio > 0) {
              final total = (precio * cantidad).round();
              label += ' \$${total.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.')}';
            }
            return label;
          }
          return e.toString();
        }).where((s) => s.isNotEmpty).toList();
      }
    }

    // Costo total de adiciones = suma(precio_unitario × cantidad) de detalleAdiciones
    double costoAdiciones = 0;
    final daForCost = json['detalleAdiciones'];
    if (daForCost is List) {
      for (final e in daForCost) {
        if (e is Map) {
          final a = e['adicion'];
          final precio = double.tryParse(
            (e['precio_unitario'] ?? (a is Map ? a['precio'] : null) ?? 0).toString(),
          ) ?? 0.0;
          final cant = (e['cantidad'] as num?)?.toInt() ?? 1;
          costoAdiciones += precio * cant;
        }
      }
    }

    // Salsas: json['salsas'] can be a JSON string or List
    List<String> salsas = [];
    final salsasRaw = json['salsas'];
    if (salsasRaw != null) {
      try {
        List parsed = salsasRaw is String ? (jsonDecode(salsasRaw) as List? ?? []) : (salsasRaw is List ? salsasRaw : []);
        salsas = parsed.map<String>((s) {
          final raw = (s is Map ? (s['nombre'] ?? s['id'] ?? '') : s).toString().replaceAll('_', ' ').trim();
          return raw.split(' ').map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
        }).where((s) => s.isNotEmpty).toList();
      } catch (_) {}
    }
    String? chocolate = json['chocolate']?.toString();

    // ── es_bowl: viene del producto anidado (detalleVentas.producto.es_bowl) ──
    bool esBowl = false;
    int maxToppings = 0;
    if (prodRaw is Map) {
      esBowl = prodRaw['es_bowl'] == true || prodRaw['es_bowl'] == 1;
      maxToppings = int.tryParse((prodRaw['max_toppings'] ?? 0).toString()) ?? 0;
    }

    // ── Raw IDs para reconstruir items al editar la venta ──
    List<Map<String, dynamic>> rawToppings = [];
    final dt = json['detalleToppings'];
    if (dt is List) {
      rawToppings = dt.map<Map<String, dynamic>>((e) {
        if (e is Map && e['id_topping'] != null) {
          return {'id_topping': e['id_topping'], 'cantidad': (e['cantidad'] as num?)?.toInt() ?? 1};
        }
        return {};
      }).where((m) => m.isNotEmpty).toList();
    }

    List<Map<String, dynamic>> rawAdiciones = [];
    final da = json['detalleAdiciones'];
    if (da is List) {
      rawAdiciones = da.map<Map<String, dynamic>>((e) {
        if (e is Map && e['id_adicion'] != null) {
          return {'id_adicion': e['id_adicion'], 'cantidad': (e['cantidad'] as num?)?.toInt() ?? 1};
        }
        return {};
      }).where((m) => m.isNotEmpty).toList();
    }

    return LineaDetalle(
      idProducto: json['id_producto'] ?? (prodRaw is Map ? prodRaw['id_producto'] ?? 0 : 0),
      nombreProducto: nombreProducto,
      cantidad: json['cantidad'] ?? 1,
      precioUnitario: double.tryParse((json['precio_unitario'] ?? 0).toString()) ?? 0.0,
      toppings: toppings,
      adiciones: adiciones,
      salsas: salsas,
      chocolate: chocolate,
      esBowl: esBowl,
      rawToppings: rawToppings,
      rawAdiciones: rawAdiciones,
      maxToppings: maxToppings,
      costoAdiciones: costoAdiciones,
    );
  }

  // Igual que React calcularDesglose/calcItemEdit: (precio_unitario + adicionPerUnit) × cantidad
  double get subtotal => (precioUnitario + costoAdiciones) * cantidad;
}

/// Línea usada al crear pedidos (IDs, no nombres)
class PedidoLinea {
  final int productoId;
  final String nombreProducto;
  final int cantidad;
  final double precioUnitario;
  final List<int> toppingIds;
  final List<int> adicionIds;

  const PedidoLinea({
    required this.productoId,
    required this.nombreProducto,
    required this.cantidad,
    required this.precioUnitario,
    required this.toppingIds,
    required this.adicionIds,
  });

  Map<String, dynamic> toJson() => {
        'id_producto': productoId,
        'cantidad': cantidad,
        'precio_unitario': precioUnitario,
        'toppings': toppingIds,
        'adiciones': adicionIds,
      };
}

class Pedido {
  final int id;
  /// Para registros VentaDomiciliario: id_venta de la venta anidada.
  /// Se usa cuando se necesita cambiar estado de la venta (devolver).
  final int? ventaId;
  final String estado;
  final double total;
  final double costoDomicilio;
  final String? clienteNombre;
  final String? clienteTelefono;
  final String? direccion;
  final String? ciudad;
  final String? barrio;
  final double? latitud;
  final double? longitud;
  final String? metodoPago;
  final double? montoEfectivo;
  final double? montoTransferencia;
  final String? comprobante;
  final String? comprobanteUrl;
  final DateTime? creadoEn;
  final List<LineaDetalle> lineas;
  final double descuentoPuntos;
  final int puntosUsados;
  final int puntosGanados;
  final String? observaciones;
  final String? motivoAnulacion;
  final String? nombreDomiciliario;

  const Pedido({
    required this.id,
    this.ventaId,
    required this.estado,
    required this.total,
    this.costoDomicilio = 0,
    this.clienteNombre,
    this.clienteTelefono,
    this.direccion,
    this.ciudad,
    this.barrio,
    this.latitud,
    this.longitud,
    this.metodoPago,
    this.montoEfectivo,
    this.montoTransferencia,
    this.comprobante,
    this.comprobanteUrl,
    this.creadoEn,
    this.lineas = const [],
    this.descuentoPuntos = 0,
    this.puntosUsados = 0,
    this.puntosGanados = 0,
    this.observaciones,
    this.motivoAnulacion,
    this.nombreDomiciliario,
  });

  factory Pedido.fromJson(Map<String, dynamic> json) {
    // ── detectar si es registro VentaDomiciliario ────────────────────────────
    final esDomicilio = json['id_venta_domiciliario'] != null;
    final ventaMap = esDomicilio && json['venta'] is Map
        ? json['venta'] as Map<String, dynamic>
        : null;

    // ── estado ──────────────────────────────────────────────────────────────
    // Domicilios: estadoDomicilio.nombre_estado ('asignado','en_camino','entregado')
    // Ventas:     estado.nombre_estado          ('pendiente','en_proceso','listo','despachado','entregado','anulado')
    String estado = 'pendiente';
    final estadoRaw = json['estado'];
    final estadoDomiRaw = json['estadoDomicilio'];
    if (estadoDomiRaw is Map) {
      estado = (estadoDomiRaw['nombre_estado'] ?? estadoDomiRaw['nombre'] ?? 'asignado').toString();
    } else if (estadoRaw is Map) {
      estado = (estadoRaw['nombre_estado'] ?? estadoRaw['nombre'] ?? 'pendiente').toString();
    } else if (estadoRaw != null) {
      estado = estadoRaw.toString();
    }

    // ── ventaId (para domicilios: id de la venta anidada) ───────────────────
    int? ventaId;
    if (esDomicilio && ventaMap != null) {
      ventaId = ventaMap['id_venta'] as int?;
    }

    // ── cliente nombre — snapshot primero, JOIN como fallback ───────────────
    String? clienteNombre;
    final snapSrc = ventaMap ?? json;
    clienteNombre = snapSrc['nombre_cliente']?.toString() ?? snapSrc['cliente_nombre']?.toString();
    if (clienteNombre == null) {
      final clienteRaw = snapSrc['cliente'];
      if (clienteRaw is Map) {
        final usuario = clienteRaw['usuario'];
        if (usuario is Map) clienteNombre = usuario['nombre']?.toString();
        clienteNombre ??= clienteRaw['nombre']?.toString();
      } else if (clienteRaw is String) {
        clienteNombre = clienteRaw;
      }
    }

    // ── telefono cliente — snapshot primero, JOIN como fallback ─────────────
    String? clienteTelefono;
    clienteTelefono = snapSrc['telefono_cliente']?.toString() ?? snapSrc['cliente_telefono']?.toString();
    if (clienteTelefono == null) {
      final cMap = snapSrc['cliente'];
      if (cMap is Map) {
        clienteTelefono = cMap['telefono']?.toString();
      }
    }

    // ── total ────────────────────────────────────────────────────────────────
    // Prisma devuelve Decimal como String → usar tryParse
    double total = 0;
    final totalSrc = ventaMap ?? json;
    if (totalSrc['total'] != null) {
      total = double.tryParse(totalSrc['total'].toString()) ?? 0;
    }

    // ── dirección ────────────────────────────────────────────────────────────
    // Se lee de las columnas propias de la venta (direccion_linea/barrio/
    // ciudad, copiadas al momento de la compra), no de la relación con
    // `direcciones` -- así el detalle de un pedido ya hecho no se ve afectado
    // si esa dirección se edita o se borra después.
    final dirSrc = ventaMap ?? json;
    final String? direccion = dirSrc['direccion_linea']?.toString();
    final String? barrio = dirSrc['barrio']?.toString();
    final String? ciudad = dirSrc['ciudad']?.toString();

    // ── fecha ────────────────────────────────────────────────────────────────
    final fechaSrc = ventaMap ?? json;
    final fechaStr = fechaSrc['fecha'] ?? json['hora_asignacion'] ??
        json['creado_en'] ?? json['created_at'];
    final creadoEn = fechaStr != null ? DateTime.tryParse(fechaStr.toString()) : null;

    // ── lineas ───────────────────────────────────────────────────────────────
    List<LineaDetalle> lineas = [];
    final lineasSrc = ventaMap ?? json;
    final lineasRaw = lineasSrc['detalleVentas'] ?? json['lineas'];
    if (lineasRaw is List) {
      lineas = lineasRaw
          .map((e) => LineaDetalle.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    // ── método de pago + desglose mixto ─────────────────────────────────────
    String? metodoPago = (ventaMap ?? json)['metodo_pago']?.toString();
    double? montoEfectivo;
    double? montoTransferencia;

    // comprobante_url: primero desde Venta directamente, luego desde detallePago
    String? comprobanteUrl = (ventaMap ?? json)['comprobante_url']?.toString();

    final pagosSrc = ventaMap ?? json;
    final pagos = pagosSrc['pagos'];
    if (pagos is List && pagos.isNotEmpty) {
      final p0 = pagos[0];
      if (p0 is Map) {
        final dp = p0['detallePagos'];
        if (dp is List && dp.isNotEmpty) {
          if (metodoPago == null || metodoPago.isEmpty) {
            if (dp.length > 1) {
              metodoPago = 'mixto';
            } else {
              final dp0 = dp[0];
              if (dp0 is Map) {
                final mpMap = dp0['metodoPago'];
                if (mpMap is Map) {
                  metodoPago = mpMap['nombre']?.toString();
                }
              }
            }
          }
          // Extraer montos individuales para mixto + comprobante desde detallePago
          for (final dpItem in dp) {
            if (dpItem is Map) {
              final mpMap = dpItem['metodoPago'];
              final nombre = (mpMap is Map ? mpMap['nombre'] : null)?.toString() ?? '';
              final monto = double.tryParse((dpItem['monto'] ?? 0).toString()) ?? 0;
              if (nombre == 'efectivo') montoEfectivo = monto;
              if (nombre == 'transferencia') {
                montoTransferencia = monto;
                // Fallback: leer comprobante desde detallePago si no está en Venta
                comprobanteUrl ??= dpItem['comprobante']?.toString();
              }
            }
          }
        }
      }
    }

    // ── descuento puntos y puntos usados ────────────────────────────────────
    double descuentoPuntos = double.tryParse((ventaMap ?? json)['descuento_puntos']?.toString() ?? '0') ?? 0;
    int puntosUsados = ((ventaMap ?? json)['puntos_usados'] ?? (ventaMap ?? json)['puntos_a_usar'] ?? 0) as int? ?? int.tryParse(((ventaMap ?? json)['puntos_usados'] ?? 0).toString()) ?? 0;

    // ── observaciones ────────────────────────────────────────────────────────
    String? observaciones = (ventaMap ?? json)['observaciones']?.toString();

    // ── motivo anulación ─────────────────────────────────────────────────────
    String? motivoAnulacion = (ventaMap ?? json)['motivo_anulacion']?.toString();

    // ── puntos ganados (acumulación neta) ───────────────────────────────────
    // Neto acumulacion - reversion, no solo la suma de acumulaciones: una
    // venta que pasó por entregado más de una vez (devuelta a listo y
    // reentregada) tiene una fila de reversion por cada retroceso, y
    // sumarlas sin descontar mostraba el doble de los puntos que el cliente
    // realmente tiene ganados en esta venta.
    int puntosGanados = 0;
    final movsRaw = (ventaMap ?? json)['movimientosPuntos'];
    if (movsRaw is List) {
      for (final m in movsRaw) {
        if (m is Map && (m['tipo'] == 'acumulacion' || m['tipo'] == 'reversion')) {
          puntosGanados += int.tryParse((m['puntos'] ?? 0).toString()) ?? 0;
        }
      }
    }

    return Pedido(
        id: json['id_venta_domiciliario'] ?? json['id_venta'] ?? json['id'] ?? 0,
        ventaId: ventaId,
        estado: estado,
        total: total,
        costoDomicilio: double.tryParse(
          (json['costo_domicilio'] ?? ventaMap?['costo_domicilio'] ?? 0).toString()
        ) ?? 0,
        clienteNombre: clienteNombre,
        clienteTelefono: clienteTelefono,
        direccion: direccion,
        ciudad: ciudad,
        barrio: barrio,
        latitud: json['latitud'] != null ? double.tryParse(json['latitud'].toString()) : null,
        longitud: json['longitud'] != null ? double.tryParse(json['longitud'].toString()) : null,
        metodoPago: metodoPago,
        montoEfectivo: montoEfectivo,
        montoTransferencia: montoTransferencia,
        comprobante: json['comprobante']?.toString(),
        comprobanteUrl: comprobanteUrl,
        creadoEn: creadoEn,
        lineas: lineas,
        descuentoPuntos: descuentoPuntos,
        puntosUsados: puntosUsados,
        puntosGanados: puntosGanados,
        observaciones: observaciones,
        motivoAnulacion: motivoAnulacion,
        nombreDomiciliario: json['nombreDomiciliario']?.toString(),
      );
  }

  String get idFormateado => 'V-${id.toString().padLeft(4, '0')}';

  bool get esPendiente => estado == 'pendiente';
  bool get esConfirmado => estado == 'en_proceso';
  bool get esListo => estado == 'listo';
  bool get esDespachado => estado == 'despachado';
  bool get esEntregado => estado == 'entregado';

  /// Hora formateada HH:mm (o cadena vacía si creadoEn es null)
  String? get hora {
    if (creadoEn == null) return null;
    final h = creadoEn!.hour.toString().padLeft(2, '0');
    final m = creadoEn!.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Alias legible para metodoPago
  String? get formaPago => metodoPago;

  /// Subtotal = suma de (precioUnitario × cantidad) de cada línea
  double get subtotal => lineas.fold(0, (acc, l) => acc + l.subtotal);

  Pedido copyWith({
    int? id,
    int? ventaId,
    String? estado,
    double? total,
    double? costoDomicilio,
    String? clienteNombre,
    String? clienteTelefono,
    String? direccion,
    String? ciudad,
    String? barrio,
    double? latitud,
    double? longitud,
    String? metodoPago,
    double? montoEfectivo,
    double? montoTransferencia,
    String? comprobante,
    String? comprobanteUrl,
    DateTime? creadoEn,
    List<LineaDetalle>? lineas,
    double? descuentoPuntos,
    int? puntosUsados,
    int? puntosGanados,
    String? observaciones,
    String? motivoAnulacion,
    String? nombreDomiciliario,
  }) => Pedido(
    id: id ?? this.id,
    ventaId: ventaId ?? this.ventaId,
    estado: estado ?? this.estado,
    total: total ?? this.total,
    costoDomicilio: costoDomicilio ?? this.costoDomicilio,
    clienteNombre: clienteNombre ?? this.clienteNombre,
    clienteTelefono: clienteTelefono ?? this.clienteTelefono,
    direccion: direccion ?? this.direccion,
    ciudad: ciudad ?? this.ciudad,
    barrio: barrio ?? this.barrio,
    latitud: latitud ?? this.latitud,
    longitud: longitud ?? this.longitud,
    metodoPago: metodoPago ?? this.metodoPago,
    montoEfectivo: montoEfectivo ?? this.montoEfectivo,
    montoTransferencia: montoTransferencia ?? this.montoTransferencia,
    comprobante: comprobante ?? this.comprobante,
    comprobanteUrl: comprobanteUrl ?? this.comprobanteUrl,
    creadoEn: creadoEn ?? this.creadoEn,
    lineas: lineas ?? this.lineas,
    descuentoPuntos: descuentoPuntos ?? this.descuentoPuntos,
    puntosUsados: puntosUsados ?? this.puntosUsados,
    puntosGanados: puntosGanados ?? this.puntosGanados,
    observaciones: observaciones ?? this.observaciones,
    motivoAnulacion: motivoAnulacion ?? this.motivoAnulacion,
    nombreDomiciliario: nombreDomiciliario ?? this.nombreDomiciliario,
  );

  /// Dirección completa legible
  String get direccionCompleta {
    final parts = [direccion, barrio, ciudad]
        .where((s) => s != null && s.isNotEmpty)
        .toList();
    return parts.join(', ');
  }

  /// Link wa.me (asume Colombia +57)
  String? get whatsappUrl {
    if (clienteTelefono == null) return null;
    final digits = clienteTelefono!.replaceAll(RegExp(r'\D'), '');
    final number = digits.startsWith('57') ? digits : '57$digits';
    return 'https://wa.me/$number';
  }

  /// Link Google Maps
  String? get mapsUrl {
    if (latitud != null && longitud != null) {
      return 'https://maps.google.com/?q=$latitud,$longitud';
    }
    if (direccionCompleta.isNotEmpty) {
      final q = Uri.encodeComponent(direccionCompleta);
      return 'https://maps.google.com/?q=$q';
    }
    return null;
  }
}
