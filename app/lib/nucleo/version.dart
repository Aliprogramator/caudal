// Avisar de versiones nuevas y, en Android, instalarlas sin salir de la app.
//
// Las versiones se publican como releases de GitHub. Cada una lleva adjunto el
// APK. Para cambiar donde se publica basta con tocar [origen].

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Version que lleva esta copia. Sube tambien la de pubspec.yaml al publicar.
const String versionApp = '1.4.0';

/// usuario/repositorio de GitHub donde se publican las versiones
const String origen = 'Aliprogramator/caudal';

const String _api = 'https://api.github.com/repos/$origen/releases/latest';

class Novedad {
  final String version;
  final String notas;
  final String apk;
  final String pagina;
  final int peso;

  const Novedad({
    required this.version,
    required this.notas,
    required this.apk,
    required this.pagina,
    required this.peso,
  });

  /// En iPhone no se puede instalar desde dentro: Apple no lo permite.
  bool get sePuedeInstalar => Platform.isAndroid && apk.isNotEmpty;
}

/// '1.10.0' -> [1, 10, 0]. Compara numero a numero, no como texto: si no,
/// la 1.9.0 pareceria mas nueva que la 1.10.0.
List<int> _numeros(String v) {
  final hallados = RegExp(r'\d+').allMatches(v).map((m) => int.parse(m.group(0)!));
  final lista = hallados.take(4).toList();
  return lista.isEmpty ? [0] : lista;
}

bool hayNovedad(String instalada, String publicada) {
  final a = _numeros(instalada);
  final b = _numeros(publicada);
  for (var i = 0; i < 4; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (y != x) return y > x;
  }
  return false;
}

/// Pregunta a GitHub si hay algo mas nuevo. Devuelve null si ya estas al dia
/// o si no se pudo comprobar: quedarse callado es mejor que dar un error.
Future<Novedad?> buscarActualizacion({Duration espera = const Duration(seconds: 12)}) async {
  try {
    final dio = Dio(BaseOptions(
      connectTimeout: espera,
      receiveTimeout: espera,
      headers: {'User-Agent': 'Caudal', 'Accept': 'application/vnd.github+json'},
      responseType: ResponseType.plain,
    ));
    final r = await dio.get(_api);
    if (r.statusCode != 200) return null;

    final datos = jsonDecode(r.data as String) as Map<String, dynamic>;
    final etiqueta = (datos['tag_name'] ?? datos['name'] ?? '').toString();
    if (etiqueta.isEmpty || !hayNovedad(versionApp, etiqueta)) return null;

    var apk = '';
    var peso = 0;
    for (final a in (datos['assets'] as List? ?? const [])) {
      final nombre = (a['name'] ?? '').toString().toLowerCase();
      // el ligero primero; si solo hay universal, ese
      if (nombre.endsWith('.apk')) {
        final esUniversal = nombre.contains('universal');
        if (apk.isEmpty || !esUniversal) {
          apk = (a['browser_download_url'] ?? '').toString();
          peso = (a['size'] ?? 0) as int;
          if (!esUniversal) break;
        }
      }
    }

    return Novedad(
      version: etiqueta.replaceAll(RegExp('^[vV]'), ''),
      notas: (datos['body'] ?? '').toString().trim(),
      apk: apk,
      pagina: (datos['html_url'] ?? '').toString(),
      peso: peso,
    );
  } catch (_) {
    return null;
  }
}

/// Trae el APK nuevo y lo deja listo para instalar. Devuelve su ruta.
Future<String> descargarApk(
  Novedad novedad, {
  void Function(double)? alProgresar,
  CancelToken? cancelar,
}) async {
  final carpeta = await getTemporaryDirectory();
  final destino = '${carpeta.path}/Caudal-${novedad.version}.apk';

  final ya = File(destino);
  if (await ya.exists() && novedad.peso > 0 && await ya.length() == novedad.peso) {
    alProgresar?.call(100);
    return destino;                      // ya estaba bajado entero
  }

  await Dio().download(
    novedad.apk,
    destino,
    cancelToken: cancelar,
    options: Options(headers: {'User-Agent': 'Caudal'}),
    onReceiveProgress: (hecho, total) {
      if (total > 0) alProgresar?.call(hecho / total * 100);
    },
  );
  return destino;
}

/// Lanza el instalador de Android. El sistema pide permiso la primera vez.
Future<String?> instalar(String rutaApk) async {
  final r = await OpenFilex.open(rutaApk, type: 'application/vnd.android.package-archive');
  if (r.type == ResultType.done) return null;
  if (r.type == ResultType.permissionDenied) {
    return 'Android necesita tu permiso para instalar. Activalo en los ajustes '
        'del telefono, en "Instalar apps desconocidas".';
  }
  return 'No se pudo abrir el instalador: ${r.message}';
}
