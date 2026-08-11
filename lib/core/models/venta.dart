class Venta {
  final int id;
  final String estado;
  final double total;
  final String? clienteNombre;
  final DateTime? fechaVenta;
  final String? direccion;

  const Venta({
    required this.id,
    required this.estado,
    required this.total,
    this.clienteNombre,
    this.fechaVenta,
    this.direccion,
  });

  factory Venta.fromJson(Map<String, dynamic> json) {
    // cliente puede ser Map{"usuario":{"nombre":"..."}} o Map{"nombre":"..."} o String
    String? clienteNombre;
    final clienteRaw = json['cliente'];
    if (clienteRaw is Map) {
      final usuario = clienteRaw['usuario'];
      if (usuario is Map) {
        clienteNombre = usuario['nombre']?.toString();
      }
      clienteNombre ??= clienteRaw['nombre']?.toString();
    } else if (clienteRaw is String) {
      clienteNombre = clienteRaw;
    }
    clienteNombre ??= json['cliente_nombre']?.toString();

    // fecha — el campo real en la API es "fecha"
    DateTime? fecha;
    final fechaStr = json['fecha'] ??
        json['fecha_venta'] ??
        json['creado_en'] ??
        json['created_at'];
    if (fechaStr != null) {
      fecha = DateTime.tryParse(fechaStr.toString());
    }

    // estado puede venir como Map {"id_estado":1,"nombre_estado":"pendiente",...} o String
    final estadoRaw = json['estado'];
    final String estado;
    if (estadoRaw is Map) {
      estado = (estadoRaw['nombre_estado'] ?? estadoRaw['nombre'] ?? 'pendiente').toString();
    } else {
      estado = estadoRaw?.toString() ?? 'pendiente';
    }

    return Venta(
      id: json['id_venta'] ?? json['id'] ?? 0,
      estado: estado,
      total: double.tryParse(json['total']?.toString() ?? '0') ?? 0.0,
      clienteNombre: clienteNombre,
      fechaVenta: fecha,
      direccion: json['direccion']?.toString(),
    );
  }

  String get idFormateado => 'V-${id.toString().padLeft(4, '0')}';
}
