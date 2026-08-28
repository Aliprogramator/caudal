import 'package:caudal/nucleo/capturador_oculto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el capturador se prepara antes de que haga falta', () {
    final c = CapturadorOculto();
    expect(c.controlador, isNull, reason: 'aun no se ha preparado');
    expect(c.trabajando, isFalse);
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
}
