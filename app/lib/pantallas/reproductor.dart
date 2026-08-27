import 'package:flutter/material.dart';

import '../main.dart';
import '../nucleo/formato.dart';
import '../nucleo/tema.dart';
import '../widgets/comunes.dart';

/// Reproductor de música a pantalla completa.
class PantallaReproductor extends StatelessWidget {
  const PantallaReproductor({super.key});

  @override
  Widget build(BuildContext context) {
    final audio = Servicios.de(context).audio;

    return Scaffold(
      backgroundColor: Tono.fondo,
      body: ListenableBuilder(
        listenable: audio,
        builder: (context, _) {
          final pista = audio.actual;
          if (pista == null) {
            return const Vacio(
              icono: Icons.music_off_rounded,
              titulo: 'No hay nada sonando',
              detalle: 'Elige una canción en tu biblioteca.',
            );
          }

          return SafeArea(
            child: Column(
              children: [
                _barraSuperior(context, audio.cola.length, audio.indice),
                const Spacer(flex: 2),
                Hero(
                  tag: 'caratula',
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Medidas.radioGrande),
                      boxShadow: [
                        BoxShadow(
                          color: Tono.acento.withValues(alpha: 0.16),
                          blurRadius: 46,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: Miniatura(
                      url: pista.miniatura,
                      ancho: MediaQuery.of(context).size.width * 0.72,
                      alto: MediaQuery.of(context).size.width * 0.72,
                      radio: Medidas.radioGrande,
                      icono: Icons.music_note_rounded,
                    ),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Column(
                    children: [
                      Text(
                        pista.titulo,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Tono.texto,
                          height: 1.3,
                          letterSpacing: -0.3,
                        ),
                      ),
                      if (pista.autor.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Text(
                          pista.autor,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14.5, color: Tono.texto3),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                _barraTiempo(context, audio),
                const SizedBox(height: 10),
                _controles(context, audio),
                const Spacer(flex: 2),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _barraSuperior(BuildContext context, int total, int indice) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
            color: Tono.texto2,
          ),
          const Spacer(),
          if (total > 1)
            Text(
              '${indice + 1} de $total',
              style: const TextStyle(color: Tono.texto3, fontSize: 12.5),
            ),
          const Spacer(),
          _botonModoMusica(context),
        ],
      ),
    );
  }

  /// Atajo para subir el volumen sin ir a los ajustes.
  Widget _botonModoMusica(BuildContext context) {
    final servicios = Servicios.de(context);
    final activo = servicios.ajustes.modoMusica;
    return IconButton(
      onPressed: () async {
        final nuevo = !activo;
        await servicios.ajustes.definirModoMusica(nuevo);
        await servicios.audio.definirModoMusica(
            nuevo, refuerzo: servicios.ajustes.refuerzoReproductor);
        if (context.mounted) {
          avisar(context, nuevo ? 'Modo musica encendido' : 'Volumen normal');
        }
      },
      icon: Icon(activo ? Icons.volume_up_rounded : Icons.volume_down_rounded),
      color: activo ? Tono.acento : Tono.texto3,
      tooltip: activo ? 'Modo musica encendido' : 'Que suene mas fuerte',
    );
  }

  Widget _barraTiempo(BuildContext context, audio) {
    return StreamBuilder<Duration>(
      stream: audio.posicion,
      builder: (context, snap) {
        final total = audio.motor.duration ?? Duration.zero;
        var actual = snap.data ?? Duration.zero;
        if (actual > total && total > Duration.zero) actual = total;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackShape: const RoundedRectSliderTrackShape(),
                ),
                child: Slider(
                  value: total.inMilliseconds == 0
                      ? 0
                      : actual.inMilliseconds.clamp(0, total.inMilliseconds).toDouble(),
                  max: total.inMilliseconds == 0 ? 1 : total.inMilliseconds.toDouble(),
                  onChanged: total.inMilliseconds == 0
                      ? null
                      : (v) => audio.irA(Duration(milliseconds: v.round())),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(formatoDuracion(actual),
                        style: const TextStyle(color: Tono.texto3, fontSize: 12)),
                    Text(formatoDuracion(total),
                        style: const TextStyle(color: Tono.texto3, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _controles(BuildContext context, audio) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: audio.anterior,
          icon: const Icon(Icons.skip_previous_rounded),
          iconSize: 40,
          color: Tono.texto2,
        ),
        const SizedBox(width: 18),
        GestureDetector(
          onTap: audio.alternar,
          child: Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              gradient: Tono.gradiente,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Tono.acento.withValues(alpha: 0.32),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              audio.sonando ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 38,
              color: const Color(0xFF04202A),
            ),
          ),
        ),
        const SizedBox(width: 18),
        IconButton(
          onPressed: audio.siguiente,
          icon: const Icon(Icons.skip_next_rounded),
          iconSize: 40,
          color: Tono.texto2,
        ),
      ],
    );
  }
}
