import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../main.dart';
import '../nucleo/descargas.dart';
import '../nucleo/formato.dart';
import '../nucleo/modelos.dart';
import '../nucleo/tema.dart';
import '../widgets/comunes.dart';
import 'reproductor.dart';
import 'video_vista.dart';

/// Lo que ya está guardado en el teléfono: música y videos.
class VistaBiblioteca extends StatefulWidget {
  const VistaBiblioteca({super.key});

  @override
  State<VistaBiblioteca> createState() => _VistaBibliotecaState();
}

class _VistaBibliotecaState extends State<VistaBiblioteca>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _buscar = TextEditingController();

  GestorDescargas? _gestor;
  List<Pista> _musica = [];
  List<Pista> _videos = [];
  bool _cargando = true;
  String _filtro = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _cargar();
      _gestor = Servicios.de(context).descargas;
      _gestor!.addListener(_alCambiarDescargas);
    });
  }

  @override
  void dispose() {
    // sin quitarlo, el gestor seguiría llamando a una pantalla ya destruida
    _gestor?.removeListener(_alCambiarDescargas);
    _tabs.dispose();
    _buscar.dispose();
    super.dispose();
  }

  void _alCambiarDescargas() {
    // cuando una descarga acaba, la biblioteca debe reflejarlo
    if (mounted) _cargar();
  }

  Future<void> _cargar() async {
    final almacen = Servicios.de(context).almacen;
    final musica = await almacen.listar(soloAudio: true, filtro: _filtro);
    final videos = await almacen.listar(soloAudio: false, filtro: _filtro);
    if (!mounted) return;
    setState(() {
      _musica = musica;
      _videos = videos;
      _cargando = false;
    });
  }

  Future<void> _borrar(Pista pista) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar del teléfono'),
        content: Text('Se eliminará "${pista.titulo}" y no se podrá recuperar.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Tono.error),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    final servicios = Servicios.de(context);
    await servicios.audio.olvidar(pista.id);
    await servicios.almacen.borrar(pista.id);
    await _cargar();
    if (mounted) avisar(context, 'Borrado');
  }

  Future<void> _abrirFuera(Pista pista) async {
    final resultado = await OpenFilex.open(pista.archivo);
    if (resultado.type != ResultType.done && mounted) {
      avisar(context, 'No hay ninguna app que pueda abrirlo', esError: true);
    }
  }

  Future<void> _compartir(Pista pista) async {
    if (!File(pista.archivo).existsSync()) {
      if (mounted) avisar(context, 'El archivo ya no está', esError: true);
      return;
    }
    await SharePlus.instance.share(
      ShareParams(files: [XFile(pista.archivo)], text: pista.titulo),
    );
  }

  void _reproducir(Pista pista, List<Pista> lista) {
    final servicios = Servicios.de(context);
    if (pista.esAudio) {
      final indice = lista.indexWhere((p) => p.id == pista.id);
      servicios.audio.reproducirLista(lista, desde: indice < 0 ? 0 : indice);
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PantallaReproductor()),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PantallaVideo(pista: pista)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _cabecera(),
            TabBar(
              controller: _tabs,
              indicatorColor: Tono.acento,
              indicatorSize: TabBarIndicatorSize.label,
              labelColor: Tono.texto,
              unselectedLabelColor: Tono.texto3,
              dividerColor: Tono.borde,
              labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              tabs: [
                Tab(text: 'Música${_musica.isEmpty ? '' : ' · ${_musica.length}'}'),
                Tab(text: 'Videos${_videos.isEmpty ? '' : ' · ${_videos.length}'}'),
              ],
            ),
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabs,
                      children: [
                        _lista(_musica, esAudio: true),
                        _lista(_videos, esAudio: false),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cabecera() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Medidas.margen, 12, Medidas.margen, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Biblioteca', style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              if (_musica.isNotEmpty)
                IconButton(
                  onPressed: () {
                    Servicios.de(context).audio.reproducirLista(_musica);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const PantallaReproductor()));
                  },
                  icon: const Icon(Icons.shuffle_rounded),
                  color: Tono.texto2,
                  tooltip: 'Reproducir toda la música',
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: TextField(
              controller: _buscar,
              style: const TextStyle(fontSize: 14),
              onChanged: (v) {
                _filtro = v;
                _cargar();
              },
              decoration: InputDecoration(
                hintText: 'Buscar en lo descargado',
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                prefixIcon: const Icon(Icons.search_rounded, size: 19, color: Tono.texto3),
                suffixIcon: _filtro.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        color: Tono.texto3,
                        onPressed: () {
                          _buscar.clear();
                          _filtro = '';
                          _cargar();
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lista(List<Pista> pistas, {required bool esAudio}) {
    if (pistas.isEmpty) {
      return Vacio(
        icono: esAudio ? Icons.music_note_rounded : Icons.movie_outlined,
        titulo: _filtro.isNotEmpty
            ? 'Nada coincide con "$_filtro"'
            : (esAudio ? 'Todavía no hay música' : 'Todavía no hay videos'),
        detalle: _filtro.isNotEmpty
            ? 'Prueba con otras palabras.'
            : 'Lo que descargues aparecerá aquí, listo para verse sin conexión.',
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      color: Tono.acento,
      backgroundColor: Tono.superficie,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(Medidas.margen, 12, Medidas.margen, 24),
        itemCount: pistas.length,
        separatorBuilder: (_, _) => const SizedBox(height: 9),
        itemBuilder: (context, i) => _FilaPista(
          pista: pistas[i],
          alPulsar: () => _reproducir(pistas[i], pistas),
          alBorrar: () => _borrar(pistas[i]),
          alCompartir: () => _compartir(pistas[i]),
          alAbrirFuera: () => _abrirFuera(pistas[i]),
        ),
      ),
    );
  }
}

class _FilaPista extends StatelessWidget {
  const _FilaPista({
    required this.pista,
    required this.alPulsar,
    required this.alBorrar,
    required this.alCompartir,
    required this.alAbrirFuera,
  });

  final Pista pista;
  final VoidCallback alPulsar;
  final VoidCallback alBorrar;
  final VoidCallback alCompartir;
  final VoidCallback alAbrirFuera;

  @override
  Widget build(BuildContext context) {
    final existe = File(pista.archivo).existsSync();

    return Material(
      color: Tono.superficie,
      borderRadius: BorderRadius.circular(Medidas.radio),
      child: InkWell(
        borderRadius: BorderRadius.circular(Medidas.radio),
        onTap: existe ? alPulsar : null,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Medidas.radio),
            border: Border.all(color: Tono.borde),
          ),
          child: Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Miniatura(
                    url: pista.miniatura,
                    ancho: pista.esAudio ? 56 : 96,
                    alto: 56,
                    icono: pista.esAudio ? Icons.music_note_rounded : Icons.movie_outlined,
                  ),
                  if (existe)
                    Container(
                      width: 27,
                      height: 27,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 18),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pista.titulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: existe ? Tono.texto : Tono.texto3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (pista.autor.isNotEmpty) pista.autor,
                        if (pista.duracion > 0) formatoSegundos(pista.duracion),
                        if (pista.tamano > 0) formatoBytes(pista.tamano),
                        formatoFecha(pista.fecha),
                      ].where((x) => x.isNotEmpty).join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (!existe) ...[
                      const SizedBox(height: 4),
                      const Text(
                        'El archivo ya no está en el teléfono',
                        style: TextStyle(color: Tono.error, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, size: 20, color: Tono.texto3),
                color: Tono.superficieAlta,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Medidas.radioChico)),
                onSelected: (v) {
                  switch (v) {
                    case 'compartir':
                      alCompartir();
                    case 'abrir':
                      alAbrirFuera();
                    case 'borrar':
                      alBorrar();
                  }
                },
                itemBuilder: (_) => [
                  if (existe)
                    const PopupMenuItem(
                      value: 'compartir',
                      child: Row(children: [
                        Icon(Icons.share_rounded, size: 18),
                        SizedBox(width: 11),
                        Text('Compartir'),
                      ]),
                    ),
                  if (existe)
                    const PopupMenuItem(
                      value: 'abrir',
                      child: Row(children: [
                        Icon(Icons.open_in_new_rounded, size: 18),
                        SizedBox(width: 11),
                        Text('Abrir con otra app'),
                      ]),
                    ),
                  const PopupMenuItem(
                    value: 'borrar',
                    child: Row(children: [
                      Icon(Icons.delete_outline_rounded, size: 18, color: Tono.error),
                      SizedBox(width: 11),
                      Text('Borrar', style: TextStyle(color: Tono.error)),
                    ]),
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
