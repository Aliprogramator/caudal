/// Reconoce, solo mirando la dirección, si lo que hay en pantalla es un video
/// o una canción que se puede descargar.
///
/// Sirve para enseñar los botones al instante, sin esperar al servidor. Luego el
/// servidor confirma y añade el título y la miniatura.
library;

/// Patrones por sitio: dominio -> rutas que corresponden a una publicación.
final _reglas = <_Regla>[
  // --- YouTube
  _Regla(['youtube.com', 'm.youtube.com', 'music.youtube.com'], [
    RegExp(r'^/watch'),
    RegExp(r'^/shorts/[\w-]+'),
    RegExp(r'^/live/[\w-]+'),
    RegExp(r'^/embed/[\w-]+'),
    RegExp(r'^/playlist'),
  ]),
  _Regla(['youtu.be'], [RegExp(r'^/[\w-]{5,}')]),

  // --- Instagram
  _Regla(['instagram.com'], [
    RegExp(r'^/reel(s)?/[\w-]+'),
    RegExp(r'^/p/[\w-]+'),
    RegExp(r'^/tv/[\w-]+'),
    RegExp(r'^/[\w.]+/reel(s)?/[\w-]+'),
  ]),

  // --- TikTok
  _Regla(['tiktok.com'], [
    RegExp(r'^/@[\w.-]+/video/\d+'),
    RegExp(r'^/v/\d+'),
    RegExp(r'^/t/\w+'),
  ]),
  _Regla(['vm.tiktok.com', 'vt.tiktok.com'], [RegExp(r'^/\w+')]),

  // --- X / Twitter
  _Regla(['twitter.com', 'x.com'], [RegExp(r'^/[\w]+/status/\d+')]),

  // --- Facebook
  _Regla(['facebook.com', 'm.facebook.com'], [
    RegExp(r'^/watch'),
    RegExp(r'^/reel/\d+'),
    RegExp(r'^/[\w.]+/videos/'),
    RegExp(r'^/video'),
  ]),
  _Regla(['fb.watch'], [RegExp(r'^/\w+')]),

  // --- Otras redes y plataformas de video
  _Regla(['twitch.tv'], [RegExp(r'^/videos/\d+'), RegExp(r'^/\w+/clip/')]),
  _Regla(['clips.twitch.tv'], [RegExp(r'^/\w+')]),
  _Regla(['vimeo.com'], [RegExp(r'^/\d+')]),
  _Regla(['dailymotion.com'], [RegExp(r'^/video/\w+')]),
  _Regla(['dai.ly'], [RegExp(r'^/\w+')]),
  _Regla(['reddit.com'], [RegExp(r'/comments/\w+')]),
  _Regla(['v.redd.it', 'redd.it'], [RegExp(r'^/\w+')]),
  _Regla(['kick.com'], [RegExp(r'^/\w+/videos/'), RegExp(r'^/video/')]),
  _Regla(['rumble.com'], [RegExp(r'^/v\w+')]),
  _Regla(['odysee.com'], [RegExp(r'^/@?[^/]+/[^/]+')]),
  _Regla(['bilibili.com'], [RegExp(r'^/video/\w+')]),
  _Regla(['b23.tv'], [RegExp(r'^/\w+')]),
  _Regla(['nicovideo.jp'], [RegExp(r'^/watch/\w+')]),
  _Regla(['vk.com', 'vkvideo.ru'], [RegExp(r'^/video')]),
  _Regla(['ok.ru'], [RegExp(r'^/video/\d+')]),
  _Regla(['bsky.app'], [RegExp(r'^/profile/[^/]+/post/\w+')]),
  _Regla(['threads.net', 'threads.com'], [RegExp(r'^/@[\w.]+/post/\w+')]),
  _Regla(['snapchat.com'], [RegExp(r'^/spotlight/\w+')]),
  _Regla(['pinterest.com', 'pinterest.es'], [RegExp(r'^/pin/\d+')]),
  _Regla(['pin.it'], [RegExp(r'^/\w+')]),
  _Regla(['streamable.com'], [RegExp(r'^/\w+')]),
  _Regla(['9gag.com'], [RegExp(r'^/gag/\w+')]),
  _Regla(['imgur.com'], [RegExp(r'^/gallery/\w+'), RegExp(r'^/a/\w+')]),
  _Regla(['coub.com'], [RegExp(r'^/view/\w+')]),
  _Regla(['ted.com'], [RegExp(r'^/talks/\w+')]),
  _Regla(['tumblr.com'], [RegExp(r'/post/\d+')]),
  _Regla(['linkedin.com'], [RegExp(r'^/posts/')]),
  _Regla(['weibo.com'], [RegExp(r'^/tv/'), RegExp(r'^/\d+/\w+')]),
  _Regla(['douyin.com'], [RegExp(r'^/video/\d+')]),
  _Regla(['xiaohongshu.com'], [RegExp(r'^/explore/\w+')]),
  _Regla(['newgrounds.com'], [RegExp(r'^/portal/view/\d+')]),
  _Regla(['archive.org'], [RegExp(r'^/details/')]),

  // --- Audio
  _Regla(['soundcloud.com'], [RegExp(r'^/[^/]+/[^/]+')]),
  _Regla(['on.soundcloud.com', 'snd.sc'], [RegExp(r'^/\w+')]),
  _Regla(['bandcamp.com'], [RegExp(r'^/track/'), RegExp(r'^/album/')]),
  _Regla(['mixcloud.com'], [RegExp(r'^/[^/]+/[^/]+')]),
];

class _Regla {
  const _Regla(this.dominios, this.rutas);
  final List<String> dominios;
  final List<RegExp> rutas;
}

/// Extensiones de archivo que ya son un medio directo.
final _extensionesMedia = RegExp(
  r'\.(mp4|m4v|mov|mkv|webm|avi|flv|m3u8|mpd|mp3|m4a|aac|ogg|opus|flac|wav)(\?|$)',
  caseSensitive: false,
);

/// ¿Esta dirección apunta a algo que se pueda descargar?
bool pareceDescargable(String url) {
  if (url.isEmpty) return false;

  final Uri uri;
  try {
    uri = Uri.parse(url);
  } on FormatException {
    return false;
  }
  if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) return false;

  // un enlace directo a un archivo de video o audio siempre vale
  if (_extensionesMedia.hasMatch(uri.path)) return true;

  var host = uri.host.toLowerCase();
  if (host.startsWith('www.')) host = host.substring(4);

  final ruta = uri.path.isEmpty ? '/' : uri.path;

  for (final regla in _reglas) {
    final coincideDominio = regla.dominios.any((d) => host == d || host.endsWith('.$d'));
    if (!coincideDominio) continue;
    for (final patron in regla.rutas) {
      if (patron.hasMatch(ruta)) return true;
    }
    // el dominio es de los buenos pero la ruta no: es una portada o un perfil
    return false;
  }
  return false;
}

/// Sitios donde solo hay sonido: ahí el botón de audio va primero.
bool esSitioDeAudio(String url) {
  try {
    var host = Uri.parse(url).host.toLowerCase();
    if (host.startsWith('www.')) host = host.substring(4);
    const soloAudio = [
      'music.youtube.com',
      'soundcloud.com',
      'on.soundcloud.com',
      'snd.sc',
      'bandcamp.com',
      'mixcloud.com',
    ];
    return soloAudio.any((d) => host == d || host.endsWith('.$d'));
  } on FormatException {
    return false;
  }
}
