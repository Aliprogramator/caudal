import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../main.dart';
import '../nucleo/captura.dart';
import '../nucleo/deteccion.dart';
import '../nucleo/formato.dart';
import '../nucleo/modelos.dart';
import '../nucleo/motor_local.dart';
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

/// Navegador propio: al entrar en un video aparecen solos los botones para
/// bajarlo en video o en audio, sin tener que buscar nada en un menú.
class VistaNavegador extends StatefulWidget {
  const VistaNavegador({super.key});

  @override
  State<VistaNavegador> createState() => _VistaNavegadorState();
}

class _VistaNavegadorState extends State<VistaNavegador> with AutomaticKeepAliveClientMixin {
  late final WebViewController _web;
  final _direccion = TextEditingController();
  final _focoDireccion = FocusNode();

  String _urlActual = '';
  String _titulo = '';
  int _progreso = 0;
  bool _cargando = false;
  bool _arrancado = false;
  final List<MedioCapturado> _mediosDetectados = [];

  // --- barra de descarga rápida
  Ficha? _ficha;
  bool _resolviendo = false;
  bool _ocultaPorElUsuario = false;
  String _urlDeLaFicha = '';
  int _peticion = 0;
  Timer? _retardo;
  Timer? _reinyeccion;
  bool _buscandoMedia = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Tono.fondo)
      ..setUserAgent(
        // sin esto, algunas webs sirven una version movil recortada sin video
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/124.0.0.0 Mobile Safari/537.36',
      )
      ..addJavaScriptChannel('CaudalMedios', onMessageReceived: _mediosEncontrados)
      ..addJavaScriptChannel('CaudalRuta', onMessageReceived: _rutaCambiada)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => setState(() => _progreso = p),
        onPageStarted: (url) {
          setState(() {
            _cargando = true;
            _mediosDetectados.clear();
          });
          // cuanto antes se enganche, mas peticiones de video vemos pasar
          _web.runJavaScript(guionCaptura);
          _cambiarUrl(url);
        },
        onPageFinished: (url) async {
          setState(() => _cargando = false);
          _cambiarUrl(url);
          final t = await _web.getTitle();
          if (mounted) setState(() => _titulo = t ?? '');
          _vigilarRuta();
          _insistirConLaCaptura();
          _buscarMedios();
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && mounted) {
            setState(() => _cargando = false);
          }
        },
      ));
  }

  @override
  void dispose() {
    _retardo?.cancel();
    _reinyeccion?.cancel();
    _direccion.dispose();
    _focoDireccion.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- detección

  /// YouTube y compañía cambian de video sin recargar la página, así que hay
  /// que vigilar el historial para enterarse.
  void _vigilarRuta() {
    _web.runJavaScript('''
      (function () {
        if (window.__caudalRuta) return;
        window.__caudalRuta = true;
        var ultima = location.href;
        function avisar() {
          if (location.href !== ultima) {
            ultima = location.href;
            try { CaudalRuta.postMessage(ultima); } catch (e) {}
          }
        }
        var ps = history.pushState, rs = history.replaceState;
        history.pushState = function () { ps.apply(history, arguments); setTimeout(avisar, 80); };
        history.replaceState = function () { rs.apply(history, arguments); setTimeout(avisar, 80); };
        window.addEventListener('popstate', function () { setTimeout(avisar, 80); });
        setInterval(avisar, 900);
      })();
    ''');
  }

  void _rutaCambiada(JavaScriptMessage mensaje) {
    _cambiarUrl(mensaje.message);
    _web.getTitle().then((t) {
      if (mounted && t != null) setState(() => _titulo = t);
    });
  }

  /// Punto único por el que pasa cualquier cambio de dirección.
  void _cambiarUrl(String url) {
    if (url == _urlActual) return;
    setState(() {
      _urlActual = url;
      _direccion.text = url;
      _ocultaPorElUsuario = false;
      if (_urlDeLaFicha != url) {
        _ficha = null;
        _urlDeLaFicha = '';
      }
    });
    _programarResolucion();
  }

  /// Mira de qué va la página, con un respiro para no disparar una consulta
  /// por cada rebote de navegación.
  void _programarResolucion() {
    _retardo?.cancel();
    if (!pareceDescargable(_urlActual)) {
      setState(() => _resolviendo = false);
      return;
    }
    setState(() => _resolviendo = true);
    _retardo = Timer(const Duration(milliseconds: 700), _resolver);
  }

  Future<void> _resolver() async {
    final url = _urlActual;
    final mio = ++_peticion;
    try {
      // YouTube da titulo, autor y calidades de verdad; el resto de sitios se
      // resuelven con lo que el navegador ya sabe de la pagina
      final ficha = await Servicios.de(context).descargas.resolverSiPuede(url);
      if (!mounted || mio != _peticion || url != _urlActual) return;
      setState(() {
        _ficha = ficha ?? Ficha(url: url, titulo: _titulo, plataforma: sitioDe(url));
        _urlDeLaFicha = url;
        _resolviendo = false;
      });
    } catch (_) {
      if (!mounted || mio != _peticion) return;
      // sin datos, pero la barra sigue: el video se baja igual con lo capturado
      setState(() {
        _ficha = Ficha(url: url, titulo: _titulo, plataforma: sitioDe(url));
        _urlDeLaFicha = url;
        _resolviendo = false;
      });
    }
  }

  /// Vuelve a plantar el guión de captura varias veces seguidas.
  ///
  /// Una sola inyección no basta: según cuándo entre, la página todavía no ha
  /// terminado de montarse y el enganche se pierde. Insistir unos segundos
  /// cuesta nada y es la diferencia entre ver pasar el video o no verlo.
  void _insistirConLaCaptura() {
    _reinyeccion?.cancel();
    var veces = 0;
    _web.runJavaScript(guionCaptura);
    _reinyeccion = Timer.periodic(const Duration(milliseconds: 900), (t) {
      if (!mounted || ++veces > 8) {
        t.cancel();
        return;
      }
      _web.runJavaScript(guionCaptura);
    });
  }

  /// Pregunta a la página qué videos o audios tiene cargados.
  void _buscarMedios() {
    _web.runJavaScript('''
      (function () {
        try {
          var vistos = [];
          document.querySelectorAll('video, audio, source').forEach(function (n) {
            var s = n.currentSrc || n.src || '';
            if (s && s.indexOf('blob:') !== 0 && vistos.indexOf(s) < 0) vistos.push(s);
          });
          if (vistos.length) CaudalMedios.postMessage(JSON.stringify(vistos));
        } catch (e) {}
      })();
    ''');
  }

  void _mediosEncontrados(JavaScriptMessage mensaje) {
    try {
      final datos = jsonDecode(mensaje.message);
      if (!mounted) return;

      // el guion nuevo manda un objeto por medio; el repaso del DOM, una lista
      final nuevos = <MedioCapturado>[];
      if (datos is Map) {
        final u = (datos['url'] ?? '').toString();
        if (u.startsWith('http')) {
          nuevos.add(MedioCapturado(u, (datos['origen'] ?? '').toString()));
        }
      } else if (datos is List) {
        for (final x in datos) {
          final u = x.toString();
          if (u.startsWith('http')) nuevos.add(MedioCapturado(u, 'dom'));
        }
      }
      if (nuevos.isEmpty) return;

      final yaEstan = _mediosDetectados.map((m) => m.url).toSet();
      setState(() {
        _mediosDetectados.addAll(nuevos.where((m) => !yaEstan.contains(m.url)));
      });
    } catch (_) {
      // si la pagina devuelve algo raro, seguimos sin medios detectados
    }
  }

  bool get _barraVisible =>
      _arrancado &&
      !_ocultaPorElUsuario &&
      (_resolviendo || _ficha != null) &&
      pareceDescargable(_urlActual);

  // ---------------------------------------------------------------- descargas

  /// Descarga sin preguntar nada: la mejor calidad que haya.
  /// La mejor dirección de las que vimos pasar mientras la página reproducía.
  ///
  /// Para YouTube se devuelve vacía a propósito: allí el motor resuelve el
  /// video entero y saca mejor calidad que lo que sirve el reproductor web.
  ///
  /// Si todavía no hemos visto pasar nada, se empuja al video a arrancar y se
  /// espera un momento: casi siempre con eso aparece.
  /// Las cookies de la pagina que se esta viendo.
  ///
  /// Sin ellas muchos sitios responden 403 a la descarga: es como se aseguran
  /// de que quien pide el video es el mismo que estaba viendo la pagina.
  Future<String> _cookiesDeLaPagina() async {
    try {
      final r = await _web.runJavaScriptReturningResult('document.cookie');
      final texto = r.toString();
      // el resultado viene entrecomillado y con las comillas escapadas
      return texto
          .replaceAll(RegExp(r'^"|"$'), '')
          .replaceAll(r'\"', '"')
          .trim();
    } catch (_) {
      return '';
    }
  }

  Future<String> _mediaParaDescargar(TipoMedio tipo) async {
    if (MotorLocal.puedeSolo(_urlActual)) return '';

    var mejor = mejorCapturado(_mediosDetectados, paraAudio: tipo == TipoMedio.audio);
    if (mejor != null) return mejor.url;

    // nada capturado: le damos un empujón al reproductor y esperamos
    await _web.runJavaScript(guionCaptura);
    await _web.runJavaScript(guionDespertar);

    for (var intento = 0; intento < 12; intento++) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return '';
      mejor = mejorCapturado(_mediosDetectados, paraAudio: tipo == TipoMedio.audio);
      if (mejor != null) return mejor.url;
      // cada tanto, otro repaso por si el video acaba de aparecer
      if (intento == 5) _buscarMedios();
    }
    return '';
  }

  Future<void> _descargarDirecto(TipoMedio tipo) async {
    final servicios = Servicios.de(context);
    if (_urlActual.isEmpty || _buscandoMedia) return;

    final esYoutube = MotorLocal.puedeSolo(_urlActual);
    if (!esYoutube && _mediosDetectados.isEmpty) {
      setState(() => _buscandoMedia = true);
      avisar(context, 'Buscando el video en la pagina...');
    }

    final media = await _mediaParaDescargar(tipo);
    if (!mounted) return;
    setState(() => _buscandoMedia = false);

    if (!esYoutube && media.isEmpty) {
      // el numero dice si el problema es que no vemos nada pasar o que lo que
      // pasa no nos sirve; sin eso no hay forma de saber por donde falla
      avisar(
        context,
        _mediosDetectados.isEmpty
            ? 'No se vio pasar ningun video. Dale al play y vuelve a intentarlo.'
            : 'Se vieron ${_mediosDetectados.length} archivos pero ninguno servia. '
                'Prueba a darle al play.',
        esError: true,
      );
      return;
    }

    final galletas = await _cookiesDeLaPagina();
    if (!mounted) return;

    servicios.descargas.encolar(
      url: _urlActual,
      urlMedia: media,
      cookies: galletas,
      tipo: tipo,
      calidad: 'mejor',
      formatoAudio: servicios.ajustes.formatoAudio,
      titulo: _ficha?.titulo.isNotEmpty == true ? _ficha!.titulo : _titulo,
      autor: _ficha?.autor ?? '',
      miniatura: _ficha?.miniatura ?? '',
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
    if (_urlActual.isEmpty) return;

    final eleccion = await mostrarHojaDescarga(
      context,
      url: _urlActual,
      descargas: servicios.descargas,
      ajustes: servicios.ajustes,
      fichaConocida: _ficha,
    );
    if (eleccion == null || !mounted) return;

    // lo que vimos pasar en la pagina vale igual desde aqui
    final media = await _mediaParaDescargar(eleccion.tipo);
    final galletas = await _cookiesDeLaPagina();
    if (!mounted) return;

    encolarYAvisar(
      context,
      gestor: servicios.descargas,
      url: _urlActual,
      urlMedia: media,
      cookies: galletas,
      tipo: eleccion.tipo,
      calidad: eleccion.calidad,
      formatoAudio: eleccion.formatoAudio,
      titulo: eleccion.ficha.titulo.isNotEmpty ? eleccion.ficha.titulo : _titulo,
      autor: eleccion.ficha.autor,
      miniatura: eleccion.ficha.miniatura,
    );
  }

  void _ir(String entrada) {
    final texto = entrada.trim();
    if (texto.isEmpty) return;
    final url = pareceEnlace(texto)
        ? normalizarEnlace(texto)
        : 'https://www.google.com/search?q=${Uri.encodeQueryComponent(texto)}';
    _focoDireccion.unfocus();
    setState(() => _arrancado = true);
    _web.loadRequest(Uri.parse(url));
  }

  // ---------------------------------------------------------------- interfaz

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _barraDireccion(),
            if (_cargando && _progreso < 100)
              BarraProgreso(valor: _progreso / 100, alto: 2.5),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _arrancado ? WebViewWidget(controller: _web) : _portada(),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: BarraRapida(
                      visible: _barraVisible,
                      resolviendo: _resolviendo && _ficha == null,
                      ficha: _ficha,
                      tituloPagina: _titulo,
                      priorizarAudio: esSitioDeAudio(_urlActual),
                      alDescargarVideo: () => _descargarDirecto(TipoMedio.completo),
                      alDescargarAudio: () => _descargarDirecto(TipoMedio.audio),
                      alAbrirOpciones: _abrirOpciones,
                      alCerrar: () => setState(() => _ocultaPorElUsuario = true),
                    ),
                  ),
                ],
              ),
            ),
            if (_arrancado) _barraInferior(),
          ],
        ),
      ),
    );
  }

  Widget _barraDireccion() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
            hintText: 'Busca o escribe una dirección',
            prefixIcon: Icon(
              _urlActual.startsWith('https') ? Icons.lock_rounded : Icons.public_rounded,
              size: 16,
              color: _urlActual.startsWith('https') ? Tono.exito : Tono.texto3,
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 38),
            suffixIcon: _direccion.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    color: Tono.texto3,
                    onPressed: _web.reload,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _barraInferior() {
    final hayMedios = _mediosDetectados.isNotEmpty;
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
            onPressed: () async {
              if (await _web.canGoBack()) _web.goBack();
            },
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
            color: Tono.texto2,
          ),
          IconButton(
            onPressed: () async {
              if (await _web.canGoForward()) _web.goForward();
            },
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 19),
            color: Tono.texto2,
          ),
          IconButton(
            onPressed: () => setState(() {
              _arrancado = false;
              _ficha = null;
            }),
            icon: const Icon(Icons.home_rounded, size: 21),
            color: Tono.texto2,
          ),
          IconButton(
            onPressed: hayMedios ? _verMediosDetectados : null,
            icon: Badge(
              isLabelVisible: hayMedios,
              label: Text('${_mediosDetectados.length}'),
              backgroundColor: Tono.acento,
              textColor: const Color(0xFF04202A),
              child: const Icon(Icons.playlist_add_rounded, size: 21),
            ),
            color: Tono.texto2,
            disabledColor: Tono.texto3.withValues(alpha: 0.4),
            tooltip: 'Medios sueltos de la página',
          ),
          IconButton(
            onPressed: _urlActual.isEmpty ? null : _abrirOpciones,
            icon: const Icon(Icons.download_rounded, size: 22),
            color: Tono.acento,
            disabledColor: Tono.texto3.withValues(alpha: 0.4),
            tooltip: 'Descargar esta página',
          ),
        ],
      ),
    );
  }

  void _verMediosDetectados() {
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
                  for (final medio in _mediosDetectados)
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
      url: _urlActual.isEmpty ? url : _urlActual,
      // aqui la direccion ya es la del archivo: se pasa como tal
      urlMedia: url,
      cookies: galletas,
      tipo: eleccion.tipo,
      calidad: eleccion.calidad,
      formatoAudio: eleccion.formatoAudio,
      titulo: eleccion.ficha.titulo.isNotEmpty ? eleccion.ficha.titulo : _titulo,
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
              'descargable, la app lo detecta sola.',
          icono: Icons.lightbulb_outline_rounded,
          color: Tono.acento,
        ),
      ],
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
