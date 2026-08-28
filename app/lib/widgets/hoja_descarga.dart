import 'package:flutter/material.dart';

import '../nucleo/ajustes.dart';
import '../nucleo/descargas.dart';
import '../nucleo/formato.dart';
import '../nucleo/modelos.dart';
import '../nucleo/tema.dart';
import 'comunes.dart';

/// Lo que el usuario eligió en la hoja de descarga.
class EleccionDescarga {
  const EleccionDescarga({
    required this.tipo,
    required this.calidad,
    required this.formatoAudio,
    required this.ficha,
  });

  final TipoMedio tipo;
  final String calidad;
  final String formatoAudio;
  final Ficha ficha;
}

/// Hoja inferior para elegir qué descargar de un enlace.
///
/// Mira de qué va el enlace mientras se muestra, así el usuario ve enseguida
/// de qué video se trata y qué calidades hay de verdad.
Future<EleccionDescarga?> mostrarHojaDescarga(
  BuildContext context, {
  required String url,
  required Ajustes ajustes,
  required GestorDescargas descargas,
  Ficha? fichaConocida,
}) {
  return showModalBottomSheet<EleccionDescarga>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Tono.superficie,
    builder: (_) => _HojaDescarga(
      url: url,
      ajustes: ajustes,
      descargas: descargas,
      fichaConocida: fichaConocida,
    ),
  );
}

class _HojaDescarga extends StatefulWidget {
  const _HojaDescarga({
    required this.url,
    required this.ajustes,
    required this.descargas,
    this.fichaConocida,
  });

  final String url;
  final Ajustes ajustes;
  final GestorDescargas descargas;
  final Ficha? fichaConocida;

  @override
  State<_HojaDescarga> createState() => _HojaDescargaState();
}

class _HojaDescargaState extends State<_HojaDescarga> {
  Ficha? _ficha;
  String _error = '';
  bool _cargando = true;

  late TipoMedio _tipo = widget.ajustes.tipoPorDefecto;
  late String _calidad = widget.ajustes.calidad;
  late String _formatoAudio = widget.ajustes.formatoAudio;

  @override
  void initState() {
    super.initState();
    _resolver();
  }

  Future<void> _resolver() async {
    if (widget.fichaConocida != null && widget.fichaConocida!.calidades.isNotEmpty) {
      setState(() {
        _ficha = widget.fichaConocida;
        _cargando = false;
      });
      return;
    }
    try {
      final ficha = await widget.descargas.resolverSiPuede(widget.url);
      if (!mounted) return;
      setState(() {
        _ficha = ficha;
        _cargando = false;
        // si el enlace no trae imagen, solo tiene sentido bajar el audio
        if (ficha != null && !ficha.tieneVideo && ficha.tieneAudio) {
          _tipo = TipoMedio.audio;
        }
      });
    } on ErrorCaudal catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.mensaje;
        _cargando = false;
      });
    }
  }

  bool get _soloAudio => _tipo == TipoMedio.audio;

  @override
  Widget build(BuildContext context) {
    final abajo = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: abajo),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.86,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                Medidas.margen, 4, Medidas.margen, Medidas.margen),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cabecera(),
                const SizedBox(height: 20),
                if (_error.isNotEmpty)
                  Aviso(texto: _error, icono: Icons.error_outline_rounded, color: Tono.error)
                else ...[
                  _seccion('¿Qué quieres bajar?'),
                  const SizedBox(height: 10),
                  _selectorTipo(),
                  const SizedBox(height: 20),
                  if (_soloAudio) ...[
                    _seccion('Formato del audio'),
                    const SizedBox(height: 10),
                    _selectorAudio(),
                  ] else ...[
                    _seccion('Calidad'),
                    const SizedBox(height: 10),
                    _selectorCalidad(),
                  ],
                  const SizedBox(height: 24),
                  BotonPrincipal(
                    texto: 'Descargar',
                    icono: Icons.download_rounded,
                    ancho: double.infinity,
                    cargando: _cargando,
                    alPulsar: _cargando ? null : _confirmar,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cabecera() {
    final f = _ficha;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Miniatura(
          url: f?.miniatura ?? '',
          ancho: 116,
          alto: 66,
          icono: Icons.movie_outlined,
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_cargando && f == null) ...[
                Container(height: 15, width: double.infinity, decoration: _hueso()),
                const SizedBox(height: 7),
                Container(height: 13, width: 130, decoration: _hueso()),
              ] else ...[
                Text(
                  f?.titulo.isNotEmpty == true ? f!.titulo : widget.url,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 5),
                Text(
                  f?.autor.isNotEmpty == true ? f!.autor : sitioDe(widget.url),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 7),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Etiqueta(sitioDe(widget.url), color: Tono.acento),
                  if (f != null && f.duracionTexto.isNotEmpty)
                    Etiqueta(f.duracionTexto, icono: Icons.schedule_rounded),
                  if (f?.esDirecto == true)
                    const Etiqueta('En directo', color: Tono.error),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  BoxDecoration _hueso() => BoxDecoration(
        color: Tono.superficieAlta,
        borderRadius: BorderRadius.circular(6),
      );

  Widget _seccion(String texto) => Text(
        texto,
        style: const TextStyle(
          color: Tono.texto2,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      );

  Widget _selectorTipo() {
    final f = _ficha;
    final opciones = <TipoMedio>[
      if (f == null || f.tieneVideo) TipoMedio.completo,
      if (f == null || f.tieneVideo) TipoMedio.video,
      if (f == null || f.tieneAudio) TipoMedio.audio,
    ];

    return Column(
      children: [
        for (final t in opciones) ...[
          _FilaOpcion(
            elegida: _tipo == t,
            icono: switch (t) {
              TipoMedio.completo => Icons.movie_rounded,
              TipoMedio.video => Icons.videocam_off_rounded,
              TipoMedio.audio => Icons.music_note_rounded,
            },
            titulo: t.titulo,
            detalle: t.detalle,
            alPulsar: () => setState(() => _tipo = t),
          ),
          if (t != opciones.last) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _selectorCalidad() {
    final calidades = _ficha?.calidades ?? const <Calidad>[];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip('La mejor', 'mejor'),
        for (final c in calidades) _chip(c.etiqueta, c.valor),
      ],
    );
  }

  Widget _selectorAudio() {
    const formatos = [
      ('MP3', 'mp3', 'Compatible con todo'),
      ('M4A', 'm4a', 'Mejor calidad, mismo tamaño'),
      ('FLAC', 'flac', 'Sin pérdida, ocupa más'),
      ('WAV', 'wav', 'Sin comprimir'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (etiqueta, valor, _) in formatos)
          _chipAudio(etiqueta, valor),
      ],
    );
  }

  Widget _chip(String etiqueta, String valor) {
    final activo = _calidad == valor;
    return _Pastilla(
      texto: etiqueta,
      activo: activo,
      alPulsar: () => setState(() => _calidad = valor),
    );
  }

  Widget _chipAudio(String etiqueta, String valor) {
    final activo = _formatoAudio == valor;
    return _Pastilla(
      texto: etiqueta,
      activo: activo,
      alPulsar: () => setState(() => _formatoAudio = valor),
    );
  }

  void _confirmar() {
    // lo elegido se convierte en la preferencia para la próxima vez
    widget.ajustes.definirTipo(_tipo);
    widget.ajustes.definirCalidad(_calidad);
    widget.ajustes.definirFormatoAudio(_formatoAudio);

    Navigator.of(context).pop(EleccionDescarga(
      tipo: _tipo,
      calidad: _calidad,
      formatoAudio: _formatoAudio,
      ficha: _ficha ??
          Ficha(url: widget.url, titulo: sitioDe(widget.url)),
    ));
  }
}

class _FilaOpcion extends StatelessWidget {
  const _FilaOpcion({
    required this.elegida,
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.alPulsar,
  });

  final bool elegida;
  final IconData icono;
  final String titulo;
  final String detalle;
  final VoidCallback alPulsar;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: elegida ? Tono.acento.withValues(alpha: 0.10) : Tono.superficieAlta,
      borderRadius: BorderRadius.circular(Medidas.radio),
      child: InkWell(
        borderRadius: BorderRadius.circular(Medidas.radio),
        onTap: alPulsar,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Medidas.radio),
            border: Border.all(
              color: elegida ? Tono.acento : Tono.borde,
              width: elegida ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icono, size: 21, color: elegida ? Tono.acento : Tono.texto3),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: elegida ? Tono.texto : Tono.texto2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(detalle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              AnimatedScale(
                scale: elegida ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: const Icon(Icons.check_circle_rounded, color: Tono.acento, size: 21),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pastilla extends StatelessWidget {
  const _Pastilla({required this.texto, required this.activo, required this.alPulsar});

  final String texto;
  final bool activo;
  final VoidCallback alPulsar;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: activo ? Tono.acento.withValues(alpha: 0.14) : Tono.superficieAlta,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: alPulsar,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: activo ? Tono.acento : Tono.borde, width: activo ? 1.5 : 1),
          ),
          child: Text(
            texto,
            style: TextStyle(
              fontSize: 13,
              fontWeight: activo ? FontWeight.w700 : FontWeight.w500,
              color: activo ? Tono.acento : Tono.texto2,
            ),
          ),
        ),
      ),
    );
  }
}
