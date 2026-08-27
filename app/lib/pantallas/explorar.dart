import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../nucleo/formato.dart';
import '../nucleo/modelos.dart';
import '../nucleo/servidor.dart';
import '../nucleo/tema.dart';
import '../widgets/comunes.dart';
import '../widgets/hoja_descarga.dart';
import 'ajustes_vista.dart';
import 'listas_vista.dart';
import 'acceso.dart';
import 'inicio.dart';

/// Pantalla principal: buscar música por nombre o pegar un enlace.
class VistaExplorar extends StatefulWidget {
  const VistaExplorar({super.key});

  @override
  State<VistaExplorar> createState() => _VistaExplorarState();
}

class _VistaExplorarState extends State<VistaExplorar> {
  final _campo = TextEditingController();
  final _foco = FocusNode();

  List<Resultado> _resultados = [];
  bool _buscando = false;
  String _error = '';
  String _ultimaConsulta = '';

  @override
  void dispose() {
    _campo.dispose();
    _foco.dispose();
    super.dispose();
  }

  Future<void> _enviar([String? texto]) async {
    final entrada = (texto ?? _campo.text).trim();
    if (entrada.isEmpty) return;

    final servicios = Servicios.de(context);
    if (!servicios.ajustes.conSesion) {
      _pedirConexion();
      return;
    }

    _foco.unfocus();

    if (pareceEnlace(entrada)) {
      await _descargarEnlace(normalizarEnlace(entrada));
      return;
    }

    setState(() {
      _buscando = true;
      _error = '';
      _ultimaConsulta = entrada;
    });

    try {
      final res = await servicios.servidor.buscar(entrada);
      if (!mounted) return;
      setState(() {
        _resultados = res;
        _buscando = false;
      });
      servicios.ajustes.recordarBusqueda(entrada);
    } on ErrorCaudal catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.mensaje;
        _buscando = false;
        _resultados = [];
      });
    }
  }

  Future<void> _descargarEnlace(String url, {Resultado? origen}) async {
    final servicios = Servicios.de(context);
    final eleccion = await mostrarHojaDescarga(
      context,
      url: url,
      servidor: servicios.servidor,
      ajustes: servicios.ajustes,
    );
    if (eleccion == null || !mounted) return;

    encolarYAvisar(
      context,
      gestor: servicios.descargas,
      url: url,
      tipo: eleccion.tipo,
      calidad: eleccion.calidad,
      formatoAudio: eleccion.formatoAudio,
      titulo: eleccion.ficha.titulo.isNotEmpty
          ? eleccion.ficha.titulo
          : (origen?.titulo ?? ''),
      autor: eleccion.ficha.autor.isNotEmpty ? eleccion.ficha.autor : (origen?.autor ?? ''),
      miniatura: eleccion.ficha.miniatura.isNotEmpty
          ? eleccion.ficha.miniatura
          : (origen?.miniatura ?? ''),
    );
    _campo.clear();
  }

  Future<void> _pegar() async {
    final datos = await Clipboard.getData(Clipboard.kTextPlain);
    final texto = datos?.text?.trim() ?? '';
    if (texto.isEmpty) {
      if (mounted) avisar(context, 'No hay nada copiado', esError: true);
      return;
    }
    _campo.text = texto;
    if (pareceEnlace(texto)) _enviar(texto);
  }

  void _pedirConexion() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PantallaAcceso()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final servicios = Servicios.de(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: servicios.ajustes,
          builder: (context, _) {
            final conSesion = servicios.ajustes.conSesion;
            return CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverToBoxAdapter(child: _cabecera()),
                SliverToBoxAdapter(child: _buscador()),
                if (!conSesion)
                  SliverToBoxAdapter(child: _tarjetaConectar())
                else if (_error.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(Medidas.margen),
                      child: Aviso(
                        texto: _error,
                        icono: Icons.wifi_off_rounded,
                        color: Tono.error,
                        accion: TextButton(
                          onPressed: () => _enviar(_ultimaConsulta),
                          child: const Text('Reintentar'),
                        ),
                      ),
                    ),
                  )
                else if (_buscando)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_resultados.isNotEmpty)
                  _listaResultados()
                else
                  SliverToBoxAdapter(child: _sugerencias()),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _cabecera() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Medidas.margen, 12, Medidas.margen, 6),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: Tono.gradiente,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.water_drop_rounded, color: Color(0xFF04202A), size: 21),
          ),
          const SizedBox(width: 11),
          const TextoDegradado('Caudal'),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const VistaAjustes()),
            ),
            icon: const Icon(Icons.settings_rounded),
            color: Tono.texto3,
            tooltip: 'Ajustes',
          ),
        ],
      ),
    );
  }

  Widget _buscador() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Medidas.margen, 6, Medidas.margen, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Busca una canción o pega un enlace',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _campo,
            focusNode: _foco,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _enviar(),
            style: const TextStyle(fontSize: 15.5),
            decoration: InputDecoration(
              hintText: 'Nombre de la canción o enlace',
              prefixIcon: const Icon(Icons.search_rounded, color: Tono.texto3),
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
                    onPressed: () => _enviar(),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                    color: Tono.acento,
                    tooltip: 'Buscar',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: Tono.superficie,
            borderRadius: BorderRadius.circular(Medidas.radio),
            child: InkWell(
              borderRadius: BorderRadius.circular(Medidas.radio),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const VistaListas()),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Medidas.radio),
                  border: Border.all(color: Tono.borde),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        gradient: Tono.gradienteSuave,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.queue_music_rounded,
                          size: 18, color: Tono.acento),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Traer una lista',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text('De Spotify, Apple Music o YouTube Music',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: Tono.texto3),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaConectar() {
    return Padding(
      padding: const EdgeInsets.all(Medidas.margen),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: Tono.gradienteSuave,
          borderRadius: BorderRadius.circular(Medidas.radioGrande),
          border: Border.all(color: Tono.acento.withValues(alpha: 0.28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.link_rounded, color: Tono.acento, size: 22),
                const SizedBox(width: 10),
                Text('Conecta con tu servidor',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Caudal usa el servidor que corre en tu computadora para resolver los '
              'enlaces. Enciéndelo y escanea el código QR que aparece en pantalla.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            BotonPrincipal(
              texto: 'Escanear código QR',
              icono: Icons.qr_code_scanner_rounded,
              alPulsar: _pedirConexion,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sugerencias() {
    final recientes = Servicios.de(context).ajustes.busquedas;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Medidas.margen, 18, Medidas.margen, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (recientes.isNotEmpty) ...[
            Row(
              children: [
                Text('Búsquedas recientes',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    Servicios.de(context).ajustes.limpiarBusquedas();
                    setState(() {});
                  },
                  child: const Text('Borrar'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final b in recientes)
                  ActionChip(
                    label: Text(b),
                    avatar: const Icon(Icons.history_rounded, size: 15),
                    onPressed: () {
                      _campo.text = b;
                      _enviar(b);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 26),
          ],
          Text('Cómo funciona', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          _paso(1, Icons.search_rounded, 'Busca por nombre',
              'Escribe el título de una canción y elige el resultado.'),
          _paso(2, Icons.public_rounded, 'O navega como siempre',
              'Abre cualquier web en el navegador de la app y descarga lo que veas.'),
          _paso(3, Icons.library_music_rounded, 'Escúchalo sin conexión',
              'Lo descargado queda en tu biblioteca y suena con la pantalla apagada.'),
        ],
      ),
    );
  }

  Widget _paso(int numero, IconData icono, String titulo, String detalle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Tono.superficieAlta,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Tono.borde),
            ),
            child: Icon(icono, size: 19, color: Tono.acento),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w600, color: Tono.texto)),
                const SizedBox(height: 3),
                Text(detalle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _listaResultados() {
    return SliverList.separated(
      itemCount: _resultados.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final r = _resultados[i];
        return Padding(
          padding: EdgeInsets.fromLTRB(
              Medidas.margen, i == 0 ? 14 : 0, Medidas.margen, 0),
          child: _FilaResultado(
            resultado: r,
            alPulsar: () => _descargarEnlace(r.url, origen: r),
          ),
        );
      },
    );
  }
}

class _FilaResultado extends StatelessWidget {
  const _FilaResultado({required this.resultado, required this.alPulsar});

  final Resultado resultado;
  final VoidCallback alPulsar;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Tono.superficie,
      borderRadius: BorderRadius.circular(Medidas.radio),
      child: InkWell(
        borderRadius: BorderRadius.circular(Medidas.radio),
        onTap: alPulsar,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Medidas.radio),
            border: Border.all(color: Tono.borde),
          ),
          child: Row(
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Miniatura(url: resultado.miniatura, ancho: 108, alto: 62),
                  if (resultado.duracionTexto.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.all(5),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        resultado.duracionTexto,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resultado.titulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600, color: Tono.texto, height: 1.3),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (resultado.autor.isNotEmpty) resultado.autor,
                        if (resultado.vistas > 0) formatoVistas(resultado.vistas),
                      ].join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Tono.acento.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.download_rounded, color: Tono.acento, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
