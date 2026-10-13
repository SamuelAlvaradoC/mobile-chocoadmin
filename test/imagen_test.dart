import 'package:flutter_test/flutter_test.dart';
import 'package:chocoadmin/core/utils/imagen.dart';

void main() {
  const url = 'https://res.cloudinary.com/dnoxlv5kn/image/upload/v1779300851/pz3lkzl4if1vgmzd0fdf.png';
  test('agrega formato/calidad automáticos y ancho máximo', () {
    expect(imgCl(url), 'https://res.cloudinary.com/dnoxlv5kn/image/upload/f_auto,q_auto,c_limit,w_600/v1779300851/pz3lkzl4if1vgmzd0fdf.png');
    expect(imgCl(url, w: 300), contains('w_300'));
  });
  test('no toca URLs que no son de Cloudinary ni las ya transformadas', () {
    expect(imgCl('https://otro.com/a.png'), 'https://otro.com/a.png');
    final ya = imgCl(url);
    expect(imgCl(ya), ya);
  });
}
