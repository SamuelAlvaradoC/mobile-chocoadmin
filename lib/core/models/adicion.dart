class Adicion {
  final int id;
  final String nombre;
  final double precio;
  final String? img;

  const Adicion({required this.id, required this.nombre, required this.precio, this.img});

  factory Adicion.fromJson(Map<String, dynamic> json) => Adicion(
        id: json['id_adicion'] ?? json['id'] ?? 0,
        nombre: json['nombre'] ?? '',
        precio: double.tryParse(json['precio']?.toString() ?? '0') ?? 0.0,
        img: json['img'] ?? json['imagen'],
      );

  @override
  bool operator ==(Object other) => other is Adicion && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
