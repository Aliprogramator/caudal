import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ajustes.dart';
import 'almacen.dart';
import 'formato.dart';
import 'modelos.dart';
import 'motor_local.dart';
import 'servidor.dart';

/// Una descarga vista desde el teléfono.
///
/// Pasa por dos fases: el servidor la prepara (baja y convierte) y después el
/// teléfono se trae el archivo. El progreso que ve el usuario junta las dos.
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
  });

  final String id;
  final String url;

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

  String idTrabajo = '';
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
    required this.servidor,
    required this.almacen,
    required this.ajustes,
  });

  final Servidor servidor;
  final Almacen almacen;
  final Ajustes ajustes;

  final List<Descarga> _cola = [];
  final Dio _dio = Dio();
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
  }) {
    final d = Descarga(
      id: 'd${++_contador}_${DateTime.now().millisecondsSinceEpoch}',
      url: url,
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
      // Lo que el telefono puede resolver por su cuenta se baja directo de la
      // fuente: asi el archivo no pasa por el servidor ni depende de el.
      if (ajustes.descargaDirecta && MotorLocal.puedeSolo(d.url)) {
        try {
          await _bajarAqui(d);
          return;
        } on _SinSoporte {
          // seguimos por el servidor
        }
      }
      await _prepararEnServidor(d);
      if (d.estado == EstadoDescarga.cancelada || d.pausada) return;
      await _traerArchivo(d);
    } on ErrorCaudal catch (e) {
      if (!d.pausada && d.estado != EstadoDescarga.cancelada) {
        d.estado = EstadoDescarga.error;
        d.error = e.mensaje;
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

  /// Descarga sin servidor: el telefono resuelve y baja de la fuente.
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
        alProgresar: (pct, fase) {
          d.progreso = pct;
          d.detalle = fase;
          notifyListeners();
        },
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
      // si aqui no se pudo, que lo intente el servidor
      throw _SinSoporte();
    }
  }

  /// Fase 1: el servidor busca, descarga y convierte. Ocupa el 0-45 % del avance.
  Future<void> _prepararEnServidor(Descarga d) async {
    d.estado = EstadoDescarga.preparando;
    d.detalle = 'Pidiendo al servidor';
    notifyListeners();

    if (d.idTrabajo.isEmpty) {
      final trabajo = await servidor.crearTrabajo(
        url: d.url,
        busqueda: d.busqueda,
        tipo: d.tipo,
        calidad: d.calidad,
        formatoAudio: d.formatoAudio,
        // el modo musica solo tiene sentido cuando lo que se baja es sonido
        refuerzoAudio: d.esAudio && ajustes.modoMusica,
      );
      d.idTrabajo = trabajo.id;
    }

    while (true) {
      if (d.pausada || d.estado == EstadoDescarga.cancelada) return;
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (d.pausada || d.estado == EstadoDescarga.cancelada) return;

      final estado = await servidor.verTrabajo(d.idTrabajo);
      if (estado.titulo.isNotEmpty) d.titulo = estado.titulo;
      if (estado.autor.isNotEmpty) d.autor = estado.autor;
      if (estado.miniatura.isNotEmpty && d.miniatura.isEmpty) d.miniatura = estado.miniatura;
      if (estado.duracion > 0) d.duracion = estado.duracion;

      d.progreso = estado.progreso * 0.45;
      d.detalle = estado.mensaje;
      notifyListeners();

      if (estado.listo) {
        d.bytesTotales = estado.tamano;
        if (estado.nombre.isNotEmpty) d.titulo = p.basenameWithoutExtension(estado.nombre);
        d.archivo = await _rutaDestino(estado.nombre, d.esAudio);
        return;
      }
      if (estado.fallo) {
        throw ErrorCaudal(estado.error.isEmpty ? 'El servidor no pudo prepararlo.' : estado.error);
      }
      if (estado.cancelado) {
        d.estado = EstadoDescarga.cancelada;
        d.detalle = 'Cancelada';
        return;
      }
    }
  }

  /// Fase 2: traer el archivo al teléfono. Ocupa el 45-100 % del avance.
  Future<void> _traerArchivo(Descarga d) async {
    d.estado = EstadoDescarga.descargando;
    d.detalle = 'Trayendo al teléfono';
    notifyListeners();

    final parcial = File('${d.archivo}.part');
    var yaTiene = await parcial.exists() ? await parcial.length() : 0;

    d.cancelador = CancelToken();
    final cabeceras = Map<String, String>.from(servidor.cabeceras);
    if (yaTiene > 0) cabeceras['Range'] = 'bytes=$yaTiene-';

    final respuesta = await _dio.get<ResponseBody>(
      servidor.urlArchivo(d.idTrabajo),
      options: Options(
        headers: cabeceras,
        responseType: ResponseType.stream,
        receiveTimeout: const Duration(minutes: 10),
        followRedirects: true,
      ),
      cancelToken: d.cancelador,
    );

    // si el servidor ignoró el Range, hay que empezar de cero
    if (respuesta.statusCode == 200 && yaTiene > 0) {
      yaTiene = 0;
      if (await parcial.exists()) await parcial.delete();
    }

    final largoCabecera =
        int.tryParse('${respuesta.headers.value(Headers.contentLengthHeader) ?? 0}') ?? 0;
    final total = yaTiene + largoCabecera;
    if (total > 0) d.bytesTotales = total;

    final salida = parcial.openWrite(mode: yaTiene > 0 ? FileMode.append : FileMode.write);
    var recibidos = yaTiene;
    final inicio = DateTime.now();
    var ultimoAviso = DateTime.now();

    try {
      await for (final trozo in respuesta.data!.stream) {
        if (d.pausada || d.estado == EstadoDescarga.cancelada) {
          await salida.flush();
          await salida.close();
          if (d.estado == EstadoDescarga.cancelada) {
            if (await parcial.exists()) await parcial.delete();
          } else {
            d.estado = EstadoDescarga.pausada;
            d.detalle = 'En pausa';
            d.bytesRecibidos = recibidos;
            notifyListeners();
          }
          return;
        }

        salida.add(trozo);
        recibidos += trozo.length;

        final ahora = DateTime.now();
        if (ahora.difference(ultimoAviso).inMilliseconds > 220) {
          ultimoAviso = ahora;
          final transcurrido = ahora.difference(inicio).inMilliseconds / 1000.0;
          d.bytesRecibidos = recibidos;
          d.velocidad = transcurrido > 0 ? (recibidos - yaTiene) / transcurrido : 0;
          if (d.bytesTotales > 0) {
            d.progreso = 45 + (recibidos / d.bytesTotales) * 55;
            if (d.velocidad > 0) {
              d.segundosRestantes = ((d.bytesTotales - recibidos) / d.velocidad).round();
            }
          }
          notifyListeners();
        }
      }

      await salida.flush();
      await salida.close();
    } catch (e) {
      await salida.flush();
      await salida.close();
      // solo un DioException puede ser una cancelación; el cast a ciegas rompía
      if (e is DioException && CancelToken.isCancel(e)) {
        if (d.estado == EstadoDescarga.cancelada) {
          if (await parcial.exists()) await parcial.delete();
        } else {
          d.estado = EstadoDescarga.pausada;
          d.detalle = 'En pausa';
          notifyListeners();
        }
        return;
      }
      rethrow;
    }

    await parcial.rename(d.archivo);

    final tamanoFinal = await File(d.archivo).length();
    d.bytesRecibidos = tamanoFinal;
    d.bytesTotales = tamanoFinal;
    d.progreso = 100;
    d.estado = EstadoDescarga.completada;
    d.detalle = 'Guardado';
    d.velocidad = 0;
    d.segundosRestantes = 0;

    await almacen.guardar(Pista(
      id: 0,
      titulo: d.titulo,
      autor: d.autor,
      archivo: d.archivo,
      miniatura: d.miniatura,
      duracion: d.duracion,
      tamano: tamanoFinal,
      origen: d.url,
      esAudio: d.esAudio,
      fecha: DateTime.now().millisecondsSinceEpoch,
    ));

    // el servidor ya no necesita guardar el archivo
    unawaited(servidor.cancelarTrabajo(d.idTrabajo));

    notifyListeners();
    if (!_terminadas.isClosed) _terminadas.add(d);
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
    final veniaDeCancelada = d.estado == EstadoDescarga.cancelada;
    d.pausada = false;
    d.error = '';
    d.estado = EstadoDescarga.enCola;
    d.detalle = 'En cola';
    // al cancelar se le pide al servidor que borre el trabajo, así que
    // reintentar tiene que empezar pidiéndolo otra vez desde cero
    if (veniaDeCancelada) d.idTrabajo = '';
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
    if (d.idTrabajo.isNotEmpty) {
      unawaited(servidor.cancelarTrabajo(d.idTrabajo));
    }
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
  Future<String> _rutaDestino(String nombreServidor, bool audio) async {
    final carpeta = await carpetaDeGuardado(audio, ajustes.guardarEnPublico);
    final nombre = nombreSeguro(p.basenameWithoutExtension(nombreServidor));
    final extension = p.extension(nombreServidor).isEmpty
        ? (audio ? '.mp3' : '.mp4')
        : p.extension(nombreServidor);

    var destino = p.join(carpeta.path, '$nombre$extension');
    var n = 1;
    while (await File(destino).exists()) {
      destino = p.join(carpeta.path, '$nombre ($n)$extension');
      n++;
    }
    return destino;
  }

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

/// Marca que el telefono no pudo con esa descarga y hay que pedirsela al servidor.
class _SinSoporte implements Exception {}
