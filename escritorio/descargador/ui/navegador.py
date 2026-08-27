# -*- coding: utf-8 -*-
"""Navegador integrado: entra a cualquier web y baja lo que estes viendo."""

from PySide6.QtCore import QUrl, Qt, Signal
from PySide6.QtWebEngineCore import QWebEngineSettings
from PySide6.QtWebEngineWidgets import QWebEngineView
from PySide6.QtWidgets import (QFrame, QGridLayout, QHBoxLayout, QLabel, QLineEdit,
                               QProgressBar, QPushButton, QVBoxLayout, QWidget)

from .. import redes
from .estilos import C
from . import iconos

SUGERIDOS = [
    ("YouTube", "https://www.youtube.com", "youtube"),
    ("YouTube Music", "https://music.youtube.com", "ytmusic"),
    ("Instagram", "https://www.instagram.com", "instagram"),
    ("TikTok", "https://www.tiktok.com", "tiktok"),
    ("X", "https://x.com", "twitter"),
    ("Facebook", "https://www.facebook.com", "facebook"),
    ("SoundCloud", "https://soundcloud.com", "soundcloud"),
    ("Twitch", "https://www.twitch.tv", "twitch"),
]


class VistaNavegador(QWidget):
    """Navegador con los botones de descarga que aparecen solos."""

    descargar = Signal(str, str)     # url, tipo (completo | audio)

    def __init__(self, padre=None):
        super().__init__(padre)
        self.url_actual = ""

        raiz = QVBoxLayout(self)
        raiz.setContentsMargins(0, 0, 0, 0)
        raiz.setSpacing(0)

        raiz.addWidget(self._barra())

        self.progreso = QProgressBar()
        self.progreso.setFixedHeight(3)
        self.progreso.setTextVisible(False)
        self.progreso.hide()
        raiz.addWidget(self.progreso)

        self.web = QWebEngineView()
        ajustes = self.web.settings()
        ajustes.setAttribute(QWebEngineSettings.PluginsEnabled, True)
        ajustes.setAttribute(QWebEngineSettings.FullScreenSupportEnabled, True)
        ajustes.setAttribute(QWebEngineSettings.PlaybackRequiresUserGesture, False)
        self.web.urlChanged.connect(self._al_cambiar_url)
        self.web.loadProgress.connect(self._al_progresar)
        self.web.loadFinished.connect(lambda _: self.progreso.hide())
        raiz.addWidget(self.web, 1)

        self.barra_descarga = self._barra_descarga()
        raiz.addWidget(self.barra_descarga)
        self.barra_descarga.hide()

        self.portada = self._portada()
        raiz.addWidget(self.portada, 1)
        self.web.hide()

    # ------------------------------------------------------------ interfaz

    def _barra(self):
        marco = QFrame()
        marco.setObjectName("cabecera_nav")
        h = QHBoxLayout(marco)
        h.setContentsMargins(12, 10, 12, 10)
        h.setSpacing(7)

        for icono, ayuda, accion in (
            ("atras", "Atras", lambda: self.web.back()),
            ("adelante", "Adelante", lambda: self.web.forward()),
            ("casa", "Inicio", self.ir_al_inicio),
        ):
            b = QPushButton()
            b.setObjectName("icono")
            b.setIcon(iconos.icono(icono, 17))
            b.setFixedSize(32, 32)
            b.setToolTip(ayuda)
            b.setCursor(Qt.PointingHandCursor)
            b.clicked.connect(accion)
            h.addWidget(b)

        self.campo = QLineEdit()
        self.campo.setPlaceholderText("Busca en YouTube o escribe una direccion")
        self.campo.returnPressed.connect(lambda: self.ir(self.campo.text()))
        h.addWidget(self.campo, 1)

        b = QPushButton()
        b.setObjectName("icono")
        b.setIcon(iconos.icono("reintentar", 17))
        b.setFixedSize(32, 32)
        b.setToolTip("Recargar")
        b.setCursor(Qt.PointingHandCursor)
        b.clicked.connect(lambda: self.web.reload())
        h.addWidget(b)

        return marco

    def _barra_descarga(self):
        marco = QFrame()
        marco.setObjectName("barra_descarga")
        h = QHBoxLayout(marco)
        h.setContentsMargins(16, 11, 16, 11)
        h.setSpacing(12)

        icono = QLabel()
        icono.setPixmap(iconos.pixmap("video", 20, C["acento"]))
        h.addWidget(icono)

        self.et_detectado = QLabel("Se puede descargar lo que estas viendo")
        self.et_detectado.setStyleSheet("font-size:13px;font-weight:600;")
        h.addWidget(self.et_detectado, 1)

        bt_video = QPushButton("  Descargar video")
        bt_video.setObjectName("principal")
        bt_video.setIcon(iconos.icono("descargar", 16, "#04202A"))
        bt_video.setCursor(Qt.PointingHandCursor)
        bt_video.clicked.connect(lambda: self.descargar.emit(self.url_actual, "completo"))
        h.addWidget(bt_video)

        bt_audio = QPushButton("  Solo audio")
        bt_audio.setIcon(iconos.icono("musica", 16))
        bt_audio.setCursor(Qt.PointingHandCursor)
        bt_audio.clicked.connect(lambda: self.descargar.emit(self.url_actual, "audio"))
        h.addWidget(bt_audio)

        return marco

    def _portada(self):
        marco = QWidget()
        v = QVBoxLayout(marco)
        v.setAlignment(Qt.AlignCenter)
        v.setSpacing(16)

        t = QLabel("Navega y descarga")
        t.setAlignment(Qt.AlignCenter)
        t.setStyleSheet("font-size:22px;font-weight:700;letter-spacing:-0.4px;")
        v.addWidget(t)

        s = QLabel("Entra donde quieras. Cuando abras un video, abajo apareceran\n"
                   "los botones para bajarlo en video o solo el audio.")
        s.setAlignment(Qt.AlignCenter)
        s.setObjectName("ayuda")
        v.addWidget(s)

        rejilla = QWidget()
        rejilla.setMaximumWidth(560)
        g = QGridLayout(rejilla)
        g.setSpacing(11)
        for i, (nombre, url, clave) in enumerate(SUGERIDOS):
            b = QPushButton(f"  {nombre}")
            b.setObjectName("acceso_web")
            b.setIcon(iconos.icono_plataforma(clave, 22))
            b.setIconSize(b.iconSize() * 1.25)
            b.setMinimumHeight(58)
            b.setCursor(Qt.PointingHandCursor)
            b.clicked.connect(lambda _=False, u=url: self.ir(u))
            g.addWidget(b, i // 4, i % 4)
        v.addWidget(rejilla, 0, Qt.AlignCenter)

        return marco

    # ------------------------------------------------------------ navegacion

    def ir(self, texto):
        texto = (texto or "").strip()
        if not texto:
            return
        if redes.es_url(texto):
            url = redes.normalizar(texto)
        else:
            # lo que no es una direccion se busca directamente en YouTube
            consulta = QUrl.toPercentEncoding(texto).data().decode()
            url = f"https://www.youtube.com/results?search_query={consulta}"
        self.portada.hide()
        self.web.show()
        self.web.setUrl(QUrl(url))

    def ir_al_inicio(self):
        self.web.hide()
        self.barra_descarga.hide()
        self.portada.show()
        self.campo.clear()
        self.url_actual = ""

    def _al_cambiar_url(self, url):
        self.url_actual = url.toString()
        self.campo.setText(self.url_actual)
        self._revisar_descargable()

    def _al_progresar(self, valor):
        self.progreso.setValue(valor)
        self.progreso.setVisible(0 < valor < 100)

    def _revisar_descargable(self):
        sirve = redes.parece_descargable(self.url_actual)
        self.barra_descarga.setVisible(sirve and self.web.isVisible())
        if sirve:
            plataforma = redes.detectar(self.url_actual)
            self.et_detectado.setText(
                f"Listo para descargar  ·  {plataforma.nombre}")
