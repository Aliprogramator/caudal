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
}
