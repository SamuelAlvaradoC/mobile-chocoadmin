// Espejo en el frontend de la validación real del backend (ver
// chocoadmin-api/src/utils/validarSinHtml.js) -- esto es solo para que el
// usuario vea el error de inmediato sin esperar la respuesta del servidor.
// La protección real sigue siendo la del backend: cualquiera puede
// saltarse esto pegándole directo a la API.
//
// Flutter no trae un parser HTML nativo (a diferencia del navegador con
// DOMParser en el frontend web), así que aquí se usa una regex que
// reconoce sintaxis de tag válida: "<" seguido inmediatamente de una
// letra o "/" (igual que exige el propio estándar HTML5). Textos como
// "a < b" o "5>3" no cumplen ese patrón y no se detectan como tag.
final RegExp _tagHtml = RegExp(r'<\/?[a-zA-Z][^>]*>');

bool contieneEtiquetaHtml(String? texto) {
  if (texto == null || texto.isEmpty) return false;
  return _tagHtml.hasMatch(texto);
}

const String mensajeHtml = 'El texto no puede contener etiquetas HTML o código';
