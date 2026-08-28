import 'package:flutter/material.dart';

import '../main.dart';
import '../nucleo/ajustes.dart';
import '../nucleo/descargas.dart';
import '../nucleo/formato.dart';
import '../nucleo/modelos.dart';
import '../nucleo/tema.dart';
import '../nucleo/version.dart';
import '../widgets/comunes.dart';
import '../widgets/hoja_version.dart';

/// Ajustes de la app, cuenta y estado de la conexión.
class VistaAjustes extends StatefulWidget {
  const VistaAjustes({super.key});

  @override
  State<VistaAjustes> createState() => _VistaAjustesState();
}

class _VistaAjustesState extends State<VistaAjustes> {
  Map<String, int> _resumen = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cargarResumen();
    });
  }

  Future<void> _cargarResumen() async {
    final r = await Servicios.de(context).almacen.resumen();
    if (mounted) setState(() => _resumen = r);
  }





  @override
  Widget build(BuildContext context) {
    final servicios = Servicios.de(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListenableBuilder(
        listenable: servicios.ajustes,
        builder: (context, _) {
          final a = servicios.ajustes;

          return ListView(
            padding: const EdgeInsets.fromLTRB(Medidas.margen, 4, Medidas.margen, 30),
            children: [

              _seccion('Modo música'),
              _tarjetaModoMusica(a, servicios),

              _seccion('Descargas'),
              _tarjeta([
                SwitchListTile(
                  value: a.guardarEnPublico,
                  onChanged: (v) async {
                    if (v) {
                      final ok = await GestorDescargas.pedirPermisoAlmacenamiento();
                      if (!ok) {
                        if (context.mounted) {
                          avisar(context,
                              'Sin ese permiso las descargas se guardan solo dentro de la app',
                              esError: true);
                        }
                        return;
                      }
                    }
                    await a.definirGuardarEnPublico(v);
                  },
                  title: const Text('Guardar en la carpeta Descargas'),
                  subtitle: Text(
                    a.guardarEnPublico
                        ? 'En Descargas/Caudal, visible para tus otras apps'
                        : 'Dentro de la app: se borra si desinstalas Caudal',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: a.avisarAlTerminar,
                  onChanged: a.definirAvisar,
                  title: const Text('Avisar al terminar'),
                  subtitle: Text('Un mensaje breve cuando se guarda algo',
                      style: Theme.of(context).textTheme.bodySmall),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                ),
              ]),

              _seccion('Preferencias por defecto'),
              _tarjeta([
                ListTile(
                  leading: const Icon(Icons.tune_rounded),
                  title: const Text('Qué descargar'),
                  subtitle: Text(a.tipoPorDefecto.titulo,
                      style: Theme.of(context).textTheme.bodySmall),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Tono.texto3),
                  onTap: () => _elegirTipo(a),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.hd_rounded),
                  title: const Text('Calidad de video'),
                  subtitle: Text(
                      a.calidad == 'mejor' ? 'La mejor disponible' : '${a.calidad}p',
                      style: Theme.of(context).textTheme.bodySmall),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Tono.texto3),
                  onTap: () => _elegirCalidad(a),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.audiotrack_rounded),
                  title: const Text('Formato de audio'),
                  subtitle: Text(a.formatoAudio.toUpperCase(),
                      style: Theme.of(context).textTheme.bodySmall),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Tono.texto3),
                  onTap: () => _elegirAudio(a),
                ),
              ]),

              _seccion('Almacenamiento'),
              _tarjeta([
                ListTile(
                  leading: const Icon(Icons.folder_rounded),
                  title: const Text('Lo que tienes guardado'),
                  subtitle: Text(
                    _resumen.isEmpty
                        ? 'Calculando...'
                        : '${_resumen['audio']} canciones · ${_resumen['video']} videos · '
                            '${formatoBytes(_resumen['bytes'] ?? 0)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_rounded),
                  title: const Text('Quitar lo que ya no existe'),
                  subtitle: Text('Limpia de la lista los archivos que borraste aparte',
                      style: Theme.of(context).textTheme.bodySmall),
                  onTap: () async {
                    final quitados = await Servicios.de(context).almacen.depurar();
                    await _cargarResumen();
                    if (context.mounted) {
                      avisar(context,
                          quitados == 0 ? 'Todo está en su sitio' : 'Se quitaron $quitados');
                    }
                  },
                ),
              ]),

              _seccion('Version'),
              _tarjeta([
                ListTile(
                  leading: const Icon(Icons.system_update_rounded),
                  title: const Text('Buscar actualizaciones'),
                  subtitle: Text(
                    _buscandoVersion ? 'Comprobando...' : _estadoVersion,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  trailing: _buscandoVersion
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: _buscandoVersion ? null : _buscarVersion,
                ),
              ]),

              const SizedBox(height: 26),
              Center(
                child: Column(
                  children: [
                    const Icon(Icons.water_drop_rounded, color: Tono.texto3, size: 20),
                    const SizedBox(height: 6),
                    Text('Caudal $versionApp',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 3),
                    Text(
                      'Descarga solo contenido cuyo uso te permitan\nla licencia y los '
                      'términos del sitio.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------- cuenta

  bool _buscandoVersion = false;
  String _estadoVersion = 'Tienes la version $versionApp';

  Future<void> _buscarVersion() async {
    setState(() => _buscandoVersion = true);
    final novedad = await buscarActualizacion();
    if (!mounted) return;
    setState(() {
      _buscandoVersion = false;
      _estadoVersion = novedad == null
          ? 'Tienes la $versionApp. Es la mas reciente.'
          : 'Hay una nueva: ${novedad.version}';
    });
    if (novedad != null) await mostrarHojaVersion(context, novedad);
  }

  Widget _tarjetaModoMusica(Ajustes a, Servicios servicios) {
    return _tarjeta([
      SwitchListTile(
        value: a.modoMusica,
        onChanged: (v) async {
          await a.definirModoMusica(v);
          await servicios.audio.definirModoMusica(v, refuerzo: a.refuerzoReproductor);
          if (v && mounted) {
            avisar(context, 'Lo que descargues a partir de ahora sonará más fuerte');
          }
        },
        secondary: Icon(
          a.modoMusica ? Icons.volume_up_rounded : Icons.volume_down_rounded,
          color: a.modoMusica ? Tono.acento : Tono.texto3,
        ),
        title: const Text('Que suene lo más fuerte posible'),
        subtitle: Text(
          a.modoMusica
              ? 'El audio se nivela al descargarlo y el reproductor empuja el volumen'
              : 'Volumen normal, tal cual viene el original',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      if (a.modoMusica) ...[
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Empuje del reproductor',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const Spacer(),
                  Text(
                    '${(a.refuerzoReproductor * 100).round()} %',
                    style: const TextStyle(
                        color: Tono.acento, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ],
              ),
              Slider(
                value: a.refuerzoReproductor,
                min: 1.0,
                max: 2.0,
                divisions: 10,
                onChanged: (v) async {
                  await a.definirRefuerzoReproductor(v);
                  await servicios.audio.definirModoMusica(true, refuerzo: v);
                },
              ),
              Text(
                'Por encima del 160 % puede empezar a distorsionar en canciones ya de '
                'por sí fuertes.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              const Aviso(
                texto: 'Lo ya descargado mantiene su volumen: para que suene más fuerte '
                    'hay que volver a bajarlo con el modo activado.',
                icono: Icons.info_outline_rounded,
                color: Tono.texto3,
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ],
    ]);
  }

  // ---------------------------------------------------------------- piezas

  Widget _seccion(String texto) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
        child: Text(
          texto.toUpperCase(),
          style: const TextStyle(
            color: Tono.texto3,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      );

  Widget _tarjeta(List<Widget> hijos) => Container(
        decoration: BoxDecoration(
          color: Tono.superficie,
          borderRadius: BorderRadius.circular(Medidas.radio),
          border: Border.all(color: Tono.borde),
        ),
        child: Column(children: hijos),
      );

  Future<void> _elegirTipo(Ajustes a) async {
    await _hojaOpciones(
      titulo: 'Qué descargar por defecto',
      opciones: const [
        ('Video con audio', 'completo'),
        ('Solo video', 'video'),
        ('Solo audio', 'audio'),
      ],
      actual: a.tipoPorDefecto.clave,
      alElegir: (v) => a.definirTipo(TipoMedioTexto.desdeClave(v)),
    );
  }

  Future<void> _elegirCalidad(Ajustes a) async {
    await _hojaOpciones(
      titulo: 'Calidad de video',
      opciones: const [
        ('La mejor disponible', 'mejor'),
        ('4K · 2160p', '2160'),
        ('Full HD · 1080p', '1080'),
        ('HD · 720p', '720'),
        ('SD · 480p', '480'),
        ('Ligero · 360p', '360'),
      ],
      actual: a.calidad,
      alElegir: a.definirCalidad,
    );
  }

  Future<void> _elegirAudio(Ajustes a) async {
    await _hojaOpciones(
      titulo: 'Formato de audio',
      opciones: const [
        ('MP3 · compatible con todo', 'mp3'),
        ('M4A · mejor calidad', 'm4a'),
        ('FLAC · sin pérdida', 'flac'),
        ('WAV · sin comprimir', 'wav'),
      ],
      actual: a.formatoAudio,
      alElegir: a.definirFormatoAudio,
    );
  }

  Future<void> _hojaOpciones({
    required String titulo,
    required List<(String, String)> opciones,
    required String actual,
    required void Function(String) alElegir,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Tono.superficie,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Medidas.margen, 4, Medidas.margen, 8),
              child: Text(titulo, style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final (etiqueta, valor) in opciones)
              ListTile(
                title: Text(etiqueta),
                trailing: actual == valor
                    ? const Icon(Icons.check_rounded, color: Tono.acento)
                    : null,
                onTap: () {
                  alElegir(valor);
                  Navigator.of(context).pop();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
