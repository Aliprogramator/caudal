import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../main.dart';
import '../nucleo/captura.dart';
import '../nucleo/deteccion.dart';
import '../nucleo/descargas.dart';
import '../nucleo/formato.dart';
import '../nucleo/modelos.dart';
import '../nucleo/motor_local.dart';
import '../nucleo/navegador_caudal.dart';
import '../nucleo/tema.dart';
import '../widgets/barra_rapida.dart';
import '../widgets/comunes.dart';
import '../widgets/hoja_descarga.dart';
import 'inicio.dart';

/// Sitios sugeridos al abrir el navegador por primera vez.
const _sugeridos = [
  ('YouTube', 'https://www.youtube.com', Icons.play_circle_fill_rounded, Color(0xFFFF0033)),
  ('YouTube Music', 'https://music.youtube.com', Icons.library_music_rounded, Color(0xFFFF0033)),
  ('Instagram', 'https://www.instagram.com', Icons.camera_alt_rounded, Color(0xFFE1306C)),
  ('TikTok', 'https://www.tiktok.com', Icons.music_video_rounded, Color(0xFF00F2EA)),
  ('X', 'https://x.com', Icons.tag_rounded, Color(0xFF1D9BF0)),
  ('Facebook', 'https://www.facebook.com', Icons.facebook_rounded, Color(0xFF1877F2)),
  ('SoundCloud', 'https://soundcloud.com', Icons.cloud_rounded, Color(0xFFFF5500)),
  ('Twitch', 'https://www.twitch.tv', Icons.videogame_asset_rounded, Color(0xFF9146FF)),
];

/// Cuantas pestanas se dejan abrir a la vez.
///
/// Cada una es un navegador entero corriendo: pasado cierto punto el telefono
/// empieza a cerrarlas por su cuenta y se pierde lo que hubiera en ellas.
const int _topeDePestanas = 8;

/// El navegador de Caudal.
///
/// Al entrar en un video aparecen solos los botones para bajarlo, y lo que la
/// propia web mande descargar se recoge tambien.
class VistaNavegador extends StatefulWidget {
  const VistaNavegador({super.key});

  @override
  State<VistaNavegador> createState() => _VistaNavegadorState();
}

class _VistaNavegadorState extends State<VistaNavegador>
    with AutomaticKeepAliveClientMixin {
  final _direccion = TextEditingController();
  final _focoDireccion = FocusNode();

  NavegadorCaudal? _nav;
  StreamSubscription<PeticionDescarga>? _escuchaDescargas;
  Timer? _retardo;
  int _peticion = 0;
  bool _buscandoMedia = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final navegador = Servicios.de(context).navegador;
    if (identical(navegador, _nav)) return;
    _nav?.removeListener(_alCambiarPestanas);
    _escuchaDescargas?.cancel();
    _nav = navegador;
    navegador.addListener(_alCambiarPestanas);
    navegador.preparar();
    _escuchaDescargas = navegador.alPedirDescarga.listen(_atenderDescargaWeb);
  }

  @override
  void dispose() {
    _retardo?.cancel();
    _escuchaDescargas?.cancel();
    _nav?.removeListener(_alCambiarPestanas);
    _direccion.dispose();
    _focoDireccion.dispose();
    super.dispose();
  }

  void _alCambiarPestanas() {
    if (!mounted) return;
    setState(() {});
    _sincronizarDireccion();
  }

  NavegadorCaudal get _navegador => _nav!;
  Pestana get _pestana => _navegador.activa;

  void _sincronizarDireccion() {
    final url = _pestana.url;
    if (_focoDireccion.hasFocus) return;
    if (_direccion.text != url) _direccion.text = url;
  }

  // ---------------------------------------------------------------- deteccion

  /// Punto unico por el que pasa cualquier cambio de direccion.
  void _cambiarUrl(Pestana pestana, String url) {
    if (url.isEmpty || url == pestana.url) return;

    // Al pasar de un reel al siguiente, o de un video de YouTube a otro, la
    // pagina no se recarga: cambia la direccion y ya. Si no se olvidan los
    // medios del anterior, el boton de descargar baja el video equivocado.
    // Los saltos que solo cambian parametros no cuentan: ahi seguimos en lo
    // mismo y tirar lo capturado seria perderlo por nada.
    if (_esOtraPagina(pestana.url, url)) pestana.olvidarMedios();

    pestana.barraOculta = false;
    if (pestana.urlDeLaFicha != url) {
      pestana.ficha = null;
      pestana.urlDeLaFicha = '';
    }
    pestana.cambiar(url: url);
    if (identical(pestana, _pestana)) {
      _sincronizarDireccion();
      _programarResolucion();
    }
  }

  /// Mira de que va la pagina, con un respiro para no disparar una consulta
  /// por cada rebote de navegacion.
  void _programarResolucion() {
    _retardo?.cancel();
    final pestana = _pestana;
    if (!pareceDescargable(pestana.url)) {
      if (pestana.resolviendo) {
        pestana.resolviendo = false;
        pestana.refrescar();
      }
      return;
    }
    pestana.resolviendo = true;
    pestana.refrescar();
    _retardo = Timer(const Duration(milliseconds: 700), _resolver);
  }

  Future<void> _resolver() async {
    final pestana = _pestana;
    final url = pestana.url;
    final mio = ++_peticion;
    Ficha? ficha;
    try {
      // YouTube da titulo, autor y calidades de verdad; el resto de sitios se
      // resuelven con lo que el navegador ya sabe de la pagina
      ficha = await Servicios.de(context).descargas.resolverSiPuede(url);
    } catch (_) {
      // sin datos, pero la barra sigue: el video se baja igual con lo capturado
      ficha = null;
    }
    if (!mounted || mio != _peticion || url != pestana.url) return;
    pestana.ficha =
        ficha ?? Ficha(url: url, titulo: pestana.titulo, plataforma: sitioDe(url));
    pestana.urlDeLaFicha = url;
    pestana.resolviendo = false;
    pestana.refrescar();
  }

  /// Si las dos direcciones son de verdad paginas distintas.
  static bool _esOtraPagina(String antes, String ahora) {
    if (antes.isEmpty) return false;
    try {
      final a = Uri.parse(antes);
      final b = Uri.parse(ahora);
      if (a.host != b.host || a.path != b.path) return true;
      // youtube.com/watch?v=... : el video va en el parametro, no en la ruta
      return a.queryParameters['v'] != b.queryParameters['v'];
    } on FormatException {
      return antes != ahora;
    }
  }

  bool get _barraVisible {
    final p = _pestana;
    return !p.vacia &&
        !p.barraOculta &&
        (p.resolviendo || p.ficha != null) &&
        pareceDescargable(p.url);
  }

  // ---------------------------------------------------------------- descargas

  /// Las cookies de sesion de la pagina que se esta viendo.
  ///
  /// Se piden al navegador, no a la pagina: las que de verdad autorizan la
  /// descarga van marcadas HttpOnly y `document.cookie` no las ve. Con las de
  /// la pagina, Instagram y compania responden 403.
  Future<String> _cookiesDeLaPagina() =>
      NavegadorCaudal.cookiesDe(_pestana.url);

  /// Las direcciones vistas, de mejor a peor.
  ///
  /// Si todavia no hemos visto pasar nada, se empuja al video a arrancar y se
  /// espera un momento: casi siempre con eso aparece.
  Future<List<String>> _mediosParaDescargar(TipoMedio tipo) async {
    final pestana = _pestana;
    final paraAudio = tipo == TipoMedio.audio;

    List<String> deLoVisto() => candidatasOrdenadas(pestana.medios, paraAudio: paraAudio)
        .map((m) => m.url)
        .toList();

    if (pestana.medios.isNotEmpty) return deLoVisto();

    // en YouTube no se insiste ni se despierta nada: su motor va primero
    if (MotorLocal.puedeSolo(pestana.url)) return const [];

    // nada capturado: le damos un empujon al reproductor y esperamos
    await pestana.web?.evaluateJavascript(source: guionDespertar);

    for (var intento = 0; intento < 12; intento++) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return const [];
      if (pestana.medios.isNotEmpty) return deLoVisto();
      if (intento == 5) {
        await pestana.web?.evaluateJavascript(source: guionDespertar);
      }
    }
    return const [];
  }

  Future<void> _descargarDirecto(TipoMedio tipo) async {
    final servicios = Servicios.de(context);
    final pestana = _pestana;
    if (pestana.url.isEmpty || _buscandoMedia) return;

    final esYoutube = MotorLocal.puedeSolo(pestana.url);
    if (!esYoutube && pestana.medios.isEmpty) {
      setState(() => _buscandoMedia = true);
      avisar(context, 'Buscando el video en la pagina...');
    }

    final medios = await _mediosParaDescargar(tipo);
    if (!mounted) return;
    setState(() => _buscandoMedia = false);

    if (!esYoutube && medios.isEmpty) {
      avisar(
        context,
        'No se vio pasar ningun video. Dale al play y vuelve a intentarlo.',
        esError: true,
      );
      return;
    }

    final galletas = await _cookiesDeLaPagina();
    if (!mounted) return;

    servicios.descargas.encolar(
      url: pestana.url,
      urlMedia: medios.isEmpty ? '' : medios.first,
      candidatas: medios,
      cookies: galletas,
      tipo: tipo,
      calidad: 'mejor',
      formatoAudio: servicios.ajustes.formatoAudio,
      titulo: pestana.ficha?.titulo.isNotEmpty == true
          ? pestana.ficha!.titulo
          : pestana.titulo,
      autor: pestana.ficha?.autor ?? '',
      miniatura: pestana.ficha?.miniatura ?? '',
    );

    avisar(
      context,
      tipo == TipoMedio.audio
          ? 'Bajando el audio en la mejor calidad'
          : 'Bajando el video en la mejor calidad',
    );
  }

  Future<void> _abrirOpciones() async {
    final servicios = Servicios.de(context);
    final pestana = _pestana;
    if (pestana.url.isEmpty) return;

    final eleccion = await mostrarHojaDescarga(
      context,
      url: pestana.url,
      descargas: servicios.descargas,
      ajustes: servicios.ajustes,
      fichaConocida: pestana.ficha,
    );
    if (eleccion == null || !mounted) return;

    // lo que vimos pasar en la pagina vale igual desde aqui
    final medios = await _mediosParaDescargar(eleccion.tipo);
    final galletas = await _cookiesDeLaPagina();
    if (!mounted) return;

    encolarYAvisar(
      context,
      gestor: servicios.descargas,
      url: pestana.url,
      urlMedia: medios.isEmpty ? '' : medios.first,
      candidatas: medios,
      cookies: galletas,
      tipo: eleccion.tipo,
      calidad: eleccion.calidad,
      formatoAudio: eleccion.formatoAudio,
      titulo: eleccion.ficha.titulo.isNotEmpty
          ? eleccion.ficha.titulo
          : pestana.titulo,
      autor: eleccion.ficha.autor,
      miniatura: eleccion.ficha.miniatura,
    );
  }

  /// Lo que la propia web mando descargar.
  ///
  /// Antes esto no ocurria nunca: el visor de siempre no avisa de las
  /// descargas, asi que pulsar el boton de descargar de cualquier pagina no
  /// hacia absolutamente nada.
  Future<void> _atenderDescargaWeb(PeticionDescarga peticion) async {
    if (!mounted) return;
    final servicios = Servicios.de(context);
    // el archivo casi nunca sale del mismo dominio que la pagina: las cookies
    // que valen son las del servidor que lo sirve, y si ahi no hay ninguna,
    // las de la pagina desde la que se pidio
    var galletas = await NavegadorCaudal.cookiesDe(peticion.url);
    if (galletas.isEmpty && peticion.referente.isNotEmpty) {
      galletas = await NavegadorCaudal.cookiesDe(peticion.referente);
    }
    if (!mounted) return;

    final nombre = peticion.nombre.isNotEmpty
        ? peticion.nombre
        : _nombreDeLaUrl(peticion.url);

    servicios.descargas.encolarArchivo(
      url: peticion.url,
      nombre: nombre,
      cookies: galletas,
      referente: peticion.referente,
      esAudio: peticion.esAudio,
    );

    avisar(context, 'Bajando $nombre');
  }

  /// Un archivo que la pagina armo ella misma y nos entrega ya hecho.
  Future<void> _guardarArchivoDeLaPagina(String mensaje) async {
    Map<String, dynamic> datos;
    try {
      datos = Map<String, dynamic>.from(jsonDecode(mensaje) as Map);
    } catch (_) {
      return;
    }
    final contenido = '${datos['datos'] ?? ''}';
    if (contenido.isEmpty || !mounted) return;

    final nombre = '${datos['nombre'] ?? 'descarga'}';
    try {
      final bytes = base64Decode(contenido);
      final ajustes = Servicios.de(context).ajustes;
      final esAudio = RegExp(r'\.(mp3|m4a|aac|ogg|opus|flac|wav)$',
              caseSensitive: false)
          .hasMatch(nombre);
      final esMedia = esAudio ||
          RegExp(r'\.(mp4|m4v|mov|mkv|webm|avi|flv)$', caseSensitive: false)
              .hasMatch(nombre);
      final carpeta = await GestorDescargas.carpetaDeGuardado(
        esAudio,
        ajustes.guardarEnPublico,
        subcarpeta: esMedia ? null : 'Archivos',
      );
      final ruta = await MotorLocal().guardarBytes(
        datos: bytes,
        nombre: nombre,
        carpeta: carpeta,
      );
      if (!mounted) return;
      avisar(context, 'Guardado ${ruta.split(Platform.pathSeparator).last}');
    } catch (_) {
      if (mounted) {
        avisar(context, 'No se pudo guardar ese archivo', esError: true);
      }
    }
  }

  static String _nombreDeLaUrl(String url) {
    try {
      final partes = Uri.parse(url).pathSegments;
      if (partes.isNotEmpty && partes.last.isNotEmpty) return partes.last;
    } catch (_) {
      // una direccion rara: se le pone un nombre y ya
    }
    return 'descarga';
  }

  // ---------------------------------------------------------------- navegar

  void _ir(String entrada) {
    final texto = entrada.trim();
    if (texto.isEmpty) return;
    final url = pareceEnlace(texto)
        ? normalizarEnlace(texto)
        : 'https://www.google.com/search?q=${Uri.encodeQueryComponent(texto)}';
    _focoDireccion.unfocus();
    // en la portada todavia no hay navegador montado: al apuntar la direccion
    // hay que reconstruir para que nazca ya cargandola
    setState(() => _pestana.cargar(url));
    _programarResolucion();
  }

  // ---------------------------------------------------------------- interfaz

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_nav == null) return const SizedBox.shrink();

    final pestana = _pestana;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _barraDireccion(),
            ListenableBuilder(
              listenable: pestana,
              builder: (context, _) => pestana.cargando && pestana.progreso < 100
                  ? BarraProgreso(valor: pestana.progreso / 100, alto: 2.5)
                  : const SizedBox(height: 2.5),
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IndexedStack(
                      index: _navegador.indice,
                      children: [
                        for (final p in _navegador.pestanas) _lienzo(p),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ListenableBuilder(
                      listenable: pestana,
                      builder: (context, _) => BarraRapida(
                        visible: _barraVisible,
                        resolviendo: pestana.resolviendo && pestana.ficha == null,
                        ficha: pestana.ficha,
                        tituloPagina: pestana.titulo,
                        priorizarAudio: esSitioDeAudio(pestana.url),
                        alDescargarVideo: () => _descargarDirecto(TipoMedio.completo),
                        alDescargarAudio: () => _descargarDirecto(TipoMedio.audio),
                        alAbrirOpciones: _abrirOpciones,
                        alCerrar: () {
                          pestana.barraOculta = true;
                          pestana.refrescar();
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _barraInferior(),
          ],
        ),
      ),
    );
  }

  /// Lo que se ve en una pestana: la portada o su navegador.
  Widget _lienzo(Pestana pestana) {
    if (pestana.vacia && pestana.windowId == null) return _portada();
    return _VistaWeb(
      key: ObjectKey(pestana),
      pestana: pestana,
      navegador: _navegador,
      alCambiarUrl: (url) => _cambiarUrl(pestana, url),
      alGuardarArchivo: _guardarArchivoDeLaPagina,
      alPedirVentana: (url, windowId) {
        if (_navegador.pestanas.length >= _topeDePestanas) {
          avisar(context, 'Ya hay demasiadas pestanas abiertas', esError: true);
          return false;
        }
        _navegador.abrir(url: url, windowId: windowId);
        return true;
      },
    );
  }

  Widget _barraDireccion() {
    final pestana = _pestana;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 44,
              child: TextField(
                controller: _direccion,
                focusNode: _focoDireccion,
                textInputAction: TextInputAction.go,
                keyboardType: TextInputType.url,
                onSubmitted: _ir,
                style: const TextStyle(fontSize: 13.5),
                decoration: InputDecoration(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                  hintText: 'Busca o escribe una dirección',
                  prefixIcon: Icon(
                    pestana.url.startsWith('https')
                        ? Icons.lock_rounded
                        : Icons.public_rounded,
                    size: 16,
                    color: pestana.url.startsWith('https')
                        ? Tono.exito
                        : Tono.texto3,
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 38),
                  suffixIcon: pestana.url.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          color: Tono.texto3,
                          onPressed: () => pestana.web?.reload(),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _BotonPestanas(
            cuantas: _navegador.pestanas.length,
            alPulsar: _abrirListaDePestanas,
          ),
        ],
      ),
    );
  }

  Widget _barraInferior() {
    final pestana = _pestana;
    return ListenableBuilder(
      listenable: pestana,
      builder: (context, _) {
        final hayMedios = pestana.medios.isNotEmpty;
        return Container(
          decoration: const BoxDecoration(
            color: Tono.superficie,
            border: Border(top: BorderSide(color: Tono.borde)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                onPressed: pestana.puedeAtras ? () => pestana.web?.goBack() : null,
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
                color: Tono.texto2,
                disabledColor: Tono.texto3.withValues(alpha: 0.4),
              ),
              IconButton(
                onPressed:
                    pestana.puedeAdelante ? () => pestana.web?.goForward() : null,
                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 19),
                color: Tono.texto2,
                disabledColor: Tono.texto3.withValues(alpha: 0.4),
              ),
              IconButton(
                onPressed: _irAlInicio,
                icon: const Icon(Icons.home_rounded, size: 21),
                color: Tono.texto2,
              ),
              IconButton(
                onPressed: hayMedios ? _verMediosDetectados : null,
                icon: Badge(
                  isLabelVisible: hayMedios,
                  label: Text('${pestana.medios.length}'),
                  backgroundColor: Tono.acento,
                  textColor: const Color(0xFF04202A),
                  child: const Icon(Icons.playlist_add_rounded, size: 21),
                ),
                color: Tono.texto2,
                disabledColor: Tono.texto3.withValues(alpha: 0.4),
                tooltip: 'Medios sueltos de la página',
              ),
              IconButton(
                onPressed: pestana.url.isEmpty ? null : _abrirOpciones,
                icon: const Icon(Icons.download_rounded, size: 22),
                color: Tono.acento,
                disabledColor: Tono.texto3.withValues(alpha: 0.4),
                tooltip: 'Descargar esta página',
              ),
            ],
          ),
        );
      },
    );
  }

  void _irAlInicio() {
    final pestana = _pestana;
    pestana.olvidarMedios();
    pestana.ficha = null;
    pestana.urlDeLaFicha = '';
    pestana.urlInicial = '';
    pestana.cambiar(url: '', titulo: '', cargando: false, progreso: 0);
    pestana.web = null;
    _direccion.clear();
    setState(() {});
  }

  void _abrirListaDePestanas() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Tono.superficie,
      builder: (_) => StatefulBuilder(
        builder: (contextoHoja, refrescar) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Medidas.margen, 6, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Pestañas',
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    TextButton.icon(
                      onPressed: _navegador.pestanas.length >= _topeDePestanas
                          ? null
                          : () {
                              _navegador.abrir();
                              Navigator.of(contextoHoja).pop();
                            },
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Nueva'),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (var i = 0; i < _navegador.pestanas.length; i++)
                      _FilaPestana(
                        pestana: _navegador.pestanas[i],
                        activa: i == _navegador.indice,
                        alAbrir: () {
                          _navegador.irA(i);
                          Navigator.of(contextoHoja).pop();
                        },
                        alCerrar: () {
                          _navegador.cerrar(_navegador.pestanas[i]);
                          refrescar(() {});
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _verMediosDetectados() {
    final pestana = _pestana;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Tono.superficie,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Medidas.margen, 4, Medidas.margen, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Medios en esta página',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Archivos que la página tiene cargados. Úsalo si los botones '
                    'de arriba no encuentran el video.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final medio in candidatasOrdenadas(pestana.medios))
                    ListTile(
                      leading: Icon(
                        medio.esSoloAudio
                            ? Icons.music_note_rounded
                            : Icons.movie_outlined,
                        color: Tono.acento,
                      ),
                      title: Text(
                        Uri.parse(medio.url).pathSegments.isEmpty
                            ? medio.url
                            : Uri.parse(medio.url).pathSegments.last,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: Text(
                        medio.esLista
                            ? '${sitioDe(medio.url)} · por trozos'
                            : sitioDe(medio.url),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      trailing: const Icon(Icons.download_rounded, size: 20),
                      onTap: () {
                        Navigator.of(context).pop();
                        _descargarMedioDirecto(medio.url);
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _descargarMedioDirecto(String url) async {
    final servicios = Servicios.de(context);
    final pestana = _pestana;
    final eleccion = await mostrarHojaDescarga(
      context,
      url: url,
      descargas: servicios.descargas,
      ajustes: servicios.ajustes,
    );
    if (eleccion == null || !mounted) return;
    final galletas = await _cookiesDeLaPagina();
    if (!mounted) return;
    encolarYAvisar(
      context,
      gestor: servicios.descargas,
      url: pestana.url.isEmpty ? url : pestana.url,
      // aqui la direccion ya es la del archivo: se pasa como tal
      urlMedia: url,
      cookies: galletas,
      tipo: eleccion.tipo,
      calidad: eleccion.calidad,
      formatoAudio: eleccion.formatoAudio,
      titulo: eleccion.ficha.titulo.isNotEmpty
          ? eleccion.ficha.titulo
          : pestana.titulo,
      miniatura: eleccion.ficha.miniatura,
    );
  }

  Widget _portada() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(Medidas.margen, 8, Medidas.margen, 24),
      children: [
        Text('Navegador', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Entra donde quieras. Al abrir un video aparecen solos los botones '
          'para bajarlo.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 22),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.82,
          children: [
            for (final (nombre, url, icono, color) in _sugeridos)
              _Acceso(nombre: nombre, url: url, icono: icono, color: color, alPulsar: _ir),
          ],
        ),
        const SizedBox(height: 24),
        const Aviso(
          texto: 'Cualquier web sirve, no solo estas. Cuando estés viendo algo '
              'descargable, la app lo detecta sola. Y si la propia página te '
              'ofrece un archivo, también se guarda.',
          icono: Icons.lightbulb_outline_rounded,
          color: Tono.acento,
        ),
      ],
    );
  }
}

/// El navegador de una pestana.
///
/// Aqui se ata todo lo que el visor de siempre no dejaba hacer: el guion que
/// entra antes que el de la pagina, el interceptor que ve pasar cada peticion,
/// las descargas que dispara el sitio y las ventanas que pide abrir.
class _VistaWeb extends StatefulWidget {
  const _VistaWeb({
    super.key,
    required this.pestana,
    required this.navegador,
    required this.alCambiarUrl,
    required this.alGuardarArchivo,
    required this.alPedirVentana,
  });

  final Pestana pestana;
  final NavegadorCaudal navegador;
  final void Function(String url) alCambiarUrl;
  final void Function(String mensaje) alGuardarArchivo;
  final bool Function(String url, int windowId) alPedirVentana;

  @override
  State<_VistaWeb> createState() => _VistaWebState();
}

class _VistaWebState extends State<_VistaWeb> {
  Pestana get _p => widget.pestana;

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      windowId: _p.windowId,
      initialUrlRequest: _p.windowId != null || _p.urlInicial.isEmpty
          ? null
          : URLRequest(url: WebUri(_p.urlInicial)),
      initialSettings: ajustesNavegador(),
      initialUserScripts: guionesDeArranque(),
      onWebViewCreated: (controlador) {
        _p.web = controlador;
        controlador.addJavaScriptHandler(
          handlerName: 'caudalMedios',
          callback: (argumentos) {
            if (argumentos.isNotEmpty) _medioEncontrado('${argumentos.first}');
            return null;
          },
        );
        controlador.addJavaScriptHandler(
          handlerName: 'caudalRuta',
          callback: (argumentos) {
            if (argumentos.isNotEmpty) widget.alCambiarUrl('${argumentos.first}');
            return null;
          },
        );
        controlador.addJavaScriptHandler(
          handlerName: 'caudalArchivo',
          callback: (argumentos) {
            if (argumentos.isNotEmpty) widget.alGuardarArchivo('${argumentos.first}');
            return null;
          },
        );
      },

      // --- lo que ve pasar el navegador
      //
      // Por aqui pasa todo lo que pide la pagina, incluido lo que piden sus
      // workers. Es la red que el guion de JavaScript no puede tender.
      shouldInterceptRequest: (controlador, peticion) async {
        final url = peticion.url.toString();
        if (podriaSerMedia(url)) _p.anotar(url, 'red');
        return null;      // que la peticion siga su curso normal
      },
      onLoadResource: (controlador, recurso) async {
        final url = recurso.url.toString();
        if (podriaSerMedia(url)) _p.anotar(url, 'recurso');
      },

      // --- lo que la propia web manda descargar
      onDownloadStartRequest: (controlador, peticion) async {
        widget.navegador.pedirDescarga(PeticionDescarga(
          url: peticion.url.toString(),
          nombre: peticion.suggestedFilename ?? '',
          tipoMime: peticion.mimeType ?? '',
          tamano: peticion.contentLength,
          referente: _p.url,
        ));
      },

      // --- las ventanas que pide abrir la pagina
      onCreateWindow: (controlador, accion) async {
        final destino = accion.request.url?.toString() ?? '';
        return widget.alPedirVentana(destino, accion.windowId);
      },
      onCloseWindow: (controlador) async {
        if (_p.windowId != null) widget.navegador.cerrar(_p);
      },

      // --- estado de la pagina
      onLoadStart: (controlador, url) {
        _p.olvidarMedios();
        _p.cambiar(cargando: true);
        widget.alCambiarUrl(url?.toString() ?? '');
      },
      onLoadStop: (controlador, url) async {
        _p.cambiar(cargando: false);
        widget.alCambiarUrl(url?.toString() ?? '');
        final titulo = await controlador.getTitle();
        _p.cambiar(titulo: titulo ?? '');
        await _p.refrescarBotones();
      },
      onProgressChanged: (controlador, progreso) {
        _p.cambiar(progreso: progreso, cargando: progreso < 100);
      },
      onTitleChanged: (controlador, titulo) {
        _p.cambiar(titulo: titulo ?? '');
      },
      onUpdateVisitedHistory: (controlador, url, esRecarga) async {
        widget.alCambiarUrl(url?.toString() ?? '');
        await _p.refrescarBotones();
      },
      onReceivedError: (controlador, peticion, error) {
        if (peticion.isForMainFrame ?? false) _p.cambiar(cargando: false);
      },

      // --- enlaces que no son paginas
      shouldOverrideUrlLoading: (controlador, accion) async {
        final destino = accion.request.url;
        if (destino == null) return NavigationActionPolicy.ALLOW;
        final esquema = destino.scheme.toLowerCase();
        if (esquema == 'http' || esquema == 'https' || esquema == 'about') {
          return NavigationActionPolicy.ALLOW;
        }
        // intent://, market://, whatsapp://... no son paginas: si se dejan
        // pasar, el navegador se queda en una pantalla de error
        return NavigationActionPolicy.CANCEL;
      },

      // --- permisos que pide el sitio
      onPermissionRequest: (controlador, peticion) async {
        // el permiso de contenido protegido hace falta para que se vea el
        // video en muchos sitios, y no dice nada del usuario
        final soloDrm = peticion.resources.every(
            (r) => r.toString().toLowerCase().contains('protected'));
        return PermissionResponse(
          resources: peticion.resources,
          action: soloDrm
              ? PermissionResponseAction.GRANT
              : PermissionResponseAction.DENY,
        );
      },
    );
  }

  void _medioEncontrado(String mensaje) {
    try {
      final datos = jsonDecode(mensaje);
      if (datos is Map) {
        _p.anotar('${datos['url'] ?? ''}', '${datos['origen'] ?? ''}');
      } else if (datos is List) {
        for (final x in datos) {
          _p.anotar('$x', 'dom');
        }
      }
    } catch (_) {
      // si la pagina devuelve algo raro, seguimos sin medios detectados
    }
  }
}

class _BotonPestanas extends StatelessWidget {
  const _BotonPestanas({required this.cuantas, required this.alPulsar});

  final int cuantas;
  final VoidCallback alPulsar;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: alPulsar,
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: Tono.texto3, width: 1.6),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          '$cuantas',
          style: const TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w700, color: Tono.texto2),
        ),
      ),
    );
  }
}

class _FilaPestana extends StatelessWidget {
  const _FilaPestana({
    required this.pestana,
    required this.activa,
    required this.alAbrir,
    required this.alCerrar,
  });

  final Pestana pestana;
  final bool activa;
  final VoidCallback alAbrir;
  final VoidCallback alCerrar;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        activa ? Icons.web_asset_rounded : Icons.web_asset_outlined,
        color: activa ? Tono.acento : Tono.texto3,
        size: 20,
      ),
      title: Text(
        pestana.nombreCorto,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          fontWeight: activa ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      subtitle: pestana.url.isEmpty
          ? null
          : Text(pestana.url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall),
      trailing: IconButton(
        icon: const Icon(Icons.close_rounded, size: 18),
        color: Tono.texto3,
        onPressed: alCerrar,
      ),
      onTap: alAbrir,
    );
  }
}

class _Acceso extends StatelessWidget {
  const _Acceso({
    required this.nombre,
    required this.url,
    required this.icono,
    required this.color,
    required this.alPulsar,
  });

  final String nombre;
  final String url;
  final IconData icono;
  final Color color;
  final void Function(String) alPulsar;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(Medidas.radio),
      onTap: () => alPulsar(url),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Icon(icono, color: color, size: 25),
          ),
          const SizedBox(height: 7),
          Text(
            nombre,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: Tono.texto2),
          ),
        ],
      ),
    );
  }
}
