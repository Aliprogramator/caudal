// Leer listas de Spotify, Apple Music y YouTube desde el propio telefono.
//
// De Spotify y Apple no se baja nada: sus archivos van cifrados y no se pueden
// convertir. Lo que se hace es leer que canciones tiene la lista y despues
// buscar cada una en YouTube, que es de donde sale el audio.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'modelos.dart';

/// Lo que se puede leer de cada sitio, para contarselo al usuario.
const int topeSpotifyEmbed = 50;

Dio _cliente() => Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 25),
      responseType: ResponseType.plain,
      validateStatus: (c) => c != null && c < 500,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/126.0 Safari/537.36',
        'Accept-Language': 'es-ES,es;q=0.9,en;q=0.8',
      },
    ));

/// Lee una lista de donde sea. Lanza [ErrorCaudal] con algo que se pueda leer.
Future<ListaImportada> leerLista(String url) async {
  final u = url.trim();
  if (u.isEmpty) throw ErrorCaudal('Pega el enlace de una lista.');

  final bajo = u.toLowerCase();
  if (bajo.contains('spotify.com')) return _spotify(u);
  if (bajo.contains('music.apple.com')) return _apple(u);
  if (bajo.contains('youtube.com') || bajo.contains('youtu.be')) {
    return _youtube(u);
  }
  throw ErrorCaudal(
    'Ese enlace no es de Spotify, Apple Music ni YouTube. Copia el enlace de '
    'la lista desde la propia aplicacion.',
  );
}

// ----------------------------------------------------------------- Spotify

Future<ListaImportada> _spotify(String url) async {
  final id = RegExp(r'/(playlist|album)/([A-Za-z0-9]+)').firstMatch(url);
  if (id == null) {
    throw ErrorCaudal('Ese enlace de Spotify no es de una lista ni de un album.');
  }
  final tipo = id.group(1)!;
  final clave = id.group(2)!;

  // la pagina para incrustar trae las canciones en un JSON, sin pedir cuenta
  final r = await _cliente().get<String>('https://open.spotify.com/embed/$tipo/$clave');
  final html = r.data ?? '';
  final crudo = RegExp(r'<script id="__NEXT_DATA__"[^>]*>(.+?)</script>', dotAll: true)
      .firstMatch(html)
      ?.group(1);
  if (crudo == null) {
    throw ErrorCaudal(
      'No se pudo leer esa lista. Comprueba que sea publica: si es privada, '
      'Spotify no deja verla desde fuera.',
    );
  }

  try {
    final datos = jsonDecode(crudo) as Map<String, dynamic>;
    final entidad = (((datos['props'] as Map)['pageProps'] as Map)['state'] as Map)['data']
        as Map<String, dynamic>;
    final lista = entidad['entity'] as Map<String, dynamic>;

    final canciones = <CancionLista>[];
    for (final t in (lista['trackList'] as List? ?? [])) {
      final m = t as Map<String, dynamic>;
      final titulo = (m['title'] ?? '').toString();
      final artista = (m['subtitle'] ?? '').toString();
      if (titulo.isEmpty) continue;
      canciones.add(CancionLista(
        titulo: titulo,
        artista: artista,
        duracion: (((m['duration'] ?? 0) as num) / 1000).round(),
        busqueda: artista.isEmpty ? titulo : '$artista $titulo',
      ));
    }

    if (canciones.isEmpty) {
      throw ErrorCaudal('Esa lista de Spotify aparece vacia.');
    }

    return ListaImportada(
      titulo: (lista['name'] ?? 'Lista de Spotify').toString(),
      plataforma: 'Spotify',
      autor: ((lista['subtitle'] ?? '')).toString(),
      portada: _portadaSpotify(lista),
      canciones: canciones,
    );
  } on ErrorCaudal {
    rethrow;
  } catch (_) {
    throw ErrorCaudal('Spotify cambio el formato de sus paginas y no se pudo leer.');
  }
}

String _portadaSpotify(Map<String, dynamic> lista) {
  try {
    final imagenes = (lista['coverArt'] as Map?)?['sources'] as List?;
    if (imagenes != null && imagenes.isNotEmpty) {
      return ((imagenes.last as Map)['url'] ?? '').toString();
    }
  } catch (_) {
    // sin portada tampoco pasa nada
  }
  return '';
}

// ------------------------------------------------------------- Apple Music

Future<ListaImportada> _apple(String url) async {
  final r = await _cliente().get<String>(url);
  final html = r.data ?? '';

  final crudo = RegExp(
    r'<script[^>]+id="serialized-server-data"[^>]*>(.+?)</script>',
    dotAll: true,
  ).firstMatch(html)?.group(1);
  if (crudo == null) {
    throw ErrorCaudal(
      'No se pudo leer esa lista de Apple Music. Comprueba que el enlace sea '
      'publico.',
    );
  }

  final tituloLista = _metaApple(html, 'og:title');

  try {
    final canciones = <CancionLista>[];
    final vistas = <String>{};

    // el JSON viene muy anidado y cambia de forma: buscamos los pares de
    // titulo y artista alla donde esten
    void recorrer(dynamic nodo) {
      if (nodo is Map) {
        final titulo = (nodo['title'] ?? nodo['name'] ?? '').toString();
        final artista =
            (nodo['subtitleLinks'] is List && (nodo['subtitleLinks'] as List).isNotEmpty)
                ? ((nodo['subtitleLinks'] as List).first as Map)['title'].toString()
                : (nodo['artistName'] ?? nodo['subtitle'] ?? '').toString();

        // el titulo de la propia lista no es una cancion
        final esCabecera =
            tituloLista.isNotEmpty && titulo.toLowerCase() == tituloLista.toLowerCase();
        final clave = '$titulo|$artista';
        if (titulo.isNotEmpty && artista.isNotEmpty && !esCabecera && vistas.add(clave)) {
          canciones.add(CancionLista(
            titulo: titulo,
            artista: artista,
            busqueda: '$artista $titulo',
          ));
        }
        for (final v in nodo.values) {
          recorrer(v);
        }
      } else if (nodo is List) {
        for (final v in nodo) {
          recorrer(v);
        }
      }
    }

    recorrer(jsonDecode(crudo));

    if (canciones.isEmpty) {
      throw ErrorCaudal('No se encontraron canciones en esa lista de Apple Music.');
    }

    return ListaImportada(
      titulo: tituloLista.isEmpty ? 'Lista de Apple Music' : tituloLista,
      plataforma: 'Apple Music',
      portada: _metaApple(html, 'og:image'),
      canciones: canciones,
    );
  } on ErrorCaudal {
    rethrow;
  } catch (_) {
    throw ErrorCaudal('Apple Music cambio el formato de sus paginas y no se pudo leer.');
  }
}

String _metaApple(String html, String propiedad) {
  final m = RegExp(
    '<meta[^>]+property=["\']$propiedad["\'][^>]+content=["\']([^"\']+)["\']',
    caseSensitive: false,
  ).firstMatch(html);
  return (m?.group(1) ?? '')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
}

// ----------------------------------------------------------------- YouTube

Future<ListaImportada> _youtube(String url) async {
  final yt = YoutubeExplode();
  try {
    final lista = await yt.playlists.get(url);
    final canciones = <CancionLista>[];

    // aqui no hay tope: se leen todos los videos que tenga
    await for (final v in yt.playlists.getVideos(lista.id)) {
      canciones.add(CancionLista(
        titulo: v.title,
        artista: v.author,
        duracion: v.duration?.inSeconds ?? 0,
        url: 'https://www.youtube.com/watch?v=${v.id.value}',
        miniatura: v.thumbnails.mediumResUrl,
      ));
    }

    if (canciones.isEmpty) {
      throw ErrorCaudal('Esa lista de YouTube aparece vacia o es privada.');
    }

    return ListaImportada(
      titulo: lista.title,
      plataforma: 'YouTube',
      autor: lista.author,
      canciones: canciones,
    );
  } on ErrorCaudal {
    rethrow;
  } catch (_) {
    throw ErrorCaudal(
      'No se pudo leer esa lista de YouTube. Comprueba que el enlace sea de una '
      'lista publica.',
    );
  } finally {
    yt.close();
  }
}
