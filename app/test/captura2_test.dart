import 'package:caudal/nucleo/captura.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('direcciones reales de cada red', () {
    test('TikTok, sin extension ninguna', () {
      final m = MedioCapturado(
          'https://v16-webapp.tiktok.com/video/tos/useast2a/tos-abc/?a=1988&br=2500', 'xhr');
      expect(m.esArchivoEntero, isTrue, reason: 'TikTok debe contar como archivo entero');
      expect(m.esLista, isFalse);
    });

    test('Instagram, mp4 con parametros firmados', () {
      final m = MedioCapturado(
          'https://scontent.cdninstagram.com/o1/v/t16/f2/m86/AQO.mp4?efg=eyJ2ZW5j', 'fetch');
      expect(m.esArchivoEntero, isTrue);
    });

    test('un trozo suelto no vale como archivo entero', () {
      expect(MedioCapturado('https://c.com/seg-3.m4s', 'xhr').esArchivoEntero, isFalse);
      expect(MedioCapturado('https://c.com/seg-3.ts', 'xhr').esArchivoEntero, isFalse);
    });

    test('entre TikTok y un trozo, gana TikTok', () {
      final mejor = mejorCapturado([
        MedioCapturado('https://c.com/seg-1.m4s', 'xhr'),
        MedioCapturado('https://v16.tiktok.com/video/tos/x/?a=1', 'xhr'),
      ]);
      expect(mejor!.url, contains('tiktok'));
    });
  });

  group('el guion mira el tipo declarado, no solo la direccion', () {
    test('comprueba content-type', () {
      expect(guionCaptura, contains("content-type"));
      expect(guionCaptura, contains("video/"));
      expect(guionCaptura, contains("audio/"));
    });

    test('reconoce las rutas de cada red', () {
      expect(guionCaptura, contains(r'\/video\/tos\/'));
      expect(guionCaptura, contains('bytestart'));
      expect(guionCaptura, contains('videoplayback'));
    });

    test('mira tambien la respuesta, no solo la peticion', () {
      expect(guionCaptura, contains('responseURL'));
      expect(guionCaptura, contains('readyState'));
    });

    test('sabe despertar el video', () {
      expect(guionDespertar, contains('.play()'));
      expect(guionDespertar, contains('muted'));
    });
  });
  group('quitar los trozos de la direccion', () {
    test('fuera el range, que es lo que partia el archivo', () {
      const conTrozo =
          'https://r5.googlevideo.com/videoplayback?expire=1&itag=140'
          '&range=0-1048575&rn=3&rbuf=0&sig=abc';
      final limpia = limpiarTrozos(conTrozo);
      expect(limpia, isNot(contains('range=')));
      expect(limpia, isNot(contains('rn=')));
      expect(limpia, isNot(contains('rbuf=')));
      // lo que identifica y firma el video tiene que seguir ahi
      expect(limpia, contains('itag=140'));
      expect(limpia, contains('sig=abc'));
      expect(limpia, contains('expire=1'));
    });

    test('una direccion sin parametros se queda igual', () {
      const u = 'https://cdn.ejemplo.com/video.mp4';
      expect(limpiarTrozos(u), u);
    });

    test('no se lleva por delante parametros parecidos', () {
      final limpia = limpiarTrozos('https://c.com/v.mp4?arange=1&rnd=2&range=0-99');
      expect(limpia, contains('arange=1'));
      expect(limpia, contains('rnd=2'));
      expect(limpia, isNot(contains('&range=0-99')));
    });

    test('lo capturado llega ya limpio', () {
      final m = MedioCapturado(
          'https://r5.googlevideo.com/videoplayback?itag=140&range=0-1048575', 'xhr');
      expect(m.url, isNot(contains('range=')));
      expect(m.url, contains('itag=140'));
    });
  });

}
