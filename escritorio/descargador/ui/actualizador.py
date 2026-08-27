# -*- coding: utf-8 -*-
"""Avisar de versiones nuevas y instalarlas sin que el usuario busque nada."""

from PySide6.QtCore import QThread, Qt, Signal
from PySide6.QtWidgets import (QDialog, QHBoxLayout, QLabel, QProgressBar,
                               QPushButton, QTextEdit, QVBoxLayout)

from .. import version
from . import iconos


class Buscador(QThread):
    """Pregunta a GitHub si hay algo nuevo. Nunca molesta si no lo hay."""

    resultado = Signal(object)      # dict con la novedad, o None

    def run(self):
        try:
            self.resultado.emit(version.buscar_actualizacion())
        except Exception:
            self.resultado.emit(None)


class Descarga(QThread):
    progreso = Signal(int)
    listo = Signal(str)
    fallo = Signal(str)

    def __init__(self, url):
        super().__init__()
        self.url = url

    def run(self):
        try:
            ruta = version.descargar(self.url, lambda p: self.progreso.emit(int(p)))
            self.listo.emit(ruta)
        except Exception as e:
            self.fallo.emit(f"No se pudo bajar la actualizacion: {str(e)[:110]}")


class DialogoActualizacion(QDialog):
    """Cuenta que hay version nueva y la instala si el usuario quiere."""

    def __init__(self, novedad, padre=None):
        super().__init__(padre)
        self.novedad = novedad
        self.descarga = None

        self.setWindowTitle("Hay una version nueva")
        self.setMinimumWidth(520)

        v = QVBoxLayout(self)
        v.setContentsMargins(24, 22, 24, 18)
        v.setSpacing(13)

        titulo = QLabel(f"Caudal {novedad['version']} ya esta lista")
        titulo.setStyleSheet("font-size:19px;font-weight:700;letter-spacing:-0.3px;")
        v.addWidget(titulo)

        sub = QLabel(f"Tienes la {version.VERSION}. La nueva se instala encima "
                     "y conserva tus descargas y ajustes.")
        sub.setObjectName("ayuda")
        sub.setWordWrap(True)
        v.addWidget(sub)

        if novedad.get("notas"):
            notas = QTextEdit()
            notas.setReadOnly(True)
            notas.setPlainText(novedad["notas"][:2000])
            notas.setFixedHeight(150)
            v.addWidget(notas)

        self.barra = QProgressBar()
        self.barra.setRange(0, 100)
        self.barra.setFixedHeight(6)
        self.barra.setTextVisible(False)
        self.barra.hide()
        v.addWidget(self.barra)

        self.et_estado = QLabel("")
        self.et_estado.setObjectName("ayuda")
        v.addWidget(self.et_estado)

        fila = QHBoxLayout()
        fila.addStretch(1)
        self.bt_luego = QPushButton("Mas tarde")
        self.bt_luego.clicked.connect(self.reject)
        fila.addWidget(self.bt_luego)

        self.bt_instalar = QPushButton("  Instalar ahora")
        self.bt_instalar.setObjectName("principal")
        self.bt_instalar.setIcon(iconos.icono("descargar", 16, "#04202A"))
        self.bt_instalar.setCursor(Qt.PointingHandCursor)
        self.bt_instalar.clicked.connect(self._instalar)
        fila.addWidget(self.bt_instalar)
        v.addLayout(fila)

        if not novedad.get("instalador"):
            self.bt_instalar.setEnabled(False)
            self.et_estado.setText(
                "Esta version no trae instalador adjunto. Bajala desde la pagina "
                "del proyecto.")

    def _instalar(self):
        self.bt_instalar.setEnabled(False)
        self.bt_luego.setEnabled(False)
        self.barra.show()
        self.et_estado.setText("Bajando la actualizacion...")

        self.descarga = Descarga(self.novedad["instalador"])
        self.descarga.progreso.connect(self.barra.setValue)
        self.descarga.listo.connect(self._lanzar)
        self.descarga.fallo.connect(self._fallo)
        self.descarga.start()

    def _lanzar(self, ruta):
        self.et_estado.setText("Instalando. Caudal se cerrara un momento...")
        version.instalar_y_salir(ruta)

    def _fallo(self, mensaje):
        self.barra.hide()
        self.bt_instalar.setEnabled(True)
        self.bt_luego.setEnabled(True)
        self.et_estado.setText(mensaje)
