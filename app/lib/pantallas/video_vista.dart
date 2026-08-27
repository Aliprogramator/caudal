import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../nucleo/formato.dart';
import '../nucleo/modelos.dart';
import '../nucleo/tema.dart';
import '../widgets/comunes.dart';

/// Reproductor de los videos descargados.
class PantallaVideo extends StatefulWidget {
  const PantallaVideo({super.key, required this.pista});

  final Pista pista;

  @override
  State<PantallaVideo> createState() => _PantallaVideoState();
}

class _PantallaVideoState extends State<PantallaVideo> {
  VideoPlayerController? _control;
  bool _listo = false;
  String _error = '';
  bool _controlesVisibles = true;

  @override
  void initState() {
    super.initState();
    _preparar();
  }

  Future<void> _preparar() async {
    final archivo = File(widget.pista.archivo);
    if (!await archivo.exists()) {
      setState(() => _error = 'El archivo ya no está en el teléfono.');
      return;
    }
    try {
      final c = VideoPlayerController.file(archivo);
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      c.addListener(_alCambiar);
      setState(() {
        _control = c;
        _listo = true;
      });
      await c.play();
      // en horizontal se aprovecha mucho mejor la pantalla
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Este video no se puede reproducir aquí. '
            'Prueba a abrirlo con otra app desde la biblioteca.');
      }
    }
  }

  void _alCambiar() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _control?.removeListener(_alCambiar);
    _control?.dispose();
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(child: _contenido()),
            if (_controlesVisibles) _capaControles(),
          ],
        ),
      ),
    );
  }

  Widget _contenido() {
    if (_error.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Vacio(
          icono: Icons.error_outline_rounded,
          titulo: 'No se pudo abrir',
          detalle: _error,
          accion: OutlinedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Volver'),
          ),
        ),
      );
    }
    if (!_listo || _control == null) {
      return const CircularProgressIndicator();
    }
    return GestureDetector(
      onTap: () => setState(() => _controlesVisibles = !_controlesVisibles),
      child: AspectRatio(
        aspectRatio: _control!.value.aspectRatio,
        child: VideoPlayer(_control!),
      ),
    );
  }

  Widget _capaControles() {
    final c = _control;
    return Positioned.fill(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha: 0.75), Colors.transparent],
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                ),
                Expanded(
                  child: Text(
                    widget.pista.titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          if (c != null && _listo)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 20, 14, 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                ),
              ),
              child: Column(
                children: [
                  VideoProgressIndicator(
                    c,
                    allowScrubbing: true,
                    colors: const VideoProgressColors(
                      playedColor: Tono.acento,
                      bufferedColor: Colors.white24,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        formatoDuracion(c.value.position),
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => c.seekTo(
                            c.value.position - const Duration(seconds: 10)),
                        icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
                      ),
                      IconButton(
                        onPressed: () =>
                            c.value.isPlaying ? c.pause() : c.play(),
                        icon: Icon(
                          c.value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                      IconButton(
                        onPressed: () => c.seekTo(
                            c.value.position + const Duration(seconds: 10)),
                        icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
                      ),
                      const Spacer(),
                      Text(
                        formatoDuracion(c.value.duration),
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
