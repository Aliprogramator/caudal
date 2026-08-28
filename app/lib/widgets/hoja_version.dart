import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../nucleo/formato.dart';
import '../nucleo/tema.dart';
import '../nucleo/version.dart';
import 'comunes.dart';

/// Cuenta que hay una version nueva y la instala si el usuario quiere.
///
/// En Android baja el APK y abre el instalador del sistema. En iPhone no se
/// puede: Apple no deja instalar nada desde dentro de una app, asi que solo
/// se explica de donde bajarla.
Future<void> mostrarHojaVersion(BuildContext context, Novedad novedad) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    backgroundColor: Tono.superficie,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Medidas.radioGrande)),
    ),
    builder: (_) => _HojaVersion(novedad: novedad),
  );
}

class _HojaVersion extends StatefulWidget {
  const _HojaVersion({required this.novedad});

  final Novedad novedad;

  @override
  State<_HojaVersion> createState() => _HojaVersionState();
}

class _HojaVersionState extends State<_HojaVersion> {
  double _progreso = 0;
  bool _bajando = false;
  String? _error;
  CancelToken? _cancelar;

  @override
  void dispose() {
    _cancelar?.cancel();
    super.dispose();
  }

  Future<void> _instalar() async {
    setState(() {
      _bajando = true;
      _error = null;
      _progreso = 0;
    });

    _cancelar = CancelToken();
    try {
      final ruta = await descargarApk(
        widget.novedad,
        cancelar: _cancelar,
        alProgresar: (p) {
          if (mounted) setState(() => _progreso = p);
        },
      );
      final fallo = await instalar(ruta);
      if (!mounted) return;
      if (fallo != null) {
        setState(() {
          _bajando = false;
          _error = fallo;
        });
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted || (_cancelar?.isCancelled ?? false)) return;
      setState(() {
        _bajando = false;
        _error = 'No se pudo bajar la actualizacion. Comprueba tu conexion.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.novedad;
    return Padding(
      padding: EdgeInsets.only(
        left: Medidas.margen + 4,
        right: Medidas.margen + 4,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 26,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Tono.bordeClaro,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  gradient: Tono.gradiente,
                  borderRadius: BorderRadius.circular(Medidas.radioChico),
                ),
                child: const Icon(Icons.system_update_rounded,
                    color: Tono.fondo, size: 22),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Caudal ${n.version} ya esta lista',
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Tono.texto,
                            letterSpacing: -0.3)),
                    const SizedBox(height: 3),
                    Text(
                      n.peso > 0
                          ? 'Tienes la $versionApp  ·  ${formatoBytes(n.peso)}'
                          : 'Tienes la $versionApp',
                      style: const TextStyle(fontSize: 12.5, color: Tono.texto3),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          if (n.notas.isNotEmpty)
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 190),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Tono.superficieAlta,
                borderRadius: BorderRadius.circular(Medidas.radioChico),
                border: Border.all(color: Tono.borde),
              ),
              child: SingleChildScrollView(
                child: Text(
                  n.notas,
                  style: const TextStyle(
                      fontSize: 13, height: 1.55, color: Tono.texto2),
                ),
              ),
            ),

          if (!n.sePuedeInstalar) ...[
            const SizedBox(height: 16),
            const Aviso(
              texto: 'En iPhone la version nueva se instala desde tu computadora, '
                  'igual que la primera vez.',
            ),
          ],

          if (_bajando) ...[
            const SizedBox(height: 20),
            BarraProgreso(valor: _progreso / 100),
            const SizedBox(height: 9),
            Text(
              _progreso >= 99.5
                  ? 'Abriendo el instalador...'
                  : 'Bajando  ${_progreso.toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12.5, color: Tono.texto3),
            ),
          ],

          if (_error != null) ...[
            const SizedBox(height: 16),
            Aviso(texto: _error!, color: Tono.error, icono: Icons.error_outline_rounded),
          ],

          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _bajando ? null : () => Navigator.of(context).pop(),
                  child: Text(_bajando ? 'Espera...' : 'Mas tarde',
                      style: const TextStyle(color: Tono.texto3)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: BotonPrincipal(
                  texto: _bajando ? 'Bajando' : 'Instalar ahora',
                  icono: Icons.download_rounded,
                  cargando: _bajando,
                  ancho: double.infinity,
                  alPulsar: (n.sePuedeInstalar && !_bajando) ? _instalar : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
