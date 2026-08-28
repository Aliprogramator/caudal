/// Modelos de datos de Caudal.
library;

/// Un fallo que se le puede contar al usuario tal cual, con sus palabras.
class ErrorCaudal implements Exception {
  ErrorCaudal(this.mensaje, {this.esDeConexion = false});

  final String mensaje;
  final bool esDeConexion;

  @override
  String toString() => mensaje;
}

/// Qué se descarga de un enlace.
enum TipoMedio { completo, video, audio }

extension TipoMedioTexto on TipoMedio {
  String get clave => switch (this) {
        TipoMedio.completo => 'completo',
        TipoMedio.video => 'video',
        TipoMedio.audio => 'audio',
      };

  String get titulo => switch (this) {
        TipoMedio.completo => 'Video con audio',
        TipoMedio.video => 'Solo video',
        TipoMedio.audio => 'Solo audio',
      };

  String get detalle => switch (this) {
        TipoMedio.completo => 'El video completo, como se ve en la web',
        TipoMedio.video => 'Solo la imagen, sin sonido',
        TipoMedio.audio => 'Solo el sonido, ideal para música',
      };

  static TipoMedio desdeClave(String? clave) => switch (clave) {
        'video' => TipoMedio.video,
        'audio' => TipoMedio.audio,
        _ => TipoMedio.completo,
      };
}

/// Una calidad disponible para un video.
class Calidad {
  const Calidad({required this.valor, required this.etiqueta, required this.altura});

  final String valor;
  final String etiqueta;
  final int altura;

  factory Calidad.desdeJson(Map<String, dynamic> j) => Calidad(
        valor: '${j['valor'] ?? 'mejor'}',
        etiqueta: '${j['etiqueta'] ?? ''}',
        altura: (j['altura'] as num?)?.toInt() ?? 0,
      );
}

/// Lo que el servidor sabe de un enlace antes de descargarlo.
class Ficha {
  const Ficha({
    required this.url,
    required this.titulo,
    this.autor = '',
    this.miniatura = '',
    this.duracion = 0,
    this.duracionTexto = '',
    this.plataforma = '',
    this.calidades = const [],
    this.tieneVideo = true,
    this.tieneAudio = true,
    this.esDirecto = false,
    this.esLista = false,
    this.elementos = const [],
  });

  final String url;
  final String titulo;
  final String autor;
  final String miniatura;
  final int duracion;
  final String duracionTexto;
  final String plataforma;
  final List<Calidad> calidades;
  final bool tieneVideo;
  final bool tieneAudio;
  final bool esDirecto;
  final bool esLista;
  final List<Ficha> elementos;

  factory Ficha.desdeJson(Map<String, dynamic> j) {
    final esLista = j['es_lista'] == true;
    return Ficha(
      url: '${j['url'] ?? ''}',
      titulo: '${j['titulo'] ?? ''}',
      autor: '${j['autor'] ?? ''}',
      miniatura: '${j['miniatura'] ?? ''}',
      duracion: (j['duracion'] as num?)?.toInt() ?? 0,
      duracionTexto: '${j['duracion_texto'] ?? ''}',
      plataforma: '${j['plataforma'] ?? ''}',
      tieneVideo: j['tiene_video'] != false,
      tieneAudio: j['tiene_audio'] != false,
      esDirecto: j['es_directo'] == true,
      esLista: esLista,
      calidades: ((j['calidades'] as List?) ?? [])
          .map((e) => Calidad.desdeJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      elementos: ((j['elementos'] as List?) ?? [])
          .map((e) => Ficha.desdeJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

/// Un resultado de búsqueda.
class Resultado {
  const Resultado({
    required this.url,
    required this.titulo,
    this.autor = '',
    this.miniatura = '',
    this.duracionTexto = '',
    this.vistas = 0,
  });

  final String url;
  final String titulo;
  final String autor;
  final String miniatura;
  final String duracionTexto;
  final int vistas;

  factory Resultado.desdeJson(Map<String, dynamic> j) => Resultado(
        url: '${j['url'] ?? ''}',
        titulo: '${j['titulo'] ?? ''}',
        autor: '${j['autor'] ?? ''}',
        miniatura: '${j['miniatura'] ?? ''}',
        duracionTexto: '${j['duracion_texto'] ?? ''}',
        vistas: (j['vistas'] as num?)?.toInt() ?? 0,
      );
}

/// Estados por los que pasa una descarga en el teléfono.
enum EstadoDescarga { enCola, preparando, descargando, completada, error, cancelada, pausada }

extension EstadoTexto on EstadoDescarga {
  String get titulo => switch (this) {
        EstadoDescarga.enCola => 'En cola',
        EstadoDescarga.preparando => 'Preparando',
        EstadoDescarga.descargando => 'Descargando',
        EstadoDescarga.completada => 'Listo',
        EstadoDescarga.error => 'Error',
        EstadoDescarga.cancelada => 'Cancelada',
        EstadoDescarga.pausada => 'En pausa',
      };

  bool get activa =>
      this == EstadoDescarga.enCola ||
      this == EstadoDescarga.preparando ||
      this == EstadoDescarga.descargando;
}

/// Un elemento ya guardado en el teléfono.
class Pista {
  const Pista({
    required this.id,
    required this.titulo,
    required this.archivo,
    required this.esAudio,
    this.autor = '',
    this.miniatura = '',
    this.duracion = 0,
    this.tamano = 0,
    this.origen = '',
    this.fecha = 0,
  });

  final int id;
  final String titulo;
  final String archivo;
  final bool esAudio;
  final String autor;
  final String miniatura;
  final int duracion;
  final int tamano;
  final String origen;
  final int fecha;

  Map<String, Object?> aFila() => {
        'titulo': titulo,
        'autor': autor,
        'archivo': archivo,
        'miniatura': miniatura,
        'duracion': duracion,
        'tamano': tamano,
        'origen': origen,
        'es_audio': esAudio ? 1 : 0,
        'fecha': fecha,
      };

  factory Pista.desdeFila(Map<String, Object?> f) => Pista(
        id: (f['id'] as num?)?.toInt() ?? 0,
        titulo: '${f['titulo'] ?? ''}',
        autor: '${f['autor'] ?? ''}',
        archivo: '${f['archivo'] ?? ''}',
        miniatura: '${f['miniatura'] ?? ''}',
        duracion: (f['duracion'] as num?)?.toInt() ?? 0,
        tamano: (f['tamano'] as num?)?.toInt() ?? 0,
        origen: '${f['origen'] ?? ''}',
        esAudio: ((f['es_audio'] as num?)?.toInt() ?? 0) == 1,
        fecha: (f['fecha'] as num?)?.toInt() ?? 0,
      );
}

/// Una canción dentro de una lista importada de Spotify, Apple Music o YouTube.
class CancionLista {
  const CancionLista({
    required this.titulo,
    this.artista = '',
    this.duracion = 0,
    this.url = '',
    this.busqueda = '',
    this.miniatura = '',
  });

  final String titulo;
  final String artista;
  final int duracion;

  /// Enlace exacto (YouTube). Si está vacío se busca por [busqueda].
  final String url;
  final String busqueda;
  final String miniatura;

  factory CancionLista.desdeJson(Map<String, dynamic> j) => CancionLista(
        titulo: '${j['titulo'] ?? ''}',
        artista: '${j['artista'] ?? ''}',
        duracion: (j['duracion'] as num?)?.toInt() ?? 0,
        url: '${j['url'] ?? ''}',
        busqueda: '${j['busqueda'] ?? ''}',
        miniatura: '${j['miniatura'] ?? ''}',
      );
}

/// Una lista de reproducción leída de otra plataforma.
class ListaImportada {
  const ListaImportada({
    required this.titulo,
    required this.plataforma,
    this.autor = '',
    this.portada = '',
    this.canciones = const [],
  });

  final String titulo;
  final String plataforma;
  final String autor;
  final String portada;
  final List<CancionLista> canciones;

  int get total => canciones.length;

  factory ListaImportada.desdeJson(Map<String, dynamic> j) => ListaImportada(
        titulo: '${j['titulo'] ?? ''}',
        plataforma: '${j['plataforma'] ?? ''}',
        autor: '${j['autor'] ?? ''}',
        portada: '${j['portada'] ?? ''}',
        canciones: ((j['canciones'] as List?) ?? [])
            .map((e) => CancionLista.desdeJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}
