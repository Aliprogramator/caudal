import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../nucleo/formato.dart';
import '../nucleo/modelos.dart';
import '../nucleo/servidor.dart';
import '../nucleo/tema.dart';
import '../widgets/comunes.dart';
import 'inicio.dart';

/// Traer una lista de reproducción de Spotify, Apple Music o YouTube Music
/// y descargar sus canciones en MP3.
class VistaListas extends StatefulWidget {
  const VistaListas({super.key});

  @override
  State<VistaListas> createState() => _VistaListasState();
}

class _VistaListasState extends State<VistaListas> {
  final _campo = TextEditingController();
  ListaImportada? _lista;
  Set<int> _elegidas = {};
  bool _leyendo = false;
  String _error = '';

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  Future<void> _leer() async {
    final url = _campo.text.trim();
    if (url.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _leyendo = true;
      _error = '';
      _lista = null;
    });

    try {
      final lista = await Servicios.de(context).servidor.leerLista(url);
      if (!mounted) return;
      setState(() {
        _lista = lista;
        _elegidas = {for (var i = 0; i < lista.canciones.length; i++) i};
        _leyendo = false;
      });
    } on ErrorCaudal catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.mensaje;
        _leyendo = false;
      });
    }
  }

  Future<void> _pegar() async {
    final datos = await Clipboard.getData(Clipboard.kTextPlain);
    final texto = datos?.text?.trim() ?? '';
    if (texto.isEmpty) {
      if (mounted) avisar(context, 'No hay nada copiado', esError: true);
      return;
    }
    _campo.text = texto;
    _leer();
  }

  void _descargar() {
    final lista = _lista;
    if (lista == null || _elegidas.isEmpty) return;

    final servicios = Servicios.de(context);
    for (final i in _elegidas.toList()..sort()) {
      final c = lista.canciones[i];
      servicios.descargas.encolar(
        url: c.url,
        busqueda: c.url.isEmpty ? c.busqueda : '',
        tipo: TipoMedio.audio,
        formatoAudio: servicios.ajustes.formatoAudio,
        titulo: c.titulo,
        autor: c.artista,
        miniatura: c.miniatura,
      );
    }

    avisar(context, '${_elegidas.length} canciones en la cola');
    Navigator.of(context).pop();
    irADescargas(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Traer una lista')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Medidas.margen, 8, Medidas.margen, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pega el enlace de una lista y se descargan sus canciones.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _campo,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _leer(),
                  decoration: InputDecoration(
                    hintText: 'Enlace de Spotify, Apple Music o YouTube Music',
                    prefixIcon: const Icon(Icons.queue_music_rounded, color: Tono.texto3),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: _pegar,
                          icon: const Icon(Icons.content_paste_rounded, size: 20),
                          color: Tono.texto3,
                          tooltip: 'Pegar',
                        ),
                        IconButton(
                          onPressed: _leer,
                          icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                          color: Tono.acento,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 7,
                  children: const [
                    Etiqueta('Spotify', color: Color(0xFF1DB954)),
                    Etiqueta('Apple Music', color: Color(0xFFFA243C)),
                    Etiqueta('YouTube Music', color: Color(0xFFFF0033)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(child: _cuerpo()),
        ],
      ),
      bottomNavigationBar: (_lista != null && _elegidas.isNotEmpty)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(Medidas.margen),
                child: BotonPrincipal(
                  texto: 'Descargar ${_elegidas.length} '
                      '${_elegidas.length == 1 ? 'canción' : 'canciones'}',
                  icono: Icons.download_rounded,
                  ancho: double.infinity,
                  alPulsar: _descargar,
                ),
              ),
            )
          : null,
    );
  }

  Widget _cuerpo() {
    if (_leyendo) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(Medidas.margen),
        child: Aviso(texto: _error, icono: Icons.error_outline_rounded, color: Tono.error),
      );
    }

    final lista = _lista;
    if (lista == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(Medidas.margen, 10, Medidas.margen, 24),
        children: [
          const Vacio(
            icono: Icons.playlist_add_rounded,
            titulo: 'Trae tus listas',
            detalle: 'Copia el enlace de una lista o un álbum y pégalo arriba.',
          ),
          const SizedBox(height: 10),
          const Aviso(
            texto: 'Se leen los títulos de la lista y cada canción se busca y se '
                'descarga en MP3. Las listas tienen que ser públicas.',
            icono: Icons.lightbulb_outline_rounded,
            color: Tono.acento,
          ),
          const SizedBox(height: 12),
          Aviso(
            texto: 'Lo que ya tienes descargado dentro de Spotify, Apple Music o '
                'YouTube Premium no se puede convertir: esos archivos van cifrados y '
                'solo funcionan dentro de su propia app.',
            icono: Icons.lock_outline_rounded,
            color: Tono.texto3,
            accion: Text(
              'Por eso Caudal parte de la lista, no del archivo.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        _cabeceraLista(lista),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 12),
            itemCount: lista.canciones.length,
            itemBuilder: (context, i) {
              final c = lista.canciones[i];
              final marcada = _elegidas.contains(i);
              return CheckboxListTile(
                value: marcada,
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _elegidas.add(i);
                  } else {
                    _elegidas.remove(i);
                  }
                }),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  c.titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  [
                    if (c.artista.isNotEmpty) c.artista,
                    if (c.duracion > 0) formatoSegundos(c.duracion),
                  ].join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _cabeceraLista(ListaImportada lista) {
    final todas = _elegidas.length == lista.canciones.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Medidas.margen, 4, Medidas.margen, 10),
      child: Row(
        children: [
          Miniatura(
            url: lista.portada,
            ancho: 58,
            alto: 58,
            radio: 12,
            icono: Icons.queue_music_rounded,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lista.titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '${lista.plataforma}  ·  ${lista.total} canciones',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              _elegidas = todas
                  ? {}
                  : {for (var i = 0; i < lista.canciones.length; i++) i};
            }),
            child: Text(todas ? 'Ninguna' : 'Todas'),
          ),
        ],
      ),
    );
  }
}
