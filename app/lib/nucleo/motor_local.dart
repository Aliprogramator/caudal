import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'formato.dart';
import 'modelos.dart';

/// Descarga directamente en el teléfono, sin que el archivo pase por el servidor.
///
/// De momento cubre YouTube y YouTube Music, que es de donde sale casi toda la
/// música. Para el resto de redes hace falta el servidor, porque resolverlas
/// exige yt-dlp y eso no corre dentro del teléfono.
class MotorLocal {
  MotorLocal();

  final YoutubeExplode _yt = YoutubeExplode();

  /// ¿Este enlace se puede resolver aquí mismo, sin servidor?
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
    final ok = await _ffmpeg(
        '-y -i "${video.path}" -i "${audio.path}" -c copy -shortest "$destino"');
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

  Future<bool> _ffmpeg(String orden) async {
    final sesion = await FFmpegKit.execute(orden);
    final codigo = await sesion.getReturnCode();
    return ReturnCode.isSuccess(codigo);
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
