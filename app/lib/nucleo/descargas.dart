import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ajustes.dart';
import 'almacen.dart';
import 'extractores.dart';
import 'formato.dart';
import 'modelos.dart';
import 'motor_local.dart';

/// Una descarga vista desde el teléfono.
///
/// Todo ocurre aquí dentro: se busca la dirección del video, se trae el
/// archivo y, si hace falta, se convierte. Nada pasa por ningún servidor.
class Descarga {
  Descarga({
    required this.id,
    required this.url,
    this.busqueda = '',
    required this.tipo,
    required this.calidad,
    required this.formatoAudio,
    this.titulo = '',
    this.autor = '',
    this.miniatura = '',
    this.urlMedia = '',
    this.cookies = '',
  });

  final String id;
  final String url;

  /// Direccion del archivo en si, cuando el navegador la vio pasar mientras la
  /// pagina reproducia el video. Vacia para YouTube, que se resuelve solo.
  final String urlMedia;

  /// Cookies de la pagina de donde salio. Muchos sitios rechazan la peticion
  /// si no llegan: es la forma que tienen de comprobar que eres tu.
  final String cookies;

  /// Texto a buscar cuando no hay enlace exacto (canciones de Spotify o Apple).
  final String busqueda;
  final TipoMedio tipo;
  final String calidad;
  final String formatoAudio;

  String titulo;
  String autor;
  String miniatura;

  EstadoDescarga estado = EstadoDescarga.enCola;
  String detalle = 'En cola';
  String error = '';
  double progreso = 0;
  int bytesRecibidos = 0;
  int bytesTotales = 0;
  double velocidad = 0;
  int segundosRestantes = 0;
  int duracion = 0;
  String archivo = '';
  CancelToken? cancelador;
  bool pausada = false;

  bool get esAudio => tipo == TipoMedio.audio;
  bool get terminada =>
      estado == EstadoDescarga.completada ||
      estado == EstadoDescarga.error ||
      estado == EstadoDescarga.cancelada;
}

/// Cola de descargas del teléfono.
class GestorDescargas extends ChangeNotifier {
  GestorDescargas({
    required this.almacen,
    required this.ajustes,
  });
  final Almacen almacen;
  final Ajustes ajustes;

  final List<Descarga> _cola = [];
  final MotorLocal _local = MotorLocal();
  int _enMarcha = 0;
  int _contador = 0;

  static const _maxSimultaneas = 2;

  List<Descarga> get lista => List.unmodifiable(_cola);
  List<Descarga> get activas => _cola.where((d) => d.estado.activa).toList();
  bool get hayActividad => _cola.any((d) => d.estado.activa);

  /// Avisa a la interfaz cuando una descarga termina bien.
  final StreamController<Descarga> _terminadas = StreamController<Descarga>.broadcast();
  Stream<Descarga> get alTerminar => _terminadas.stream;

  Descarga encolar({
    String url = '',
    String busqueda = '',
    required TipoMedio tipo,
    String calidad = 'mejor',
    String? formatoAudio,
    String titulo = '',
    String autor = '',
    String miniatura = '',
    String urlMedia = '',
    String cookies = '',
  }) {
    final d = Descarga(
      id: 'd${++_contador}_${DateTime.now().millisecondsSinceEpoch}',
      url: url,
      urlMedia: urlMedia,
      cookies: cookies,
      busqueda: busqueda,
      tipo: tipo,
      calidad: calidad,
      formatoAudio: formatoAudio ?? ajustes.formatoAudio,
      titulo: titulo.isEmpty ? (busqueda.isEmpty ? sitioDe(url) : busqueda) : titulo,
      autor: autor,
      miniatura: miniatura,
    );
    _cola.insert(0, d);
    notifyListeners();
    _bombear();
    return d;
  }

  /// Devuelve el callback de avance de una descarga, con freno.
  ///
  /// Sin freno esto avisa a la interfaz por cada trozo que llega: cientos de
  /// veces por segundo. Repintar tanto deja la pantalla agarrotada y parece
  /// que la descarga no avanza, justo lo contrario de lo que se busca.
  void Function(double, String) _avisarDelAvance(Descarga d) {
    var ultimo = DateTime.fromMillisecondsSinceEpoch(0);
    return (pct, fase) {
      d.progreso = pct;
      d.detalle = fase;
      final ahora = DateTime.now();
      // siempre se avisa del final y de los cambios de fase, pase lo que pase
      final esHito = pct >= 100 || pct <= 0;
      if (esHito || ahora.difference(ultimo).inMilliseconds >= 250) {
        ultimo = ahora;
        notifyListeners();
      }
    };
  }

  void _bombear() {
    if (_enMarcha >= _maxSimultaneas) return;
    for (final d in _cola.reversed) {
      if (_enMarcha >= _maxSimultaneas) break;
      if (d.estado == EstadoDescarga.enCola && !d.pausada) {
        _procesar(d);
      }
    }
  }

  Future<void> _procesar(Descarga d) async {
    _enMarcha++;
    try {
      // YouTube se resuelve solo y da la mejor calidad, con el sonido aparte.
      if (MotorLocal.puedeSolo(d.url)) {
        try {
          // averiguar el video no deberia tardar tanto: si tarda, algo va mal
          // y no vale la pena tener el hueco ocupado esperando
          await _bajarAqui(d).timeout(const Duration(hours: 3));
          return;
        } on _SinSoporte {
          // no se pudo por ahi; probamos como con cualquier otra pagina
        }
      }
      await _bajarDeLaPagina(d).timeout(const Duration(hours: 3));
    } on ErrorCaudal catch (e) {
      if (!d.pausada && d.estado != EstadoDescarga.cancelada) {
        d.estado = EstadoDescarga.error;
        d.error = e.mensaje;
        d.detalle = 'Error';
      }
    } on TimeoutException {
      if (!d.pausada && d.estado != EstadoDescarga.cancelada) {
        d.estado = EstadoDescarga.error;
        d.error = 'La descarga tardo demasiado y se corto. Vuelve a intentarlo.';
        d.detalle = 'Error';
      }
    } catch (e) {
      if (!d.pausada && d.estado != EstadoDescarga.cancelada) {
        d.estado = EstadoDescarga.error;
        d.error = 'No se pudo completar la descarga.';
        d.detalle = 'Error';
      }
    } finally {
      _enMarcha--;
      notifyListeners();
      _bombear();
    }
  }

  /// YouTube: el telefono resuelve el video y lo baja de la fuente.
  Future<void> _bajarAqui(Descarga d) async {
    d.estado = EstadoDescarga.descargando;
    d.detalle = 'Preparando';
    notifyListeners();

    final carpeta = await GestorDescargas.carpetaDeGuardado(
        d.esAudio, ajustes.guardarEnPublico);

    try {
      final archivo = await _local.descargar(
        url: d.url,
        tipo: d.tipo,
        calidad: d.calidad,
        formatoAudio: d.formatoAudio,
        carpeta: carpeta,
        reforzarAudio: d.esAudio && ajustes.modoMusica,
        cancelado: () => d.estado == EstadoDescarga.cancelada || d.pausada,
        alProgresar: _avisarDelAvance(d),
      );

      final tamano = await File(archivo).length();
      d.archivo = archivo;
      d.bytesRecibidos = tamano;
      d.bytesTotales = tamano;
      d.progreso = 100;
      d.estado = EstadoDescarga.completada;
      d.detalle = 'Guardado en el telefono';

      await almacen.guardar(Pista(
        id: 0,
        titulo: d.titulo,
        autor: d.autor,
        archivo: archivo,
        miniatura: d.miniatura,
        duracion: d.duracion,
        tamano: tamano,
        origen: d.url,
        esAudio: d.esAudio,
        fecha: DateTime.now().millisecondsSinceEpoch,
      ));

      notifyListeners();
      if (!_terminadas.isClosed) _terminadas.add(d);
    } catch (e) {
      if (d.estado == EstadoDescarga.cancelada) {
        d.detalle = 'Cancelada';
        notifyListeners();
        return;
      }
      if (d.pausada) {
        d.estado = EstadoDescarga.pausada;
        d.detalle = 'En pausa';
        notifyListeners();
        return;
      }
      // si por aqui no se pudo, se intenta como con cualquier otra pagina
      throw _SinSoporte();
    }
  }

  /// Descarga de cualquier otro sitio: Instagram, TikTok, X, Facebook...
  ///
  /// Se usa la direccion que el navegador vio pasar mientras la pagina
  /// reproducia el video. Si no hay ninguna (porque la descarga se pidio
  /// desde fuera del navegador), se intenta leerla de la propia pagina.
  Future<void> _bajarDeLaPagina(Descarga d) async {
    d.estado = EstadoDescarga.descargando;
    d.detalle = 'Buscando el video';
    notifyListeners();

    var media = d.urlMedia;
    var titulo = d.titulo;

    if (media.isEmpty) {
      // leer la pagina no puede eternizarse: si no contesta, se avisa
      final hallado = await extraer(d.url)
          .timeout(const Duration(seconds: 45), onTimeout: () => null);
      if (hallado == null || !hallado.vale) {
        throw ErrorCaudal(
          'No se encontro el video en esa pagina. Abrela en el navegador de '
          'Caudal, dale al play un segundo y descargala desde ahi.',
        );
      }
      media = hallado.url;
      if (titulo.isEmpty || titulo == sitioDe(d.url)) {
        if (hallado.titulo.isNotEmpty) titulo = hallado.titulo;
      }
      if (d.autor.isEmpty) d.autor = hallado.autor;
      if (d.miniatura.isEmpty) d.miniatura = hallado.miniatura;
      if (d.duracion == 0) d.duracion = hallado.duracion;
    }

    final carpeta = await GestorDescargas.carpetaDeGuardado(
        d.esAudio, ajustes.guardarEnPublico);

    try {
      final archivo = await _local.descargarMedio(
        urlMedia: media,
        titulo: titulo,
        tipo: d.tipo,
        formatoAudio: d.formatoAudio,
        carpeta: carpeta,
        referente: d.url,
        cookies: d.cookies,
        reforzarAudio: d.esAudio && ajustes.modoMusica,
        cancelado: () => d.estado == EstadoDescarga.cancelada || d.pausada,
        alProgresar: _avisarDelAvance(d),
      );

      final tamano = await File(archivo).length();
      d.archivo = archivo;
      d.titulo = titulo;
      d.bytesRecibidos = tamano;
      d.bytesTotales = tamano;
      d.progreso = 100;
      d.estado = EstadoDescarga.completada;
      d.detalle = 'Guardado en el telefono';

      await almacen.guardar(Pista(
        id: 0,
        titulo: d.titulo,
        autor: d.autor,
        archivo: archivo,
        miniatura: d.miniatura,
        duracion: d.duracion,
        tamano: tamano,
        origen: d.url,
        esAudio: d.esAudio,
        fecha: DateTime.now().millisecondsSinceEpoch,
      ));

      notifyListeners();
      if (!_terminadas.isClosed) _terminadas.add(d);
    } catch (e) {
      if (d.estado == EstadoDescarga.cancelada) {
        d.detalle = 'Cancelada';
        notifyListeners();
        return;
      }
      if (d.pausada) {
        d.estado = EstadoDescarga.pausada;
        d.detalle = 'En pausa';
        notifyListeners();
        return;
      }
      rethrow;
    }
  }


  // ---------------------------------------------------------------- control

  void pausar(String id) {
    final d = _buscar(id);
    if (d == null || !d.estado.activa) return;
    d.pausada = true;
    d.cancelador?.cancel('pausa');
    if (d.estado != EstadoDescarga.descargando) {
      d.estado = EstadoDescarga.pausada;
      d.detalle = 'En pausa';
    }
    notifyListeners();
  }

  void reanudar(String id) {
    final d = _buscar(id);
    if (d == null) return;
    if (d.estado != EstadoDescarga.pausada &&
        d.estado != EstadoDescarga.error &&
        d.estado != EstadoDescarga.cancelada) {
      return;
    }
    d.pausada = false;
    d.error = '';
    d.estado = EstadoDescarga.enCola;
    d.detalle = 'En cola';
    notifyListeners();
    _bombear();
  }

  Future<void> cancelar(String id) async {
    final d = _buscar(id);
    if (d == null) return;
    d.estado = EstadoDescarga.cancelada;
    d.detalle = 'Cancelada';
    d.pausada = false;
    d.cancelador?.cancel('cancelada');
    final parcial = File('${d.archivo}.part');
    if (d.archivo.isNotEmpty && await parcial.exists()) {
      try {
        await parcial.delete();
      } on FileSystemException {
        // no pasa nada: se limpia en el siguiente intento
      }
    }
    notifyListeners();
    _bombear();
  }

  void quitar(String id) {
    final d = _buscar(id);
    if (d == null) return;
    if (d.estado.activa) cancelar(id);
    _cola.removeWhere((x) => x.id == id);
    notifyListeners();
  }

  void limpiarTerminadas() {
    _cola.removeWhere((d) => d.terminada);
    notifyListeners();
  }

  void pausarTodo() {
    for (final d in _cola) {
      if (d.estado.activa) pausar(d.id);
    }
  }

  void reanudarTodo() {
    for (final d in _cola) {
      if (d.estado == EstadoDescarga.pausada || d.estado == EstadoDescarga.error) {
        reanudar(d.id);
      }
    }
  }

  Descarga? _buscar(String id) {
    for (final d in _cola) {
      if (d.id == id) return d;
    }
    return null;
  }

  // ---------------------------------------------------------------- archivos

  /// Dónde se guarda: en la carpeta pública si se puede, si no en la de la app.

  static Future<Directory> carpetaDeGuardado(bool audio, bool preferirPublico) async {
    final sub = audio ? 'Musica' : 'Videos';

    if (preferirPublico && Platform.isAndroid) {
      for (final base in ['/storage/emulated/0/Download', '/sdcard/Download']) {
        try {
          final carpeta = Directory(p.join(base, 'Caudal', sub));
          if (!await carpeta.exists()) await carpeta.create(recursive: true);
          // comprobamos que de verdad se puede escribir ahí
          final prueba = File(p.join(carpeta.path, '.caudal'));
          await prueba.writeAsString('ok');
          await prueba.delete();
          return carpeta;
        } on FileSystemException {
          continue;
        }
      }
    }

    final base = Platform.isAndroid
        ? (await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory())
        : await getApplicationDocumentsDirectory();
    final carpeta = Directory(p.join(base.path, 'Caudal', sub));
    if (!await carpeta.exists()) await carpeta.create(recursive: true);
    return carpeta;
  }

  /// Pide el permiso necesario para escribir en la carpeta pública.
  static Future<bool> pedirPermisoAlmacenamiento() async {
    if (!Platform.isAndroid) return true;
    if (await Permission.manageExternalStorage.isGranted) return true;

    final storage = await Permission.storage.request();
    if (storage.isGranted) return true;

    final gestionar = await Permission.manageExternalStorage.request();
    return gestionar.isGranted;
  }

  /// Datos de un enlace, resueltos aqui mismo si se puede.
  /// Busca canciones y videos en YouTube, desde el propio telefono.
  Future<List<Resultado>> buscar(String texto) => _local.buscar(texto);

  Future<Ficha?> resolverSiPuede(String url) async {
    if (!ajustes.descargaDirecta || !MotorLocal.puedeSolo(url)) return null;
    try {
      return await _local.resolver(url);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _local.cerrar();
    _terminadas.close();
    super.dispose();
  }
}

/// Marca que por el camino de YouTube no se pudo, y toca el camino general.
class _SinSoporte implements Exception {}
