// Pillar el video de cualquier sitio mirando lo que pide la propia pagina.
//
// Instagram, TikTok y compania no ponen el video en el HTML: lo montan con
// JavaScript y se lo sirven al reproductor por trozos, asi que leer la pagina
// desde fuera no sirve de nada.
//
// Lo que si funciona: dentro del navegador de la app la pagina se abre de
// verdad, con su JavaScript y con la sesion del usuario. Si nos enganchamos a
// las peticiones que hace, vemos pasar la direccion real del video.

/// JavaScript que se planta en cada pagina antes de que cargue.
///
/// Engancha fetch y XMLHttpRequest, mira los video del DOM y avisa a la app
/// por el canal CaudalMedios cada vez que encuentra algo que parece media.
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

  function avisar(u, origen, tipoDeclarado) {
    try {
      if (!u || typeof u !== 'string' || u.indexOf('http') !== 0) return;

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
  try {
    new MutationObserver(function () { repasarDom(); })
      .observe(document.documentElement, {childList: true, subtree: true});
  } catch (e) {}

  repasarDom();
  setInterval(repasarDom, 1500);
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

/// Una direccion de media que se vio pasar por la pagina.
class MedioCapturado {
  MedioCapturado(this.url, this.origen);

  final String url;

  /// De donde salio: fetch, xhr o dom. Solo sirve para depurar.
  final String origen;

  String get _limpia => url.split('?').first.toLowerCase();

  bool get esLista => _limpia.endsWith('.m3u8') || _limpia.endsWith('.mpd');

  bool get esSoloAudio =>
      RegExp(r'\.(m4a|mp3|aac|ogg|opus)$').hasMatch(_limpia) ||
      url.contains('mime=audio');

  /// Un archivo entero que se puede bajar tal cual, no un trozo ni una lista.
  ///
  /// TikTok sirve el suyo desde /video/tos/ sin extension ninguna, asi que la
  /// extension no puede ser la unica senal.
  bool get esArchivoEntero {
    if (esLista || _limpia.endsWith('.m4s') || _limpia.endsWith('.ts')) return false;
    if (RegExp(r'\.(mp4|m4v|mov|webm|m4a|mp3|aac|ogg|opus)$').hasMatch(_limpia)) {
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
    return p;
  }
}

/// Se queda con la mejor direccion de las que se vieron pasar.
///
/// [paraAudio] cambia la preferencia: cuando el usuario pide solo sonido, una
/// pista de audio suelta es exactamente lo que queremos.
MedioCapturado? mejorCapturado(List<MedioCapturado> medios, {bool paraAudio = false}) {
  if (medios.isEmpty) return null;
  final ordenados = [...medios];
  ordenados.sort((a, b) {
    final pa = a.puntos + (paraAudio && a.esSoloAudio ? 60 : 0);
    final pb = b.puntos + (paraAudio && b.esSoloAudio ? 60 : 0);
    return pb.compareTo(pa);
  });
  return ordenados.first;
}
