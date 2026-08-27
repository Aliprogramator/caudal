import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'nucleo/ajustes.dart';
import 'nucleo/almacen.dart';
import 'nucleo/descargas.dart';
import 'nucleo/servidor.dart';
import 'nucleo/tema.dart';
import 'pantallas/acceso.dart';
import 'pantallas/inicio.dart';
import 'reproduccion/reproductor_audio.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // deja que la musica siga sonando con la pantalla apagada
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.kevinrr.caudal.audio',
    androidNotificationChannelName: 'Reproduccion',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
  );

  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Tono.superficie,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  final ajustes = await Ajustes.abrir();

  // si no pidió que le recordaran, la sesión no sobrevive al cierre
  if (!ajustes.mantenerSesion) {
    await ajustes.cerrarSesion();
  }
  final almacen = await Almacen.abrir();
  final servidor = Servidor(
    local: ajustes.servidorLocal,
    publica: ajustes.servidorPublico,
    token: ajustes.token,
  );
  final descargas = GestorDescargas(servidor: servidor, almacen: almacen, ajustes: ajustes);
  final audio = ReproductorAudio();
  await audio.definirModoMusica(ajustes.modoMusica,
      refuerzo: ajustes.refuerzoReproductor);

  // si el servidor rechaza la sesion, el telefono la olvida y pide entrar de nuevo
  servidor.alCaducarSesion.listen((_) => ajustes.cerrarSesion());

  runApp(CaudalApp(
    ajustes: ajustes,
    almacen: almacen,
    servidor: servidor,
    descargas: descargas,
    audio: audio,
  ));
}

/// Contenedor de servicios: cualquier pantalla los alcanza con `Servicios.de(context)`.
class Servicios extends InheritedWidget {
  const Servicios({
    super.key,
    required this.ajustes,
    required this.almacen,
    required this.servidor,
    required this.descargas,
    required this.audio,
    required super.child,
  });

  final Ajustes ajustes;
  final Almacen almacen;
  final Servidor servidor;
  final GestorDescargas descargas;
  final ReproductorAudio audio;

  static Servicios de(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<Servicios>();
    assert(s != null, 'No hay Servicios en este arbol de widgets');
    return s!;
  }

  @override
  bool updateShouldNotify(Servicios anterior) => false;
}

/// Decide qué se ve al abrir: la cuenta si no hay sesión, o la app si la hay.
class _Puerta extends StatelessWidget {
  const _Puerta();

  @override
  Widget build(BuildContext context) {
    final ajustes = Servicios.de(context).ajustes;
    return ListenableBuilder(
      listenable: ajustes,
      builder: (context, _) {
        if (!ajustes.conSesion) {
          return const PantallaAcceso(comoPuerta: true);
        }
        return const PantallaInicio();
      },
    );
  }
}

class CaudalApp extends StatelessWidget {
  const CaudalApp({
    super.key,
    required this.ajustes,
    required this.almacen,
    required this.servidor,
    required this.descargas,
    required this.audio,
  });

  final Ajustes ajustes;
  final Almacen almacen;
  final Servidor servidor;
  final GestorDescargas descargas;
  final ReproductorAudio audio;

  @override
  Widget build(BuildContext context) {
    return Servicios(
      ajustes: ajustes,
      almacen: almacen,
      servidor: servidor,
      descargas: descargas,
      audio: audio,
      child: MaterialApp(
        title: 'Caudal',
        debugShowCheckedModeBanner: false,
        theme: construirTema(),
        home: const _Puerta(),
        builder: (context, hijo) {
          // el tamano de letra del sistema no debe romper el diseno
          final escala = MediaQuery.of(context).textScaler.clamp(
                minScaleFactor: 0.85,
                maxScaleFactor: 1.25,
              );
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: escala),
            child: hijo!,
          );
        },
      ),
    );
  }
}
