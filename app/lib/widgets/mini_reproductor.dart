import 'package:flutter/material.dart';

import '../main.dart';
import '../nucleo/tema.dart';
import '../pantallas/reproductor.dart';
import 'comunes.dart';

/// Barra fina sobre la navegación que muestra lo que está sonando.
class MiniReproductor extends StatelessWidget {
  const MiniReproductor({super.key});

  @override
  Widget build(BuildContext context) {
    final audio = Servicios.de(context).audio;

    return ListenableBuilder(
      listenable: audio,
      builder: (context, _) {
        final pista = audio.actual;

        return AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: pista == null
              ? const SizedBox(width: double.infinity)
              : Material(
                  color: Tono.superficieAlta,
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PantallaReproductor()),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StreamBuilder<Duration>(
                          stream: audio.posicion,
                          builder: (context, snap) {
                            final total = audio.motor.duration ?? Duration.zero;
                            final actual = snap.data ?? Duration.zero;
                            final valor = total.inMilliseconds > 0
                                ? actual.inMilliseconds / total.inMilliseconds
                                : 0.0;
                            return BarraProgreso(valor: valor, alto: 2.5);
                          },
                        ),
                        SizedBox(
                          height: Medidas.miniReproductor - 2.5,
                          child: Row(
                            children: [
                              const SizedBox(width: 10),
                              Hero(
                                tag: 'caratula',
                                child: Miniatura(
                                  url: pista.miniatura,
                                  ancho: 46,
                                  alto: 46,
                                  radio: 10,
                                  icono: Icons.music_note_rounded,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      pista.titulo,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: Tono.texto,
                                      ),
                                    ),
                                    if (pista.autor.isNotEmpty)
                                      Text(
                                        pista.autor,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 11.5, color: Tono.texto3),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: audio.anterior,
                                icon: const Icon(Icons.skip_previous_rounded),
                                color: Tono.texto2,
                                iconSize: 26,
                              ),
                              IconButton(
                                onPressed: audio.alternar,
                                icon: Icon(
                                  audio.sonando
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                                color: Tono.acento,
                                iconSize: 32,
                              ),
                              IconButton(
                                onPressed: audio.siguiente,
                                icon: const Icon(Icons.skip_next_rounded),
                                color: Tono.texto2,
                                iconSize: 26,
                              ),
                              const SizedBox(width: 4),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }
}
