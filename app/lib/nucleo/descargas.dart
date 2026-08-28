import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ajustes.dart';
import 'almacen.dart';
import 'capturador_oculto.dart';
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
    required this.capturador,
  });
  final Almacen almacen;
  final Ajustes ajustes;

  /// Para abrir la pagina a escondidas cuando el enlace no viene del navegador.
  final CapturadorOculto capturador;

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

  /// Convierte un fallo en algo que se pueda leer y sirva para saber qué pasó.
  static String _mensajeDe(Object e) {
    if (e is ErrorCaudal) return e.mensaje;

    var texto = e.toString();
    // las excepciones de Dart vienen con este prefijo delante
    texto = texto.replaceFirst(RegExp(r'^(Exception|_Exception):\s*'), '');

    if (e is FileSystemException) {
      final motivo = e.osError?.message ?? '';
      if (motivo.toLowerCase().contains('permission') ||
          motivo.toLowerCase().contains('denied')) {
        return 'Android no deja guardar ahí. En Ajustes, cambia dónde se '
            'guardan las descargas o dale permiso de almacenamiento.';
      }
      return 'No se pudo guardar el archivo: $motivo';
    }
    if (e is SocketException) {
      return 'No hay conexión con ese sitio. Comprueba tu internet.';
    }
    if (e is HandshakeException) {
      return 'Falló la conexión segura con ese sitio.';
    }
    if (e is TimeoutException) {
      return 'El sitio no respondió a tiempo. Vuelve a intentarlo.';
    }

    if (texto.length > 160) texto = '${texto.substring(0, 157)}...';
    return texto.isEmpty ? 'No se pudo completar la descarga.' : texto;
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
        // Y solo por ahi: el camino general captura lo que el reproductor va
        // pidiendo, y en YouTube eso son trozos sueltos que no valen como
        // archivo. Antes se caia ahi al fallar y se bajaba basura, tapando
        // ademas el motivo de verdad.
        await _bajarAqui(d).timeout(const Duration(hours: 3));
        return;
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
        // decir siempre "no se pudo" no ayuda a nadie: tapaba el motivo real y
        // dejaba a ciegas tanto al usuario como a quien tiene que arreglarlo
        d.error = _mensajeDe(e);
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
      // el motivo se cuenta tal cual: antes se convertia en _SinSoporte y se
      // perdia, y encima se seguia por un camino que en YouTube no funciona
      throw ErrorCaudal(_motivoDeYoutube(e));
    }
  }

  /// Traduce lo que dice YouTube a algo que el usuario pueda entender.
  static String _motivoDeYoutube(Object e) {
    final texto = e.toString();
    final bajo = texto.toLowerCase();

    if (bajo.contains('age') || bajo.contains('sign in') || bajo.contains('login')) {
      return 'Ese video tiene restriccion de edad y YouTube pide iniciar '
          'sesion para verlo. Prueba con otra version del mismo video.';
    }
    if (bajo.contains('unavailable') || bajo.contains('not available')) {
      return 'Ese video ya no esta disponible en YouTube.';
    }
    if (bajo.contains('private')) {
      return 'Ese video es privado.';
    }
    if (bajo.contains('live')) {
      return 'Es una emision en directo: no se puede descargar mientras esta '
          'en marcha.';
    }
    if (bajo.contains('socket') || bajo.contains('connection') ||
        bajo.contains('timeout') || bajo.contains('host')) {
      return 'No se pudo hablar con YouTube. Comprueba tu conexion.';
    }
    return _mensajeDe(e);
  }

  /// Descarga de cualquier otro sitio: Instagram, TikTok, X, Facebook...
  ///
  /// Se usa la direccion que el navegador vio pasar mientras la pagina
  /// reproducia el video. Si no hay ninguna (porque la descarga se pidio
  /// desde fuera del navegador), se intenta leerla de la propia pagina.
  Future<void> _bajarDeLaPagina(Descarga d) async {
    d.estado = EstadoDescarga.descargando;
    d.detalle = 'Buscando el video';
    // un poco de avance desde el principio: un cero quieto parece averiado
    d.progreso = 1;
    notifyListeners();

    var media = d.urlMedia;
    var titulo = d.titulo;

    var galletas = d.cookies;

    if (media.isEmpty) {
      // primero lo barato: a veces la pagina lleva el video en sus etiquetas
      final hallado = await extraer(d.url)
          .timeout(const Duration(seconds: 30), onTimeout: () => null);
      if (hallado != null && hallado.vale) {
        media = hallado.url;
        if (titulo.isEmpty || titulo == sitioDe(d.url)) {
          if (hallado.titulo.isNotEmpty) titulo = hallado.titulo;
        }
        if (d.autor.isEmpty) d.autor = hallado.autor;
        if (d.miniatura.isEmpty) d.miniatura = hallado.miniatura;
        if (d.duracion == 0) d.duracion = hallado.duracion;
      }
    }

    if (media.isEmpty) {
      // Instagram y TikTok no ponen el video en la pagina: hay que abrirla de
      // verdad y ver que pide. Se hace en un navegador que no se ve.
      d.detalle = 'Abriendo la pagina';
      d.progreso = 3;
      notifyListeners();
      final oculta = await capturador
          .capturar(d.url, paraAudio: d.esAudio)
          .timeout(const Duration(seconds: 40),
              onTimeout: () => const CapturaOculta());
      if (oculta.vale) {
        d.detalle = 'Video encontrado';
        d.progreso = 5;
        notifyListeners();
        media = oculta.url;
        if (galletas.isEmpty) galletas = oculta.cookies;
        if ((titulo.isEmpty || titulo == sitioDe(d.url)) &&
            oculta.titulo.isNotEmpty) {
          titulo = oculta.titulo;
        }
      }
    }

    if (media.isEmpty) {
      throw ErrorCaudal(
        'No se encontro el video en esa pagina. Puede que sea privada o que '
        'haga falta iniciar sesion: abrela en el navegador de Caudal, dale al '
        'play y descargala desde ahi.',
      );
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
        cookies: galletas,
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
        } catch (_) {
          // Android puede negarlo de varias formas segun la version; da igual
          // cual sea, si no se puede escribir ahi se prueba el siguiente sitio
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

