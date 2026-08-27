import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../nucleo/tema.dart';

/// Miniatura con esquinas redondeadas y un relleno bonito si no hay imagen.
class Miniatura extends StatelessWidget {
  const Miniatura({
    super.key,
    this.url = '',
    this.archivoLocal = '',
    this.ancho = 112,
    this.alto = 64,
    this.radio = Medidas.radioChico,
    this.icono = Icons.play_arrow_rounded,
  });

  final String url;
  final String archivoLocal;
  final double ancho;
  final double alto;
  final double radio;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radio),
      child: SizedBox(
        width: ancho,
        height: alto,
        child: _contenido(),
      ),
    );
  }

  Widget _contenido() {
    if (archivoLocal.isNotEmpty && File(archivoLocal).existsSync()) {
      return Image.file(File(archivoLocal), fit: BoxFit.cover, errorBuilder: (_, _, _) => _vacia());
    }
    if (url.isEmpty) return _vacia();
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (_, _) => Container(color: Tono.superficieAlta),
      errorWidget: (_, _, _) => _vacia(),
    );
  }

  Widget _vacia() {
    return Container(
      decoration: const BoxDecoration(gradient: Tono.gradienteSuave),
      child: Center(
        child: Icon(icono, color: Tono.texto3, size: alto * 0.36),
      ),
    );
  }
}

/// Pantalla o zona sin contenido, explicando qué hacer.
class Vacio extends StatelessWidget {
  const Vacio({
    super.key,
    required this.icono,
    required this.titulo,
    this.detalle = '',
    this.accion,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                gradient: Tono.gradienteSuave,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Icon(icono, size: 38, color: Tono.acento),
            ),
            const SizedBox(height: 20),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (detalle.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                detalle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (accion != null) ...[
              const SizedBox(height: 22),
              accion!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Etiqueta pequeña de una sola línea (sitio, calidad, duración...).
class Etiqueta extends StatelessWidget {
  const Etiqueta(this.texto, {super.key, this.color, this.icono});

  final String texto;
  final Color? color;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Tono.texto3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 11.5, color: c),
            const SizedBox(width: 4),
          ],
          Text(
            texto,
            style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Botón grande con el degradado de la marca.
class BotonPrincipal extends StatelessWidget {
  const BotonPrincipal({
    super.key,
    required this.texto,
    required this.alPulsar,
    this.icono,
    this.cargando = false,
    this.ancho,
  });

  final String texto;
  final VoidCallback? alPulsar;
  final IconData? icono;
  final bool cargando;
  final double? ancho;

  @override
  Widget build(BuildContext context) {
    final activo = alPulsar != null && !cargando;
    return Opacity(
      opacity: activo ? 1 : 0.55,
      child: Container(
        width: ancho,
        decoration: BoxDecoration(
          gradient: Tono.gradiente,
          borderRadius: BorderRadius.circular(Medidas.radio),
          boxShadow: activo
              ? [
                  BoxShadow(
                    color: Tono.acento.withValues(alpha: 0.22),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(Medidas.radio),
            onTap: activo ? alPulsar : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
              child: Row(
                mainAxisSize: ancho == null ? MainAxisSize.min : MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (cargando)
                    const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Color(0xFF04202A)),
                    )
                  else if (icono != null)
                    Icon(icono, size: 19, color: const Color(0xFF04202A)),
                  if (cargando || icono != null) const SizedBox(width: 9),
                  Text(
                    texto,
                    style: const TextStyle(
                      color: Color(0xFF04202A),
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Aviso en línea, para explicar un problema sin robar la pantalla.
class Aviso extends StatelessWidget {
  const Aviso({
    super.key,
    required this.texto,
    this.icono = Icons.info_outline_rounded,
    this.color = Tono.aviso,
    this.accion,
  });

  final String texto;
  final IconData icono;
  final Color color;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        border: Border.all(color: color.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(Medidas.radio),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: color, size: 19),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(texto, style: const TextStyle(color: Tono.texto2, fontSize: 13, height: 1.4)),
                if (accion != null) ...[const SizedBox(height: 8), accion!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Barra de progreso fina con esquinas redondeadas.
class BarraProgreso extends StatelessWidget {
  const BarraProgreso({
    super.key,
    required this.valor,
    this.color = Tono.acento,
    this.alto = 6,
    this.indeterminada = false,
  });

  final double valor; // 0..1
  final Color color;
  final double alto;
  final bool indeterminada;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(alto),
      child: LinearProgressIndicator(
        value: indeterminada ? null : valor.clamp(0.0, 1.0),
        minHeight: alto,
        backgroundColor: Tono.superficieMax,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}

/// Muestra un mensaje breve abajo, con estilo propio.
void avisar(BuildContext context, String mensaje, {bool esError = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Row(
      children: [
        Icon(
          esError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
          color: esError ? Tono.error : Tono.exito,
          size: 19,
        ),
        const SizedBox(width: 11),
        Expanded(child: Text(mensaje)),
      ],
    ),
    duration: Duration(seconds: esError ? 5 : 3),
  ));
}
