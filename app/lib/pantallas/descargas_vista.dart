import 'package:flutter/material.dart';

import '../main.dart';
import '../nucleo/descargas.dart';
import '../nucleo/formato.dart';
import '../nucleo/modelos.dart';
import '../nucleo/tema.dart';
import '../widgets/comunes.dart';

/// Cola de descargas: qué se está bajando y en qué punto va.
class VistaDescargas extends StatelessWidget {
  const VistaDescargas({super.key});

  @override
  Widget build(BuildContext context) {
    final gestor = Servicios.de(context).descargas;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: gestor,
          builder: (context, _) {
            final lista = gestor.lista;
            return Column(
              children: [
                _cabecera(context, gestor),
                Expanded(
                  child: lista.isEmpty
                      ? const Vacio(
                          icono: Icons.download_rounded,
                          titulo: 'Aquí verás tus descargas',
                          detalle:
                              'Busca una canción o navega hasta un video y pulsa Descargar.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                              Medidas.margen, 4, Medidas.margen, 20),
                          itemCount: lista.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, i) =>
                              _TarjetaDescarga(descarga: lista[i], gestor: gestor),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _cabecera(BuildContext context, GestorDescargas gestor) {
    final activas = gestor.activas.length;
    final terminadas = gestor.lista.where((d) => d.terminada).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Medidas.margen, 12, Medidas.margen, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Descargas', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 3),
                Text(
                  activas > 0
                      ? '$activas en marcha'
                      : (gestor.lista.isEmpty ? 'Nada en la cola' : 'Todo al día'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (activas > 0)
            IconButton(
              onPressed: gestor.pausarTodo,
              icon: const Icon(Icons.pause_rounded),
              color: Tono.texto2,
              tooltip: 'Pausar todo',
            ),
          if (terminadas > 0)
            IconButton(
              onPressed: gestor.limpiarTerminadas,
              icon: const Icon(Icons.cleaning_services_rounded, size: 20),
              color: Tono.texto3,
              tooltip: 'Limpiar terminadas',
            ),
        ],
      ),
    );
  }
}

class _TarjetaDescarga extends StatelessWidget {
  const _TarjetaDescarga({required this.descarga, required this.gestor});

  final Descarga descarga;
  final GestorDescargas gestor;

  Color get _color => switch (descarga.estado) {
        EstadoDescarga.completada => Tono.exito,
        EstadoDescarga.error => Tono.error,
        EstadoDescarga.pausada => Tono.aviso,
        EstadoDescarga.cancelada => Tono.texto3,
        EstadoDescarga.preparando => Tono.acento2,
        _ => Tono.acento,
      };

  @override
  Widget build(BuildContext context) {
    final d = descarga;

    return Dismissible(
      key: ValueKey(d.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Tono.error.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(Medidas.radio),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Tono.error),
      ),
      onDismissed: (_) => gestor.quitar(d.id),
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: Tono.superficie,
          borderRadius: BorderRadius.circular(Medidas.radio),
          border: Border.all(color: Tono.borde),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Miniatura(
                  url: d.miniatura,
                  ancho: 92,
                  alto: 54,
                  icono: d.esAudio ? Icons.music_note_rounded : Icons.movie_outlined,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.titulo,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.3),
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 6,
                        runSpacing: 5,
                        children: [
                          Etiqueta(
                            d.tipo == TipoMedio.audio
                                ? d.formatoAudio.toUpperCase()
                                : (d.calidad == 'mejor' ? 'Mejor calidad' : '${d.calidad}p'),
                            color: Tono.acento,
                            icono: d.esAudio
                                ? Icons.music_note_rounded
                                : Icons.hd_rounded,
                          ),
                          Etiqueta(sitioDe(d.url)),
                        ],
                      ),
                    ],
                  ),
                ),
                _botones(context),
              ],
            ),
            const SizedBox(height: 10),
            if (d.estado != EstadoDescarga.completada || d.progreso < 100)
              BarraProgreso(
                valor: d.progreso / 100,
                color: _color,
                indeterminada:
                    d.estado == EstadoDescarga.preparando && d.progreso <= 0,
              ),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(child: _lineaEstado(context)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineaEstado(BuildContext context) {
    final d = descarga;

    if (d.estado == EstadoDescarga.error) {
      return Text(
        d.error,
        style: const TextStyle(color: Tono.error, fontSize: 11.5, height: 1.35),
      );
    }

    final trozos = <String>[];
    switch (d.estado) {
      case EstadoDescarga.completada:
        trozos.add('Guardado');
        if (d.bytesTotales > 0) trozos.add(formatoBytes(d.bytesTotales));
      case EstadoDescarga.descargando:
        trozos.add('${d.progreso.toStringAsFixed(0)} %');
        if (d.bytesTotales > 0) {
          trozos.add('${formatoBytes(d.bytesRecibidos)} de ${formatoBytes(d.bytesTotales)}');
        }
        if (d.velocidad > 0) trozos.add(formatoVelocidad(d.velocidad));
        if (d.segundosRestantes > 0) trozos.add(formatoRestante(d.segundosRestantes));
      case EstadoDescarga.preparando:
        trozos.add(d.detalle);
        if (d.progreso > 0) trozos.add('${d.progreso.toStringAsFixed(0)} %');
      default:
        trozos.add(d.detalle);
    }

    return Text(
      trozos.join('  ·  '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: d.estado == EstadoDescarga.completada ? Tono.exito : Tono.texto3,
        fontSize: 11.5,
        fontWeight: d.estado == EstadoDescarga.completada ? FontWeight.w600 : FontWeight.w400,
      ),
    );
  }

  Widget _botones(BuildContext context) {
    final d = descarga;

    if (d.estado == EstadoDescarga.completada) {
      return IconButton(
        onPressed: () {
          irADescargasBiblioteca(context);
        },
        icon: const Icon(Icons.check_circle_rounded, color: Tono.exito, size: 22),
        tooltip: 'Está en tu biblioteca',
      );
    }

    if (d.estado.activa) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => gestor.pausar(d.id),
            icon: const Icon(Icons.pause_rounded, size: 21),
            color: Tono.texto2,
            tooltip: 'Pausar',
          ),
          IconButton(
            onPressed: () => gestor.cancelar(d.id),
            icon: const Icon(Icons.close_rounded, size: 20),
            color: Tono.texto3,
            tooltip: 'Cancelar',
          ),
        ],
      );
    }

    return IconButton(
      onPressed: () => gestor.reanudar(d.id),
      icon: Icon(
        d.estado == EstadoDescarga.pausada
            ? Icons.play_arrow_rounded
            : Icons.refresh_rounded,
        size: 22,
      ),
      color: Tono.acento,
      tooltip: d.estado == EstadoDescarga.pausada ? 'Continuar' : 'Reintentar',
    );
  }
}

/// Deja al usuario en la biblioteca, donde ya está el archivo.
void irADescargasBiblioteca(BuildContext context) {
  avisar(context, 'Lo tienes en la pestaña Biblioteca');
}
