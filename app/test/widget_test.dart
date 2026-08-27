import 'package:caudal/nucleo/deteccion.dart';
import 'package:caudal/nucleo/formato.dart';
import 'package:caudal/nucleo/modelos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formato de tamaños', () {
    test('usa bytes sin decimales y escala bien', () {
      expect(formatoBytes(0), '0 B');
      expect(formatoBytes(512), '512 B');
      expect(formatoBytes(1024), '1.0 KB');
      expect(formatoBytes(1024 * 1024 * 3.7), '3.7 MB');
      expect(formatoBytes(1024 * 1024 * 1024 * 2), '2.0 GB');
    });

    test('a partir de 100 quita el decimal para que no se alargue', () {
      expect(formatoBytes(1024 * 150), '150 KB');
    });
  });

  group('formato de tiempos', () {
    test('muestra horas solo cuando hacen falta', () {
      expect(formatoDuracion(const Duration(seconds: 45)), '0:45');
      expect(formatoDuracion(const Duration(minutes: 3, seconds: 7)), '3:07');
      expect(formatoDuracion(const Duration(hours: 1, minutes: 2, seconds: 5)), '1:02:05');
    });

    test('el tiempo restante se redondea a algo legible', () {
      expect(formatoRestante(0), '');
      expect(formatoRestante(30), 'quedan 30s');
      expect(formatoRestante(90), 'quedan 2 min');
    });
  });

  group('detección de enlaces', () {
    test('reconoce enlaces con y sin esquema', () {
      expect(pareceEnlace('https://youtu.be/abc'), isTrue);
      expect(pareceEnlace('youtube.com/watch?v=1'), isTrue);
      expect(pareceEnlace('instagram.com/reel/x'), isTrue);
    });

    test('no confunde una búsqueda con un enlace', () {
      expect(pareceEnlace('musica para estudiar'), isFalse);
      expect(pareceEnlace(''), isFalse);
      expect(pareceEnlace('hola'), isFalse);
    });

    test('completa el esquema que falta', () {
      expect(normalizarEnlace('youtube.com/abc'), 'https://youtube.com/abc');
      expect(normalizarEnlace('http://x.com/1'), 'http://x.com/1');
    });
  });

  group('nombre del sitio', () {
    test('reconoce los sitios más habituales', () {
      expect(sitioDe('https://www.youtube.com/watch?v=1'), 'YouTube');
      expect(sitioDe('https://youtu.be/abc'), 'YouTube');
      expect(sitioDe('https://x.com/user/status/1'), 'X');
      expect(sitioDe('https://www.instagram.com/reel/x'), 'Instagram');
    });

    test('para los demás usa el dominio limpio', () {
      expect(sitioDe('https://www.ejemplo.net/video'), 'ejemplo.net');
    });
  });

  group('nombres de archivo', () {
    test('quita los caracteres que Android y Windows no aceptan', () {
      expect(nombreSeguro('a/b\\c:d*e?f'), 'a_b_c_d_e_f');
      expect(nombreSeguro('  espacios  de sobra  '), 'espacios de sobra');
    });

    test('nunca devuelve vacío', () {
      expect(nombreSeguro(''), 'descarga');
      expect(nombreSeguro('...'), 'descarga');
    });

    test('recorta los títulos larguísimos', () {
      final largo = 'x' * 300;
      expect(nombreSeguro(largo).length, lessThanOrEqualTo(90));
    });
  });

  group('tipos de descarga', () {
    test('van y vuelven de su clave sin perderse', () {
      expect(TipoMedioTexto.desdeClave('audio'), TipoMedio.audio);
      expect(TipoMedioTexto.desdeClave('video'), TipoMedio.video);
      expect(TipoMedioTexto.desdeClave('completo'), TipoMedio.completo);
      expect(TipoMedioTexto.desdeClave(null), TipoMedio.completo);
      expect(TipoMedio.audio.clave, 'audio');
    });
  });

  group('lectura de lo que manda el servidor', () {
    test('una ficha normal se lee entera', () {
      final f = Ficha.desdeJson({
        'titulo': 'Una canción',
        'autor': 'Alguien',
        'duracion': 185,
        'duracion_texto': '3:05',
        'miniatura': 'http://x/y.jpg',
        'tiene_video': true,
        'tiene_audio': true,
        'calidades': [
          {'valor': '1080', 'etiqueta': 'Full HD · 1080p', 'altura': 1080},
        ],
      });
      expect(f.titulo, 'Una canción');
      expect(f.esLista, isFalse);
      expect(f.calidades.single.altura, 1080);
    });

    test('una respuesta vacía no rompe nada', () {
      final f = Ficha.desdeJson({});
      expect(f.titulo, '');
      expect(f.calidades, isEmpty);
      expect(f.tieneAudio, isTrue);
    });

    test('las listas traen sus elementos', () {
      final f = Ficha.desdeJson({
        'es_lista': true,
        'titulo': 'Mi lista',
        'elementos': [
          {'url': 'http://a', 'titulo': 'uno'},
          {'url': 'http://b', 'titulo': 'dos'},
        ],
      });
      expect(f.esLista, isTrue);
      expect(f.elementos.length, 2);
      expect(f.elementos.first.titulo, 'uno');
    });
  });

  group('detectar si la pagina es descargable', () {
    test('reconoce las paginas de video de cada red', () {
      expect(pareceDescargable('https://www.youtube.com/watch?v=abc123'), isTrue);
      expect(pareceDescargable('https://www.youtube.com/shorts/abc123'), isTrue);
      expect(pareceDescargable('https://youtu.be/abc12345'), isTrue);
      expect(pareceDescargable('https://www.instagram.com/reel/Cx1y2z3/'), isTrue);
      expect(pareceDescargable('https://www.tiktok.com/@user/video/7106594312292453675'), isTrue);
      expect(pareceDescargable('https://x.com/alguien/status/1234567890'), isTrue);
      expect(pareceDescargable('https://www.facebook.com/watch/?v=123'), isTrue);
      expect(pareceDescargable('https://vimeo.com/123456'), isTrue);
      expect(pareceDescargable('https://soundcloud.com/artista/cancion'), isTrue);
    });

    test('NO se activa en portadas, perfiles ni buscadores', () {
      expect(pareceDescargable('https://www.youtube.com'), isFalse);
      expect(pareceDescargable('https://www.youtube.com/'), isFalse);
      expect(pareceDescargable('https://www.youtube.com/results?search_query=algo'), isFalse);
      expect(pareceDescargable('https://www.youtube.com/@uncanal'), isFalse);
      expect(pareceDescargable('https://www.instagram.com/'), isFalse);
      expect(pareceDescargable('https://www.instagram.com/unperfil/'), isFalse);
      expect(pareceDescargable('https://www.tiktok.com/@user'), isFalse);
      expect(pareceDescargable('https://x.com/alguien'), isFalse);
      expect(pareceDescargable('https://www.google.com/search?q=hola'), isFalse);
      expect(pareceDescargable('https://es.wikipedia.org/wiki/Musica'), isFalse);
    });

    test('acepta enlaces directos a un archivo de medios', () {
      expect(pareceDescargable('https://cdn.ejemplo.com/clip.mp4'), isTrue);
      expect(pareceDescargable('https://cdn.ejemplo.com/audio.mp3?token=1'), isTrue);
      expect(pareceDescargable('https://cdn.ejemplo.com/lista.m3u8'), isTrue);
      expect(pareceDescargable('https://ejemplo.com/pagina.html'), isFalse);
    });

    test('descarta lo que no es una direccion web', () {
      expect(pareceDescargable(''), isFalse);
      expect(pareceDescargable('about:blank'), isFalse);
      expect(pareceDescargable('javascript:void(0)'), isFalse);
      expect(pareceDescargable('no es una url'), isFalse);
    });

    test('sabe donde solo hay musica, para poner ese boton primero', () {
      expect(esSitioDeAudio('https://music.youtube.com/watch?v=1'), isTrue);
      expect(esSitioDeAudio('https://soundcloud.com/a/b'), isTrue);
      expect(esSitioDeAudio('https://artista.bandcamp.com/track/x'), isTrue);
      expect(esSitioDeAudio('https://www.youtube.com/watch?v=1'), isFalse);
    });
  });

  group('listas importadas de otras plataformas', () {
    test('lee una lista de Spotify con sus canciones', () {
      final l = ListaImportada.desdeJson({
        'titulo': 'Mi lista',
        'plataforma': 'Spotify',
        'canciones': [
          {'titulo': 'Cancion A', 'artista': 'Alguien', 'duracion': 200,
           'busqueda': 'Alguien Cancion A'},
          {'titulo': 'Cancion B', 'artista': 'Otro', 'duracion': 180,
           'busqueda': 'Otro Cancion B'},
        ],
      });
      expect(l.plataforma, 'Spotify');
      expect(l.total, 2);
      expect(l.canciones.first.busqueda, 'Alguien Cancion A');
      // sin enlace exacto: habra que buscarla
      expect(l.canciones.first.url, isEmpty);
    });

    test('las de YouTube si traen el enlace exacto', () {
      final l = ListaImportada.desdeJson({
        'titulo': 'Lista YT',
        'plataforma': 'YouTube',
        'canciones': [
          {'titulo': 'Video', 'url': 'https://youtu.be/abc', 'artista': 'Canal'},
        ],
      });
      expect(l.canciones.single.url, 'https://youtu.be/abc');
    });

    test('una lista vacia no rompe nada', () {
      final l = ListaImportada.desdeJson({});
      expect(l.total, 0);
      expect(l.titulo, isEmpty);
    });
  });

  group('estados de descarga', () {
    test('solo cuentan como activos los que están en marcha', () {
      expect(EstadoDescarga.descargando.activa, isTrue);
      expect(EstadoDescarga.preparando.activa, isTrue);
      expect(EstadoDescarga.enCola.activa, isTrue);
      expect(EstadoDescarga.completada.activa, isFalse);
      expect(EstadoDescarga.pausada.activa, isFalse);
      expect(EstadoDescarga.error.activa, isFalse);
    });
  });
}
