/// Utilidades de presentación: tamaños, tiempos y textos.
library;

String formatoBytes(num bytes) {
  var n = bytes.toDouble();
  const unidades = ['B', 'KB', 'MB', 'GB', 'TB'];
  var i = 0;
  while (n >= 1024 && i < unidades.length - 1) {
    n /= 1024;
    i++;
  }
  if (i == 0) return '${n.round()} B';
  return '${n.toStringAsFixed(n >= 100 ? 0 : 1)} ${unidades[i]}';
}

String formatoVelocidad(num bytesPorSegundo) => '${formatoBytes(bytesPorSegundo)}/s';

String formatoDuracion(Duration d) {
  final horas = d.inHours;
  final minutos = d.inMinutes.remainder(60);
  final segundos = d.inSeconds.remainder(60);
  final mm = minutos.toString().padLeft(horas > 0 ? 2 : 1, '0');
  final ss = segundos.toString().padLeft(2, '0');
  return horas > 0 ? '$horas:$mm:$ss' : '$mm:$ss';
}

String formatoSegundos(int segundos) => formatoDuracion(Duration(seconds: segundos));

/// "quedan 2 min", pensado para leerse de un vistazo.
String formatoRestante(int segundos) {
  if (segundos <= 0) return '';
  if (segundos < 60) return 'quedan ${segundos}s';
  if (segundos < 3600) return 'quedan ${(segundos / 60).ceil()} min';
  final horas = segundos ~/ 3600;
  return 'quedan ${horas}h ${((segundos % 3600) / 60).round()} min';
}

String formatoVistas(int vistas) {
  if (vistas <= 0) return '';
  if (vistas < 1000) return '$vistas vistas';
  if (vistas < 1000000) return '${(vistas / 1000).toStringAsFixed(vistas < 10000 ? 1 : 0)} mil vistas';
  return '${(vistas / 1000000).toStringAsFixed(vistas < 10000000 ? 1 : 0)} M de vistas';
}

String formatoFecha(int milisegundos) {
  if (milisegundos <= 0) return '';
  final fecha = DateTime.fromMillisecondsSinceEpoch(milisegundos);
  final ahora = DateTime.now();
  final diferencia = ahora.difference(fecha);

  if (diferencia.inMinutes < 1) return 'hace un momento';
  if (diferencia.inMinutes < 60) return 'hace ${diferencia.inMinutes} min';
  if (diferencia.inHours < 24) return 'hace ${diferencia.inHours} h';
  if (diferencia.inDays == 1) return 'ayer';
  if (diferencia.inDays < 7) return 'hace ${diferencia.inDays} días';

  const meses = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
  ];
  final mes = meses[fecha.month - 1];
  return fecha.year == ahora.year
      ? '${fecha.day} $mes'
      : '${fecha.day} $mes ${fecha.year}';
}

/// Deja un nombre de archivo utilizable en Android y en iOS.
String nombreSeguro(String nombre, {int limite = 90}) {
  var limpio = nombre
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  while (limpio.endsWith('.') || limpio.endsWith(' ')) {
    limpio = limpio.substring(0, limpio.length - 1);
  }
  if (limpio.length > limite) limpio = limpio.substring(0, limite).trim();
  return limpio.isEmpty ? 'descarga' : limpio;
}

/// Detecta si un texto es un enlace, con o sin esquema.
bool pareceEnlace(String texto) {
  final t = texto.trim();
  if (t.isEmpty || t.contains(' ') || t.contains('\n')) return false;
  if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(t)) return true;
  return RegExp(r'^[\w-]+(\.[\w-]+)+(/|$|\?)').hasMatch(t);
}

String normalizarEnlace(String texto) {
  var t = texto.trim();
  if (t.isEmpty) return '';
  if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(t)) t = 'https://$t';
  return t;
}

/// Nombre corto del sitio, para mostrarlo como etiqueta.
String sitioDe(String url) {
  try {
    var host = Uri.parse(normalizarEnlace(url)).host.toLowerCase();
    if (host.startsWith('www.')) host = host.substring(4);
    if (host.startsWith('m.')) host = host.substring(2);
    const conocidos = {
      'youtube.com': 'YouTube',
      'youtu.be': 'YouTube',
      'music.youtube.com': 'YouTube Music',
      'instagram.com': 'Instagram',
      'tiktok.com': 'TikTok',
      'twitter.com': 'X',
      'x.com': 'X',
      'facebook.com': 'Facebook',
      'fb.watch': 'Facebook',
      'soundcloud.com': 'SoundCloud',
      'twitch.tv': 'Twitch',
      'vimeo.com': 'Vimeo',
      'reddit.com': 'Reddit',
      'dailymotion.com': 'Dailymotion',
      'bandcamp.com': 'Bandcamp',
      'pinterest.com': 'Pinterest',
    };
    for (final entrada in conocidos.entries) {
      if (host == entrada.key || host.endsWith('.${entrada.key}')) return entrada.value;
    }
    return host;
  } catch (_) {
    return 'enlace';
  }
}
