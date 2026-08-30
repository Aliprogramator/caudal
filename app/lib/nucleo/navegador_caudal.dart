// El navegador de Caudal.
//
// No es un visor de paginas: es la herramienta con la que la app ve lo que
// hace cada sitio. Por eso esta montado sobre un WebView con acceso completo,
// y no sobre el visor de siempre, que no deja:
//
//   - ver pasar las peticiones de la pagina (ni las de sus workers),
//   - plantar JavaScript antes de que arranque el de la pagina,
//   - leer las cookies de sesion (las HttpOnly no las ve document.cookie),
//   - atender las descargas que dispara un enlace,
//   - abrir las ventanas que la pagina pide con target=_blank.
//
// Sin esas cinco cosas, descargar de una web moderna es cuestion de suerte.

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'captura.dart';
import 'formato.dart';
import 'modelos.dart';

/// Con que navegador nos presentamos.
///
/// Sin un agente creible muchas webs sirven una version recortada, sin video.
const String agenteCaudal =
    'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/124.0.0.0 Mobile Safari/537.36';

/// Como se comporta el navegador.
///
/// Los `use...` son los que encienden los avisos que necesitamos: sin ellos el
/// WebView hace su trabajo en silencio y la app no se entera de nada.
///
/// Escuchar la red no es gratis: cada peticion cruza al lado de Dart y el
/// navegador espera la respuesta. Por eso se enciende una sola de las dos vias
/// segun el telefono: en Android el interceptor, que lo ve todo; en iPhone, que
/// no tiene interceptor, el aviso de recursos cargados, que ve bastante menos
/// pero es lo que hay. Encender las dos donde solo hace falta una es pagar el
/// peaje dos veces por la misma direccion.
InAppWebViewSettings ajustesNavegador({bool transparente = false}) {
  final esAndroid = defaultTargetPlatform == TargetPlatform.android;
  return InAppWebViewSettings(
      userAgent: agenteCaudal,
      javaScriptEnabled: true,
      javaScriptCanOpenWindowsAutomatically: true,
      supportMultipleWindows: true,
      useShouldInterceptRequest: esAndroid,  // ver pasar cada peticion
      useOnDownloadStart: true,              // atender las descargas
      useOnLoadResource: !esAndroid,         // en iPhone, lo unico que hay
      useShouldOverrideUrlLoading: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      thirdPartyCookiesEnabled: true,
      domStorageEnabled: true,
      databaseEnabled: true,
      cacheEnabled: true,
      clearCache: false,
      useHybridComposition: true,
      allowFileAccessFromFileURLs: false,
      allowUniversalAccessFromFileURLs: false,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
      transparentBackground: transparente,
      supportZoom: true,
      builtInZoomControls: true,
      displayZoomControls: false,
      useWideViewPort: true,
      loadWithOverviewMode: true,
      verticalScrollBarEnabled: false,
      horizontalScrollBarEnabled: false,
  );
}

/// Los guiones que se plantan en cada marco antes que el JavaScript del sitio.
///
/// El momento importa mas que el contenido: si se inyectan despues, la pagina
/// ya se ha quedado con su copia de fetch y pide el video sin que lo veamos.
/// Medido: inyectando tarde se pierden cuatro de cada siete videos.
UnmodifiableListView<UserScript> guionesDeArranque() =>
    UnmodifiableListView<UserScript>([
      UserScript(
        source: guionPuente,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      ),
      UserScript(
        source: guionCaptura,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      ),
      UserScript(
        source: guionRuta,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: true,
      ),
      UserScript(
        source: guionDescargasDePagina,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
        forMainFrameOnly: false,
      ),
    ]);

/// Descargas que el navegador no puede atender por su cuenta.
///
/// Cuando una web arma el archivo ella misma —lo genera en memoria y lo ofrece
/// como `blob:`— no hay ninguna direccion que pedirle a ningun servidor: el
/// archivo ya esta dentro de la pagina. Aqui se intercepta ese clic y se manda
/// el contenido a la app, que es la unica forma de guardarlo.
const String guionDescargasDePagina = r'''
(function () {
  if (window.__caudalDescargas) return;
  window.__caudalDescargas = true;

  var TOPE = 64 * 1024 * 1024;   // mas de esto no cabe por el puente

  function mandar(href, nombre) {
    try {
      fetch(href).then(function (r) { return r.blob(); }).then(function (b) {
        if (b.size > TOPE) return;
        var lector = new FileReader();
        lector.onload = function () {
          try {
            window.flutter_inappwebview.callHandler('caudalArchivo', JSON.stringify({
              nombre: nombre || 'descarga',
              tipo: b.type || '',
              tamano: b.size,
              datos: String(lector.result).split(',')[1] || '',
            }));
          } catch (e) {}
        };
        lector.readAsDataURL(b);
      }).catch(function () {});
    } catch (e) {}
  }

  document.addEventListener('click', function (e) {
    try {
      var n = e.target;
      while (n && n.tagName !== 'A') n = n.parentElement;
      if (!n) return;
      var href = n.getAttribute('href') || '';
      if (href.indexOf('blob:') !== 0 && href.indexOf('data:') !== 0) return;
      e.preventDefault();
      e.stopPropagation();
      mandar(href, n.getAttribute('download'));
    } catch (er) {}
  }, true);

  // algunas paginas ni siquiera ensenan el enlace: lo crean, lo pulsan por
  // dentro y lo tiran. Ese clic no pasa por el listener de arriba.
  try {
    var pulsarOriginal = HTMLAnchorElement.prototype.click;
    HTMLAnchorElement.prototype.click = function () {
      try {
        var href = this.getAttribute('href') || '';
        if ((href.indexOf('blob:') === 0 || href.indexOf('data:') === 0) &&
            this.hasAttribute('download')) {
          mandar(href, this.getAttribute('download'));
          return;
        }
      } catch (e) {}
      return pulsarOriginal.apply(this, arguments);
    };
  } catch (e) {}
})();
''';

/// Una direccion que el sitio quiere que se descargue.
class PeticionDescarga {
  const PeticionDescarga({
    required this.url,
    this.nombre = '',
    this.tipoMime = '',
    this.tamano = 0,
    this.referente = '',
  });

  final String url;
  final String nombre;
  final String tipoMime;
  final int tamano;
  final String referente;

  bool get esVideo =>
      tipoMime.startsWith('video/') ||
      RegExp(r'\.(mp4|m4v|mov|mkv|webm|avi|flv)$', caseSensitive: false)
          .hasMatch(nombre.isEmpty ? url.split('?').first : nombre);

  bool get esAudio =>
      tipoMime.startsWith('audio/') ||
      RegExp(r'\.(mp3|m4a|aac|ogg|opus|flac|wav)$', caseSensitive: false)
          .hasMatch(nombre.isEmpty ? url.split('?').first : nombre);
}

/// Una pestana abierta.
class Pestana extends ChangeNotifier {
  Pestana({this.urlInicial = '', this.windowId});

  /// Con que direccion nace. Vacia significa portada.
  String urlInicial;

  /// Cuando la abre la propia pagina con target=_blank, Android reserva una
  /// ventana y hay que engancharse a ella por este numero. Si se ignora, el
  /// enlace no abre nada: es el motivo de que media web "no haga nada".
  final int? windowId;

  InAppWebViewController? web;

  String url = '';
  String titulo = '';
  int progreso = 0;
  bool cargando = false;
  bool puedeAtras = false;
  bool puedeAdelante = false;

  /// Lo que se ha visto pasar en esta pestana.
  final List<MedioCapturado> medios = [];

  /// Direcciones ya anotadas, para no repetir trabajo en cada peticion.
  final Set<String> _yaVistas = <String>{};

  /// Lo que se sabe de lo que hay en pantalla, para la barra de descarga.
  Ficha? ficha;
  String urlDeLaFicha = '';
  bool resolviendo = false;
  bool barraOculta = false;

  bool get vacia => url.isEmpty && urlInicial.isEmpty;

  /// Manda a la pestana a una direccion.
  ///
  /// Si el navegador de esta pestana todavia no existe —una pestana recien
  /// abierta que aun ensena la portada—, se apunta la direccion para que nazca
  /// ya cargandola.
  void cargar(String direccion) {
    if (direccion.isEmpty) return;
    barraOculta = false;
    if (web != null) {
      web!.loadUrl(urlRequest: URLRequest(url: WebUri(direccion)));
      url = direccion;
      notifyListeners();
      return;
    }
    urlInicial = direccion;
    url = direccion;
    cargando = true;
    notifyListeners();
  }

  String get nombreCorto {
    if (titulo.trim().isNotEmpty) return titulo.trim();
    if (url.isEmpty) return 'Pestana nueva';
    return sitioDe(url);
  }

  /// Anota una direccion venga de donde venga. Devuelve si era nueva.
  bool anotar(String direccion, String origen) {
    if (direccion.isEmpty || !direccion.startsWith('http')) return false;
    final medio = MedioCapturado(direccion, origen);
    if (!_yaVistas.add(medio.url)) return false;
    medios.add(medio);
    // la lista puede crecer sin freno en una pagina con muchos videos
    if (medios.length > 250) medios.removeRange(0, 50);
    notifyListeners();
    return true;
  }

  /// Avisa a la interfaz de un cambio hecho desde fuera de la pestana.
  void refrescar() => notifyListeners();

  void olvidarMedios() {
    if (medios.isEmpty && _yaVistas.isEmpty) return;
    medios.clear();
    _yaVistas.clear();
    notifyListeners();
  }

  void cambiar({
    String? url,
    String? titulo,
    int? progreso,
    bool? cargando,
  }) {
    var hayCambio = false;
    if (url != null && url != this.url) {
      this.url = url;
      hayCambio = true;
    }
    if (titulo != null && titulo != this.titulo) {
      this.titulo = titulo;
      hayCambio = true;
    }
    if (progreso != null && progreso != this.progreso) {
      this.progreso = progreso;
      hayCambio = true;
    }
    if (cargando != null && cargando != this.cargando) {
      this.cargando = cargando;
      hayCambio = true;
    }
    if (hayCambio) notifyListeners();
  }

  Future<void> refrescarBotones() async {
    final atras = await web?.canGoBack() ?? false;
    final adelante = await web?.canGoForward() ?? false;
    if (atras == puedeAtras && adelante == puedeAdelante) return;
    puedeAtras = atras;
    puedeAdelante = adelante;
    notifyListeners();
  }
}

/// Las pestanas abiertas y lo que sabe el navegador de la sesion.
class NavegadorCaudal extends ChangeNotifier {
  NavegadorCaudal() {
    pestanas.add(Pestana());
  }

  final List<Pestana> pestanas = [];
  int indice = 0;

  /// Descargas que dispara la propia web, para que las recoja la pantalla.
  final StreamController<PeticionDescarga> _descargas =
      StreamController<PeticionDescarga>.broadcast();
  Stream<PeticionDescarga> get alPedirDescarga => _descargas.stream;

  Pestana get activa => pestanas[indice.clamp(0, pestanas.length - 1)];

  bool _preparado = false;

  /// Quien quiere enterarse de lo que pide un service worker.
  ///
  /// El service worker es uno para toda la app, no uno por navegador: lo que
  /// pide no lleva escrito de que pestana viene. Por eso se reparte a todos los
  /// interesados —la pestana que se esta viendo y, si esta trabajando, el
  /// navegador oculto— y cada uno se queda con lo que le sirve.
  static final List<void Function(String)> _oyentesDelWorker = [];

  static void escucharAlWorker(void Function(String) oyente) {
    if (!_oyentesDelWorker.contains(oyente)) _oyentesDelWorker.add(oyente);
  }

  static void dejarDeEscucharAlWorker(void Function(String) oyente) {
    _oyentesDelWorker.remove(oyente);
  }

  /// Enciende lo que hay que encender una sola vez en toda la app.
  ///
  /// El service worker va aparte: sus peticiones no pasan por el interceptor
  /// del WebView, y en Instagram y en cualquier sitio que sirva el video desde
  /// ahi, es justo por donde pasa lo que buscamos.
  Future<void> preparar() async {
    if (_preparado) return;
    _preparado = true;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      if (await WebViewFeature.isFeatureSupported(
          WebViewFeature.SERVICE_WORKER_SHOULD_INTERCEPT_REQUEST)) {
        await ServiceWorkerController.instance().setServiceWorkerClient(
          ServiceWorkerClient(
            shouldInterceptRequest: (peticion) async {
              final url = peticion.url.toString();
              if (podriaSerMedia(url)) {
                activa.anotar(url, 'sw');
                for (final oyente in [..._oyentesDelWorker]) {
                  oyente(url);
                }
              }
              return null;   // que la siga sirviendo el service worker
            },
          ),
        );
      }
    } catch (_) {
      // en algunos Android no esta disponible; se sigue sin ello
    }
  }

  void irA(int i) {
    if (i < 0 || i >= pestanas.length || i == indice) return;
    indice = i;
    notifyListeners();
  }

  Pestana abrir({String url = '', int? windowId, bool enSegundoPlano = false}) {
    final nueva = Pestana(urlInicial: url, windowId: windowId);
    pestanas.add(nueva);
    if (!enSegundoPlano) indice = pestanas.length - 1;
    notifyListeners();
    return nueva;
  }

  void cerrar(Pestana pestana) {
    final i = pestanas.indexOf(pestana);
    if (i < 0) return;
    pestanas.removeAt(i);
    pestana.dispose();
    if (pestanas.isEmpty) pestanas.add(Pestana());
    if (indice >= pestanas.length) indice = pestanas.length - 1;
    notifyListeners();
  }

  void pedirDescarga(PeticionDescarga peticion) {
    if (!_descargas.isClosed) _descargas.add(peticion);
  }

  /// Las cookies de sesion del sitio, las que la pagina no deja leer.
  ///
  /// Las de verdad —las que dicen quien eres— van marcadas HttpOnly y
  /// `document.cookie` no las ve. Pedirlas asi es la diferencia entre que la
  /// descarga responda 200 o responda 403.
  static Future<String> cookiesDe(String url) async {
    if (url.isEmpty) return '';
    try {
      final galletas = await CookieManager.instance().getCookies(url: WebUri(url));
      if (galletas.isEmpty) return '';
      return galletas.map((c) => '${c.name}=${c.value}').join('; ');
    } catch (_) {
      return '';
    }
  }

  @override
  void dispose() {
    _descargas.close();
    for (final p in pestanas) {
      p.dispose();
    }
    super.dispose();
  }
}
