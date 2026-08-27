import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../nucleo/modelos.dart';

/// Reproductor de música con cola, que sigue sonando en segundo plano.
class ReproductorAudio extends ChangeNotifier {
  ReproductorAudio() {
    _motor.playerStateStream.listen((_) => notifyListeners());
    _motor.currentIndexStream.listen((i) {
      if (i != null && i >= 0 && i < _cola.length) {
        _indice = i;
        notifyListeners();
      }
    });
  }

  final AudioPlayer _motor = AudioPlayer();
  List<Pista> _cola = [];
  int _indice = -1;
  bool _modoMusica = false;
  double _refuerzo = 1.6;

  AudioPlayer get motor => _motor;
  List<Pista> get cola => List.unmodifiable(_cola);
  int get indice => _indice;

  Pista? get actual =>
      (_indice >= 0 && _indice < _cola.length) ? _cola[_indice] : null;

  bool get sonando => _motor.playing;
  bool get hayAlgo => actual != null;
  bool get modoMusica => _modoMusica;

  /// Modo musica: empuja el volumen por encima del maximo normal.
  ///
  /// El salto grande de volumen viene de que el archivo se descarga
  /// normalizado; esto es el empujon final del reproductor.
  Future<void> definirModoMusica(bool activo, {double refuerzo = 1.6}) async {
    _modoMusica = activo;
    _refuerzo = refuerzo.clamp(1.0, 2.0);
    await _aplicarVolumen();
    notifyListeners();
  }

  Future<void> _aplicarVolumen() async {
    try {
      await _motor.setVolume(_modoMusica ? _refuerzo : 1.0);
    } on Exception {
      // si la plataforma no admite pasar de 1.0, se queda en el maximo normal
      await _motor.setVolume(1.0);
    }
  }

  Stream<Duration> get posicion => _motor.positionStream;
  Stream<Duration?> get total => _motor.durationStream;

  /// Pone a sonar una lista empezando por [desde].
  Future<void> reproducirLista(List<Pista> pistas, {int desde = 0}) async {
    final validas = <Pista>[];
    for (final p in pistas) {
      if (p.esAudio && File(p.archivo).existsSync()) validas.add(p);
    }
    if (validas.isEmpty) return;

    var inicio = desde;
    if (desde >= 0 && desde < pistas.length) {
      // el indice puede moverse si se descartaron pistas cuyo archivo ya no esta
      final elegida = pistas[desde];
      final nuevo = validas.indexWhere((p) => p.id == elegida.id);
      inicio = nuevo >= 0 ? nuevo : 0;
    } else {
      inicio = 0;
    }

    _cola = validas;
    _indice = inicio;
    notifyListeners();

    final fuentes = validas
        .map((p) => AudioSource.file(
              p.archivo,
              tag: MediaItem(
                id: '${p.id}',
                title: p.titulo,
                artist: p.autor.isEmpty ? 'Caudal' : p.autor,
                duration: p.duracion > 0 ? Duration(seconds: p.duracion) : null,
                artUri: p.miniatura.isNotEmpty ? Uri.tryParse(p.miniatura) : null,
              ),
            ))
        .toList();

    await _motor.setAudioSources(fuentes, initialIndex: inicio, initialPosition: Duration.zero);
    await _aplicarVolumen();
    await _motor.play();
  }

  Future<void> alternar() async {
    if (_motor.playing) {
      await _motor.pause();
    } else {
      await _motor.play();
    }
    notifyListeners();
  }

  Future<void> siguiente() async {
    if (_motor.hasNext) await _motor.seekToNext();
  }

  Future<void> anterior() async {
    // como en cualquier reproductor: si ya avanzo, primero vuelve al principio
    if (_motor.position.inSeconds > 3) {
      await _motor.seek(Duration.zero);
    } else if (_motor.hasPrevious) {
      await _motor.seekToPrevious();
    } else {
      await _motor.seek(Duration.zero);
    }
  }

  Future<void> irA(Duration donde) => _motor.seek(donde);

  Future<void> detener() async {
    await _motor.stop();
    _cola = [];
    _indice = -1;
    notifyListeners();
  }

  /// Quita de la cola una pista borrada, para no dejar el reproductor colgado.
  Future<void> olvidar(int idPista) async {
    if (actual?.id == idPista) {
      await detener();
    } else {
      _cola.removeWhere((p) => p.id == idPista);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _motor.dispose();
    super.dispose();
  }
}
