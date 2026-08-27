# -*- coding: utf-8 -*-
"""Reproductor: barra inferior siempre a mano y ventana de video.

Reproduce lo que ya esta en el disco, asi que funciona igual sin internet.
"""

import os
import random

from PySide6.QtCore import Qt, QUrl, Signal
from PySide6.QtGui import QPixmap
from PySide6.QtMultimedia import QAudioOutput, QMediaPlayer
from PySide6.QtMultimediaWidgets import QVideoWidget
from PySide6.QtWidgets import (QFrame, QHBoxLayout, QLabel, QPushButton, QSlider,
                               QVBoxLayout, QWidget)

from .estilos import C
from . import iconos


def _formato(ms):
    s = max(0, int(ms // 1000))
    return f"{s // 60}:{s % 60:02d}"


_CACHE_PORTADAS = {}


def caratula_pixmap(fila, lado=56, radio=8):
    """Portada de un elemento de la biblioteca, o un relleno si no hay.

    Se guarda en memoria: sin esto, cada refresco de la biblioteca volvia a
    leer del disco y a escalar todas las imagenes.
    """
    ruta = (fila or {}).get("caratula") or ""
    clave = (ruta, lado, radio)
    if clave in _CACHE_PORTADAS:
        return _CACHE_PORTADAS[clave]

    datos = b""
    if ruta and os.path.exists(ruta):
        try:
            with open(ruta, "rb") as f:
                datos = f.read()
        except OSError:
            datos = b""

    pm = iconos.miniatura_redondeada(datos, lado, lado, radio)
    if len(_CACHE_PORTADAS) > 400:
        _CACHE_PORTADAS.clear()
    _CACHE_PORTADAS[clave] = pm
    return pm


class Reproductor(QFrame):
    """Barra de reproduccion fija en la parte de abajo."""

    pidio_video = Signal(dict)
    modo_musica_cambiado = Signal(bool)

    def __init__(self, ajustes=None, padre=None):
        super().__init__(padre)
        self.ajustes = ajustes
        self.setObjectName("reproductor")
        self.setFixedHeight(84)

        self.cola = []
        self.indice = -1
        self.aleatorio = False

        self.motor = QMediaPlayer(self)
        self.salida = QAudioOutput(self)
        self.motor.setAudioOutput(self.salida)
        self.salida.setVolume(0.85)
        self.motor.positionChanged.connect(self._al_avanzar)
        self.motor.durationChanged.connect(self._al_durar)
        self.motor.playbackStateChanged.connect(self._al_cambiar_estado)
        self.motor.mediaStatusChanged.connect(self._al_cambiar_medio)

        raiz = QHBoxLayout(self)
        raiz.setContentsMargins(16, 10, 16, 10)
        raiz.setSpacing(16)

        # --- lo que suena
        self.caratula = QLabel()
        self.caratula.setFixedSize(56, 56)
        raiz.addWidget(self.caratula)

        textos = QVBoxLayout()
        textos.setSpacing(2)
        textos.setAlignment(Qt.AlignVCenter)
        self.et_titulo = QLabel("Nada sonando")
        self.et_titulo.setStyleSheet("font-size:13.5px;font-weight:600;")
        textos.addWidget(self.et_titulo)
        self.et_autor = QLabel("")
        self.et_autor.setObjectName("ayuda")
        textos.addWidget(self.et_autor)
        contenedor = QWidget()
        contenedor.setLayout(textos)
        contenedor.setFixedWidth(210)
        raiz.addWidget(contenedor)

        # --- controles y tiempo
        centro = QVBoxLayout()
        centro.setSpacing(4)

        botones = QHBoxLayout()
        botones.setSpacing(6)
        botones.setAlignment(Qt.AlignCenter)

        self.bt_aleatorio = self._boton("aleatorio", "Aleatorio", self._alternar_aleatorio)
        botones.addWidget(self.bt_aleatorio)
        botones.addWidget(self._boton("anterior", "Anterior", self.anterior))
        self.bt_play = QPushButton()
        self.bt_play.setObjectName("play")
        self.bt_play.setFixedSize(40, 40)
        self.bt_play.setCursor(Qt.PointingHandCursor)
        self.bt_play.setIcon(iconos.icono("reproducir", 20, "#04202A"))
        self.bt_play.clicked.connect(self.alternar)
        botones.addWidget(self.bt_play)
        botones.addWidget(self._boton("siguiente", "Siguiente", self.siguiente))
        self.bt_pantalla = self._boton("video", "Ver el video", self._abrir_video)
        botones.addWidget(self.bt_pantalla)
        centro.addLayout(botones)

        tiempo = QHBoxLayout()
        tiempo.setSpacing(9)
        self.et_actual = QLabel("0:00")
        self.et_actual.setObjectName("ayuda")
        tiempo.addWidget(self.et_actual)

        self.barra = QSlider(Qt.Horizontal)
        self.barra.setRange(0, 0)
        self.barra.sliderMoved.connect(self.motor.setPosition)
        tiempo.addWidget(self.barra, 1)

        self.et_total = QLabel("0:00")
        self.et_total.setObjectName("ayuda")
        tiempo.addWidget(self.et_total)
        centro.addLayout(tiempo)

        raiz.addLayout(centro, 1)

        # --- modo musica y volumen
        vol = QHBoxLayout()
        vol.setSpacing(7)

        self.bt_modo = QPushButton()
        self.bt_modo.setObjectName("icono")
        self.bt_modo.setFixedSize(32, 32)
        self.bt_modo.setCheckable(True)
        self.bt_modo.setCursor(Qt.PointingHandCursor)
        self.bt_modo.clicked.connect(self._alternar_modo_musica)
        vol.addWidget(self.bt_modo)

        icono_vol = QLabel()
        icono_vol.setPixmap(iconos.pixmap("musica", 17, C["texto3"]))
        vol.addWidget(icono_vol)
        self.volumen = QSlider(Qt.Horizontal)
        self.volumen.setRange(0, 100)
        self.volumen.setValue(85)
        self.volumen.setFixedWidth(96)
        self.volumen.valueChanged.connect(lambda v: self.salida.setVolume(v / 100))
        vol.addWidget(self.volumen)
        raiz.addLayout(vol)

        self._pintar_vacio()
        self._pintar_modo_musica()

    # ------------------------------------------------------------ modo musica

    def _alternar_modo_musica(self):
        """Que la musica que descargues suene mucho mas fuerte."""
        if self.ajustes is None:
            return
        nuevo = not bool(self.ajustes["modo_musica"])
        self.ajustes["modo_musica"] = nuevo
        self.ajustes.guardar()
        self._pintar_modo_musica()
        self.modo_musica_cambiado.emit(nuevo)

    def _pintar_modo_musica(self):
        activo = bool(self.ajustes["modo_musica"]) if self.ajustes else False
        self.bt_modo.setChecked(activo)
        self.bt_modo.setIcon(
            iconos.icono("altavoz_fuerte" if activo else "altavoz", 17,
                         C["acento"] if activo else C["texto3"]))
        self.bt_modo.setToolTip(
            "Modo musica ENCENDIDO: lo que descargues sonara mas fuerte"
            if activo else
            "Modo musica: nivela el audio para que suene lo mas fuerte posible")

    def _boton(self, icono, ayuda, accion):
        b = QPushButton()
        b.setObjectName("icono")
        b.setIcon(iconos.icono(icono, 17))
        b.setFixedSize(32, 32)
        b.setToolTip(ayuda)
        b.setCursor(Qt.PointingHandCursor)
        b.clicked.connect(accion)
        return b

    # ------------------------------------------------------------ control

    def reproducir(self, lista, desde=0):
        """Pone a sonar una lista de elementos de la biblioteca."""
        validos = [f for f in lista if f.get("archivo") and os.path.exists(f["archivo"])]
        if not validos:
            return
        if 0 <= desde < len(lista):
            elegido = lista[desde]
            desde = next((i for i, f in enumerate(validos)
                          if f.get("id") == elegido.get("id")), 0)
        else:
            desde = 0

        self.cola = validos
        self.indice = desde
        self._cargar()

    def _cargar(self):
        if not (0 <= self.indice < len(self.cola)):
            return
        fila = self.cola[self.indice]
        self.motor.setSource(QUrl.fromLocalFile(fila["archivo"]))
        self.motor.play()
        self._pintar(fila)

    def alternar(self):
        if self.motor.playbackState() == QMediaPlayer.PlayingState:
            self.motor.pause()
        elif self.cola:
            self.motor.play()

    def siguiente(self):
        if not self.cola:
            return
        if self.aleatorio and len(self.cola) > 1:
            nuevo = self.indice
            while nuevo == self.indice:
                nuevo = random.randrange(len(self.cola))
            self.indice = nuevo
        else:
            self.indice = (self.indice + 1) % len(self.cola)
        self._cargar()

    def anterior(self):
        if not self.cola:
            return
        # como en cualquier reproductor: si ya avanzo, vuelve al principio
        if self.motor.position() > 3000:
            self.motor.setPosition(0)
            return
        self.indice = (self.indice - 1) % len(self.cola)
        self._cargar()

    def detener(self):
        self.motor.stop()
        self.cola = []
        self.indice = -1
        self._pintar_vacio()

    def _alternar_aleatorio(self):
        self.aleatorio = not self.aleatorio
        self.bt_aleatorio.setIcon(
            iconos.icono("aleatorio", 17, C["acento"] if self.aleatorio else C["texto3"]))

    def _abrir_video(self):
        if 0 <= self.indice < len(self.cola):
            fila = self.cola[self.indice]
            if not fila.get("es_audio"):
                self.pidio_video.emit(fila)

    @property
    def actual(self):
        if 0 <= self.indice < len(self.cola):
            return self.cola[self.indice]
        return None

    # ------------------------------------------------------------ pintado

    def _pintar(self, fila):
        self.caratula.setPixmap(caratula_pixmap(fila, 56, 9))
        self.et_titulo.setText(fila.get("titulo") or "Sin titulo")
        self.et_autor.setText(fila.get("autor") or fila.get("plataforma") or "")
        self.bt_pantalla.setEnabled(not fila.get("es_audio"))

    def _pintar_vacio(self):
        self.caratula.setPixmap(iconos.miniatura_redondeada(b"", 56, 56, 9))
        self.et_titulo.setText("Nada sonando")
        self.et_autor.setText("Elige algo en tu biblioteca")
        self.bt_pantalla.setEnabled(False)
        self.barra.setRange(0, 0)
        self.et_actual.setText("0:00")
        self.et_total.setText("0:00")

    def _al_avanzar(self, pos):
        if not self.barra.isSliderDown():
            self.barra.setValue(pos)
        self.et_actual.setText(_formato(pos))

    def _al_durar(self, dur):
        self.barra.setRange(0, dur)
        self.et_total.setText(_formato(dur))

    def _al_cambiar_estado(self, estado):
        sonando = estado == QMediaPlayer.PlayingState
        self.bt_play.setIcon(
            iconos.icono("pausa" if sonando else "reproducir", 20, "#04202A"))

    def _al_cambiar_medio(self, estado):
        if estado == QMediaPlayer.EndOfMedia:
            self.siguiente()


class VistaVideo(QWidget):
    """Reproductor de video a pantalla completa dentro de la app."""

    cerrado = Signal()

    def __init__(self, padre=None):
        super().__init__(padre)
        self.motor = QMediaPlayer(self)
        self.salida = QAudioOutput(self)
        self.motor.setAudioOutput(self.salida)
        self.salida.setVolume(0.9)

        self.pantalla = QVideoWidget()
        self.motor.setVideoOutput(self.pantalla)
        self.motor.positionChanged.connect(self._al_avanzar)
        self.motor.durationChanged.connect(lambda d: self.barra.setRange(0, d))

        raiz = QVBoxLayout(self)
        raiz.setContentsMargins(0, 0, 0, 0)
        raiz.setSpacing(0)

        cabecera = QHBoxLayout()
        cabecera.setContentsMargins(12, 10, 12, 10)
        atras = QPushButton("  Volver")
        atras.setObjectName("icono")
        atras.setIcon(iconos.icono("cerrar", 17))
        atras.setCursor(Qt.PointingHandCursor)
        atras.clicked.connect(self._cerrar)
        cabecera.addWidget(atras)
        self.et_titulo = QLabel("")
        self.et_titulo.setStyleSheet("font-size:14px;font-weight:600;")
        cabecera.addWidget(self.et_titulo, 1)
        raiz.addLayout(cabecera)

        raiz.addWidget(self.pantalla, 1)

        pie = QHBoxLayout()
        pie.setContentsMargins(14, 8, 14, 12)
        pie.setSpacing(10)
        self.bt_play = QPushButton()
        self.bt_play.setObjectName("icono")
        self.bt_play.setIcon(iconos.icono("pausa", 19))
        self.bt_play.setCursor(Qt.PointingHandCursor)
        self.bt_play.clicked.connect(self._alternar)
        pie.addWidget(self.bt_play)

        self.et_tiempo = QLabel("0:00")
        self.et_tiempo.setObjectName("ayuda")
        pie.addWidget(self.et_tiempo)

        self.barra = QSlider(Qt.Horizontal)
        self.barra.sliderMoved.connect(self.motor.setPosition)
        pie.addWidget(self.barra, 1)
        raiz.addLayout(pie)

    def abrir(self, fila):
        self.et_titulo.setText(fila.get("titulo") or "")
        self.motor.setSource(QUrl.fromLocalFile(fila["archivo"]))
        self.motor.play()
        self.bt_play.setIcon(iconos.icono("pausa", 19))

    def _alternar(self):
        if self.motor.playbackState() == QMediaPlayer.PlayingState:
            self.motor.pause()
            self.bt_play.setIcon(iconos.icono("reproducir", 19))
        else:
            self.motor.play()
            self.bt_play.setIcon(iconos.icono("pausa", 19))

    def _al_avanzar(self, pos):
        if not self.barra.isSliderDown():
            self.barra.setValue(pos)
        self.et_tiempo.setText(_formato(pos))

    def _cerrar(self):
        self.motor.stop()
        self.cerrado.emit()
