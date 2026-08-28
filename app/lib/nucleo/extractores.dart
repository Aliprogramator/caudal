// Sacar la direccion real del video de cada red, dentro del propio telefono.
//
// YouTube lo resuelve youtube_explode_dart. El resto de sitios no tienen una
// libreria que lo haga, asi que se lee la propia pagina y se busca donde
// guardan la direccion del archivo. Cada red lo guarda a su manera.
//
// Esto depende de como esten hechas las paginas hoy: si una red cambia su
// formato, deja de encontrarlo y hay que ajustar el patron. Por eso al final
// hay una busqueda generica que funciona con casi cualquier sitio.

import 'dart:convert';

import 'package:dio/dio.dart';

/// Lo que se saca de una pagina: donde esta el video y como se llama.
class MedioHallado {
  const MedioHallado({
    required this.url,
    this.titulo = '',
    this.autor = '',
    this.miniatura = '',
    this.audio = '',
    this.duracion = 0,
  });

  /// Direccion del video (o del audio, si el sitio los sirve por separado).
  final String url;
  final String titulo;
  final String autor;
  final String miniatura;

  /// Algunas redes sirven el sonido aparte. Vacio = el video ya lo lleva.
  final String audio;
  final int duracion;

  bool get vale => url.isNotEmpty;
}

/// Un navegador de escritorio: muchas redes esconden el video a los moviles.
const _navegador =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/126.0 Safari/537.36';

Dio _cliente({Map<String, String>? extra}) {
  final d = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 25),
    followRedirects: true,
    maxRedirects: 6,
    responseType: ResponseType.plain,
    // los errores los miramos nosotros: muchas redes responden 4xx con el
    // contenido dentro igualmente
    validateStatus: (c) => c != null && c < 500,
    headers: {
      'User-Agent': _navegador,
      'Accept-Language': 'es-ES,es;q=0.9,en;q=0.8',
    },
  ));
  if (extra != null) d.options.headers.addAll(extra);
  return d;
}

/// Decide que extractor toca por la direccion.
Future<MedioHallado?> extraer(String url) async {
  final u = url.toLowerCase();
  try {
    if (u.contains('instagram.com')) return await _instagram(url);
    if (u.contains('tiktok.com')) return await _tiktok(url);
    if (u.contains('twitter.com') || u.contains('x.com')) return await _twitter(url);
    if (u.contains('facebook.com') || u.contains('fb.watch')) return await _facebook(url);
    return await _generico(url);
  } catch (_) {
    // si el extractor propio falla, probamos la busqueda generica antes de
    // rendirnos: a veces la pagina expone el video en sus etiquetas
    try {
      return await _generico(url);
    } catch (_) {
      return null;
    }
  }
}

// --------------------------------------------------------------- utilidades

String _limpiar(String s) =>
    s.replaceAll(r'\/', '/').replaceAll(r'\"', '"').replaceAll(r'&', '&').trim();

/// Primer grupo que capture el patron, ya limpio.
String _buscar(String texto, RegExp patron, {int grupo = 1}) {
  final m = patron.firstMatch(texto);
  return m == null ? '' : _limpiar(m.group(grupo) ?? '');
}

String _desescaparHtml(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>');

/// Contenido de una etiqueta meta, la busque por property o por name y este
/// el content antes o despues.
String _meta(String html, String propiedad) {
  final comilla = r'''["']''';
  for (final atributo in ['property', 'name']) {
    final directo = RegExp(
      '<meta[^>]+$atributo=$comilla$propiedad$comilla[^>]+content=$comilla([^"\']+)$comilla',
      caseSensitive: false,
    );
    var r = _buscar(html, directo);
    if (r.isNotEmpty) return _desescaparHtml(r);

    final alReves = RegExp(
      '<meta[^>]+content=$comilla([^"\']+)$comilla[^>]+$atributo=$comilla$propiedad$comilla',
      caseSensitive: false,
    );
    r = _buscar(html, alReves);
    if (r.isNotEmpty) return _desescaparHtml(r);
  }
  return '';
}

// --------------------------------------------------------------- Instagram

Future<MedioHallado?> _instagram(String url) async {
  final html = (await _cliente().get<String>(url)).data ?? '';

  // la direccion del video aparece en el JSON que la pagina trae dentro
  var video = _buscar(html, RegExp(r'"video_url":"([^"]+)"'));
  if (video.isEmpty) video = _buscar(html, RegExp(r'"playback_url":"([^"]+)"'));
  if (video.isEmpty) video = _meta(html, 'og:video');
  if (video.isEmpty) video = _meta(html, 'og:video:secure_url');
  if (video.isEmpty) return null;

  final autor = _buscar(html, RegExp(r'"username":"([^"]+)"'));
  var titulo = _meta(html, 'og:title');
  if (titulo.isEmpty) titulo = autor.isEmpty ? 'Instagram' : 'Instagram - $autor';

  return MedioHallado(
    url: video,
    titulo: titulo,
    autor: autor,
    miniatura: _meta(html, 'og:image'),
  );
}

// ------------------------------------------------------------------ TikTok

Future<MedioHallado?> _tiktok(String url) async {
  final html = (await _cliente().get<String>(url)).data ?? '';

  // TikTok deja todos los datos en un JSON dentro de la propia pagina
  final crudo = _buscar(
    html,
    RegExp(
      r'<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__"[^>]*>(.+?)</script>',
      dotAll: true,
    ),
  );

  if (crudo.isNotEmpty) {
    try {
      final datos = jsonDecode(crudo) as Map<String, dynamic>;
      final escena = datos['__DEFAULT_SCOPE__'] as Map<String, dynamic>?;
      final detalle = escena?['webapp.video-detail'] as Map<String, dynamic>?;
      final item = (detalle?['itemInfo'] as Map<String, dynamic>?)?['itemStruct']
          as Map<String, dynamic>?;
      if (item != null) {
        final video = item['video'] as Map<String, dynamic>?;
        final directo = (video?['playAddr'] ?? video?['downloadAddr'] ?? '').toString();
        if (directo.isNotEmpty) {
          final autor = (item['author'] as Map<String, dynamic>?)?['uniqueId'] ?? '';
          final dur = video?['duration'];
          return MedioHallado(
            url: _limpiar(directo),
            titulo: (item['desc'] ?? 'TikTok').toString(),
            autor: autor.toString(),
            miniatura: (video?['cover'] ?? '').toString(),
            duracion: dur is int ? dur : 0,
          );
        }
      }
    } catch (_) {
      // seguimos con los patrones de abajo
    }
  }

  var video = _buscar(html, RegExp(r'"playAddr":"([^"]+)"'));
  if (video.isEmpty) video = _meta(html, 'og:video');
  if (video.isEmpty) return null;

  final titulo = _meta(html, 'og:title');
  return MedioHallado(
    url: video,
    titulo: titulo.isEmpty ? 'TikTok' : titulo,
    miniatura: _meta(html, 'og:image'),
  );
}

// ---------------------------------------------------------------- X/Twitter

/// Clave publica que usa la propia web de X para sus llamadas.
const _claveX =
    'Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7'
    'ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA';

Future<MedioHallado?> _twitter(String url) async {
  final id = _buscar(url, RegExp(r'/status/(\d+)'));
  if (id.isEmpty) return null;

  final dio = _cliente(extra: {'Authorization': _claveX});

  // X exige identificarse como visitante antes de dejar consultar nada
  final activar =
      await dio.post<String>('https://api.twitter.com/1.1/guest/activate.json');
  final invitado = _buscar(activar.data ?? '', RegExp(r'"guest_token":"(\d+)"'));
  if (invitado.isEmpty) return null;

  final r = await dio.get<String>(
    'https://api.twitter.com/1.1/statuses/show/$id.json',
    queryParameters: {'tweet_mode': 'extended', 'include_entities': 'true'},
    options: Options(headers: {'x-guest-token': invitado}),
  );

  try {
    final t = jsonDecode(r.data ?? '{}') as Map<String, dynamic>;
    final entidades =
        (t['extended_entities'] ?? t['entities']) as Map<String, dynamic>?;
    final medios = entidades?['media'] as List?;
    if (medios == null || medios.isEmpty) return null;

    final primero = medios.first as Map<String, dynamic>;
    final info = primero['video_info'] as Map<String, dynamic>?;
    final variantes = (info?['variants'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .where((v) => (v['content_type'] ?? '') == 'video/mp4')
        .toList()
      ..sort((a, b) =>
          ((b['bitrate'] ?? 0) as int).compareTo((a['bitrate'] ?? 0) as int));
    if (variantes.isEmpty) return null;

    final autor = (t['user'] as Map<String, dynamic>?)?['screen_name'] ?? '';
    final milis = (info?['duration_millis'] ?? 0) as int;
    return MedioHallado(
      url: (variantes.first['url'] ?? '').toString(),
      titulo: (t['full_text'] ?? t['text'] ?? 'X').toString(),
      autor: autor.toString(),
      miniatura: (primero['media_url_https'] ?? '').toString(),
      duracion: (milis / 1000).round(),
    );
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------- Facebook

Future<MedioHallado?> _facebook(String url) async {
  final html = (await _cliente().get<String>(url)).data ?? '';

  // Facebook guarda la buena calidad en hd y la normal en sd
  var video = _buscar(html, RegExp(r'"browser_native_hd_url":"([^"]+)"'));
  if (video.isEmpty) {
    video = _buscar(html, RegExp(r'"hd_src(?:_no_ratelimit)?":"([^"]+)"'));
  }
  if (video.isEmpty) {
    video = _buscar(html, RegExp(r'"browser_native_sd_url":"([^"]+)"'));
  }
  if (video.isEmpty) {
    video = _buscar(html, RegExp(r'"sd_src(?:_no_ratelimit)?":"([^"]+)"'));
  }
  if (video.isEmpty) video = _meta(html, 'og:video');
  if (video.isEmpty) return null;

  final titulo = _meta(html, 'og:title');
  return MedioHallado(
    url: video,
    titulo: titulo.isEmpty ? 'Facebook' : titulo,
    miniatura: _meta(html, 'og:image'),
  );
}

// ----------------------------------------------------------------- generico

/// Para cualquier otro sitio: casi todos anuncian su video en las etiquetas
/// que usan para las vistas previas de WhatsApp o Twitter.
Future<MedioHallado?> _generico(String url) async {
  final html = (await _cliente().get<String>(url)).data ?? '';

  var video = _meta(html, 'og:video:secure_url');
  if (video.isEmpty) video = _meta(html, 'og:video:url');
  if (video.isEmpty) video = _meta(html, 'og:video');
  if (video.isEmpty) video = _meta(html, 'twitter:player:stream');

  // ultimo recurso: un video o un source dentro del propio HTML
  if (video.isEmpty) {
    video = _buscar(html, RegExp(r'''<video[^>]+src=["']([^"']+\.mp4[^"']*)'''));
  }
  if (video.isEmpty) {
    video = _buscar(html, RegExp(r'''<source[^>]+src=["']([^"']+\.mp4[^"']*)'''));
  }
  if (video.isEmpty) return null;

  // las direcciones relativas hay que completarlas
  if (video.startsWith('/')) {
    final base = Uri.parse(url);
    video = '${base.scheme}://${base.host}$video';
  }

  return MedioHallado(
    url: video,
    titulo: _meta(html, 'og:title'),
    miniatura: _meta(html, 'og:image'),
  );
}
