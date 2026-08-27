import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'modelos.dart';

/// Biblioteca de lo ya descargado, guardada en SQLite.
class Almacen {
  Almacen._(this._db);

  final Database _db;

  static Future<Almacen> abrir() async {
    final carpeta = await getApplicationDocumentsDirectory();
    final ruta = p.join(carpeta.path, 'caudal.db');
    final db = await openDatabase(
      ruta,
      version: 1,
      onCreate: (d, _) async {
        await d.execute('''
          CREATE TABLE pistas (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            titulo TEXT NOT NULL,
            autor TEXT,
            archivo TEXT NOT NULL,
            miniatura TEXT,
            duracion INTEGER DEFAULT 0,
            tamano INTEGER DEFAULT 0,
            origen TEXT,
            es_audio INTEGER DEFAULT 0,
            fecha INTEGER DEFAULT 0
          )
        ''');
        await d.execute('CREATE INDEX idx_fecha ON pistas(fecha DESC)');
        await d.execute('CREATE INDEX idx_tipo ON pistas(es_audio)');
      },
    );
    return Almacen._(db);
  }

  Future<int> guardar(Pista pista) => _db.insert('pistas', pista.aFila());

  /// Todo lo guardado. [soloAudio] null = ambos.
  Future<List<Pista>> listar({bool? soloAudio, String filtro = ''}) async {
    final donde = <String>[];
    final args = <Object?>[];

    if (soloAudio != null) {
      donde.add('es_audio = ?');
      args.add(soloAudio ? 1 : 0);
    }
    if (filtro.trim().isNotEmpty) {
      donde.add('(titulo LIKE ? OR autor LIKE ?)');
      args..add('%$filtro%')..add('%$filtro%');
    }

    final filas = await _db.query(
      'pistas',
      where: donde.isEmpty ? null : donde.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'fecha DESC',
    );
    return filas.map(Pista.desdeFila).toList();
  }

  Future<void> borrar(int id, {bool borrarArchivo = true}) async {
    if (borrarArchivo) {
      final filas = await _db.query('pistas', where: 'id = ?', whereArgs: [id], limit: 1);
      if (filas.isNotEmpty) {
        final ruta = '${filas.first['archivo']}';
        final archivo = File(ruta);
        if (await archivo.exists()) {
          try {
            await archivo.delete();
          } on FileSystemException {
            // si el sistema no deja borrarlo, al menos lo quitamos de la lista
          }
        }
      }
    }
    await _db.delete('pistas', where: 'id = ?', whereArgs: [id]);
  }

  /// Quita de la lista lo que ya no existe en el disco (por si el usuario lo borró aparte).
  Future<int> depurar() async {
    final filas = await _db.query('pistas');
    var quitados = 0;
    for (final f in filas) {
      final ruta = '${f['archivo']}';
      if (ruta.isEmpty || !await File(ruta).exists()) {
        await _db.delete('pistas', where: 'id = ?', whereArgs: [f['id']]);
        quitados++;
      }
    }
    return quitados;
  }

  Future<Map<String, int>> resumen() async {
    final audio = Sqflite.firstIntValue(
            await _db.rawQuery('SELECT COUNT(*) FROM pistas WHERE es_audio = 1')) ??
        0;
    final video = Sqflite.firstIntValue(
            await _db.rawQuery('SELECT COUNT(*) FROM pistas WHERE es_audio = 0')) ??
        0;
    final bytes =
        Sqflite.firstIntValue(await _db.rawQuery('SELECT COALESCE(SUM(tamano),0) FROM pistas')) ?? 0;
    return {'audio': audio, 'video': video, 'bytes': bytes};
  }

  Future<bool> yaExiste(String origen) async {
    final filas = await _db.query('pistas',
        where: 'origen = ?', whereArgs: [origen], limit: 1);
    if (filas.isEmpty) return false;
    return File('${filas.first['archivo']}').existsSync();
  }
}
