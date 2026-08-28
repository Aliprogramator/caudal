import 'package:flutter/material.dart';

import '../main.dart';
import '../nucleo/descargas.dart';
import '../nucleo/modelos.dart';
import '../nucleo/tema.dart';
import '../nucleo/version.dart';
import '../widgets/comunes.dart';
import '../widgets/hoja_version.dart';
import '../widgets/mini_reproductor.dart';
import 'biblioteca.dart';
import 'descargas_vista.dart';
import 'explorar.dart';
import 'navegador.dart';

/// Estructura de la app: cuatro destinos y el mini reproductor siempre a mano.
class PantallaInicio extends StatefulWidget {
  const PantallaInicio({super.key});

  @override
  State<PantallaInicio> createState() => _PantallaInicioState();
}

class _PantallaInicioState extends State<PantallaInicio> {
  int _indice = 0;
  final _paginas = const [
    VistaExplorar(),
    VistaNavegador(),
    VistaDescargas(),
    VistaBiblioteca(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _escucharDescargas());
    _mirarSiHayVersionNueva();
  }

  /// Al arrancar miramos si hay version nueva. Si no la hay, el usuario ni se
  /// entera: esperamos unos segundos para no competir con la carga inicial.
  Future<void> _mirarSiHayVersionNueva() async {
    await Future<void>.delayed(const Duration(seconds: 5));
    if (!mounted) return;
    final novedad = await buscarActualizacion();
    if (!mounted || novedad == null) return;
    await mostrarHojaVersion(context, novedad);
  }

  void _escucharDescargas() {
    final s = Servicios.de(context);
    s.descargas.alTerminar.listen((d) {
      if (!mounted || !s.ajustes.avisarAlTerminar) return;
      avisar(context, '${d.titulo} · guardado');
    });
  }

  void _ir(int i) {
    if (i == _indice) return;
    setState(() => _indice = i);
  }

  @override
  Widget build(BuildContext context) {
    final servicios = Servicios.de(context);

    return Scaffold(
      body: IndexedStack(index: _indice, children: _paginas),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniReproductor(),
          DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Tono.borde)),
            ),
            child: ListenableBuilder(
              listenable: servicios.descargas,
              builder: (context, _) {
                final activas = servicios.descargas.activas.length;
                return NavigationBar(
                  selectedIndex: _indice,
                  onDestinationSelected: _ir,
                  destinations: [
                    const NavigationDestination(
                      icon: Icon(Icons.search_rounded),
                      selectedIcon: Icon(Icons.search_rounded),
                      label: 'Buscar',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.public_rounded),
                      selectedIcon: Icon(Icons.public_rounded),
                      label: 'Navegador',
                    ),
                    NavigationDestination(
                      icon: Badge(
                        isLabelVisible: activas > 0,
                        label: Text('$activas'),
                        backgroundColor: Tono.acento,
                        textColor: const Color(0xFF04202A),
                        child: const Icon(Icons.download_rounded),
                      ),
                      label: 'Descargas',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.library_music_rounded),
                      label: 'Biblioteca',
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Atajo para que cualquier pantalla mande al usuario a la pestaña de descargas.
void irADescargas(BuildContext context) {
  final estado = context.findAncestorStateOfType<_PantallaInicioState>();
  estado?._ir(2);
}

/// Encola una descarga y avisa, desde donde sea.
void encolarYAvisar(
  BuildContext context, {
  required GestorDescargas gestor,
  required String url,
  required TipoMedio tipo,
  required String calidad,
  required String formatoAudio,
  String titulo = '',
  String autor = '',
  String miniatura = '',
}) {
  gestor.encolar(
    url: url,
    tipo: tipo,
    calidad: calidad,
    formatoAudio: formatoAudio,
    titulo: titulo,
    autor: autor,
    miniatura: miniatura,
  );
  avisar(context, 'Añadido a la cola de descargas');
}
