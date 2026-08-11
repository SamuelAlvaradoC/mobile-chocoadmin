class Categoria {
  final int id;
  final String nombre;
  final String? imagen;

  const Categoria({
    required this.id,
    required this.nombre,
    this.imagen,
  });

  factory Categoria.fromJson(Map<String, dynamic> json) => Categoria(
        id: json['id_categoria'] ?? json['id'] ?? 0,
        nombre: json['nombre'] ?? '',
        imagen: json['imagen'],
      );
}
