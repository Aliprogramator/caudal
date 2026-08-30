// Pillar el video de cualquier sitio mirando lo que pide la propia pagina.
//
// Instagram, TikTok y compania no ponen el video en el HTML: lo montan con
// JavaScript y se lo sirven al reproductor por trozos, asi que leer la pagina
// desde fuera no sirve de nada.
//
// Aqui hay dos redes tendidas a la vez:
//
//   1. Este guion, que se planta en cada marco de la pagina ANTES de que
//      corra su propio JavaScript. Ve lo que pide con fetch y con XHR y lo
//      que se le pone a cada <video>.
//   2. El interceptor de peticiones del navegador (navegador_caudal.dart),
//      que ve pasar absolutamente todo, incluido lo que piden los workers y
//      el service worker, donde este guion no llega.
//
// Ninguna de las dos basta sola. Medido contra un banco de pruebas con los
// siete montajes que usan las webs de verdad, solo con las dos juntas se
// consigue bajar el video en los siete.

/// El puente hacia la app.
///
/// El guion avisa con `CaudalMedios.postMessage(...)`. Aqui se conecta eso al
/// canal del navegador. Si el canal todavia no esta puesto —puede pasar en el
/// primer instante de la pagina—, los avisos se guardan y se mandan en cuanto
/// aparece: perder el primer aviso es perder justo el que importa, porque el
/// reproductor pide su video nada mas arrancar.
const String guionPuente = r'''
(function () {
  if (window.__caudalPuente) return;
  window.__caudalPuente = true;
  var cola = [];

  function listo() {
    return window.flutter_inappwebview && window.flutter_inappwebview.callHandler;
  }

  function mandar(canal, mensaje) {
    try {
      if (listo()) {
        window.flutter_inappwebview.callHandler(canal, mensaje);
      } else {
        cola.push([canal, mensaje]);
      }
    } catch (e) {
      cola.push([canal, mensaje]);
    }
  }

  window.CaudalMedios = { postMessage: function (m) { mandar('caudalMedios', m); } };
  window.CaudalRuta = { postMessage: function (m) { mandar('caudalRuta', m); } };

  setInterval(function () {
    if (!listo() || !cola.length) return;
    var pendientes = cola.splice(0, cola.length);
    for (var i = 0; i < pendientes.length; i++) {
      try {
        window.flutter_inappwebview.callHandler(pendientes[i][0], pendientes[i][1]);
      } catch (e) {}
    }
  }, 250);
})();
''';

/// JavaScript que se planta en cada pagina antes de que cargue.
///
/// Engancha fetch y XMLHttpRequest, vigila lo que se le asigna a cada <video>
/// y avisa a la app por el canal CaudalMedios cada vez que encuentra algo que
/// parece media.
const String guionCaptura = r'''
(function () {
  if (window.__caudalCaptura) return;
  window.__caudalCaptura = true;

  var vistos = {};

  // Adivinar por la direccion no basta: TikTok sirve sus videos desde
  // /video/tos/... sin extension ninguna, y los trozos de Instagram vienen
  // con bytestart. Por eso lo primero que se mira es el tipo que declara la
  // respuesta, que no miente, y la direccion queda de respaldo.
  function pintaDeMedia(u) {
    if (!u || typeof u !== 'string') return false;
    if (u.indexOf('blob:') === 0 || u.indexOf('data:') === 0) return false;
    if (u.indexOf('http') !== 0) return false;

    var sinParametros = u.split('?')[0].toLowerCase();
    if (/\.(mp4|m4v|mov|webm|m4a|mp3|aac|ogg|opus|m3u8|mpd|m4s|ts)$/.test(sinParametros)) return true;

    // rutas tipicas de cada red
    if (/\/video\/tos\//.test(sinParametros)) return true;          // TikTok
    if (/\/videoplayback/.test(sinParametros)) return true;         // YouTube
    if (/bytestart=|byteend=/.test(u)) return true;                 // Facebook, Instagram
    if (/mime=video|mime=audio/.test(u)) return true;
    if (/\/(dash|hls)\//.test(sinParametros)) return true;
    return false;
  }

  function absoluta(u) {
    try { return new URL(u, document.baseURI).href; } catch (e) { return u; }
  }

  function avisar(u, origen, tipoDeclarado) {
    try {
      if (!u || typeof u !== 'string') return;
      if (u.indexOf('blob:') === 0 || u.indexOf('data:') === 0) return;
      if (u.indexOf('http') !== 0) u = absoluta(u);
      if (u.indexOf('http') !== 0) return;

      var esMedia = false;
      if (tipoDeclarado) {
        var t = tipoDeclarado.toLowerCase();
        esMedia = t.indexOf('video/') === 0 || t.indexOf('audio/') === 0 ||
                  t.indexOf('application/vnd.apple.mpegurl') === 0 ||
                  t.indexOf('application/x-mpegurl') === 0 ||
                  t.indexOf('application/dash+xml') === 0;
      }
      if (!esMedia) esMedia = pintaDeMedia(u);
      if (!esMedia) return;

      // los trozos numerados de un mismo video se cuentan una vez
      var clave = u.split('?')[0];
      if (vistos[clave]) return;
      vistos[clave] = 1;
      CaudalMedios.postMessage(JSON.stringify({url: u, origen: origen}));
    } catch (e) {}
  }

  // --- peticiones que hace la pagina
  var fetchOriginal = window.fetch;
  if (fetchOriginal) {
    window.fetch = function (entrada, opciones) {
      var u = '';
      try {
        u = (typeof entrada === 'string') ? entrada : (entrada && entrada.url);
        avisar(u, 'fetch');
      } catch (e) {}
      var r = fetchOriginal.apply(this, arguments);
      // y cuando conteste, miramos que dice que es
      try {
        return r.then(function (respuesta) {
          try {
            avisar(respuesta.url || u, 'fetch',
                   respuesta.headers && respuesta.headers.get('content-type'));
          } catch (e) {}
          return respuesta;
        });
      } catch (e) {
        return r;
      }
    };
  }

  var abrirOriginal = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (metodo, u) {
    try {
      avisar(u, 'xhr');
      this.addEventListener('readystatechange', function () {
        try {
          if (this.readyState === 2) {
            avisar(this.responseURL || u, 'xhr',
                   this.getResponseHeader('content-type'));
          }
        } catch (e) {}
      });
    } catch (e) {}
    return abrirOriginal.apply(this, arguments);
  };

  // --- cuando alguien le pone un video a un reproductor
  //
  // Muchos sitios no piden el archivo con fetch: se lo asignan directamente al
  // elemento y es el propio navegador quien lo trae. Ahi no hay fetch que
  // enganchar, pero si hay una asignacion que vigilar.
  try {
    var proto = HTMLMediaElement.prototype;
    var descriptor = Object.getOwnPropertyDescriptor(proto, 'src');
    if (descriptor && descriptor.set && descriptor.get) {
      Object.defineProperty(proto, 'src', {
        get: function () { return descriptor.get.call(this); },
        set: function (valor) {
          try { avisar(valor, 'asignado'); } catch (e) {}
          return descriptor.set.call(this, valor);
        },
        configurable: true,
      });
    }
    proto.addEventListener('loadstart', function () {
      try { avisar(this.currentSrc || this.src || '', 'reproductor'); } catch (e) {}
    }, true);
  } catch (e) {}

  // --- lo que ya esta puesto en la pagina
  function repasarDom() {
    try {
      document.querySelectorAll('video, audio, source').forEach(function (n) {
        avisar(n.currentSrc || n.src || '', 'dom');
      });
      // algunos sitios guardan la buena en un atributo aparte
      document.querySelectorAll('[data-src], [data-video-url], [data-hd-src]').forEach(function (n) {
        avisar(n.getAttribute('data-src') || n.getAttribute('data-video-url') ||
               n.getAttribute('data-hd-src') || '', 'dom');
      });
    } catch (e) {}
  }

  // --- cuando aparece un video nuevo (scroll, cambio de reel...)
  function vigilarDom() {
    try {
      new MutationObserver(function () { repasarDom(); })
        .observe(document.documentElement, {childList: true, subtree: true});
    } catch (e) {}
    repasarDom();
  }

  // este guion entra antes que el documento: si todavia no hay raiz que
  // vigilar, se espera a que la haya
  if (document.documentElement) {
    vigilarDom();
  } else {
    document.addEventListener('DOMContentLoaded', vigilarDom);
  }
  setInterval(repasarDom, 1500);
})();
''';

/// Vigila los cambios de direccion sin recarga.
///
/// YouTube y compania cambian de video sin volver a cargar la pagina, asi que
/// hay que mirar el historial para enterarse.
const String guionRuta = r'''
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
''';

/// Empuja a la pagina a cargar el video, para que pida sus trozos y podamos
/// verlos pasar.
///
/// En Instagram o TikTok el video no se pide hasta que algo lo reproduce. Si
/// el usuario le dio a descargar sin haberlo visto, hay que darle un empujon:
/// se pone en marcha en silencio un instante y se vuelve a dejar como estaba.
const String guionDespertar = r'''
(function () {
  try {
    var vs = document.querySelectorAll('video');
    if (!vs.length) {
      // algunas paginas montan el video solo cuando algo entra en pantalla
      window.scrollBy(0, 1);
      window.scrollBy(0, -1);
      return;
    }
    vs.forEach(function (v) {
      try {
        var estabaSilenciado = v.muted;
        var estabaEnPausa = v.paused;
        v.muted = true;
        var p = v.play();
        if (p && p.then) { p.then(function(){}).catch(function(){}); }
        setTimeout(function () {
          try {
            if (estabaEnPausa) v.pause();
            v.muted = estabaSilenciado;
          } catch (e) {}
        }, 1400);
      } catch (e) {}
    });
  } catch (e) {}
})();
''';

/// Deja una direccion capturada lista para bajar el archivo entero.
///
/// Los reproductores no piden el video de una vez: lo van pidiendo a trozos,
/// anadiendo a la direccion en que byte empieza y en cual acaba. Si se baja
/// tal cual, lo que llega es un pedazo suelto que no se puede reproducir ni
/// convertir: de ahi los "Invalid data" y los archivos de cero bytes.
///
/// Quitando esos parametros, el servidor devuelve el archivo completo.
/// Comprobado: la misma direccion da 1 MB con range y 3,4 MB sin el.
String limpiarTrozos(String url) {
  if (!url.contains('?')) return url;
  const sobran = {'range', 'rn', 'rbuf', 'ump', 'srfvp', 'bytestart', 'byteend'};

  final corte = url.indexOf('?');
  final base = url.substring(0, corte);
  final partes = url
      .substring(corte + 1)
      .split('&')
      .where((p) => p.isNotEmpty && !sobran.contains(p.split('=').first))
      .toList();

  return partes.isEmpty ? base : '$base?${partes.join('&')}';
}

/// Filtro rapido para el interceptor de peticiones.
///
/// Por ahi pasa absolutamente todo lo que pide la pagina: fuentes, iconos,
/// analiticas, cientos de cosas por minuto. Antes de mirar nada con calma hay
/// que descartar de un vistazo lo que seguro que no es un video, o el propio
/// hecho de mirarlo frena la navegacion.
final RegExp _pistasDeMedia = RegExp(
  r'\.(mp4|m4v|mov|mkv|webm|m4a|mp3|aac|ogg|opus|flac|wav|m3u8|mpd|m4s|ts)(\?|$)'
  r'|/video/tos/|/videoplayback|bytestart=|byteend=|mime=video|mime=audio'
  r'|/dash/|/hls/|googlevideo\.com',
  caseSensitive: false,
);

bool podriaSerMedia(String url) {
  if (url.length < 12 || !url.startsWith('http')) return false;
  return _pistasDeMedia.hasMatch(url);
}

/// Una direccion de media que se vio pasar por la pagina.
class MedioCapturado {
  MedioCapturado(String url, this.origen) : url = limpiarTrozos(url);

  final String url;

  /// De donde salio: fetch, xhr, dom, reproductor o red. Sirve para depurar y
  /// para desempatar: lo que vio el interceptor de red es lo mas fiable.
  final String origen;

  String get _limpia => url.split('?').first.toLowerCase();

  bool get esLista => _limpia.endsWith('.m3u8') || _limpia.endsWith('.mpd');

  bool get esSoloAudio =>
      RegExp(r'\.(m4a|mp3|aac|ogg|opus|flac|wav)$').hasMatch(_limpia) ||
      url.contains('mime=audio');

  /// Un archivo entero que se puede bajar tal cual, no un trozo ni una lista.
  ///
  /// TikTok sirve el suyo desde /video/tos/ sin extension ninguna, asi que la
  /// extension no puede ser la unica senal.
  bool get esArchivoEntero {
    if (esLista || _limpia.endsWith('.m4s') || _limpia.endsWith('.ts')) return false;
    if (RegExp(r'\.(mp4|m4v|mov|webm|m4a|mp3|aac|ogg|opus|flac|wav)$').hasMatch(_limpia)) {
      return true;
    }
    return RegExp(r'/video/tos/').hasMatch(_limpia);
  }

  /// Cuanto nos interesa: preferimos un mp4 entero antes que una lista de
  /// trozos, porque se baja de una y no hay que pegar nada.
  int get puntos {
    var p = 0;
    if (esArchivoEntero) p += 100;
    if (esLista) p += 40;
    if (_limpia.endsWith('.mp4')) p += 20;
    if (esSoloAudio) p -= 10;      // si buscamos video, el audio suelto es peor
    // las direcciones largas suelen ser las firmadas de verdad
    if (url.length > 120) p += 5;
    // un trozo suelto de una lista no vale de nada por si mismo
    if (_limpia.endsWith('.ts') || _limpia.endsWith('.m4s')) p -= 60;
    return p;
  }
}

/// Ordena lo visto de mejor a peor, para poder ir probando por orden.
///
/// Quedarse solo con la mejor era rendirse antes de tiempo: si esa direccion
/// ya caduco o el servidor la rechaza, habia otras detras que si valian.
List<MedioCapturado> candidatasOrdenadas(
  List<MedioCapturado> medios, {
  bool paraAudio = false,
}) {
  final ordenados = [...medios];
  ordenados.sort((a, b) {
    final pa = a.puntos + (paraAudio && a.esSoloAudio ? 60 : 0);
    final pb = b.puntos + (paraAudio && b.esSoloAudio ? 60 : 0);
    return pb.compareTo(pa);
  });
  return ordenados;
}

/// Se queda con la mejor direccion de las que se vieron pasar.
///
/// [paraAudio] cambia la preferencia: cuando el usuario pide solo sonido, una
/// pista de audio suelta es exactamente lo que queremos.
MedioCapturado? mejorCapturado(List<MedioCapturado> medios, {bool paraAudio = false}) {
  if (medios.isEmpty) return null;
  return candidatasOrdenadas(medios, paraAudio: paraAudio).first;
}
