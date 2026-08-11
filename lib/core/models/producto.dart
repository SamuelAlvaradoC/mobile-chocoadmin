class Producto {
  final int id;
  final String nombre;
  final String? descripcion;
  final double precio;
  final bool permiteToppings;
  final int maxToppings;
  final bool permiteSalsas;
  final bool permiteChocolate;
  final bool esBowl;
  final int? idCategoria;
  final String? imagen;
  final int estado;

  const Producto({
    required this.id,
    required this.nombre,
    this.descripcion,
    required this.precio,
    required this.permiteToppings,
    this.maxToppings = 0,
    this.permiteSalsas = false,
    this.permiteChocolate = false,
    this.esBowl = false,
    this.idCategoria,
    this.imagen,
    this.estado = 1,
  });

  factory Producto.fromJson(Map<String, dynamic> json) => Producto(
        id: json['id_producto'] ?? json['id'] ?? 0,
        nombre: json['nombre'] ?? '',
        descripcion: json['descripcion'],
        precio: double.tryParse(json['precio']?.toString() ?? '0') ?? 0.0,
        permiteToppings:
            json['permite_toppings'] == 1 || json['permite_toppings'] == true,
        maxToppings: json['max_toppings'] ?? 0,
        permiteSalsas:
            json['permite_salsas'] == 1 || json['permite_salsas'] == true,
        permiteChocolate:
            json['permite_chocolate'] == 1 || json['permite_chocolate'] == true,
        esBowl: json['es_bowl'] == 1 || json['es_bowl'] == true,
        idCategoria: json['id_categoria'],
        imagen: json['img'] ?? json['imagen'] ?? json['foto'],
        estado: json['estado'] is num
            ? (json['estado'] as num).toInt()
            : int.tryParse(json['estado']?.toString() ?? '1') ?? 1,
      );
}
