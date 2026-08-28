import 'package:caudal/nucleo/captura.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reconocer lo que pasa por la pagina', () {
    test('un mp4 entero es lo mejor', () {
      final m = MedioCapturado('https://cdn.ejemplo.com/video.mp4', 'fetch');
      expect(m.esArchivoEntero, isTrue);
      expect(m.esLista, isFalse);
      expect(m.esSoloAudio, isFalse);
    });

    test('un m3u8 es una lista de trozos', () {
      final m = MedioCapturado('https://cdn.ejemplo.com/master.m3u8', 'xhr');
      expect(m.esLista, isTrue);
      expect(m.esArchivoEntero, isFalse);
    });

    test('un m4a es solo sonido', () {
      final m = MedioCapturado('https://cdn.ejemplo.com/pista.m4a', 'dom');
      expect(m.esSoloAudio, isTrue);
    });

    test('los parametros de la direccion no confunden', () {
      final m = MedioCapturado('https://x.com/v.mp4?token=abc&t=1', 'fetch');
      expect(m.esArchivoEntero, isTrue);
    });
  });

  group('elegir la mejor', () {
    final medios = [
      MedioCapturado('https://c.com/lista.m3u8', 'xhr'),
      MedioCapturado('https://c.com/video.mp4', 'fetch'),
      MedioCapturado('https://c.com/audio.m4a', 'fetch'),
    ];

    test('para video gana el mp4 entero', () {
      expect(mejorCapturado(medios)!.url, contains('video.mp4'));
    });

    test('para audio gana la pista de sonido', () {
      expect(mejorCapturado(medios, paraAudio: true)!.url, contains('audio.m4a'));
    });

    test('si solo hay lista de trozos, esa se usa', () {
      final soloLista = [MedioCapturado('https://c.com/l.m3u8', 'xhr')];
      expect(mejorCapturado(soloLista)!.esLista, isTrue);
    });

    test('sin nada capturado devuelve nada', () {
      expect(mejorCapturado([]), isNull);
    });
  });

  test('el guion se engancha a fetch, a xhr y al DOM', () {
    expect(guionCaptura, contains('window.fetch'));
    expect(guionCaptura, contains('XMLHttpRequest.prototype.open'));
    expect(guionCaptura, contains('MutationObserver'));
    expect(guionCaptura, contains('CaudalMedios.postMessage'));
  });
}
