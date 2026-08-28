// Abrir una pagina por nuestra cuenta, solo para ver pasar el video.
//
// El navegador de la app captura el video mientras el usuario mira la pagina,
// pero eso solo sirve si el usuario paso por ahi. Si pega un enlace en la
// pantalla de descargas, o lo comparte desde otra app, no hay nada capturado.
//
// Aqui se abre la pagina en un navegador que no se ve, del tamano de un pixel,
// se le da al play y se espera a ver pasar la direccion del video. Es lo mismo
// que hace el navegador de la app, pero sin molestar a nadie.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'captura.dart';

/// Lo que se saco de abrir la pagina a escondidas.
class CapturaOculta {
  const CapturaOculta({this.url = '', this.titulo = '', this.cookies = ''});

  final String url;
  final String titulo;
  final String cookies;

  bool get vale => url.isNotEmpty;
}

/// Abre paginas sin ensenarlas y devuelve el video que encuentra.
///
/// Solo trabaja de uno en uno: abrir varias paginas a la vez en un navegador
/// oculto gasta memoria y no acelera nada.
class CapturadorOculto extends ChangeNotifier {
  WebViewController? _web;
  Completer<CapturaOculta>? _enCurso;
  final List<MedioCapturado> _vistos = [];
  Timer? _insistir;
  bool _paraAudio = false;
  bool _montado = false;

  /// El navegador oculto tiene que estar en pantalla para funcionar, aunque
  /// sea de un pixel: si no, Android no ejecuta su JavaScript.
  WebViewController? get controlador => _web;

  bool get trabajando => _enCurso != null && !_enCurso!.isCompleted;

  /// Deja el navegador listo nada más arrancar la app.
  ///
  /// Crearlo en el momento de usarlo no sirve: el widget tarda un instante en
  /// aparecer en pantalla y, hasta que aparece, Android no ejecuta nada de lo
  /// que le mandemos. Se queda esperando en cero y nunca ve pasar el video.
  void preparar() {
    if (_web != null) return;
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/124.0.0.0 Mobile Safari/537.36',
      )
      ..addJavaScriptChannel('CaudalMedios', onMessageReceived: _llego);
    notifyListeners();
  }

  /// Lo llama el widget cuando ya está de verdad en pantalla.
  void marcarMontado() {
    if (_montado) return;
    _montado = true;
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
    _paraAudio = paraAudio;
    final fin = Completer<CapturaOculta>();
    _enCurso = fin;

    preparar();

    // esperar a que el widget esté de verdad en pantalla: si cargamos antes,
    // el JavaScript no llega a ejecutarse y no vemos pasar nada
    for (var i = 0; i < 40 && !_montado; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    _web!.setNavigationDelegate(NavigationDelegate(
      onPageStarted: (_) => _web!.runJavaScript(guionCaptura),
      onPageFinished: (_) {
        _web!.runJavaScript(guionCaptura);
        // en cuanto la pagina esta, se le da al play para que pida el video
        _web!.runJavaScript(guionDespertar);
        _insistirUnRato();
      },
    ));

    await _web!.loadRequest(Uri.parse(url));

    // se corta pase lo que pase: nadie espera indefinidamente
    Timer(espera, () async {
      if (!fin.isCompleted) fin.complete(await _loMejorQueTengamos());
    });

    final resultado = await fin.future;
    _insistir?.cancel();
    _enCurso = null;
    // dejamos la pagina en blanco para que no siga gastando
    try {
      await _web?.loadRequest(Uri.parse('about:blank'));
    } catch (_) {
      // si no se puede, tampoco pasa nada
    }
    return resultado;
  }

  /// Vuelve a plantar el guion unas cuantas veces, como en el navegador.
  void _insistirUnRato() {
    _insistir?.cancel();
    var veces = 0;
    _insistir = Timer.periodic(const Duration(milliseconds: 900), (t) {
      if (++veces > 12 || !trabajando) {
        t.cancel();
        return;
      }
      _web?.runJavaScript(guionCaptura);
      if (veces == 3 || veces == 7) _web?.runJavaScript(guionDespertar);
    });
  }

  void _llego(JavaScriptMessage mensaje) {
    try {
      final datos = jsonDecode(mensaje.message);
      if (datos is! Map) return;
      final u = (datos['url'] ?? '').toString();
      if (!u.startsWith('http')) return;
      if (_vistos.any((m) => m.url == u)) return;

      _vistos.add(MedioCapturado(u, (datos['origen'] ?? '').toString()));

      // un archivo entero es lo que buscamos: en cuanto aparece, terminamos
      final mejor = mejorCapturado(_vistos, paraAudio: _paraAudio);
      if (mejor != null && mejor.esArchivoEntero) {
        _terminarCon(mejor);
      }
    } catch (_) {
      // mensajes raros de la pagina: se ignoran
    }
  }

  Future<void> _terminarCon(MedioCapturado medio) async {
    final fin = _enCurso;
    if (fin == null || fin.isCompleted) return;
    fin.complete(CapturaOculta(
      url: medio.url,
      titulo: await _titulo(),
      cookies: await _cookies(),
    ));
  }

  Future<CapturaOculta> _loMejorQueTengamos() async {
    final mejor = mejorCapturado(_vistos, paraAudio: _paraAudio);
    if (mejor == null) return const CapturaOculta();
    return CapturaOculta(
      url: mejor.url,
      titulo: await _titulo(),
      cookies: await _cookies(),
    );
  }

  Future<String> _titulo() async {
    try {
      return (await _web?.getTitle()) ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<String> _cookies() async {
    try {
      final r = await _web?.runJavaScriptReturningResult('document.cookie');
      return r
              ?.toString()
              .replaceAll(RegExp(r'^"|"$'), '')
              .replaceAll(r'\"', '"')
              .trim() ??
          '';
    } catch (_) {
      return '';
    }
  }

  @override
  void dispose() {
    _insistir?.cancel();
    super.dispose();
  }
}

/// El navegador oculto, metido en la pantalla sin que se note.
///
/// Tiene que estar montado de verdad: un WebView fuera del arbol no ejecuta
/// JavaScript en Android, y entonces no veriamos pasar nada.
class NavegadorOculto extends StatefulWidget {
  const NavegadorOculto({super.key, required this.capturador});

  final CapturadorOculto capturador;

  @override
  State<NavegadorOculto> createState() => _NavegadorOcultoState();
}

class _NavegadorOcultoState extends State<NavegadorOculto> {
  @override
  void initState() {
    super.initState();
    // se deja listo desde el arranque, para que cuando haga falta ya lleve
    // rato en pantalla y responda a la primera
    widget.capturador.preparar();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.capturador.marcarMontado();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.capturador,
      builder: (context, _) {
        final c = widget.capturador.controlador;
        if (c == null) return const SizedBox.shrink();
        return SizedBox(
          width: 1,
          height: 1,
          child: Opacity(opacity: 0, child: WebViewWidget(controller: c)),
        );
      },
    );
  }
}
