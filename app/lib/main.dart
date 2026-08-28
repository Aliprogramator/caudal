import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'nucleo/ajustes.dart';
import 'nucleo/almacen.dart';
import 'nucleo/capturador_oculto.dart';
import 'nucleo/descargas.dart';
import 'nucleo/tema.dart';
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

  final almacen = await Almacen.abrir();
  final capturador = CapturadorOculto();
  final descargas = GestorDescargas(
      almacen: almacen, ajustes: ajustes, capturador: capturador);
  final audio = ReproductorAudio();
  await audio.definirModoMusica(ajustes.modoMusica,
      refuerzo: ajustes.refuerzoReproductor);

  runApp(CaudalApp(
    ajustes: ajustes,
    almacen: almacen,
    descargas: descargas,
    audio: audio,
    capturador: capturador,
  ));
}

/// Contenedor de servicios: cualquier pantalla los alcanza con `Servicios.de(context)`.
class Servicios extends InheritedWidget {
  const Servicios({
    super.key,
    required this.ajustes,
    required this.almacen,
    required this.descargas,
    required this.audio,
    required this.capturador,
    required super.child,
  });

  final Ajustes ajustes;
  final Almacen almacen;
  final GestorDescargas descargas;
  final CapturadorOculto capturador;
  final ReproductorAudio audio;

  static Servicios de(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<Servicios>();
    assert(s != null, 'No hay Servicios en este arbol de widgets');
    return s!;
  }

  @override
  bool updateShouldNotify(Servicios anterior) => false;
}

/// Al abrir se entra directo a la app.
///
/// No hay cuenta que crear ni nada que conectar: Caudal descarga dentro del
/// propio telefono, asi que no tiene sentido pedirle nada al usuario antes de
/// dejarle usarlo.
class _Puerta extends StatelessWidget {
  const _Puerta();

  @override
  Widget build(BuildContext context) => const PantallaInicio();
}

class CaudalApp extends StatelessWidget {
  const CaudalApp({
    super.key,
    required this.ajustes,
    required this.almacen,
    required this.descargas,
    required this.audio,
    required this.capturador,
  });

  final Ajustes ajustes;
  final Almacen almacen;
  final GestorDescargas descargas;
  final ReproductorAudio audio;
  final CapturadorOculto capturador;

  @override
  Widget build(BuildContext context) {
    return Servicios(
      ajustes: ajustes,
      almacen: almacen,
      descargas: descargas,
      audio: audio,
      capturador: capturador,
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
            // el navegador oculto va aqui: tiene que estar montado de verdad
            // para que Android ejecute su JavaScript, aunque no se vea
            child: Stack(
              children: [
                hijo!,
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: NavegadorOculto(capturador: capturador),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
