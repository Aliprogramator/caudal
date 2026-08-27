import 'package:flutter/material.dart';

import '../nucleo/modelos.dart';
import '../nucleo/tema.dart';
import 'comunes.dart';

/// Barra que aparece sola cuando el navegador está en un video, con los dos
/// botones de descarga directa.
class BarraRapida extends StatelessWidget {
  const BarraRapida({
    super.key,
    required this.visible,
    required this.resolviendo,
    required this.ficha,
    required this.tituloPagina,
    required this.priorizarAudio,
    required this.alDescargarVideo,
    required this.alDescargarAudio,
    required this.alAbrirOpciones,
    required this.alCerrar,
  });

  /// Se muestra cuando la página parece un video descargable.
  final bool visible;

  /// El servidor todavía está mirando de qué se trata.
  final bool resolviendo;

  /// Datos confirmados por el servidor (título, miniatura, calidades).
  final Ficha? ficha;

  /// Título que dio la propia página, mientras no haya ficha.
  final String tituloPagina;

  /// En sitios de música el botón de audio va primero.
  final bool priorizarAudio;

  final VoidCallback alDescargarVideo;
  final VoidCallback alDescargarAudio;
  final VoidCallback alAbrirOpciones;
  final VoidCallback alCerrar;

  /// Texto de la mejor calidad encontrada, para que se vea qué se va a bajar.
  String get _mejorCalidad {
    final calidades = ficha?.calidades ?? const <Calidad>[];
    if (calidades.isEmpty) return '';
    final alto = calidades.first.altura;
    if (alto >= 4320) return '8K';
    if (alto >= 2160) return '4K';
    if (alto >= 1440) return '2K';
    return '${alto}p';
  }

  bool get _soloAudioDisponible =>
      ficha != null && !ficha!.tieneVideo && ficha!.tieneAudio;

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, 1.4),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: visible ? _contenido(context) : const SizedBox.shrink(),
      ),
    );
  }

  Widget _contenido(BuildContext context) {
    final titulo = ficha?.titulo.isNotEmpty == true
        ? ficha!.titulo
        : (tituloPagina.isEmpty ? 'Buscando el video...' : tituloPagina);

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      decoration: BoxDecoration(
        color: Tono.superficieAlta,
        borderRadius: BorderRadius.circular(Medidas.radioGrande),
        border: Border.all(color: Tono.acento.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 6, 8),
            child: Row(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Miniatura(
                      url: ficha?.miniatura ?? '',
                      ancho: 62,
                      alto: 38,
                      radio: 9,
                      icono: Icons.movie_outlined,
                    ),
                    if (resolviendo)
                      const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      ),
                  ],
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: Tono.texto,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (_mejorCalidad.isNotEmpty) ...[
                            Etiqueta('hasta $_mejorCalidad', color: Tono.acento),
                            const SizedBox(width: 6),
                          ],
                          if (ficha?.duracionTexto.isNotEmpty == true)
                            Text(
                              ficha!.duracionTexto,
                              style: const TextStyle(fontSize: 11, color: Tono.texto3),
                            )
                          else if (resolviendo)
                            const Text(
                              'preparando opciones',
                              style: TextStyle(fontSize: 11, color: Tono.texto3),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: alCerrar,
                  icon: const Icon(Icons.close_rounded, size: 17),
                  color: Tono.texto3,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Ocultar',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 11),
            child: Row(
              children: [
                if (priorizarAudio || _soloAudioDisponible) ...[
                  Expanded(child: _botonAudio(destacado: true)),
                  if (!_soloAudioDisponible) ...[
                    const SizedBox(width: 8),
                    Expanded(child: _botonVideo(destacado: false)),
                  ],
                ] else ...[
                  Expanded(child: _botonVideo(destacado: true)),
                  const SizedBox(width: 8),
                  Expanded(child: _botonAudio(destacado: false)),
                ],
                const SizedBox(width: 6),
                _botonOpciones(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _botonVideo({required bool destacado}) => _Boton(
        icono: Icons.download_rounded,
        texto: 'Video',
        detalle: _mejorCalidad.isEmpty ? 'mejor calidad' : _mejorCalidad,
        destacado: destacado,
        alPulsar: alDescargarVideo,
      );

  Widget _botonAudio({required bool destacado}) => _Boton(
        icono: Icons.music_note_rounded,
        texto: 'Audio',
        detalle: 'MP3',
        destacado: destacado,
        alPulsar: alDescargarAudio,
      );

  Widget _botonOpciones() {
    return Material(
      color: Tono.superficieMax,
      borderRadius: BorderRadius.circular(Medidas.radio),
      child: InkWell(
        borderRadius: BorderRadius.circular(Medidas.radio),
        onTap: alAbrirOpciones,
        child: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Medidas.radio),
            border: Border.all(color: Tono.borde),
          ),
          child: const Icon(Icons.tune_rounded, size: 19, color: Tono.texto2),
        ),
      ),
    );
  }
}

class _Boton extends StatelessWidget {
  const _Boton({
    required this.icono,
    required this.texto,
    required this.detalle,
    required this.destacado,
    required this.alPulsar,
  });

  final IconData icono;
  final String texto;
  final String detalle;
  final bool destacado;
  final VoidCallback alPulsar;

  @override
  Widget build(BuildContext context) {
    final fondo = destacado ? null : Tono.superficieMax;
    return Container(
      height: 46,
      decoration: BoxDecoration(
        gradient: destacado ? Tono.gradiente : null,
        color: fondo,
        borderRadius: BorderRadius.circular(Medidas.radio),
        border: destacado ? null : Border.all(color: Tono.borde),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(Medidas.radio),
          onTap: alPulsar,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icono,
                size: 18,
                color: destacado ? const Color(0xFF04202A) : Tono.texto2,
              ),
              const SizedBox(width: 7),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    texto,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      color: destacado ? const Color(0xFF04202A) : Tono.texto,
                    ),
                  ),
                  Text(
                    detalle,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.2,
                      color: destacado
                          ? const Color(0xFF04202A).withValues(alpha: 0.72)
                          : Tono.texto3,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
