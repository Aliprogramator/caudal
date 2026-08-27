import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Paleta y estilos de Caudal.
///
/// Un solo acento en degradado (cian -> indigo) sobre fondos muy oscuros:
/// deja que las caratulas y miniaturas sean lo que aporta el color.
class Tono {
  static const fondo = Color(0xFF0B0E14);
  static const superficie = Color(0xFF141922);
  static const superficieAlta = Color(0xFF1C2230);
  static const superficieMax = Color(0xFF252C3C);
  static const borde = Color(0xFF232A36);
  static const bordeClaro = Color(0xFF333C4D);

  static const texto = Color(0xFFE8EBF1);
  static const texto2 = Color(0xFFA8B2C4);
  static const texto3 = Color(0xFF7C879B);

  static const acento = Color(0xFF22D3EE);
  static const acento2 = Color(0xFF6366F1);
  static const exito = Color(0xFF34D399);
  static const error = Color(0xFFF87171);
  static const aviso = Color(0xFFFBBF24);

  static const gradiente = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [acento, acento2],
  );

  /// Degradado suave para fondos de tarjetas destacadas.
  static const gradienteSuave = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x2222D3EE), Color(0x226366F1)],
  );
}

class Medidas {
  static const radio = 18.0;
  static const radioChico = 12.0;
  static const radioGrande = 26.0;
  static const margen = 18.0;
  static const espacio = 14.0;

  /// Alto del mini reproductor, para dejarle sitio en los listados.
  static const miniReproductor = 66.0;
}

ThemeData construirTema() {
  const base = ColorScheme.dark(
    primary: Tono.acento,
    onPrimary: Color(0xFF04202A),
    secondary: Tono.acento2,
    onSecondary: Colors.white,
    surface: Tono.superficie,
    onSurface: Tono.texto,
    error: Tono.error,
    onError: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: base,
    scaffoldBackgroundColor: Tono.fondo,
    canvasColor: Tono.fondo,
    splashFactory: InkSparkle.splashFactory,
    fontFamily: null, // la fuente del sistema se ve nativa en cada plataforma

    appBarTheme: const AppBarTheme(
      backgroundColor: Tono.fondo,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Tono.texto,
        fontSize: 21,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    ),

    textTheme: const TextTheme(
      headlineSmall: TextStyle(
          fontSize: 22, fontWeight: FontWeight.w700, color: Tono.texto, letterSpacing: -0.4),
      titleLarge: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w700, color: Tono.texto, letterSpacing: -0.2),
      titleMedium: TextStyle(
          fontSize: 15.5, fontWeight: FontWeight.w600, color: Tono.texto),
      bodyLarge: TextStyle(fontSize: 15, color: Tono.texto, height: 1.4),
      bodyMedium: TextStyle(fontSize: 13.5, color: Tono.texto2, height: 1.4),
      bodySmall: TextStyle(fontSize: 12, color: Tono.texto3, height: 1.35),
      labelLarge: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Tono.superficieAlta,
      hintStyle: const TextStyle(color: Tono.texto3, fontSize: 15),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Medidas.radio),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Medidas.radio),
        borderSide: const BorderSide(color: Tono.borde),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Medidas.radio),
        borderSide: const BorderSide(color: Tono.acento, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Medidas.radio),
        borderSide: const BorderSide(color: Tono.error),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Tono.acento,
        foregroundColor: const Color(0xFF04202A),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Medidas.radio)),
        textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Tono.texto,
        side: const BorderSide(color: Tono.bordeClaro),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Medidas.radio)),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: Tono.acento),
    ),

    cardTheme: CardThemeData(
      color: Tono.superficie,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Medidas.radio),
        side: const BorderSide(color: Tono.borde),
      ),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Tono.superficie,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Medidas.radioGrande)),
      ),
      showDragHandle: true,
      dragHandleColor: Tono.bordeClaro,
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: Tono.superficie,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Medidas.radioGrande)),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: Tono.superficieMax,
      contentTextStyle: const TextStyle(color: Tono.texto, fontSize: 14),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Medidas.radioChico)),
      insetPadding: const EdgeInsets.all(Medidas.margen),
    ),

    dividerTheme: const DividerThemeData(color: Tono.borde, thickness: 1, space: 1),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Tono.acento,
      linearTrackColor: Tono.superficieMax,
      circularTrackColor: Tono.superficieMax,
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Tono.superficie,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Tono.acento.withValues(alpha: 0.16),
      elevation: 0,
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((estados) {
        final activo = estados.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11.5,
          fontWeight: activo ? FontWeight.w700 : FontWeight.w500,
          color: activo ? Tono.texto : Tono.texto3,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((estados) {
        final activo = estados.contains(WidgetState.selected);
        return IconThemeData(size: 24, color: activo ? Tono.acento : Tono.texto3);
      }),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: Tono.superficieAlta,
      side: const BorderSide(color: Tono.borde),
      labelStyle: const TextStyle(color: Tono.texto2, fontSize: 12.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),

    sliderTheme: SliderThemeData(
      activeTrackColor: Tono.acento,
      inactiveTrackColor: Tono.superficieMax,
      thumbColor: Tono.acento,
      trackHeight: 4,
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
    ),

    listTileTheme: const ListTileThemeData(
      iconColor: Tono.texto2,
      textColor: Tono.texto,
      contentPadding: EdgeInsets.symmetric(horizontal: Medidas.margen, vertical: 4),
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((e) =>
          e.contains(WidgetState.selected) ? Tono.acento : Tono.texto3),
      trackColor: WidgetStateProperty.resolveWith((e) => e.contains(WidgetState.selected)
          ? Tono.acento.withValues(alpha: 0.32)
          : Tono.superficieMax),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
  );
}

/// Texto con el degradado de la marca aplicado.
class TextoDegradado extends StatelessWidget {
  const TextoDegradado(this.texto, {super.key, this.estilo});

  final String texto;
  final TextStyle? estilo;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (rect) => Tono.gradiente.createShader(rect),
      blendMode: BlendMode.srcIn,
      child: Text(texto, style: estilo ?? Theme.of(context).textTheme.headlineSmall),
    );
  }
}
