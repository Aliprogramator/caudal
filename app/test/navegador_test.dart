import 'package:caudal/nucleo/captura.dart';
import 'package:caudal/nucleo/descargas.dart';
import 'package:caudal/nucleo/modelos.dart';
import 'package:caudal/nucleo/navegador_caudal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('filtro rapido del interceptor', () {
    // Por el interceptor pasa todo lo que pide la pagina. Si mirarlo con calma
    // costara algo, la navegacion se arrastraria: por eso hay un primer filtro
    // que descarta de un vistazo lo que seguro que no es un video.
    test('deja pasar lo que puede ser un video', () {
      expect(podriaSerMedia('https://cdn.com/video.mp4'), isTrue);
      expect(podriaSerMedia('https://cdn.com/lista.m3u8'), isTrue);
      expect(podriaSerMedia('https://v.tiktok.com/video/tos/abc123'), isTrue);
      expect(
        podriaSerMedia('https://rr1.googlevideo.com/videoplayback?expire=1'),
        isTrue,
      );
      expect(
        podriaSerMedia('https://scontent.cdninstagram.com/o1/v/t2/f2/x.mp4?bytestart=0'),
        isTrue,
      );
    });

    test('descarta lo que no lo es', () {
      expect(podriaSerMedia('https://www.google.com/'), isFalse);
      expect(podriaSerMedia('https://cdn.com/estilos.css'), isFalse);
      expect(podriaSerMedia('https://cdn.com/logo.png'), isFalse);
      expect(podriaSerMedia('https://analitica.com/evento?id=7'), isFalse);
      expect(podriaSerMedia('blob:https://x.com/abc'), isFalse);
      expect(podriaSerMedia(''), isFalse);
    });
  });

  group('orden de las direcciones vistas', () {
    test('un archivo entero va antes que una lista de trozos', () {
      final orden = candidatasOrdenadas([
        MedioCapturado('https://cdn.com/lista.m3u8', 'red'),
        MedioCapturado('https://cdn.com/entero.mp4', 'red'),
      ]);
      expect(orden.first.url, contains('entero.mp4'));
    });

    test('un trozo suelto queda el ultimo: por si solo no sirve de nada', () {
      final orden = candidatasOrdenadas([
        MedioCapturado('https://cdn.com/parte7.ts', 'red'),
        MedioCapturado('https://cdn.com/lista.m3u8', 'red'),
        MedioCapturado('https://cdn.com/entero.mp4', 'red'),
      ]);
      expect(orden.last.url, contains('parte7.ts'));
    });

    test('pidiendo solo sonido, la pista de audio se adelanta', () {
      final orden = candidatasOrdenadas([
        MedioCapturado('https://cdn.com/video.mp4', 'red'),
        MedioCapturado('https://cdn.com/sonido.m4a', 'red'),
      ], paraAudio: true);
      expect(orden.first.url, contains('sonido.m4a'));
    });

    test('devuelve todas, no solo la mejor', () {
      final orden = candidatasOrdenadas([
        MedioCapturado('https://cdn.com/a.mp4', 'red'),
        MedioCapturado('https://cdn.com/b.m3u8', 'red'),
        MedioCapturado('https://cdn.com/c.webm', 'dom'),
      ]);
      expect(orden.length, 3);
    });
  });

  group('limpiar los trozos de una direccion', () {
    test('quita el rango para que llegue el archivo entero', () {
      expect(
        limpiarTrozos('https://cdn.com/v.mp4?id=7&range=0-9999&rn=3'),
        'https://cdn.com/v.mp4?id=7',
      );
    });

    test('quita tambien el bytestart de Instagram y Facebook', () {
      expect(
        limpiarTrozos('https://cdn.com/v.mp4?bytestart=0&byteend=1048&efg=xyz'),
        'https://cdn.com/v.mp4?efg=xyz',
      );
    });

    test('una direccion sin parametros se queda igual', () {
      expect(limpiarTrozos('https://cdn.com/v.mp4'), 'https://cdn.com/v.mp4');
    });
  });

  group('la descarga prueba varias direcciones', () {
    // Quedarse con una sola era rendirse antes de tiempo: cuando esa caduca o
    // el servidor la rechaza, muchas veces la siguiente si vale.
    test('junta la principal con las demas, sin repetir', () {
      final d = Descarga(
        id: 'x',
        url: 'https://sitio.com/video/1',
        urlMedia: 'https://cdn.com/a.mp4',
        candidatas: ['https://cdn.com/a.mp4', 'https://cdn.com/b.mp4'],
        tipo: TipoMedio.completo,
        calidad: 'mejor',
        formatoAudio: 'm4a',
      );
      expect(d.todasLasCandidatas,
          ['https://cdn.com/a.mp4', 'https://cdn.com/b.mp4']);
    });

    test('sin direcciones, la lista queda vacia', () {
      final d = Descarga(
        id: 'x',
        url: 'https://youtube.com/watch?v=1',
        tipo: TipoMedio.audio,
        calidad: 'mejor',
        formatoAudio: 'mp3',
      );
      expect(d.todasLasCandidatas, isEmpty);
    });
  });

  group('lo que la propia web manda descargar', () {
    test('reconoce un video por su nombre', () {
      const p = PeticionDescarga(
          url: 'https://sitio.com/d?id=9', nombre: 'pelicula.mp4');
      expect(p.esVideo, isTrue);
      expect(p.esAudio, isFalse);
    });

    test('reconoce el sonido por lo que declara el servidor', () {
      const p = PeticionDescarga(
          url: 'https://sitio.com/d?id=9', tipoMime: 'audio/mpeg');
      expect(p.esAudio, isTrue);
    });

    test('un archivo cualquiera no es ni video ni sonido', () {
      const p = PeticionDescarga(
          url: 'https://sitio.com/manual.pdf', nombre: 'manual.pdf');
      expect(p.esVideo, isFalse);
      expect(p.esAudio, isFalse);
    });
  });

  group('pestanas', () {
    test('el navegador nace con una pestana en la portada', () {
      final nav = NavegadorCaudal();
      expect(nav.pestanas.length, 1);
      expect(nav.activa.vacia, isTrue);
      nav.dispose();
    });

    test('abrir una pestana la deja como activa', () {
      final nav = NavegadorCaudal();
      nav.abrir(url: 'https://ejemplo.com');
      expect(nav.pestanas.length, 2);
      expect(nav.activa.urlInicial, 'https://ejemplo.com');
      nav.dispose();
    });

    test('cerrar la ultima deja una portada, nunca ninguna', () {
      final nav = NavegadorCaudal();
      nav.cerrar(nav.pestanas.first);
      expect(nav.pestanas.length, 1);
      expect(nav.activa.vacia, isTrue);
      nav.dispose();
    });

    test('cada pestana cuenta sus medios una sola vez', () {
      final p = Pestana();
      expect(p.anotar('https://cdn.com/v.mp4', 'red'), isTrue);
      expect(p.anotar('https://cdn.com/v.mp4', 'dom'), isFalse);
      expect(p.medios.length, 1);
      p.dispose();
    });

    test('lo que no es una direccion web no se anota', () {
      final p = Pestana();
      expect(p.anotar('blob:https://x.com/abc', 'dom'), isFalse);
      expect(p.anotar('', 'dom'), isFalse);
      expect(p.medios, isEmpty);
      p.dispose();
    });

    test('el rango se quita al anotar, para bajar el archivo entero', () {
      final p = Pestana();
      p.anotar('https://cdn.com/v.mp4?range=0-99&id=4', 'red');
      expect(p.medios.first.url, 'https://cdn.com/v.mp4?id=4');
      p.dispose();
    });
  });
}
