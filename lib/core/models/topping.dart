class Topping {
  final int id;
  final String nombre;
  final double precio;
  final String tipo;
  final String? img;

  const Topping({required this.id, required this.nombre, required this.precio, this.tipo = 'topping', this.img});

  bool get esSalsa => tipo == 'salsa';

  factory Topping.fromJson(Map<String, dynamic> json) => Topping(
        id: json['id_topping'] ?? json['id'] ?? 0,
        nombre: json['nombre'] ?? '',
        precio: double.tryParse(json['precio']?.toString() ?? '0') ?? 0.0,
        tipo: json['tipo']?.toString() ?? 'topping',
        img: json['img'] ?? json['imagen'],
      );

  @override
  bool operator ==(Object other) => other is Topping && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
