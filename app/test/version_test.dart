import 'package:caudal/nucleo/version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('comparar versiones', () {
    test('una version mayor gana', () {
      expect(hayNovedad('1.2.0', '1.3.0'), isTrue);
      expect(hayNovedad('1.2.0', '2.0.0'), isTrue);
    });

    test('la misma version no es novedad', () {
      expect(hayNovedad('1.3.0', '1.3.0'), isFalse);
    });

    test('una version anterior no es novedad', () {
      expect(hayNovedad('1.3.0', '1.2.9'), isFalse);
      expect(hayNovedad('2.0.0', '1.9.9'), isFalse);
    });

    test('compara numeros, no texto', () {
      // como texto, "1.9" pareceria mayor que "1.10"
      expect(hayNovedad('1.9.0', '1.10.0'), isTrue);
      expect(hayNovedad('1.10.0', '1.9.0'), isFalse);
    });

    test('acepta la v delante', () {
      expect(hayNovedad('1.2.0', 'v1.3.0'), isTrue);
      expect(hayNovedad('v1.3.0', 'v1.3.0'), isFalse);
    });

    test('versiones con distinto numero de partes', () {
      expect(hayNovedad('1.3', '1.3.1'), isTrue);
      expect(hayNovedad('1.3.0', '1.3'), isFalse);
    });

    test('no revienta con basura', () {
      expect(hayNovedad('', ''), isFalse);
      expect(hayNovedad('1.3.0', 'sin numeros'), isFalse);
    });
  });

  group('novedad', () {
    test('sin apk no se puede instalar', () {
      const n = Novedad(version: '2.0', notas: '', apk: '', pagina: '', peso: 0);
      expect(n.sePuedeInstalar, isFalse);
    });
  });

  test('la version de la app es la esperada', () {
    expect(versionApp, '1.4.1');
    expect(origen, 'Aliprogramator/caudal');
  });
}
