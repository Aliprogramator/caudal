# -*- coding: utf-8 -*-
"""Ventana principal del descargador."""

import os
import subprocess
import sys
import time
import webbrowser

from PySide6.QtCore import QTimer, QUrl, Qt
from PySide6.QtGui import QAction, QDesktopServices, QGuiApplication, QIcon, QKeySequence, QShortcut
from PySide6.QtWidgets import (QAbstractItemView, QApplication, QButtonGroup, QCheckBox, QComboBox,
                               QFileDialog, QFrame, QGridLayout, QHBoxLayout, QHeaderView,
                               QLabel, QLineEdit, QMenu, QMessageBox, QProgressBar,
                               QPushButton, QScrollArea, QSizePolicy, QSpinBox,
                               QStackedWidget, QSystemTrayIcon, QTableWidget,
                               QTableWidgetItem, QVBoxLayout, QWidget)

from .. import motor, redes
from ..config import APP_NOMBRE, DEFECTOS, carpeta_datos, ruta_ffmpeg
from .estilos import C, hoja
from . import iconos
from .biblioteca import VistaBiblioteca
from .navegador import VistaNavegador
from .panel_caudal import PanelCaudal
from .reproductor import Reproductor, VistaVideo
from .tarjeta import TarjetaDescarga


CALIDADES = [
    ("Mejor calidad disponible", "mejor"),
    ("4K  ·  2160p", "2160"),
    ("2K  ·  1440p", "1440"),
    ("Full HD  ·  1080p", "1080"),
    ("HD  ·  720p", "720"),
    ("SD  ·  480p", "480"),
    ("Ligero  ·  360p", "360"),
]

TIPOS = [
    ("Video con audio", "completo"),
    ("Solo video (sin audio)", "video"),
    ("Solo audio", "audio"),
]

NAVEGADORES = [
    ("No usar cookies", "ninguno"),
    ("Chrome", "chrome"),
    ("Edge", "edge"),
    ("Firefox", "firefox"),
    ("Brave", "brave"),
    ("Opera", "opera"),
    ("Vivaldi", "vivaldi"),
    ("Chromium", "chromium"),
]


def abrir_ruta(ruta):
    if not ruta or not os.path.exists(ruta):
        return False
    try:
        if sys.platform == "win32":
            os.startfile(ruta)  # noqa: S606
        else:
            QDesktopServices.openUrl(QUrl.fromLocalFile(ruta))
        return True
    except OSError:
        return False


def mostrar_en_carpeta(archivo):
    if not archivo or not os.path.exists(archivo):
        return False
    if sys.platform == "win32":
        try:
            subprocess.Popen(["explorer", "/select,", os.path.normpath(archivo)])
            return True
        except OSError:
            pass
    return abrir_ruta(os.path.dirname(archivo))


class Ventana(QWidget):
    def __init__(self, ajustes, historial, gestor):
        super().__init__()
        self.ajustes = ajustes
        self.historial = historial
        self.gestor = gestor
        self.tarjetas = {}
        self._sucias = set()
        self._ultimo_portapapeles = ""

        self.setObjectName("raiz")
        self.setWindowTitle(APP_NOMBRE)
        self.setWindowIcon(QIcon(iconos.icono_app(256)))
        self.setMinimumSize(940, 620)
        self.resize(1120, 760)
        self.setAcceptDrops(True)
        self.setStyleSheet(hoja(iconos.flechas_qss()))

        # ajustes de versiones anteriores: "solo audio" estaba dentro de la calidad
        if self.ajustes["calidad"] == "audio":
            self.ajustes["tipo_descarga"] = "audio"
            self.ajustes["calidad"] = "mejor"
            self.ajustes.guardar()

        self._construir()
        self._conectar()
        self._atajos()
        self._bandeja()

        geo = self.ajustes["geometria"]
        if geo:
            try:
                from PySide6.QtCore import QByteArray
                self.restoreGeometry(QByteArray.fromBase64(geo.encode()))
            except Exception:
                pass

        self.temporizador = QTimer(self)
        self.temporizador.timeout.connect(self._refrescar)
        self.temporizador.start(200)

        # sin sesion guardada, lo primero es la cuenta
        if not (self.ajustes["sesion_token"] or "").strip():
            QTimer.singleShot(0, lambda: self._ir_a(4))

    # ------------------------------------------------------------ estructura
    SECCIONES = [
        ("Descargas", "descargar"),
        ("Biblioteca", "musica"),
        ("Navegador", "globo"),
        ("Historial", "reloj"),
        ("Telefono", "telefono"),
        ("Ajustes", "engranaje"),
    ]

    def _construir(self):
        raiz = QVBoxLayout(self)
        raiz.setContentsMargins(0, 0, 0, 0)
        raiz.setSpacing(0)

        raiz.addWidget(self._cabecera())

        medio = QHBoxLayout()
        medio.setContentsMargins(0, 0, 0, 0)
        medio.setSpacing(0)
        medio.addWidget(self._lateral())

        self.stack = QStackedWidget()
        contenedor = QWidget()
        cl = QVBoxLayout(contenedor)
        cl.setContentsMargins(20, 16, 20, 10)
        cl.addWidget(self.stack)
        medio.addWidget(contenedor, 1)

        marco_medio = QWidget()
        marco_medio.setLayout(medio)
        raiz.addWidget(marco_medio, 1)

        # el orden tiene que coincidir con SECCIONES
        self.vista_biblioteca = VistaBiblioteca(self.historial)
        self.vista_navegador = VistaNavegador()
        self.vista_video = VistaVideo()

        self.stack.addWidget(self._panel_descargas())
        self.stack.addWidget(self.vista_biblioteca)
        self.stack.addWidget(self.vista_navegador)
        self.stack.addWidget(self._panel_historial())
        self.stack.addWidget(self._panel_telefono())
        self.stack.addWidget(self._panel_ajustes())
        self.stack.addWidget(self.vista_video)      # se abre desde la biblioteca

        self.reproductor = Reproductor(self.ajustes)
        raiz.addWidget(self.reproductor)
        raiz.addWidget(self._barra_estado())

        self.vista_biblioteca.reproducir.connect(self.reproductor.reproducir)
        self.vista_biblioteca.ver_video.connect(self._abrir_video)
        self.vista_biblioteca.aviso.connect(self._aviso_breve)
        self.vista_navegador.descargar.connect(self._descargar_del_navegador)
        self.reproductor.pidio_video.connect(self._abrir_video)
        self.reproductor.modo_musica_cambiado.connect(self._aviso_modo_musica)
        self.vista_video.cerrado.connect(lambda: self._ir_a(1))

    def _lateral(self):
        marco = QFrame()
        marco.setObjectName("lateral")
        marco.setFixedWidth(196)
        v = QVBoxLayout(marco)
        v.setContentsMargins(14, 18, 14, 18)
        v.setSpacing(3)

        # la marca tambien vive aqui: da peso a la columna
        marca = QHBoxLayout()
        marca.setSpacing(10)
        logo = QLabel()
        logo.setPixmap(iconos.icono_app(30))
        marca.addWidget(logo)
        nombre = QLabel("Caudal")
        nombre.setStyleSheet("font-size:17px;font-weight:700;letter-spacing:-0.3px;")
        marca.addWidget(nombre)
        marca.addStretch(1)
        contenedor_marca = QWidget()
        contenedor_marca.setLayout(marca)
        v.addWidget(contenedor_marca)
        v.addSpacing(18)

        self.grupo_lateral = QButtonGroup(self)
        self.grupo_lateral.setExclusive(True)
        for indice, (nombre, icono) in enumerate(self.SECCIONES):
            b = QPushButton(f"  {nombre}")
            b.setObjectName("seccion_lateral")
            b.setCheckable(True)
            b.setIcon(iconos.icono(icono, 18))
            b.setCursor(Qt.PointingHandCursor)
            b.clicked.connect(lambda _=False, i=indice: self._ir_a(i))
            self.grupo_lateral.addButton(b, indice)
            v.addWidget(b)
            if nombre in ("Navegador", "Historial"):
                v.addSpacing(10)
        self.grupo_lateral.button(0).setChecked(True)

        v.addStretch(1)
        self.et_pie_lateral = QLabel("")
        self.et_pie_lateral.setObjectName("ayuda")
        self.et_pie_lateral.setWordWrap(True)
        v.addWidget(self.et_pie_lateral)
        return marco

    def _ir_a(self, indice):
        self.stack.setCurrentIndex(indice)
        boton = self.grupo_lateral.button(indice)
        if boton:
            boton.setChecked(True)
        if indice == 1:
            self.vista_biblioteca.refrescar()
        elif indice == 3:
            self._cargar_historial()
        elif indice == 4 and hasattr(self, "panel_caudal"):
            self.panel_caudal.refrescar()

    def _aviso_modo_musica(self, activo):
        from PySide6.QtWidgets import QMessageBox
        if activo:
            QMessageBox.information(
                self, "Modo musica",
                "Encendido.\n\nLo que descargues a partir de ahora se nivela para "
                "que suene mucho mas fuerte, sin que se rompa el sonido.\n\n"
                "Lo ya descargado mantiene su volumen.")

    def _aviso_breve(self, texto):
        """Mensaje corto en la barra de abajo, sin interrumpir."""
        self.et_activas.setText(texto)

    def _abrir_video(self, fila):
        self.vista_video.abrir(fila)
        self.stack.setCurrentWidget(self.vista_video)

    def _descargar_del_navegador(self, url, tipo):
        """Los botones del navegador encolan pidiendo su tipo, sin tocar ajustes."""
        self.gestor.agregar(url, tipo=tipo)
        self._ir_a(0)

    def _cabecera(self):
        marco = QFrame()
        marco.setObjectName("cabecera")
        caja = QVBoxLayout(marco)
        caja.setContentsMargins(22, 16, 22, 16)
        caja.setSpacing(11)

        self.et_ffmpeg = QLabel("")
        self.et_ffmpeg.setObjectName("ayuda")

        fila = QHBoxLayout()
        fila.setSpacing(9)

        self.campo = QLineEdit()
        self.campo.setObjectName("url")
        self.campo.setPlaceholderText(
            "Pega aqui el enlace del video   ·   puedes pegar varios a la vez")
        self.campo.setClearButtonEnabled(True)
        fila.addWidget(self.campo, 1)

        self.bt_pegar = QPushButton()
        self.bt_pegar.setIcon(iconos.icono("pegar", 19))
        self.bt_pegar.setToolTip("Pegar del portapapeles  (Ctrl+V)")
        self.bt_pegar.setFixedSize(44, 44)
        self.bt_pegar.setCursor(Qt.PointingHandCursor)
        fila.addWidget(self.bt_pegar)

        self.bt_descargar = QPushButton("  Descargar")
        self.bt_descargar.setObjectName("principal")
        self.bt_descargar.setIcon(iconos.icono("descargar", 19, "#FFFFFF"))
        self.bt_descargar.setCursor(Qt.PointingHandCursor)
        self.bt_descargar.setFixedHeight(44)
        fila.addWidget(self.bt_descargar)
        caja.addLayout(fila)

        opciones = QHBoxLayout()
        opciones.setSpacing(9)

        self.combo_tipo = QComboBox()
        for etiqueta, valor in TIPOS:
            self.combo_tipo.addItem(etiqueta, valor)
        self._elegir(self.combo_tipo, self.ajustes["tipo_descarga"])
        self.combo_tipo.setFixedWidth(180)
        self.combo_tipo.setToolTip("Que quieres bajar: la imagen con sonido, solo la imagen o solo el sonido")
        opciones.addWidget(self.combo_tipo)

        self.combo_calidad = QComboBox()
        for etiqueta, valor in CALIDADES:
            self.combo_calidad.addItem(etiqueta, valor)
        self._elegir(self.combo_calidad, self.ajustes["calidad"])
        self.combo_calidad.setFixedWidth(190)
        self.combo_calidad.setToolTip("Calidad de la descarga")
        opciones.addWidget(self.combo_calidad)

        self.combo_formato = QComboBox()
        for etiqueta, valor in [("MP4", "mp4"), ("MKV", "mkv"), ("Original", "original")]:
            self.combo_formato.addItem(etiqueta, valor)
        self._elegir(self.combo_formato, self.ajustes["formato_salida"])
        self.combo_formato.setFixedWidth(110)
        self.combo_formato.setToolTip("Contenedor del video final")
        opciones.addWidget(self.combo_formato)

        self.combo_audio = QComboBox()
        for f in ("mp3", "m4a", "opus", "flac", "wav"):
            self.combo_audio.addItem(f.upper(), f)
        self._elegir(self.combo_audio, self.ajustes["formato_audio"])
        self.combo_audio.setFixedWidth(100)
        self.combo_audio.setToolTip("Formato cuando descargas solo audio")
        opciones.addWidget(self.combo_audio)

        self.bt_carpeta = QPushButton()
        self.bt_carpeta.setIcon(iconos.icono("carpeta", 18))
        self.bt_carpeta.setCursor(Qt.PointingHandCursor)
        self.bt_carpeta.setToolTip("Elegir carpeta de destino")
        opciones.addWidget(self.bt_carpeta)

        self.et_carpeta = QLabel("")
        self.et_carpeta.setObjectName("ayuda")
        self.et_carpeta.setCursor(Qt.PointingHandCursor)
        self.et_carpeta.mousePressEvent = lambda e: abrir_ruta(self.ajustes["carpeta"])
        opciones.addWidget(self.et_carpeta, 1)
        opciones.addWidget(self.et_ffmpeg)

        caja.addLayout(opciones)
        self._pintar_carpeta()
        return marco

    def _panel_descargas(self):
        caja_ext = QWidget()
        v = QVBoxLayout(caja_ext)
        v.setContentsMargins(0, 8, 0, 0)
        v.setSpacing(10)

        herramientas = QHBoxLayout()
        herramientas.setSpacing(8)
        self.et_cola = QLabel("Sin descargas")
        self.et_cola.setObjectName("seccion")
        herramientas.addWidget(self.et_cola)
        herramientas.addStretch(1)

        self.bt_pausar_todo = QPushButton("  Pausar todo")
        self.bt_pausar_todo.setIcon(iconos.icono("pausa", 16))
        self.bt_reanudar_todo = QPushButton("  Reanudar")
        self.bt_reanudar_todo.setIcon(iconos.icono("reproducir", 16))
        self.bt_limpiar = QPushButton("  Limpiar terminadas")
        self.bt_limpiar.setIcon(iconos.icono("papelera", 16))
        for b in (self.bt_pausar_todo, self.bt_reanudar_todo, self.bt_limpiar):
            b.setCursor(Qt.PointingHandCursor)
            herramientas.addWidget(b)
        v.addLayout(herramientas)

        self.area = QScrollArea()
        self.area.setObjectName("lienzo")
        self.area.setWidgetResizable(True)
        self.area.viewport().setAutoFillBackground(False)
        self.area.setVerticalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        interior = QWidget()
        self.lista = QVBoxLayout(interior)
        self.lista.setContentsMargins(0, 0, 8, 8)
        self.lista.setSpacing(9)
        self.lista.addStretch(1)
        self.area.setWidget(interior)
        v.addWidget(self.area, 1)

        self.vacio = self._estado_vacio()
        v.addWidget(self.vacio, 1)
        self.area.hide()
        return caja_ext

    def _estado_vacio(self):
        marco = QFrame()
        marco.setObjectName("panel")
        v = QVBoxLayout(marco)
        v.setAlignment(Qt.AlignCenter)
        v.setSpacing(14)

        icono = QLabel()
        icono.setPixmap(iconos.pixmap("descargar", 54, C["texto3"]))
        icono.setAlignment(Qt.AlignCenter)
        v.addWidget(icono)

        t = QLabel("Pega un enlace y empieza a descargar")
        t.setAlignment(Qt.AlignCenter)
        t.setStyleSheet(f"font-size:16px;font-weight:600;color:{C['texto']};")
        v.addWidget(t)

        s = QLabel("Tambien puedes arrastrar enlaces hasta esta ventana o pegar varios de golpe")
        s.setAlignment(Qt.AlignCenter)
        s.setObjectName("ayuda")
        v.addWidget(s)

        chips = QWidget()
        rejilla = QGridLayout(chips)
        rejilla.setSpacing(7)
        rejilla.setContentsMargins(0, 12, 0, 0)
        destacadas = ["youtube", "instagram", "tiktok", "twitter", "facebook", "telegram",
                      "twitch", "reddit", "vimeo", "pinterest", "soundcloud", "threads",
                      "bluesky", "kick", "dailymotion", "linkedin"]
        for i, clave in enumerate(destacadas):
            p = redes.plataforma_por_clave(clave)
            fila_chip = QWidget()
            h = QHBoxLayout(fila_chip)
            h.setContentsMargins(8, 5, 12, 5)
            h.setSpacing(8)
            ic = QLabel()
            ic.setPixmap(iconos.chip_plataforma(p, 20))
            h.addWidget(ic)
            nm = QLabel(p.nombre)
            nm.setObjectName("ayuda")
            h.addWidget(nm)
            h.addStretch(1)
            fila_chip.setStyleSheet(
                f"background:{C['superficie2']};border:1px solid {C['borde']};border-radius:9px;")
            rejilla.addWidget(fila_chip, i // 4, i % 4)
        v.addWidget(chips, 0, Qt.AlignCenter)

        mas = QLabel("y mas de 1000 sitios web compatibles")
        mas.setAlignment(Qt.AlignCenter)
        mas.setObjectName("ayuda")
        v.addWidget(mas)
        return marco

    def _panel_historial(self):
        caja = QWidget()
        v = QVBoxLayout(caja)
        v.setContentsMargins(0, 8, 0, 0)
        v.setSpacing(10)

        fila = QHBoxLayout()
        fila.setSpacing(8)
        self.buscar = QLineEdit()
        self.buscar.setPlaceholderText("Buscar en el historial...")
        self.buscar.setClearButtonEnabled(True)
        fila.addWidget(self.buscar, 1)

        self.bt_abrir_hist = QPushButton("  Abrir archivo")
        self.bt_abrir_hist.setIcon(iconos.icono("abrir", 16))
        self.bt_carpeta_hist = QPushButton("  Ver en carpeta")
        self.bt_carpeta_hist.setIcon(iconos.icono("carpeta", 16))
        self.bt_borrar_hist = QPushButton("  Vaciar historial")
        self.bt_borrar_hist.setIcon(iconos.icono("papelera", 16))
        self.bt_borrar_hist.setObjectName("peligro")
        for b in (self.bt_abrir_hist, self.bt_carpeta_hist, self.bt_borrar_hist):
            b.setCursor(Qt.PointingHandCursor)
            fila.addWidget(b)
        v.addLayout(fila)

        self.tabla = QTableWidget(0, 6)
        self.tabla.setHorizontalHeaderLabels(
            ["Titulo", "Red", "Calidad", "Tamano", "Fecha", "Estado"])
        self.tabla.verticalHeader().setVisible(False)
        self.tabla.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.tabla.setSelectionMode(QAbstractItemView.SingleSelection)
        self.tabla.setEditTriggers(QAbstractItemView.NoEditTriggers)
        self.tabla.setShowGrid(False)
        self.tabla.setAlternatingRowColors(False)
        cab = self.tabla.horizontalHeader()
        cab.setDefaultAlignment(Qt.AlignLeft | Qt.AlignVCenter)
        cab.setSectionResizeMode(0, QHeaderView.Stretch)
        for i in range(1, 6):
            cab.setSectionResizeMode(i, QHeaderView.ResizeToContents)
        v.addWidget(self.tabla, 1)
        return caja

    def _panel_telefono(self):
        """Todo lo de la app del telefono: servidor, cuenta y codigo QR."""
        self.panel_caudal = PanelCaudal(self.ajustes)
        return self.panel_caudal

    def _panel_ajustes(self):
        area = QScrollArea()
        area.setObjectName("lienzo")
        area.setWidgetResizable(True)
        area.viewport().setAutoFillBackground(False)
        caja = QWidget()
        v = QVBoxLayout(caja)
        v.setContentsMargins(0, 8, 8, 8)
        v.setSpacing(12)

        # --- destino y archivos
        p1, g1 = self._panel("DESTINO Y ARCHIVOS")
        self.aj_carpeta = QLineEdit(self.ajustes["carpeta"])
        bt_examinar = QPushButton("Examinar")
        bt_examinar.clicked.connect(self._elegir_carpeta)
        bt_abrir_dest = QPushButton("Abrir")
        bt_abrir_dest.clicked.connect(lambda: abrir_ruta(self.ajustes["carpeta"]))
        fila_c = QHBoxLayout()
        fila_c.addWidget(self.aj_carpeta, 1)
        fila_c.addWidget(bt_examinar)
        fila_c.addWidget(bt_abrir_dest)
        g1.addWidget(QLabel("Carpeta de descargas"), 0, 0)
        cont_c = QWidget()
        cont_c.setLayout(fila_c)
        g1.addWidget(cont_c, 0, 1)

        self.aj_plantilla = QLineEdit(self.ajustes["plantilla_nombre"])
        self.aj_plantilla.setToolTip(
            "Plantilla de yt-dlp. Ejemplos: %(title)s, %(id)s, %(uploader)s, %(ext)s")
        g1.addWidget(QLabel("Nombre del archivo"), 1, 0)
        g1.addWidget(self.aj_plantilla, 1, 1)

        self.aj_subcarpeta = QCheckBox("Crear una subcarpeta por cada red social")
        self.aj_subcarpeta.setChecked(bool(self.ajustes["subcarpeta_por_red"]))
        g1.addWidget(self.aj_subcarpeta, 2, 1)
        v.addWidget(p1)

        # --- descarga
        p2, g2 = self._panel("DESCARGA")
        self.aj_simultaneas = QSpinBox()
        self.aj_simultaneas.setRange(1, 8)
        self.aj_simultaneas.setValue(int(self.ajustes["simultaneas"]))
        g2.addWidget(QLabel("Descargas simultaneas"), 0, 0)
        g2.addWidget(self.aj_simultaneas, 0, 1)

        self.aj_velocidad = QSpinBox()
        self.aj_velocidad.setRange(0, 200000)
        self.aj_velocidad.setSingleStep(256)
        self.aj_velocidad.setSuffix(" KB/s   (0 = sin limite)")
        self.aj_velocidad.setValue(int(self.ajustes["limite_velocidad"]))
        g2.addWidget(QLabel("Limite de velocidad"), 1, 0)
        g2.addWidget(self.aj_velocidad, 1, 1)

        self.aj_reintentos = QSpinBox()
        self.aj_reintentos.setRange(0, 30)
        self.aj_reintentos.setValue(int(self.ajustes["reintentos"]))
        g2.addWidget(QLabel("Reintentos por descarga"), 2, 0)
        g2.addWidget(self.aj_reintentos, 2, 1)

        self.aj_playlist = QCheckBox("Descargar listas y perfiles completos")
        self.aj_playlist.setChecked(bool(self.ajustes["playlist"]))
        g2.addWidget(self.aj_playlist, 3, 1)

        self.aj_limite_lista = QSpinBox()
        self.aj_limite_lista.setRange(1, 5000)
        self.aj_limite_lista.setValue(int(self.ajustes["limite_playlist"]))
        self.aj_limite_lista.setSuffix(" videos como maximo")
        g2.addWidget(QLabel("Tope por lista"), 4, 0)
        g2.addWidget(self.aj_limite_lista, 4, 1)
        v.addWidget(p2)

        # --- extras del archivo
        p3, g3 = self._panel("EXTRAS DEL ARCHIVO")
        self.aj_miniatura = QCheckBox("Incrustar la miniatura como portada")
        self.aj_miniatura.setChecked(bool(self.ajustes["miniatura"]))
        g3.addWidget(self.aj_miniatura, 0, 1)

        self.aj_metadatos = QCheckBox("Guardar titulo, autor y capitulos en el archivo")
        self.aj_metadatos.setChecked(bool(self.ajustes["metadatos"]))
        g3.addWidget(self.aj_metadatos, 1, 1)

        self.aj_subtitulos = QCheckBox("Descargar subtitulos")
        self.aj_subtitulos.setChecked(bool(self.ajustes["subtitulos"]))
        g3.addWidget(self.aj_subtitulos, 2, 1)

        self.aj_idiomas = QLineEdit(self.ajustes["idioma_subtitulos"])
        self.aj_idiomas.setToolTip("Codigos separados por comas: es, en, pt")
        g3.addWidget(QLabel("Idiomas de subtitulos"), 3, 0)
        g3.addWidget(self.aj_idiomas, 3, 1)

        self.aj_incrustar_sub = QCheckBox("Incrustar los subtitulos dentro del video")
        self.aj_incrustar_sub.setChecked(bool(self.ajustes["incrustar_subtitulos"]))
        g3.addWidget(self.aj_incrustar_sub, 4, 1)
        v.addWidget(p3)

        # --- acceso a contenido protegido
        p4, g4 = self._panel("CONTENIDO QUE PIDE INICIAR SESION")
        self.aj_navegador = QComboBox()
        for etiqueta, valor in NAVEGADORES:
            self.aj_navegador.addItem(etiqueta, valor)
        self._elegir(self.aj_navegador, self.ajustes["navegador_cookies"])
        g4.addWidget(QLabel("Usar cookies del navegador"), 0, 0)
        g4.addWidget(self.aj_navegador, 0, 1)

        ayuda = QLabel("Instagram, X o Facebook suelen exigir sesion iniciada. Elige el navegador "
                       "donde ya iniciaste sesion y cierralo antes de descargar.")
        ayuda.setObjectName("ayuda")
        ayuda.setWordWrap(True)
        g4.addWidget(ayuda, 1, 1)

        self.aj_cookies_archivo = QLineEdit(self.ajustes["archivo_cookies"])
        self.aj_cookies_archivo.setPlaceholderText("Opcional: archivo cookies.txt")
        bt_ck = QPushButton("Elegir")
        bt_ck.clicked.connect(self._elegir_cookies)
        fila_ck = QHBoxLayout()
        fila_ck.addWidget(self.aj_cookies_archivo, 1)
        fila_ck.addWidget(bt_ck)
        cont_ck = QWidget()
        cont_ck.setLayout(fila_ck)
        g4.addWidget(QLabel("Archivo de cookies"), 2, 0)
        g4.addWidget(cont_ck, 2, 1)

        self.aj_proxy = QLineEdit(self.ajustes["proxy"])
        self.aj_proxy.setPlaceholderText("Ejemplo: socks5://127.0.0.1:1080")
        g4.addWidget(QLabel("Proxy"), 3, 0)
        g4.addWidget(self.aj_proxy, 3, 1)
        v.addWidget(p4)

        # --- comportamiento
        p5, g5 = self._panel("COMPORTAMIENTO")
        self.aj_portapapeles = QCheckBox("Detectar enlaces copiados y ponerlos en el campo")
        self.aj_portapapeles.setChecked(bool(self.ajustes["vigilar_portapapeles"]))
        g5.addWidget(self.aj_portapapeles, 0, 1)

        self.aj_notificar = QCheckBox("Avisar cuando termine una descarga")
        self.aj_notificar.setChecked(bool(self.ajustes["notificar_al_terminar"]))
        g5.addWidget(self.aj_notificar, 1, 1)

        self.aj_abrir_final = QCheckBox("Abrir la carpeta al terminar")
        self.aj_abrir_final.setChecked(bool(self.ajustes["abrir_al_terminar"]))
        g5.addWidget(self.aj_abrir_final, 2, 1)
        v.addWidget(p5)

        # --- mantenimiento
        p6, g6 = self._panel("MOTOR Y MANTENIMIENTO")
        self.et_motor = QLabel("")
        self.et_motor.setObjectName("ayuda")
        self.et_motor.setWordWrap(True)
        g6.addWidget(self.et_motor, 0, 1)

        fila_m = QHBoxLayout()
        bt_actualizar = QPushButton("  Actualizar motor yt-dlp")
        bt_actualizar.setIcon(iconos.icono("reintentar", 16))
        bt_actualizar.clicked.connect(self._actualizar_motor)
        bt_datos = QPushButton("  Abrir carpeta de datos")
        bt_datos.setIcon(iconos.icono("carpeta", 16))
        bt_datos.clicked.connect(lambda: abrir_ruta(str(carpeta_datos())))
        bt_defecto = QPushButton("  Restaurar valores por defecto")
        bt_defecto.setIcon(iconos.icono("reintentar", 16))
        bt_defecto.clicked.connect(self._restaurar)
        for b in (bt_actualizar, bt_datos, bt_defecto):
            b.setCursor(Qt.PointingHandCursor)
            fila_m.addWidget(b)
        fila_m.addStretch(1)
        cont_m = QWidget()
        cont_m.setLayout(fila_m)
        g6.addWidget(cont_m, 1, 1)
        v.addWidget(p6)

        v.addStretch(1)
        area.setWidget(caja)
        self._pintar_motor()
        return area

    def _panel(self, titulo):
        marco = QFrame()
        marco.setObjectName("panel")
        v = QVBoxLayout(marco)
        v.setContentsMargins(18, 15, 18, 17)
        v.setSpacing(12)
        et = QLabel(titulo)
        et.setObjectName("seccion")
        v.addWidget(et)
        rejilla = QGridLayout()
        rejilla.setColumnStretch(1, 1)
        rejilla.setColumnMinimumWidth(0, 200)
        rejilla.setVerticalSpacing(11)
        rejilla.setHorizontalSpacing(16)
        v.addLayout(rejilla)
        return marco, rejilla

    def _barra_estado(self):
        marco = QFrame()
        marco.setObjectName("barra_estado")
        h = QHBoxLayout(marco)
        h.setContentsMargins(22, 9, 22, 9)
        h.setSpacing(18)

        self.et_activas = QLabel("")
        self.et_activas.setObjectName("estadistica")
        h.addWidget(self.et_activas)

        self.et_velocidad = QLabel("")
        self.et_velocidad.setObjectName("estadistica")
        h.addWidget(self.et_velocidad)

        h.addStretch(1)

        self.et_total = QLabel("")
        self.et_total.setObjectName("estadistica")
        h.addWidget(self.et_total)
        return marco

    # ------------------------------------------------------------ conexiones
    def _conectar(self):
        self.bt_descargar.clicked.connect(self._encolar_campo)
        self.campo.returnPressed.connect(self._encolar_campo)
        self.bt_pegar.clicked.connect(self._pegar)
        self.bt_carpeta.clicked.connect(self._elegir_carpeta)

        self.combo_tipo.currentIndexChanged.connect(self._guardar_rapidos)
        self.combo_calidad.currentIndexChanged.connect(self._guardar_rapidos)
        self.combo_formato.currentIndexChanged.connect(self._guardar_rapidos)
        self.combo_audio.currentIndexChanged.connect(self._guardar_rapidos)

        self.bt_pausar_todo.clicked.connect(self._pausar_todo)
        self.bt_reanudar_todo.clicked.connect(self.gestor.reanudar_todo)
        self.bt_limpiar.clicked.connect(self.gestor.limpiar_terminadas)

        self.gestor.tarea_agregada.connect(self._agregar_tarjeta)
        self.gestor.tarea_cambio.connect(self._marcar_sucia)
        self.gestor.tarea_finalizada.connect(self._al_terminar)
        self.gestor.cola_cambio.connect(self._sincronizar_lista)

        self.buscar.textChanged.connect(self._cargar_historial)
        self.tabla.doubleClicked.connect(self._abrir_historial)
        self.bt_abrir_hist.clicked.connect(self._abrir_historial)
        self.bt_carpeta_hist.clicked.connect(self._carpeta_historial)
        self.bt_borrar_hist.clicked.connect(self._vaciar_historial)


        for w in (self.aj_carpeta, self.aj_plantilla, self.aj_idiomas,
                  self.aj_cookies_archivo, self.aj_proxy):
            w.editingFinished.connect(self._guardar_ajustes)
        for w in (self.aj_simultaneas, self.aj_velocidad, self.aj_reintentos,
                  self.aj_limite_lista):
            w.valueChanged.connect(self._guardar_ajustes)
        for w in (self.aj_subcarpeta, self.aj_playlist, self.aj_miniatura, self.aj_metadatos,
                  self.aj_subtitulos, self.aj_incrustar_sub, self.aj_portapapeles,
                  self.aj_notificar, self.aj_abrir_final):
            w.toggled.connect(self._guardar_ajustes)
        self.aj_navegador.currentIndexChanged.connect(self._guardar_ajustes)

        QGuiApplication.clipboard().dataChanged.connect(self._portapapeles_cambio)

    def _atajos(self):
        QShortcut(QKeySequence("Ctrl+V"), self, activated=self._pegar_y_encolar)
        QShortcut(QKeySequence("Ctrl+L"), self, activated=self.campo.setFocus)
        QShortcut(QKeySequence("Ctrl+O"), self, activated=lambda: abrir_ruta(self.ajustes["carpeta"]))
        QShortcut(QKeySequence("Ctrl+Q"), self, activated=self.close)

    def _bandeja(self):
        self.bandeja = None
        if not QSystemTrayIcon.isSystemTrayAvailable():
            return
        self.bandeja = QSystemTrayIcon(QIcon(iconos.icono_app(64)), self)
        self.bandeja.setToolTip(APP_NOMBRE)
        menu = QMenu()
        act_mostrar = QAction("Mostrar ventana", self)
        act_mostrar.triggered.connect(self._traer_al_frente)
        act_carpeta = QAction("Abrir carpeta de descargas", self)
        act_carpeta.triggered.connect(lambda: abrir_ruta(self.ajustes["carpeta"]))
        act_salir = QAction("Salir", self)
        act_salir.triggered.connect(QApplication.quit)
        menu.addAction(act_mostrar)
        menu.addAction(act_carpeta)
        menu.addSeparator()
        menu.addAction(act_salir)
        self.bandeja.setContextMenu(menu)
        self.bandeja.activated.connect(
            lambda razon: self._traer_al_frente() if razon == QSystemTrayIcon.Trigger else None)
        self.bandeja.show()

    def _traer_al_frente(self):
        self.showNormal()
        self.raise_()
        self.activateWindow()

    # ------------------------------------------------------------ acciones
    def _elegir(self, combo, valor):
        i = combo.findData(valor)
        combo.setCurrentIndex(i if i >= 0 else 0)

    def _encolar_campo(self):
        texto = self.campo.text().strip()
        if not texto:
            self.campo.setFocus()
            return
        urls = redes.extraer_urls(texto)
        if not urls:
            QMessageBox.warning(self, APP_NOMBRE,
                                "No he encontrado ningun enlace valido en lo que pegaste.")
            return
        self.gestor.agregar_varias(urls)
        self.campo.clear()
        self._ir_a(0)

    def _pegar(self):
        texto = QGuiApplication.clipboard().text().strip()
        if texto:
            self.campo.setText(texto)
            self.campo.setFocus()

    def _pegar_y_encolar(self):
        if self.campo.hasFocus():
            self.campo.paste()
            return
        texto = QGuiApplication.clipboard().text().strip()
        if redes.extraer_urls(texto):
            self.campo.setText(texto)
            self._encolar_campo()

    def _portapapeles_cambio(self):
        if not self.ajustes["vigilar_portapapeles"]:
            return
        try:
            texto = QGuiApplication.clipboard().text().strip()
        except RuntimeError:
            return
        if not texto or texto == self._ultimo_portapapeles:
            return
        self._ultimo_portapapeles = texto
        urls = redes.extraer_urls(texto)
        if urls and redes.detectar(urls[0]) is not redes.DESCONOCIDA:
            self.campo.setText(texto)
            self.campo.setFocus()
            self.campo.selectAll()

    def _elegir_carpeta(self):
        carpeta = QFileDialog.getExistingDirectory(
            self, "Elegir carpeta de descargas", self.ajustes["carpeta"])
        if carpeta:
            self.ajustes["carpeta"] = carpeta
            self.aj_carpeta.setText(carpeta)
            self.ajustes.guardar()
            self._pintar_carpeta()

    def _elegir_cookies(self):
        archivo, _ = QFileDialog.getOpenFileName(
            self, "Elegir archivo de cookies", "", "Cookies (*.txt);;Todos (*.*)")
        if archivo:
            self.aj_cookies_archivo.setText(archivo)
            self._guardar_ajustes()

    def _pausar_todo(self):
        for t in self.gestor.lista():
            if t.estado in (motor.DESCARGANDO, motor.EN_COLA, motor.ANALIZANDO):
                self.gestor.pausar(t.ident)

    def _guardar_rapidos(self):
        self.ajustes["tipo_descarga"] = self.combo_tipo.currentData()
        self.ajustes["calidad"] = self.combo_calidad.currentData()
        self.ajustes["formato_salida"] = self.combo_formato.currentData()
        self.ajustes["formato_audio"] = self.combo_audio.currentData()
        self.ajustes.guardar()
        tipo = self.ajustes["tipo_descarga"]
        # la resolucion y el contenedor solo tienen sentido si hay imagen
        self.combo_calidad.setEnabled(tipo != "audio")
        self.combo_formato.setEnabled(tipo != "audio")
        self.combo_audio.setEnabled(tipo == "audio")

    def _guardar_ajustes(self):
        a = self.ajustes
        a["carpeta"] = self.aj_carpeta.text().strip() or DEFECTOS["carpeta"]
        a["plantilla_nombre"] = self.aj_plantilla.text().strip() or DEFECTOS["plantilla_nombre"]
        a["subcarpeta_por_red"] = self.aj_subcarpeta.isChecked()
        a["simultaneas"] = self.aj_simultaneas.value()
        a["limite_velocidad"] = self.aj_velocidad.value()
        a["reintentos"] = self.aj_reintentos.value()
        a["playlist"] = self.aj_playlist.isChecked()
        a["limite_playlist"] = self.aj_limite_lista.value()
        a["miniatura"] = self.aj_miniatura.isChecked()
        a["metadatos"] = self.aj_metadatos.isChecked()
        a["subtitulos"] = self.aj_subtitulos.isChecked()
        a["idioma_subtitulos"] = self.aj_idiomas.text().strip() or "es"
        a["incrustar_subtitulos"] = self.aj_incrustar_sub.isChecked()
        a["navegador_cookies"] = self.aj_navegador.currentData()
        a["archivo_cookies"] = self.aj_cookies_archivo.text().strip()
        a["proxy"] = self.aj_proxy.text().strip()
        a["vigilar_portapapeles"] = self.aj_portapapeles.isChecked()
        a["notificar_al_terminar"] = self.aj_notificar.isChecked()
        a["abrir_al_terminar"] = self.aj_abrir_final.isChecked()
        a.guardar()
        self.gestor.actualizar_simultaneas(a["simultaneas"])
        self.aj_idiomas.setEnabled(a["subtitulos"])
        self.aj_incrustar_sub.setEnabled(a["subtitulos"])
        self.aj_limite_lista.setEnabled(a["playlist"])
        self._pintar_carpeta()

    def _restaurar(self):
        r = QMessageBox.question(self, APP_NOMBRE,
                                 "Se restauraran todos los ajustes a sus valores originales. "
                                 "El historial no se toca. Continuar?")
        if r != QMessageBox.Yes:
            return
        for k, v in DEFECTOS.items():
            if k != "geometria":
                self.ajustes[k] = v
        self.ajustes.guardar()
        QMessageBox.information(self, APP_NOMBRE,
                                "Listo. Cierra y vuelve a abrir la aplicacion para verlos aplicados.")

    def _actualizar_motor(self):
        self.setCursor(Qt.WaitCursor)
        try:
            r = subprocess.run(
                [sys.executable, "-m", "pip", "install", "--upgrade", "yt-dlp"],
                capture_output=True, text=True, timeout=300,
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            ok = r.returncode == 0
        except Exception as e:
            ok, r = False, type("R", (), {"stderr": str(e)})()
        finally:
            self.unsetCursor()
        if ok:
            QMessageBox.information(self, APP_NOMBRE,
                                    "Motor actualizado. Reinicia la aplicacion para usar la "
                                    "version nueva.")
        else:
            QMessageBox.warning(self, APP_NOMBRE,
                                f"No se pudo actualizar:\n{(r.stderr or '')[:400]}")
        self._pintar_motor()

    # ------------------------------------------------------------ lista
    def _agregar_tarjeta(self, ident):
        t = self.gestor.tareas.get(ident)
        if not t or ident in self.tarjetas:
            return
        tarjeta = TarjetaDescarga(t)
        tarjeta.accion_principal.connect(self._accion_principal)
        tarjeta.accion_abrir.connect(lambda i: mostrar_en_carpeta(
            self.gestor.tareas[i].archivo) if i in self.gestor.tareas else None)
        tarjeta.accion_quitar.connect(self.gestor.quitar)
        tarjeta.accion_menu.connect(self._menu_tarjeta)
        self.tarjetas[ident] = tarjeta
        self.lista.insertWidget(self.lista.count() - 1, tarjeta)
        self._alternar_vacio()

    def _accion_principal(self, ident):
        t = self.gestor.tareas.get(ident)
        if not t:
            return
        if t.estado in (motor.DESCARGANDO, motor.EN_COLA, motor.ANALIZANDO):
            self.gestor.pausar(ident)
        elif t.estado in (motor.PAUSADA, motor.ERROR, motor.CANCELADA):
            self.gestor.reanudar(ident)
        elif t.estado == motor.COMPLETADA:
            abrir_ruta(t.archivo)

    def _menu_tarjeta(self, ident, pos):
        t = self.gestor.tareas.get(ident)
        if not t:
            return
        menu = QMenu(self)
        if t.estado == motor.COMPLETADA and t.archivo:
            menu.addAction("Reproducir", lambda: abrir_ruta(t.archivo))
            menu.addAction("Ver en la carpeta", lambda: mostrar_en_carpeta(t.archivo))
            menu.addSeparator()
        if t.estado in (motor.ERROR, motor.CANCELADA, motor.PAUSADA):
            menu.addAction("Reintentar", lambda: self.gestor.reanudar(ident))
        if t.estado in (motor.DESCARGANDO, motor.EN_COLA, motor.ANALIZANDO):
            menu.addAction("Pausar", lambda: self.gestor.pausar(ident))
            menu.addAction("Cancelar", lambda: self.gestor.cancelar(ident))
        menu.addAction("Copiar enlace",
                       lambda: QGuiApplication.clipboard().setText(t.url))
        menu.addAction("Abrir enlace en el navegador", lambda: webbrowser.open(t.url))
        if t.error:
            menu.addSeparator()
            menu.addAction("Ver el detalle del error",
                           lambda: QMessageBox.information(self, "Detalle", t.error))
        menu.addSeparator()
        menu.addAction("Quitar de la lista", lambda: self.gestor.quitar(ident))
        menu.exec(pos)

    def _marcar_sucia(self, ident):
        self._sucias.add(ident)

    def _sincronizar_lista(self):
        for ident in list(self.tarjetas):
            if ident not in self.gestor.tareas:
                tarjeta = self.tarjetas.pop(ident)
                self.lista.removeWidget(tarjeta)
                tarjeta.deleteLater()
        self._alternar_vacio()

    def _alternar_vacio(self):
        hay = bool(self.tarjetas)
        self.area.setVisible(hay)
        self.vacio.setVisible(not hay)

    def _refrescar(self):
        # con la cola parada no hace falta repintar cinco veces por segundo
        activo = bool(self._sucias) or self.gestor.hay_actividad()
        deseado = 200 if activo else 1200
        if self.temporizador.interval() != deseado:
            self.temporizador.setInterval(deseado)

        if self._sucias:
            for ident in list(self._sucias):
                tarjeta = self.tarjetas.get(ident)
                tarea = self.gestor.tareas.get(ident)
                if tarjeta and tarea:
                    tarjeta.actualizar(tarea)
            self._sucias.clear()

        tareas = self.gestor.lista()
        activas = [t for t in tareas if t.activa]
        en_cola = [t for t in tareas if t.estado == motor.EN_COLA]
        hechas = [t for t in tareas if t.estado == motor.COMPLETADA]
        velocidad = sum(t.velocidad or 0 for t in activas)

        if tareas:
            self.et_cola.setText(
                f"{len(tareas)} en la lista  ·  {len(activas)} en marcha  ·  "
                f"{len(hechas)} {'completada' if len(hechas) == 1 else 'completadas'}")
        else:
            self.et_cola.setText("Sin descargas")

        self.et_activas.setText(
            f"{len(activas)} descargando   ·   {len(en_cola)} en cola" if tareas else "Todo tranquilo")
        self.et_velocidad.setText(
            f"{motor.formato_bytes(velocidad)}/s" if velocidad else "")

        est = self.historial.estadisticas()
        self.et_total.setText(
            f"{est['total']} descargas guardadas   ·   {motor.formato_bytes(est['bytes'])} en total")

    def _al_terminar(self, ident, ok):
        t = self.gestor.tareas.get(ident)
        if not t:
            return
        if ok and self.ajustes["notificar_al_terminar"] and self.bandeja:
            self.bandeja.showMessage(
                "Descarga completada", t.titulo[:120],
                QSystemTrayIcon.Information, 4000)
        if ok and self.ajustes["abrir_al_terminar"] and not self.gestor.hay_actividad():
            abrir_ruta(self.ajustes["carpeta"])

    # ------------------------------------------------------------ historial
    def _cargar_historial(self):
        filas = self.historial.listar(500, self.buscar.text().strip())
        self.tabla.setRowCount(len(filas))
        for i, f in enumerate(filas):
            fecha = time.strftime("%d/%m/%Y %H:%M", time.localtime(f["fecha"] or 0))
            estado = "Completada" if f["estado"] == "completada" else "Error"
            valores = [
                f["titulo"] or f["url"],
                f["plataforma"] or "",
                f["calidad"] or "",
                motor.formato_bytes(f["tamano"]) if f["tamano"] else "",
                fecha,
                estado,
            ]
            for j, v in enumerate(valores):
                celda = QTableWidgetItem(str(v))
                if j == 0:
                    celda.setData(Qt.UserRole, f["archivo"] or "")
                    celda.setToolTip(f["url"])
                if j == 5:
                    celda.setForeground(Qt.GlobalColor.green if f["estado"] == "completada"
                                        else Qt.GlobalColor.red)
                self.tabla.setItem(i, j, celda)

    def _archivo_seleccionado(self):
        fila = self.tabla.currentRow()
        if fila < 0:
            return ""
        celda = self.tabla.item(fila, 0)
        return celda.data(Qt.UserRole) if celda else ""

    def _abrir_historial(self):
        archivo = self._archivo_seleccionado()
        if not archivo or not os.path.exists(archivo):
            QMessageBox.information(self, APP_NOMBRE,
                                    "Ese archivo ya no esta en el disco (lo moviste o borraste).")
            return
        abrir_ruta(archivo)

    def _carpeta_historial(self):
        archivo = self._archivo_seleccionado()
        if archivo and os.path.exists(archivo):
            mostrar_en_carpeta(archivo)
        else:
            abrir_ruta(self.ajustes["carpeta"])

    def _vaciar_historial(self):
        r = QMessageBox.question(self, APP_NOMBRE,
                                 "Se borrara la lista del historial. Los videos descargados "
                                 "seguiran en tu carpeta. Continuar?")
        if r == QMessageBox.Yes:
            self.historial.vaciar()
            self._cargar_historial()

    # ------------------------------------------------------------ varios
    def _pintar_carpeta(self):
        ruta = self.ajustes["carpeta"]
        self.et_carpeta.setText(f"Guardando en:  {ruta}")
        self.et_carpeta.setToolTip("Clic para abrir la carpeta")

    def _pintar_motor(self):
        try:
            import yt_dlp
            version = yt_dlp.version.__version__
        except Exception:
            version = "no disponible"
        ff = ruta_ffmpeg()
        self.et_motor.setText(
            f"Motor yt-dlp {version}\n"
            f"ffmpeg: {ff or 'NO ENCONTRADO (hace falta para unir video y audio en alta calidad)'}\n"
            f"Datos y ajustes: {carpeta_datos()}")
        self.et_ffmpeg.setText("" if ff else "sin ffmpeg")
        self.et_ffmpeg.setStyleSheet(f"color:{C['aviso']};" if not ff else "")

    # ------------------------------------------------------------ eventos
    def dragEnterEvent(self, evento):
        datos = evento.mimeData()
        if datos.hasUrls() or datos.hasText():
            evento.acceptProposedAction()

    def dropEvent(self, evento):
        datos = evento.mimeData()
        texto = ""
        if datos.hasUrls():
            texto = " ".join(u.toString() for u in datos.urls())
        elif datos.hasText():
            texto = datos.text()
        urls = redes.extraer_urls(texto)
        if urls:
            self.gestor.agregar_varias(urls)
            self._ir_a(0)
            evento.acceptProposedAction()

    def showEvent(self, evento):
        super().showEvent(evento)
        self._guardar_rapidos()
        self.aj_idiomas.setEnabled(self.ajustes["subtitulos"])
        self.aj_incrustar_sub.setEnabled(self.ajustes["subtitulos"])
        self.aj_limite_lista.setEnabled(self.ajustes["playlist"])

    def closeEvent(self, evento):
        activas = [t for t in self.gestor.lista() if t.activa]
        if activas:
            r = QMessageBox.question(
                self, APP_NOMBRE,
                f"Hay {len(activas)} descarga(s) en marcha. Si sales ahora se detendran "
                "(podras retomarlas mas tarde). Salir igualmente?")
            if r != QMessageBox.Yes:
                evento.ignore()
                return
        self.gestor.cancelar_todo()
        try:
            self.ajustes["geometria"] = bytes(self.saveGeometry().toBase64()).decode()
        except Exception:
            pass
        self.ajustes.guardar()
        if self.bandeja:
            self.bandeja.hide()
        evento.accept()
