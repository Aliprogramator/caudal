import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../main.dart';
import '../nucleo/servidor.dart';
import '../nucleo/tema.dart';
import '../widgets/comunes.dart';

/// Conectar el teléfono con el servidor y entrar con la cuenta.
///
/// Son dos pasos: primero saber dónde está el servidor (por QR o a mano) y
/// luego iniciar sesión. La contraseña nunca viaja en el código QR.
class PantallaAcceso extends StatefulWidget {
  const PantallaAcceso({super.key, this.comoPuerta = false});

  /// Cuando es la primera pantalla de la app no hay a dónde volver.
  final bool comoPuerta;

  @override
  State<PantallaAcceso> createState() => _PantallaAccesoState();
}

enum _Paso { buscarServidor, escribirDireccion, entrar }

class _PantallaAccesoState extends State<PantallaAcceso> {
  MobileScannerController? _camara;

  _Paso _paso = _Paso.buscarServidor;
  bool _ocupado = false;
  String _error = '';

  String _local = '';
  String _publica = '';
  String _equipo = '';
  bool _puedeRegistrar = false;
  bool _hayCuentas = true;
  bool _creandoCuenta = false;

  final _direccion = TextEditingController();
  final _usuario = TextEditingController();
  final _clave = TextEditingController();
  final _clave2 = TextEditingController();
  final _nombre = TextEditingController();
  bool _mantener = true;

  bool _preparado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // aqui si es valido leer los servicios; en initState todavia no lo es
    if (_preparado) return;
    _preparado = true;

    final ajustes = Servicios.de(context).ajustes;
    if (ajustes.hayServidor) {
      _local = ajustes.servidorLocal;
      _publica = ajustes.servidorPublico;
      _paso = _Paso.entrar;
      WidgetsBinding.instance.addPostFrameCallback((_) => _mirarServidor());
    } else {
      _camara = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        facing: CameraFacing.back,
      );
    }
  }

  @override
  void dispose() {
    _camara?.dispose();
    _direccion.dispose();
    _usuario.dispose();
    _clave.dispose();
    _clave2.dispose();
    _nombre.dispose();
    super.dispose();
  }

  String get _nombreDispositivo {
    if (Platform.isAndroid) return 'Teléfono Android';
    if (Platform.isIOS) return 'iPhone';
    return 'Dispositivo';
  }

  // ---------------------------------------------------------------- servidor

  Future<void> _alEscanear(BarcodeCapture captura) async {
    if (_ocupado) return;
    final valor = captura.barcodes.firstOrNull?.rawValue;
    if (valor == null || valor.isEmpty) return;

    setState(() => _ocupado = true);
    try {
      final datos = jsonDecode(valor) as Map<String, dynamic>;
      final local = '${datos['servidor'] ?? ''}';
      final publica = '${datos['publico'] ?? ''}';
      if (local.isEmpty && publica.isEmpty) throw const FormatException('vacio');
      await _usarDirecciones(local, publica);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _error = 'Ese código no es el de Caudal. Abre la dirección del servidor en '
            'el navegador de tu computadora y escanea el que aparece ahí.';
      });
    }
  }

  Future<void> _usarDirecciones(String local, String publica) async {
    final servidor = Servicios.de(context).servidor;
    setState(() {
      _ocupado = true;
      _error = '';
    });
    try {
      // probamos la de casa; si no responde, la de internet
      Map<String, dynamic>? datos;
      var usada = '';
      for (final candidata in [local, publica]) {
        if (candidata.isEmpty) continue;
        try {
          datos = await servidor.comprobar(candidata);
          usada = candidata;
          break;
        } on ErrorCaudal {
          continue;
        }
      }
      if (datos == null) {
        throw ErrorCaudal(
          'No se llega a ese servidor. Comprueba que esté encendido y que estés '
          'en la misma red wifi.',
        );
      }

      if (!mounted) return;
      _local = local;
      _publica = publica;
      servidor.configurar(local: local, publica: publica);
      final ajustes = Servicios.de(context).ajustes;
      await ajustes.guardarDirecciones(
        Servidor.limpiar(local),
        Servidor.limpiar(publica),
      );

      if (!mounted) return;
      setState(() {
        _equipo = '${datos!['equipo'] ?? ''}';
        _puedeRegistrar = datos['puede_registrar'] == true;
        _hayCuentas = datos['hay_cuentas'] == true;
        _creandoCuenta = !_hayCuentas && _puedeRegistrar;
        _paso = _Paso.entrar;
        _ocupado = false;
        _error = usada == publica && local.isNotEmpty
            ? 'Conectado desde internet: en casa irá más rápido.'
            : '';
      });
    } on ErrorCaudal catch (e) {
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _error = e.mensaje;
      });
    }
  }

  Future<void> _mirarServidor() async {
    final servidor = Servicios.de(context).servidor;
    setState(() => _ocupado = true);
    try {
      final datos = await servidor.comprobar(
          _local.isNotEmpty ? _local : _publica);
      if (!mounted) return;
      setState(() {
        _equipo = '${datos['equipo'] ?? ''}';
        _puedeRegistrar = datos['puede_registrar'] == true;
        _hayCuentas = datos['hay_cuentas'] == true;
        _creandoCuenta = !_hayCuentas && _puedeRegistrar;
        _ocupado = false;
      });
    } on ErrorCaudal catch (e) {
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _error = e.mensaje;
      });
    }
  }

  // ---------------------------------------------------------------- cuenta

  Future<void> _entrar() async {
    final usuario = _usuario.text.trim();
    final clave = _clave.text;
    if (usuario.isEmpty || clave.isEmpty) {
      setState(() => _error = 'Escribe tu usuario y tu contraseña.');
      return;
    }

    setState(() {
      _ocupado = true;
      _error = '';
    });

    final servicios = Servicios.de(context);
    try {
      final sesion = _creandoCuenta
          ? await servicios.servidor.registrar(
              usuario: usuario,
              clave: clave,
              nombre: _nombre.text.trim(),
              dispositivo: _nombreDispositivo,
            )
          : await servicios.servidor.entrar(
              usuario: usuario,
              clave: clave,
              dispositivo: _nombreDispositivo,
            );

      await servicios.ajustes.definirMantenerSesion(_mantener);
      await servicios.ajustes.guardarSesion(
        token: sesion.token,
        usuario: sesion.usuario,
        nombre: sesion.nombre,
      );

      if (!mounted) return;
      avisar(context, 'Hola, ${sesion.nombre}');
      if (widget.comoPuerta) {
        // al haber sesión, la puerta deja pasar sola
        return;
      }
      Navigator.of(context).pop(true);
    } on ErrorCaudal catch (e) {
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _error = e.mensaje;
      });
    }
  }

  bool get _formularioValido {
    if (_usuario.text.trim().isEmpty || _clave.text.isEmpty) return false;
    if (_creandoCuenta && _clave.text != _clave2.text) return false;
    return true;
  }

  // ---------------------------------------------------------------- interfaz

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.comoPuerta,
        title: Text(switch (_paso) {
          _Paso.buscarServidor => 'Conectar con tu servidor',
          _Paso.escribirDireccion => 'Escribir la dirección',
          _Paso.entrar => _creandoCuenta ? 'Crear tu cuenta' : 'Iniciar sesión',
        }),
        actions: [
          if (_paso == _Paso.buscarServidor)
            IconButton(
              onPressed: () => setState(() {
                _paso = _Paso.escribirDireccion;
                _error = '';
              }),
              icon: const Icon(Icons.keyboard_rounded),
              tooltip: 'Escribirlo a mano',
            ),
          if (_paso == _Paso.escribirDireccion)
            IconButton(
              onPressed: () => setState(() {
                _paso = _Paso.buscarServidor;
                _error = '';
              }),
              icon: const Icon(Icons.qr_code_scanner_rounded),
              tooltip: 'Usar la cámara',
            ),
        ],
      ),
      body: switch (_paso) {
        _Paso.buscarServidor => _vistaEscaner(),
        _Paso.escribirDireccion => _vistaDireccion(),
        _Paso.entrar => _vistaEntrar(),
      },
    );
  }

  Widget _vistaEscaner() {
    return Column(
      children: [
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_camara != null)
                MobileScanner(controller: _camara!, onDetect: _alEscanear),
              Container(
                width: 236,
                height: 236,
                decoration: BoxDecoration(
                  border: Border.all(color: Tono.acento, width: 2.5),
                  borderRadius: BorderRadius.circular(Medidas.radioGrande),
                ),
              ),
              if (_ocupado)
                Container(
                  color: Colors.black54,
                  child: const Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          color: Tono.superficie,
          padding: const EdgeInsets.all(Medidas.margen),
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Apunta al código QR', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 7),
                Text(
                  'Enciende Caudal en tu computadora: se abrirá una página con el '
                  'código. Apunta la cámara ahí.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Aviso(texto: _error, icono: Icons.error_outline_rounded, color: Tono.error),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _vistaDireccion() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Medidas.margen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('¿Dónde está tu servidor?', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'La dirección aparece en la ventana de Caudal en tu computadora.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 22),
          TextField(
            controller: _direccion,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Dirección',
              hintText: 'http://192.168.1.10:8770',
              prefixIcon: Icon(Icons.dns_rounded),
            ),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 16),
            Aviso(texto: _error, icono: Icons.error_outline_rounded, color: Tono.error),
          ],
          const SizedBox(height: 24),
          BotonPrincipal(
            texto: 'Continuar',
            icono: Icons.arrow_forward_rounded,
            ancho: double.infinity,
            cargando: _ocupado,
            alPulsar: _ocupado
                ? null
                : () {
                    final d = _direccion.text.trim();
                    if (d.isEmpty) {
                      setState(() => _error = 'Escribe la dirección.');
                      return;
                    }
                    _usarDirecciones(d, '');
                  },
          ),
        ],
      ),
    );
  }

  Widget _vistaEntrar() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Medidas.margen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: Tono.gradienteSuave,
              borderRadius: BorderRadius.circular(Medidas.radio),
              border: Border.all(color: Tono.acento.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.dns_rounded, color: Tono.acento, size: 20),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _equipo.isEmpty ? 'Servidor encontrado' : 'Conectado con $_equipo',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _local.isNotEmpty ? _local : _publica,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _paso = _Paso.buscarServidor;
                    _camara ??= MobileScannerController(
                      detectionSpeed: DetectionSpeed.noDuplicates,
                      facing: CameraFacing.back,
                    );
                    _error = '';
                  }),
                  child: const Text('Cambiar'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          if (_creandoCuenta) ...[
            Text('Crea tu cuenta', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              _hayCuentas
                  ? 'Se guardará en tu servidor, no en internet.'
                  : 'Todavía no hay ninguna cuenta en este servidor: esta será la primera.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ] else ...[
            Text('Entra con tu cuenta', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'La misma que usas en la computadora.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 20),

          if (_creandoCuenta) ...[
            TextField(
              controller: _nombre,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Tu nombre (opcional)',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
          ],

          TextField(
            controller: _usuario,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Usuario',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _clave,
            obscureText: true,
            textInputAction: _creandoCuenta ? TextInputAction.next : TextInputAction.go,
            onSubmitted: (_) => _creandoCuenta ? null : _entrar(),
            decoration: const InputDecoration(
              labelText: 'Contraseña',
              prefixIcon: Icon(Icons.lock_outline_rounded),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_creandoCuenta) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _clave2,
              obscureText: true,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _entrar(),
              decoration: InputDecoration(
                labelText: 'Repite la contraseña',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                errorText: _clave2.text.isNotEmpty && _clave.text != _clave2.text
                    ? 'No coinciden'
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],

          if (_error.isNotEmpty) ...[
            const SizedBox(height: 16),
            Aviso(
              texto: _error,
              icono: _error.startsWith('Conectado')
                  ? Icons.info_outline_rounded
                  : Icons.error_outline_rounded,
              color: _error.startsWith('Conectado') ? Tono.acento : Tono.error,
            ),
          ],

          const SizedBox(height: 6),
          CheckboxListTile(
            value: _mantener,
            onChanged: (v) => setState(() => _mantener = v ?? true),
            title: const Text('Mantener la sesión iniciada',
                style: TextStyle(fontSize: 14)),
            subtitle: Text(
              _mantener
                  ? 'No tendrás que escribir la contraseña cada vez'
                  : 'Te pedirá la contraseña cada vez que abras la app',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          const SizedBox(height: 14),
          BotonPrincipal(
            texto: _creandoCuenta ? 'Crear cuenta y entrar' : 'Entrar',
            icono: _creandoCuenta ? Icons.person_add_alt_rounded : Icons.login_rounded,
            ancho: double.infinity,
            cargando: _ocupado,
            alPulsar: (_ocupado || !_formularioValido) ? null : _entrar,
          ),

          if (_puedeRegistrar) ...[
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () => setState(() {
                  _creandoCuenta = !_creandoCuenta;
                  _error = '';
                }),
                child: Text(_creandoCuenta
                    ? 'Ya tengo cuenta, quiero entrar'
                    : 'No tengo cuenta, crear una'),
              ),
            ),
          ] else if (!_creandoCuenta) ...[
            const SizedBox(height: 14),
            const Aviso(
              texto: 'Las cuentas solo se crean desde tu computadora o desde la wifi de '
                  'casa. Si aún no tienes una, créala allí primero.',
              icono: Icons.shield_outlined,
              color: Tono.texto3,
            ),
          ],
        ],
      ),
    );
  }
}
