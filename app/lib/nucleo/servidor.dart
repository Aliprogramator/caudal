import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import 'modelos.dart';

/// Error que ya trae un mensaje pensado para enseñar al usuario.
class ErrorCaudal implements Exception {
  ErrorCaudal(this.mensaje, {this.esDeConexion = false, this.sesionCaducada = false});

  final String mensaje;
  final bool esDeConexion;
  final bool sesionCaducada;

  @override
  String toString() => mensaje;
}

/// Datos de la sesión iniciada.
class Sesion {
  const Sesion({required this.token, required this.usuario, required this.nombre});

  final String token;
  final String usuario;
  final String nombre;

  factory Sesion.desdeJson(Map<String, dynamic> j) => Sesion(
        token: '${j['token'] ?? ''}',
        usuario: '${j['usuario'] ?? ''}',
        nombre: '${j['nombre'] ?? ''}',
      );
}

/// Un dispositivo vinculado a la cuenta.
class Dispositivo {
  const Dispositivo({
    required this.id,
    required this.nombre,
    this.plataforma = '',
    this.desde = 0,
    this.ultimoUso = 0,
    this.esEste = false,
  });

  final String id;
  final String nombre;
  final String plataforma;
  final double desde;
  final double ultimoUso;
  final bool esEste;

  factory Dispositivo.desdeJson(Map<String, dynamic> j) => Dispositivo(
        id: '${j['id'] ?? ''}',
        nombre: '${j['dispositivo'] ?? 'Dispositivo'}',
        plataforma: '${j['plataforma'] ?? ''}',
        desde: (j['desde'] as num?)?.toDouble() ?? 0,
        ultimoUso: (j['ultimo_uso'] as num?)?.toDouble() ?? 0,
        esEste: j['es_este'] == true,
      );
}

/// Estado de un trabajo que el servidor está preparando.
class EstadoTrabajo {
  const EstadoTrabajo({
    required this.id,
    required this.estado,
    required this.progreso,
    required this.mensaje,
    this.error = '',
    this.titulo = '',
    this.autor = '',
    this.miniatura = '',
    this.duracion = 0,
    this.nombre = '',
    this.tamano = 0,
  });

  final String id;
  final String estado; // esperando | preparando | listo | error | cancelado
  final double progreso;
  final String mensaje;
  final String error;
  final String titulo;
  final String autor;
  final String miniatura;
  final int duracion;
  final String nombre;
  final int tamano;

  bool get listo => estado == 'listo';
  bool get fallo => estado == 'error';
  bool get cancelado => estado == 'cancelado';

  factory EstadoTrabajo.desdeJson(Map<String, dynamic> j) => EstadoTrabajo(
        id: '${j['id'] ?? ''}',
        estado: '${j['estado'] ?? ''}',
        progreso: (j['progreso'] as num?)?.toDouble() ?? 0,
        mensaje: '${j['mensaje'] ?? ''}',
        error: '${j['error'] ?? ''}',
        titulo: '${j['titulo'] ?? ''}',
        autor: '${j['autor'] ?? ''}',
        miniatura: '${j['miniatura'] ?? ''}',
        duracion: (j['duracion'] as num?)?.toInt() ?? 0,
        nombre: '${j['nombre'] ?? ''}',
        tamano: (j['tamano'] as num?)?.toInt() ?? 0,
      );
}

/// Habla con el servidor Caudal que corre en la computadora.
///
/// Guarda dos direcciones: la de casa y la de internet. Usa la de casa siempre
/// que responda, porque es más rápida, y cae a la de internet cuando estás fuera.
class Servidor {
  Servidor({String local = '', String publica = '', String token = ''})
      : _local = limpiar(local),
        _publica = limpiar(publica),
        _token = token {  // ignore: prefer_initializing_formals
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 20),
      responseType: ResponseType.json,
    ));
    _activa = _local.isNotEmpty ? _local : _publica;
  }

  late final Dio _dio;
  String _local;
  String _publica;
  String _token;
  String _activa = '';
  DateTime? _ultimaComprobacion;

  String get local => _local;
  String get publica => _publica;
  String get token => _token;
  String get direccion => _activa;
  bool get hayDireccion => _local.isNotEmpty || _publica.isNotEmpty;
  bool get conSesion => hayDireccion && _token.isNotEmpty;

  /// Avisa cuando el servidor rechaza la sesión, para que la app cierre.
  final StreamController<void> _sesionRota = StreamController<void>.broadcast();
  Stream<void> get alCaducarSesion => _sesionRota.stream;

  static String limpiar(String d) {
    var s = d.trim();
    if (s.isEmpty) return '';
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'http://$s';
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  void configurar({String? local, String? publica, String? token}) {
    if (local != null) _local = limpiar(local);
    if (publica != null) _publica = limpiar(publica);
    if (token != null) _token = token;
    if (_activa.isEmpty) _activa = _local.isNotEmpty ? _local : _publica;
  }

  void olvidar() {
    _token = '';
  }

  Map<String, String> get cabeceras => {'X-Caudal-Token': _token};

  String urlArchivo(String idTrabajo) => '$_activa/trabajos/$idTrabajo/archivo';

  // ---------------------------------------------------------------- conexión

  /// Elige la dirección que responde: primero la de casa, luego la de internet.
  Future<void> asegurarConexion({bool forzar = false}) async {
    if (!hayDireccion) {
      throw ErrorCaudal('Todavía no has conectado la app con tu servidor.');
    }

    // si hace poco que funcionaba, no perdemos tiempo comprobando
    final reciente = _ultimaComprobacion != null &&
        DateTime.now().difference(_ultimaComprobacion!) < const Duration(minutes: 2);
    if (!forzar && reciente && _activa.isNotEmpty) return;

    for (final candidata in [_activa, _local, _publica]) {
      if (candidata.isEmpty) continue;
      if (await _responde(candidata)) {
        _activa = candidata;
        _ultimaComprobacion = DateTime.now();
        return;
      }
    }

    throw ErrorCaudal(
      'No se llega al servidor. Comprueba que esté encendido y, si estás fuera '
      'de casa, que el acceso desde internet siga activo.',
      esDeConexion: true,
    );
  }

  Future<bool> _responde(String base) async {
    try {
      final r = await _dio.get<Map<String, dynamic>>(
        '$base/salud',
        options: Options(receiveTimeout: const Duration(seconds: 6)),
      );
      return (r.data ?? {})['servidor'] == 'Caudal';
    } catch (_) {
      return false;
    }
  }

  /// Comprueba una dirección concreta y devuelve los datos del servidor.
  Future<Map<String, dynamic>> comprobar(String base) async {
    final url = limpiar(base);
    if (url.isEmpty) throw ErrorCaudal('Falta la dirección del servidor.');
    try {
      final r = await _dio.get<Map<String, dynamic>>(
        '$url/salud',
        options: Options(receiveTimeout: const Duration(seconds: 8)),
      );
      final datos = r.data ?? {};
      if (datos['servidor'] != 'Caudal') {
        throw ErrorCaudal('Esa dirección responde, pero no es un servidor Caudal.');
      }
      return datos;
    } catch (e) {
      if (e is ErrorCaudal) rethrow;
      _traducir(e);
    }
  }

  Never _traducir(Object e) {
    if (e is DioException) {
      final codigo = e.response?.statusCode;
      if (codigo == 401) {
        _sesionRota.add(null);
        throw ErrorCaudal(
          'Tu sesión caducó. Vuelve a iniciar sesión con tu usuario y contraseña.',
          sesionCaducada: true,
        );
      }
      if (codigo == 403) {
        final detalle = _detalle(e);
        throw ErrorCaudal(detalle.isNotEmpty
            ? detalle
            : 'Eso solo se puede hacer desde la computadora o desde tu red de casa.');
      }
      if (codigo == 422 || codigo == 400) {
        final detalle = _detalle(e);
        throw ErrorCaudal(detalle.isNotEmpty ? detalle : 'El servidor no pudo con eso.');
      }
      if (codigo == 409) {
        throw ErrorCaudal('El archivo todavía no está listo.');
      }
      if (codigo == 404) {
        throw ErrorCaudal('Eso ya no existe en el servidor.');
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.unknown) {
        throw ErrorCaudal(
          'No se llega al servidor. Comprueba que esté encendido y que tengas conexión.',
          esDeConexion: true,
        );
      }
      if (e.type == DioExceptionType.receiveTimeout) {
        throw ErrorCaudal('El servidor tardó demasiado en responder.', esDeConexion: true);
      }
    }
    throw ErrorCaudal('Algo salió mal hablando con el servidor.');
  }

  String _detalle(DioException e) {
    final datos = e.response?.data;
    if (datos is Map && datos['detail'] != null) return '${datos['detail']}';
    return '';
  }

  Options get _conSesion => Options(headers: {'X-Caudal-Token': _token});

  // ---------------------------------------------------------------- cuenta

  /// Crea la cuenta. Solo funciona desde la red de casa.
  Future<Sesion> registrar({
    required String usuario,
    required String clave,
    String nombre = '',
    required String dispositivo,
  }) async {
    await asegurarConexion(forzar: true);
    try {
      final r = await _dio.post<Map<String, dynamic>>('$_activa/cuenta/registro', data: {
        'usuario': usuario,
        'clave': clave,
        'nombre': nombre,
        'dispositivo': dispositivo,
        'plataforma': Platform.operatingSystem,
      });
      final sesion = Sesion.desdeJson(r.data ?? {});
      _token = sesion.token;
      return sesion;
    } catch (e) {
      _traducir(e);
    }
  }

  Future<Sesion> entrar({
    required String usuario,
    required String clave,
    required String dispositivo,
  }) async {
    await asegurarConexion(forzar: true);
    try {
      final r = await _dio.post<Map<String, dynamic>>('$_activa/cuenta/entrar', data: {
        'usuario': usuario,
        'clave': clave,
        'dispositivo': dispositivo,
        'plataforma': Platform.operatingSystem,
      });
      final sesion = Sesion.desdeJson(r.data ?? {});
      _token = sesion.token;
      return sesion;
    } catch (e) {
      _traducir(e);
    }
  }

  Future<void> salir() async {
    if (!conSesion) return;
    try {
      await _dio.post('$_activa/cuenta/salir', options: _conSesion);
    } catch (_) {
      // si el servidor no está, la sesión se olvida igual en el teléfono
    }
    _token = '';
  }

  Future<({String usuario, String nombre, List<Dispositivo> dispositivos})> miCuenta() async {
    await asegurarConexion();
    try {
      final r = await _dio.get<Map<String, dynamic>>('$_activa/cuenta/yo', options: _conSesion);
      final datos = r.data ?? {};
      final lista = ((datos['dispositivos'] as List?) ?? [])
          .map((e) => Dispositivo.desdeJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      return (
        usuario: '${datos['usuario'] ?? ''}',
        nombre: '${datos['nombre'] ?? ''}',
        dispositivos: lista,
      );
    } catch (e) {
      _traducir(e);
    }
  }

  Future<void> cambiarClave(String actual, String nueva) async {
    await asegurarConexion();
    try {
      await _dio.post('$_activa/cuenta/clave',
          data: {'clave_actual': actual, 'clave_nueva': nueva}, options: _conSesion);
      _token = '';
    } catch (e) {
      _traducir(e);
    }
  }

  Future<void> desvincular(String idDispositivo) async {
    await asegurarConexion();
    try {
      await _dio.delete('$_activa/cuenta/dispositivos/$idDispositivo', options: _conSesion);
    } catch (e) {
      _traducir(e);
    }
  }

  // ---------------------------------------------------------------- contenido

  Future<Ficha> resolver(String url) async {
    await asegurarConexion();
    try {
      final r = await _dio.post<Map<String, dynamic>>(
        '$_activa/resolver',
        data: {'url': url},
        options: Options(
          headers: {'X-Caudal-Token': _token},
          receiveTimeout: const Duration(seconds: 45),
        ),
      );
      return Ficha.desdeJson(r.data ?? {});
    } catch (e) {
      _traducir(e);
    }
  }

  Future<List<Resultado>> buscar(String consulta, {int limite = 25}) async {
    await asegurarConexion();
    try {
      final r = await _dio.get<Map<String, dynamic>>(
        '$_activa/buscar',
        queryParameters: {'q': consulta, 'limite': limite},
        options: Options(
          headers: {'X-Caudal-Token': _token},
          receiveTimeout: const Duration(seconds: 45),
        ),
      );
      final lista = (r.data?['resultados'] as List?) ?? [];
      return lista
          .map((e) => Resultado.desdeJson(Map<String, dynamic>.from(e as Map)))
          .where((x) => x.url.isNotEmpty)
          .toList();
    } catch (e) {
      _traducir(e);
    }
  }

  /// Lee las canciones de una lista de Spotify, Apple Music o YouTube Music.
  Future<ListaImportada> leerLista(String url) async {
    await asegurarConexion();
    try {
      final r = await _dio.post<Map<String, dynamic>>(
        '$_activa/listas/leer',
        data: {'url': url},
        options: Options(
          headers: {'X-Caudal-Token': _token},
          receiveTimeout: const Duration(seconds: 90),
        ),
      );
      return ListaImportada.desdeJson(r.data ?? {});
    } catch (e) {
      _traducir(e);
    }
  }

  Future<EstadoTrabajo> crearTrabajo({
    String url = '',
    String busqueda = '',
    required TipoMedio tipo,
    String calidad = 'mejor',
    String formatoAudio = 'mp3',
    String contenedor = 'mp4',
    bool refuerzoAudio = false,
  }) async {
    await asegurarConexion();
    try {
      final r = await _dio.post<Map<String, dynamic>>(
        '$_activa/trabajos',
        data: {
          'url': url,
          'busqueda': busqueda,
          'tipo': tipo.clave,
          'calidad': calidad,
          'formato_audio': formatoAudio,
          'contenedor': contenedor,
          'refuerzo_audio': refuerzoAudio,
        },
        options: _conSesion,
      );
      return EstadoTrabajo.desdeJson(r.data ?? {});
    } catch (e) {
      _traducir(e);
    }
  }

  Future<EstadoTrabajo> verTrabajo(String id) async {
    try {
      final r = await _dio.get<Map<String, dynamic>>('$_activa/trabajos/$id',
          options: _conSesion);
      return EstadoTrabajo.desdeJson(r.data ?? {});
    } catch (e) {
      _traducir(e);
    }
  }

  Future<void> cancelarTrabajo(String id) async {
    if (!conSesion) return;
    try {
      await _dio.delete('$_activa/trabajos/$id', options: _conSesion);
    } catch (_) {
      // cancelar es "lo mejor que se pueda": si el servidor ya no lo tiene, da igual
    }
  }

  void dispose() {
    _sesionRota.close();
  }
}
