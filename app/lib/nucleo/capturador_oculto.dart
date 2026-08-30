// Abrir una pagina por nuestra cuenta, solo para ver pasar el video.
//
// El navegador de la app captura el video mientras el usuario mira la pagina,
// pero eso solo sirve si el usuario paso por ahi. Si pega un enlace en la
// pantalla de descargas, o lo comparte desde otra app, no hay nada capturado.
//
// Aqui se abre la pagina en un navegador sin pantalla, se le da al play y se
// espera a ver pasar la direccion del video. Es lo mismo que hace el navegador
// de la app, con el mismo acceso, pero sin molestar a nadie.
//
// Antes esto era un WebView de un pixel escondido en una esquina de la app,
// porque el visor de siempre no ejecuta JavaScript si no esta en pantalla.
// El navegador nuevo si trae uno pensado para trabajar sin que se vea, asi que
// aquel apano ya no hace falta.

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Size;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'captura.dart';
import 'navegador_caudal.dart';

/// Lo que se saco de abrir la pagina a escondidas.
class CapturaOculta {
  const CapturaOculta({
    this.url = '',
    this.titulo = '',
    this.cookies = '',
    this.candidatas = const [],
  });

  final String url;
  final String titulo;
  final String cookies;

  /// Las demas direcciones vistas, por si la primera no sirve.
  final List<String> candidatas;

  bool get vale => url.isNotEmpty;
}

/// Abre paginas sin ensenarlas y devuelve el video que encuentra.
///
/// Solo trabaja de una en una: abrir varias paginas a la vez gasta memoria y
/// no acelera nada.
class CapturadorOculto {
  HeadlessInAppWebView? _navegador;
  Completer<CapturaOculta>? _enCurso;
  final List<MedioCapturado> _vistos = [];
  final Set<String> _yaVistas = <String>{};
  Timer? _insistir;
  bool _paraAudio = false;
  String _urlActual = '';

  bool get trabajando => _enCurso != null && !_enCurso!.isCompleted;

  /// Deja el navegador oculto en marcha.
  ///
  /// Se llama al arrancar la app: montarlo cuesta un instante y es preferible
  /// pagarlo antes que en mitad de una descarga.
  Future<void> preparar() async {
    if (_navegador != null) return;
    _navegador = HeadlessInAppWebView(
      initialSize: const Size(412, 915),
      initialSettings: ajustesNavegador(),
      initialUserScripts: guionesDeArranque(),
      initialUrlRequest: URLRequest(url: WebUri('about:blank')),
      onWebViewCreated: (controlador) {
        controlador.addJavaScriptHandler(
          handlerName: 'caudalMedios',
          callback: (argumentos) {
            if (argumentos.isNotEmpty) _llego('${argumentos.first}');
            return null;
          },
        );
        controlador.addJavaScriptHandler(
          handlerName: 'caudalRuta',
          callback: (argumentos) => null,
        );
      },
      // aqui esta la diferencia con el navegador de antes: se ve pasar cada
      // peticion, tambien las que la pagina hace desde un worker
      shouldInterceptRequest: (controlador, peticion) async {
        _anotar(peticion.url.toString(), 'red');
        return null;
      },
      onLoadResource: (controlador, recurso) async {
        _anotar(recurso.url.toString(), 'recurso');
      },
      onLoadStop: (controlador, url) async {
        // en cuanto la pagina esta, se le da al play para que pida el video
        await controlador.evaluateJavascript(source: guionDespertar);
        _insistirUnRato(controlador);
      },
    );
    await _navegador!.run();
  }

  /// Abre [url] a escondidas y espera a ver pasar un video.
  ///
  /// Devuelve una captura vacia si en [espera] no aparece nada.
  Future<CapturaOculta> capturar(
    String url, {
    bool paraAudio = false,
    Duration espera = const Duration(seconds: 22),
  }) async {
    // si ya hay una en marcha, esperamos a que acabe antes de pisar nada
    while (trabajando) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    _vistos.clear();
    _yaVistas.clear();
    _paraAudio = paraAudio;
    _urlActual = url;
    final fin = Completer<CapturaOculta>();
    _enCurso = fin;

    await preparar();
    final controlador = _navegador?.webViewController;
    if (controlador == null) {
      _enCurso = null;
      return const CapturaOculta();
    }

    // lo que pide el service worker no lleva escrito de que navegador viene:
    // hay que apuntarse a la lista mientras dure esta captura
    void delWorker(String u) => _anotar(u, 'sw');
    NavegadorCaudal.escucharAlWorker(delWorker);

    await controlador.loadUrl(urlRequest: URLRequest(url: WebUri(url)));

    // se corta pase lo que pase: nadie espera indefinidamente
    Timer(espera, () async {
      if (!fin.isCompleted) fin.complete(await _loMejorQueTengamos());
    });

    final resultado = await fin.future;
    _insistir?.cancel();
    NavegadorCaudal.dejarDeEscucharAlWorker(delWorker);
    _enCurso = null;
    // dejamos la pagina en blanco para que no siga gastando
    try {
      await controlador.loadUrl(
          urlRequest: URLRequest(url: WebUri('about:blank')));
    } catch (_) {
      // si no se puede, tampoco pasa nada
    }
    return resultado;
  }

  /// Vuelve a darle al play unas cuantas veces.
  ///
  /// El guion de captura ya va plantado desde el primer instante, pero el
  /// video de algunos sitios no se pide hasta que algo lo reproduce, y a veces
  /// el primer empujon llega antes de que el reproductor exista.
  void _insistirUnRato(InAppWebViewController controlador) {
    _insistir?.cancel();
    var veces = 0;
    _insistir = Timer.periodic(const Duration(milliseconds: 1200), (t) {
      if (++veces > 10 || !trabajando) {
        t.cancel();
        return;
      }
      controlador.evaluateJavascript(source: guionDespertar);
    });
  }

  void _llego(String mensaje) {
    try {
      final datos = jsonDecode(mensaje);
      if (datos is! Map) return;
      _anotar('${datos['url'] ?? ''}', '${datos['origen'] ?? ''}');
    } catch (_) {
      // mensajes raros de la pagina: se ignoran
    }
  }

  void _anotar(String url, String origen) {
    if (!trabajando) return;
    if (url.isEmpty || !url.startsWith('http')) return;
    // por el interceptor pasa todo lo que carga la pagina: lo que ni de lejos
    // es un video se descarta antes de mirarlo con calma
    if (origen != 'dom' && origen != 'fetch' && origen != 'xhr' &&
        !podriaSerMedia(url)) {
      return;
    }
    final medio = MedioCapturado(url, origen);
    if (!_yaVistas.add(medio.url)) return;
    _vistos.add(medio);

    // un archivo entero es lo que buscamos: en cuanto aparece, terminamos
    final mejor = mejorCapturado(_vistos, paraAudio: _paraAudio);
    if (mejor != null && mejor.esArchivoEntero) _terminarCon(mejor);
  }

  Future<void> _terminarCon(MedioCapturado medio) async {
    final fin = _enCurso;
    if (fin == null || fin.isCompleted) return;
    fin.complete(CapturaOculta(
      url: medio.url,
      titulo: await _titulo(),
      cookies: await NavegadorCaudal.cookiesDe(_urlActual),
      candidatas: candidatasOrdenadas(_vistos, paraAudio: _paraAudio)
          .map((m) => m.url)
          .toList(),
    ));
  }

  Future<CapturaOculta> _loMejorQueTengamos() async {
    final ordenadas = candidatasOrdenadas(_vistos, paraAudio: _paraAudio);
    if (ordenadas.isEmpty) return const CapturaOculta();
    return CapturaOculta(
      url: ordenadas.first.url,
      titulo: await _titulo(),
      cookies: await NavegadorCaudal.cookiesDe(_urlActual),
      candidatas: ordenadas.map((m) => m.url).toList(),
    );
  }

  Future<String> _titulo() async {
    try {
      return (await _navegador?.webViewController?.getTitle()) ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> cerrar() async {
    _insistir?.cancel();
    try {
      await _navegador?.dispose();
    } catch (_) {
      // si ya estaba cerrado, da igual
    }
    _navegador = null;
  }
}
