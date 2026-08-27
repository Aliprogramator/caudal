# -*- coding: utf-8 -*-
"""Punto de entrada del Descargador de Videos."""

import os
import sys


def _preparar_rutas():
    """Permite ejecutar tanto como paquete instalado como script suelto."""
    raiz = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if raiz not in sys.path:
        sys.path.insert(0, raiz)


def main():
    _preparar_rutas()

    # El navegador integrado se queda en negro en equipos con tarjetas graficas
    # antiguas: Chromium intenta dibujar por GPU y el driver no responde.
    # Dibujando por software se ve bien en cualquier maquina.
    os.environ.setdefault(
        "QTWEBENGINE_CHROMIUM_FLAGS",
        "--disable-gpu --disable-gpu-compositing --disable-software-rasterizer "
        "--no-sandbox",
    )

    from PySide6.QtCore import Qt
    from PySide6.QtGui import QIcon
    from PySide6.QtWidgets import QApplication

    from descargador.config import APP_NOMBRE, Ajustes
    from descargador.historial import Historial
    from descargador.motor import Gestor
    from descargador.ui import iconos
    from descargador.ui.ventana import Ventana

    QApplication.setHighDpiScaleFactorRoundingPolicy(
        Qt.HighDpiScaleFactorRoundingPolicy.PassThrough)
    # Comprobado: con desactivar la GPU solo en el navegador basta. Forzar
    # ademas OpenGL por software dejaba lenta toda la interfaz.

    app = QApplication(sys.argv)
    app.setApplicationName(APP_NOMBRE)
    app.setOrganizationName("DescargadorVideos")
    app.setWindowIcon(QIcon(iconos.icono_app(256)))
    app.setQuitOnLastWindowClosed(True)

    if sys.platform == "win32":
        try:
            import ctypes
            ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID(
                "kevin.descargadorvideos.1")
        except Exception:
            pass

    ajustes = Ajustes()
    historial = Historial()
    gestor = Gestor(ajustes, historial)

    ventana = Ventana(ajustes, historial, gestor)
    ventana.show()

    # enlaces pasados por linea de comandos o por "Abrir con"
    argumentos = [a for a in sys.argv[1:] if a.strip()]
    if argumentos:
        from descargador import redes
        urls = redes.extraer_urls(" ".join(argumentos))
        if urls:
            gestor.agregar_varias(urls)

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
