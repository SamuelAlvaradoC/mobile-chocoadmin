// URL de Cloudinary optimizada para MOSTRAR (no para guardar): formato y
// calidad automáticos (WebP/AVIF cuando el dispositivo lo soporta) y ancho
// máximo sin agrandar (c_limit). Mismo criterio que imgCl en la web
// (src/utils/cloudinary.js). Una foto de producto de ~1,6 MB pasa a decenas
// de KB -- menos datos para el cliente y menos ancho de banda de Cloudinary.
//
// Usar SOLO en el widget que la muestra: nunca guardar en la base la URL
// transformada (los formularios de edición deben seguir enviando la original).
String imgCl(String url, {int w = 600}) {
  if (!url.contains('res.cloudinary.com') || !url.contains('/upload/')) return url;
  if (url.contains('/upload/f_auto')) return url;
  return url.replaceFirst('/upload/', '/upload/f_auto,q_auto,c_limit,w_$w/');
}
