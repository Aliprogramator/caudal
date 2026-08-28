import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'modelos.dart';

/// Preferencias de la app, guardadas en el teléfono.
class Ajustes extends ChangeNotifier {
  Ajustes._(this._prefs);

  final SharedPreferences _prefs;

  static Future<Ajustes> abrir() async {
    final prefs = await SharedPreferences.getInstance();
    return Ajustes._(prefs);
  }

  // Caudal no se conecta a ningun servidor: todo lo que se descarga se queda
  // en este telefono. Aqui solo viven las preferencias del usuario.

  // ---- preferencias de descarga
  TipoMedio get tipoPorDefecto =>
      TipoMedioTexto.desdeClave(_prefs.getString('tipo') ?? 'completo');

  Future<void> definirTipo(TipoMedio t) async {
    await _prefs.setString('tipo', t.clave);
    notifyListeners();
  }

  String get calidad => _prefs.getString('calidad') ?? 'mejor';

  Future<void> definirCalidad(String c) async {
    await _prefs.setString('calidad', c);
    notifyListeners();
  }

  String get formatoAudio => _prefs.getString('formato_audio') ?? 'mp3';

  Future<void> definirFormatoAudio(String f) async {
    await _prefs.setString('formato_audio', f);
    notifyListeners();
  }

  /// Bajar directo al teléfono cuando se pueda, sin pasar por el servidor.
  bool get descargaDirecta => _prefs.getBool('descarga_directa') ?? true;

  Future<void> definirDescargaDirecta(bool v) async {
    await _prefs.setBool('descarga_directa', v);
    notifyListeners();
  }

  /// Modo música: el audio se descarga normalizado para que suene mucho más
  /// fuerte, y el reproductor añade un empujón extra de volumen.
  bool get modoMusica => _prefs.getBool('modo_musica') ?? false;

  Future<void> definirModoMusica(bool v) async {
    await _prefs.setBool('modo_musica', v);
    notifyListeners();
  }

  /// Cuánto empuja el reproductor por encima de lo normal (1.0 = sin empuje).
  double get refuerzoReproductor => _prefs.getDouble('refuerzo_reproductor') ?? 1.6;

  Future<void> definirRefuerzoReproductor(double v) async {
    await _prefs.setDouble('refuerzo_reproductor', v.clamp(1.0, 2.0));
    notifyListeners();
  }

  /// Guardar en la carpeta pública de descargas (visible para otras apps).
  bool get guardarEnPublico => _prefs.getBool('guardar_publico') ?? true;

  Future<void> definirGuardarEnPublico(bool v) async {
    await _prefs.setBool('guardar_publico', v);
    notifyListeners();
  }

  /// Avisar cuando cada descarga termina.
  bool get avisarAlTerminar => _prefs.getBool('avisar') ?? true;

  Future<void> definirAvisar(bool v) async {
    await _prefs.setBool('avisar', v);
    notifyListeners();
  }

  // ---- navegador
  List<String> get favoritos => _prefs.getStringList('favoritos') ?? const [];

  Future<void> agregarFavorito(String url) async {
    final lista = [...favoritos];
    if (!lista.contains(url)) {
      lista.insert(0, url);
      if (lista.length > 40) lista.removeLast();
      await _prefs.setStringList('favoritos', lista);
      notifyListeners();
    }
  }

  Future<void> quitarFavorito(String url) async {
    final lista = [...favoritos]..remove(url);
    await _prefs.setStringList('favoritos', lista);
    notifyListeners();
  }

  // ---- búsquedas recientes
  List<String> get busquedas => _prefs.getStringList('busquedas') ?? const [];

  Future<void> recordarBusqueda(String consulta) async {
    final texto = consulta.trim();
    if (texto.isEmpty) return;
    final lista = [...busquedas]..remove(texto);
    lista.insert(0, texto);
    if (lista.length > 12) lista.removeRange(12, lista.length);
    await _prefs.setStringList('busquedas', lista);
    notifyListeners();
  }

  Future<void> limpiarBusquedas() async {
    await _prefs.remove('busquedas');
    notifyListeners();
  }
}
