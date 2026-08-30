import 'package:caudal/nucleo/capturador_oculto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el capturador nace en reposo', () {
    final c = CapturadorOculto();
    expect(c.trabajando, isFalse, reason: 'no hay ninguna captura en marcha');
  });

  test('una captura vacia no vale', () {
    expect(const CapturaOculta().vale, isFalse);
    expect(const CapturaOculta(url: 'https://x.com/v.mp4').vale, isTrue);
  });

  test('la captura guarda titulo y cookies para la descarga', () {
    const c = CapturaOculta(
      url: 'https://cdn.com/v.mp4',
      titulo: 'Un video',
      cookies: 'sesion=abc',
    );
    expect(c.url, 'https://cdn.com/v.mp4');
    expect(c.titulo, 'Un video');
    expect(c.cookies, 'sesion=abc');
  });

  test('la captura guarda las demas direcciones por si la primera falla', () {
    const c = CapturaOculta(
      url: 'https://cdn.com/bueno.mp4',
      candidatas: ['https://cdn.com/bueno.mp4', 'https://cdn.com/otro.mp4'],
    );
    expect(c.candidatas.length, 2);
  });
}
