// Registro: aviso de aceptación con enlaces a Términos y Privacidad (web).
// Reseña de un pedido: se manda con la sesión (la API exige que sea del dueño).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chocoadmin/core/services/api_service.dart';
import 'package:chocoadmin/features/auth/widgets/aviso_legal_registro.dart';

/// Toca el TextSpan cuyo texto es [texto] dentro del Text.rich del aviso.
void _tocarEnlace(WidgetTester tester, String texto) {
  final rich = tester.widget<RichText>(find.byType(RichText).first);
  var tocado = false;
  rich.text.visitChildren((span) {
    if (span is TextSpan && span.text == texto) {
      (span.recognizer as TapGestureRecognizer).onTap!();
      tocado = true;
      return false;
    }
    return true;
  });
  expect(tocado, isTrue, reason: 'no se encontró el enlace "$texto"');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('el registro muestra el aviso y los enlaces abren las páginas de la web', (tester) async {
    final abiertas = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AvisoLegalRegistro(abrirUrl: (url) async => abiertas.add(url))),
    ));

    expect(find.textContaining('Al registrarte aceptas los', findRichText: true), findsOneWidget);
    expect(find.textContaining('Términos y condiciones', findRichText: true), findsOneWidget);
    expect(find.textContaining('Política de privacidad', findRichText: true), findsOneWidget);

    _tocarEnlace(tester, 'Términos y condiciones');
    _tocarEnlace(tester, 'Política de privacidad');
    expect(abiertas, ['https://www.chocofreseo.com/terminos', 'https://www.chocofreseo.com/privacidad']);
  });

  test('headersJson incluye el token cuando hay sesión', () async {
    SharedPreferences.setMockInitialValues({'token': 'abc'});
    expect(await ApiService.headersJson(), containsPair('Authorization', 'Bearer abc'));
  });

  test('headersJson sin sesión solo manda JSON', () async {
    SharedPreferences.setMockInitialValues({});
    final h = await ApiService.headersJson();
    expect(h['Content-Type'], 'application/json');
    expect(h.containsKey('Authorization'), isFalse);
  });
}
