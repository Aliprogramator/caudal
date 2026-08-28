import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'formato.dart';
import 'modelos.dart';

/// Descarga dentro del teléfono. Todo lo que baja Caudal pasa por aquí.
///
/// Hay dos caminos. YouTube y YouTube Music se resuelven con
/// youtube_explode_dart, que da la mejor calidad y el sonido por separado.
/// El resto de sitios se descargan de la dirección que el navegador vio pasar
/// mientras la página reproducía el video: ver [captura.dart].
class MotorLocal {
  MotorLocal();

  final YoutubeExplode _yt = YoutubeExplode();

  /// ¿Este enlace lo resuelve YouTube por su cuenta, sin mirar la página?
  static bool puedeSolo(String url) {
    final u = url.toLowerCase();
    return u.contains('youtube.com') || u.contains('youtu.be') ||
        u.contains('music.youtube.com');
  }

  /// Datos del video sin descargar nada.
  Future<Ficha> resolver(String url) async {
    final video = await _yt.videos.get(url);
    final manifiesto = await _yt.videos.streamsClient.getManifest(video.id);

    final alturas = <int>{};
    for (final s in manifiesto.videoOnly) {
      final alto = s.videoResolution.height;
      if (alto > 0) alturas.add(alto);
    }
    for (final s in manifiesto.muxed) {
      final alto = s.videoResolution.height;
      if (alto > 0) alturas.add(alto);
    }

    final calidades = alturas.toList()..sort((a, b) => b.compareTo(a));
    const nombres = {
      4320: '8K', 2160: '4K', 1440: '2K', 1080: 'Full HD', 720: 'HD',
      480: 'SD', 360: 'Ligero',
    };

    return Ficha(
      url: video.url,
      titulo: video.title,
      autor: video.author,
      miniatura: video.thumbnails.highResUrl,
      duracion: video.duration?.inSeconds ?? 0,
      duracionTexto: formatoSegundos(video.duration?.inSeconds ?? 0),
      plataforma: 'YouTube',
      tieneVideo: calidades.isNotEmpty,
      tieneAudio: manifiesto.audioOnly.isNotEmpty || manifiesto.muxed.isNotEmpty,
      calidades: [
        for (final alto in calidades)
          Calidad(
            valor: '$alto',
            etiqueta: nombres[alto] != null ? '${nombres[alto]} · ${alto}p' : '${alto}p',
            altura: alto,
          ),
      ],
    );
  }

  /// Descarga y deja el archivo listo. Devuelve la ruta final.
  ///
  /// [alProgresar] recibe 0..100 y una etiqueta de la fase.
  Future<String> descargar({
    required String url,
    required TipoMedio tipo,
    required String calidad,
    required String formatoAudio,
    required Directory carpeta,
    required void Function(double, String) alProgresar,
    required bool Function() cancelado,
    bool reforzarAudio = false,
  }) async {
    alProgresar(0, 'Buscando el video');
    final video = await _yt.videos.get(url);
    final manifiesto = await _yt.videos.streamsClient.getManifest(video.id);
    final nombre = nombreSeguro(video.title);

    if (tipo == TipoMedio.audio) {
      return _soloAudio(manifiesto, nombre, formatoAudio, carpeta,
          alProgresar, cancelado, reforzarAudio);
    }
    return _conVideo(manifiesto, nombre, calidad, tipo, carpeta,
        alProgresar, cancelado);
  }

  // ---------------------------------------------------------------- audio

  Future<String> _soloAudio(
    StreamManifest manifiesto,
    String nombre,
    String formatoAudio,
    Directory carpeta,
    void Function(double, String) alProgresar,
    bool Function() cancelado,
    bool reforzar,
  ) async {
    final pista = manifiesto.audioOnly.withHighestBitrate();
    final crudo = File(p.join(carpeta.path, '$nombre.${pista.container.name}'));

    await _bajarPista(pista, crudo, alProgresar, cancelado,
        desde: 0, hasta: reforzar || formatoAudio != 'm4a' ? 80 : 100,
        etiqueta: 'Descargando el audio');

    // m4a sin refuerzo ya sirve tal cual: nos ahorramos convertir
    if (formatoAudio == 'm4a' && !reforzar) {
      final destino = _libre(carpeta, nombre, 'm4a');
      await crudo.rename(destino);
      return destino;
    }

    alProgresar(85, 'Convirtiendo a ${formatoAudio.toUpperCase()}');
    final destino = _libre(carpeta, nombre, formatoAudio);
    final filtro = reforzar ? '-af loudnorm=I=-9:TP=-1.0:LRA=9 ' : '';
    final calidad = formatoAudio == 'mp3' ? '-b:a 192k ' : '';
    final ok = await _ffmpeg(
        '-y -i "${crudo.path}" $filtro$calidad-vn "$destino"');
    await _borrar(crudo);
    if (!ok) {
      throw Exception('No se pudo convertir el audio en el teléfono.');
    }
    alProgresar(100, 'Listo');
    return destino;
  }

  // ---------------------------------------------------------------- video

  Future<String> _conVideo(
    StreamManifest manifiesto,
    String nombre,
    String calidad,
    TipoMedio tipo,
    Directory carpeta,
    void Function(double, String) alProgresar,
    bool Function() cancelado,
  ) async {
    final tope = int.tryParse(calidad) ?? 0;

    // la pista de imagen que mejor encaje con la calidad pedida
    final candidatas = manifiesto.videoOnly.sortByVideoQuality();
    VideoOnlyStreamInfo? elegida;
    for (final s in candidatas) {
      if (tope == 0 || s.videoResolution.height <= tope) {
        elegida = s;
        break;
      }
    }
    elegida ??= candidatas.isNotEmpty ? candidatas.first : null;

    if (elegida == null) {
      throw Exception('Ese video no tiene ninguna pista de imagen descargable.');
    }

    final soloImagen = tipo == TipoMedio.video;
    final destino = _libre(carpeta, nombre, 'mp4');

    final video = File(p.join(carpeta.path, '.$nombre.video'));
    await _bajarPista(elegida, video, alProgresar, cancelado,
        desde: 0, hasta: soloImagen ? 80 : 55,
        etiqueta: 'Descargando el video');

    if (soloImagen) {
      alProgresar(85, 'Preparando el archivo');
      final ok = await _ffmpeg('-y -i "${video.path}" -c copy -an "$destino"');
      await _borrar(video);
      if (!ok) throw Exception('No se pudo preparar el video en el teléfono.');
      alProgresar(100, 'Listo');
      return destino;
    }

    final pistaAudio = manifiesto.audioOnly.withHighestBitrate();
    final audio = File(p.join(carpeta.path, '.$nombre.audio'));
    await _bajarPista(pistaAudio, audio, alProgresar, cancelado,
        desde: 55, hasta: 88, etiqueta: 'Descargando el audio');

    // YouTube ya no sirve video y audio juntos: hay que unirlos aquí
    alProgresar(90, 'Uniendo imagen y sonido');
    final ok = await _ffmpegContando(
      '-y -i "${video.path}" -i "${audio.path}" -c copy -shortest "$destino"',
      alProgresar: alProgresar,
      cancelado: cancelado,
      desde: 90,
      hasta: 99,
      etiqueta: 'Uniendo imagen y sonido',
    );
    await _borrar(video);
    await _borrar(audio);
    if (!ok) {
      throw Exception('No se pudo unir el video con su audio en el teléfono.');
    }

    alProgresar(100, 'Listo');
    return destino;
  }

  // ---------------------------------------------------------------- apoyo

  Future<void> _bajarPista(
    StreamInfo pista,
    File destino,
    void Function(double, String) alProgresar,
    bool Function() cancelado, {
    required double desde,
    required double hasta,
    required String etiqueta,
  }) async {
    final total = pista.size.totalBytes;
    var hecho = 0;
    final salida = destino.openWrite();

    try {
      await for (final trozo in _yt.videos.streamsClient.get(pista)) {
        if (cancelado()) {
          await salida.flush();
          await salida.close();
          await _borrar(destino);
          throw _Cancelado();
        }
        salida.add(trozo);
        hecho += trozo.length;
        if (total > 0) {
          alProgresar(desde + (hecho / total) * (hasta - desde), etiqueta);
        }
      }
      await salida.flush();
      await salida.close();
    } on _Cancelado {
      rethrow;
    } catch (e) {
      await salida.close();
      await _borrar(destino);
      rethrow;
    }
  }

  /// Busca en YouTube desde el propio telefono.
  Future<List<Resultado>> buscar(String texto, {int tope = 20}) async {
    final lista = await _yt.search.search(texto);
    return lista.take(tope).map((v) {
      final segundos = v.duration?.inSeconds ?? 0;
      return Resultado(
        url: 'https://www.youtube.com/watch?v=${v.id.value}',
        titulo: v.title,
        autor: v.author,
        miniatura: v.thumbnails.mediumResUrl,
        duracionTexto: segundos > 0 ? formatoSegundos(segundos) : '',
        vistas: v.engagement.viewCount,
      );
    }).toList();
  }

  // ------------------------------------------------- cualquier otro sitio

  /// Baja una dirección de video que el navegador vio pasar.
  ///
  /// Sirve para Instagram, TikTok, X, Facebook y en general cualquier página:
  /// da igual de dónde salga el archivo, aquí solo se trae y, si hace falta,
  /// se convierte. Devuelve la ruta del archivo guardado.
  Future<String> descargarMedio({
    required String urlMedia,
    required String titulo,
    required TipoMedio tipo,
    required String formatoAudio,
    required Directory carpeta,
    required void Function(double, String) alProgresar,
    required bool Function() cancelado,
    bool reforzarAudio = false,
    String referente = '',
  }) async {
    final nombre = nombreSeguro(titulo.isEmpty ? 'Caudal' : titulo);
    final soloAudio = tipo == TipoMedio.audio;
    final esListaDeTrozos = _esLista(urlMedia);

    // una lista de trozos no se baja de una: la arma ffmpeg
    if (esListaDeTrozos) {
      return _armarDesdeLista(
        urlMedia: urlMedia,
        nombre: nombre,
        soloAudio: soloAudio,
        formatoAudio: formatoAudio,
        carpeta: carpeta,
        alProgresar: alProgresar,
        cancelado: cancelado,
        reforzarAudio: reforzarAudio,
        referente: referente,
      );
    }

    final extensionOrigen = _extensionDe(urlMedia);
    final temporal = File(p.join(
      carpeta.path,
      '.caudal_${DateTime.now().millisecondsSinceEpoch}.$extensionOrigen',
    ));

    alProgresar(0, 'Descargando');
    await _bajarUrl(urlMedia, temporal, alProgresar, cancelado,
        desde: 0, hasta: soloAudio ? 70 : 96, referente: referente);

    // video tal cual: ya está
    if (!soloAudio) {
      final destino = _libre(carpeta, nombre, extensionOrigen);
      await temporal.rename(destino);
      alProgresar(100, 'Listo');
      return destino;
    }

    // solo sonido: se saca del archivo que acabamos de bajar
    alProgresar(72, 'Sacando el audio');
    final destino = _libre(carpeta, nombre, formatoAudio);
    final filtro = reforzarAudio ? '-af loudnorm=I=-9:TP=-1.0:LRA=9 ' : '';
    final codec = _codecDe(formatoAudio, reforzar: reforzarAudio);
    final ok = await _ffmpeg(
      '-y -i "${temporal.path}" -vn $filtro$codec "$destino"',
    );
    await _borrar(temporal);
    if (!ok) {
      throw Exception('No se pudo sacar el audio de ese video.');
    }
    alProgresar(100, 'Listo');
    return destino;
  }

  /// Arma el video juntando los trozos de una lista m3u8 o mpd.
  Future<String> _armarDesdeLista({
    required String urlMedia,
    required String nombre,
    required bool soloAudio,
    required String formatoAudio,
    required Directory carpeta,
    required void Function(double, String) alProgresar,
    required bool Function() cancelado,
    required bool reforzarAudio,
    required String referente,
  }) async {
    alProgresar(5, 'Juntando el video');
    final destino = _libre(carpeta, nombre, soloAudio ? formatoAudio : 'mp4');

    final cabeceras = referente.isEmpty
        ? ''
        : '-headers "Referer: $referente\r\n" ';
    final salida = soloAudio
        ? '-vn ${reforzarAudio ? '-af loudnorm=I=-9:TP=-1.0:LRA=9 ' : ''}'
            '${_codecDe(formatoAudio, reforzar: reforzarAudio)}'
        : '-c copy -bsf:a aac_adtstoasc';

    final ok = await _ffmpegContando(
      '-y $cabeceras-i "$urlMedia" $salida "$destino"',
      alProgresar: alProgresar,
      cancelado: cancelado,
      desde: 5,
      hasta: 97,
      etiqueta: soloAudio ? 'Sacando el audio' : 'Juntando el video',
    );
    if (cancelado()) {
      await _borrar(File(destino));
      throw _Cancelado();
    }
    if (!ok) {
      await _borrar(File(destino));
      throw Exception('No se pudo armar el video de esa página.');
    }
    alProgresar(100, 'Listo');
    return destino;
  }

  /// Trae un archivo por HTTP, avisando del avance.
  ///
  /// Con vigilancia: si la conexión se queda muda, la descarga se corta con un
  /// aviso en vez de quedarse ahí colgada para siempre.
  Future<void> _bajarUrl(
    String url,
    File destino,
    void Function(double, String) alProgresar,
    bool Function() cancelado, {
    required double desde,
    required double hasta,
    String referente = '',
  }) async {
    final cliente = HttpClient()
      ..connectionTimeout = const Duration(seconds: 25)
      ..idleTimeout = const Duration(seconds: 30);

    final HttpClientResponse respuesta;
    try {
      final peticion = await cliente
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 30));
      peticion.headers.set('User-Agent',
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/124.0.0.0 Mobile Safari/537.36');
      if (referente.isNotEmpty) peticion.headers.set('Referer', referente);
      respuesta = await peticion.close().timeout(const Duration(seconds: 40));
    } on TimeoutException {
      cliente.close(force: true);
      throw Exception('El sitio no respondió a tiempo. Vuelve a intentarlo.');
    }

    if (respuesta.statusCode >= 400) {
      cliente.close(force: true);
      throw Exception(
        respuesta.statusCode == 403
            ? 'Ese video esta protegido y no se deja bajar directamente.'
            : 'Ese video ya no esta disponible (${respuesta.statusCode}).',
      );
    }

    final total = respuesta.contentLength;
    var hecho = 0;
    var ultimoAvance = DateTime.now();
    final salida = destino.openWrite();

    try {
      // el timeout del stream salta si pasan 45 s sin que llegue un solo byte
      await for (final trozo in respuesta.timeout(
        const Duration(seconds: 45),
        onTimeout: (sumidero) => sumidero.addError(
          Exception('La descarga se quedo parada. Comprueba tu conexion.'),
        ),
      )) {
        if (cancelado()) {
          await salida.flush();
          await salida.close();
          cliente.close(force: true);
          await _borrar(destino);
          throw _Cancelado();
        }
        salida.add(trozo);
        hecho += trozo.length;

        // no avisamos por cada trozo: seria repintar la pantalla cien veces
        final ahora = DateTime.now();
        if (ahora.difference(ultimoAvance).inMilliseconds > 200) {
          ultimoAvance = ahora;
          alProgresar(
            total > 0 ? desde + (hecho / total) * (hasta - desde) : desde,
            total > 0 ? 'Descargando' : 'Descargando  ${_mb(hecho)}',
          );
        }
      }
      await salida.flush();
      await salida.close();
      cliente.close();
      alProgresar(hasta, 'Descargando');
    } on _Cancelado {
      rethrow;
    } catch (e) {
      await salida.close();
      cliente.close(force: true);
      await _borrar(destino);
      rethrow;
    }
  }

  static String _mb(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';

  static bool _esLista(String url) {
    final u = url.split('?').first.toLowerCase();
    return u.endsWith('.m3u8') || u.endsWith('.mpd');
  }

  static String _extensionDe(String url) {
    final u = url.split('?').first.toLowerCase();
    for (final e in ['mp4', 'm4v', 'mov', 'webm', 'm4a', 'mp3', 'aac', 'ogg', 'opus']) {
      if (u.endsWith('.$e')) return e;
    }
    return 'mp4';
  }

  static String _codecDe(String formato, {bool reforzar = false}) {
    switch (formato) {
      case 'm4a':
        // copiar la pista es instantáneo, pero nivelar el volumen exige rehacerla
        return reforzar ? '-c:a aac -b:a 192k' : '-c:a copy';
      case 'flac':
        return '-c:a flac';
      case 'wav':
        return '-c:a pcm_s16le';
      default:
        return '-c:a libmp3lame -b:a 192k';
    }
  }

  Future<bool> _ffmpeg(String orden) async {
    final sesion = await FFmpegKit.execute(orden);
    final codigo = await sesion.getReturnCode();
    return ReturnCode.isSuccess(codigo);
  }

  /// Igual que [_ffmpeg], pero contando lo que lleva hecho.
  ///
  /// Juntar los trozos de un video largo tarda minutos. Sin esto la barra se
  /// queda clavada todo ese rato y no hay forma de saber si sigue viva.
  Future<bool> _ffmpegContando(
    String orden, {
    required void Function(double, String) alProgresar,
    required bool Function() cancelado,
    required double desde,
    required double hasta,
    required String etiqueta,
    int duracionTotal = 0,
  }) async {
    final fin = Completer<bool>();
    var ultimo = DateTime.fromMillisecondsSinceEpoch(0);

    final sesion = await FFmpegKit.executeAsync(
      orden,
      (s) async {
        final codigo = await s.getReturnCode();
        if (!fin.isCompleted) fin.complete(ReturnCode.isSuccess(codigo));
      },
      null,
      (estadistica) {
        final ahora = DateTime.now();
        if (ahora.difference(ultimo).inMilliseconds < 400) return;
        ultimo = ahora;

        final segundos = estadistica.getTime() ~/ 1000;
        if (duracionTotal > 0) {
          final parte = (segundos / duracionTotal).clamp(0.0, 1.0);
          alProgresar(desde + parte * (hasta - desde), etiqueta);
        } else {
          // sin saber cuánto dura, al menos se ve que avanza
          alProgresar(desde, '$etiqueta  ${formatoSegundos(segundos)}');
        }
      },
    );

    // si el usuario cancela, se corta ffmpeg en vez de esperar a que acabe
    while (!fin.isCompleted) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (cancelado()) {
        await FFmpegKit.cancel(sesion.getSessionId());
        return false;
      }
    }
    return fin.future;
  }

  Future<void> _borrar(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } on FileSystemException {
      // si no se puede borrar el temporal, no vale la pena romper la descarga
    }
  }

  String _libre(Directory carpeta, String nombre, String extension) {
    var ruta = p.join(carpeta.path, '$nombre.$extension');
    var n = 1;
    while (File(ruta).existsSync()) {
      ruta = p.join(carpeta.path, '$nombre ($n).$extension');
      n++;
    }
    return ruta;
  }

  void cerrar() => _yt.close();
}

class _Cancelado implements Exception {}
