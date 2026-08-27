# -*- coding: utf-8 -*-
"""Traer una lista de Spotify, Apple Music o YouTube Music y descargarla."""

from PySide6.QtCore import Qt, QThread, Signal
from PySide6.QtWidgets import (QAbstractItemView, QApplication, QCheckBox, QDialog,
                               QHBoxLayout, QLabel, QLineEdit, QListWidget,
                               QListWidgetItem, QProgressBar, QPushButton, QVBoxLayout)

from .. import listas
from ..motor import formato_tiempo
from .estilos import C
from . import iconos


class Lector(QThread):
    listo = Signal(dict)
    fallo = Signal(str)

    def __init__(self, url, ajustes):
        super().__init__()
        self.url = url
        self.ajustes = ajustes

    def run(self):
        try:
            self.listo.emit(listas.leer(self.url, self.ajustes))
        except listas.ErrorLista as e:
            self.fallo.emit(str(e))
        except Exception as e:
            self.fallo.emit(f"No se pudo leer la lista: {str(e)[:90]}")


class DialogoListas(QDialog):
    """Pega un enlace, elige las canciones y se van a la cola de descargas."""

    descargar = Signal(list)      # [{titulo, artista, url|busqueda}]

    def __init__(self, ajustes, padre=None):
        super().__init__(padre)
        self.ajustes = ajustes
        self.lector = None
        self.lista = None

        self.setWindowTitle("Traer una lista")
        self.setMinimumSize(620, 560)

        raiz = QVBoxLayout(self)
        raiz.setContentsMargins(22, 20, 22, 18)
        raiz.setSpacing(14)

        titulo = QLabel("Traer una lista")
        titulo.setStyleSheet("font-size:19px;font-weight:700;letter-spacing:-0.3px;")
        raiz.addWidget(titulo)

        ayuda = QLabel("Pega el enlace de una lista o un album publico. Se leen sus "
                       "canciones y se descargan en audio.")
        ayuda.setObjectName("ayuda")
        ayuda.setWordWrap(True)
        raiz.addWidget(ayuda)

        fila = QHBoxLayout()
        fila.setSpacing(8)
        self.campo = QLineEdit()
        self.campo.setPlaceholderText("Enlace de Spotify, Apple Music o YouTube Music")
        self.campo.returnPressed.connect(self._leer)
        fila.addWidget(self.campo, 1)

        self.bt_pegar = QPushButton()
        self.bt_pegar.setIcon(iconos.icono("pegar", 17))
        self.bt_pegar.setToolTip("Pegar")
        self.bt_pegar.setCursor(Qt.PointingHandCursor)
        self.bt_pegar.clicked.connect(self._pegar)
        fila.addWidget(self.bt_pegar)

        self.bt_leer = QPushButton("  Leer")
        self.bt_leer.setObjectName("principal")
        self.bt_leer.setIcon(iconos.icono("lupa", 16, "#04202A"))
        self.bt_leer.setCursor(Qt.PointingHandCursor)
        self.bt_leer.clicked.connect(self._leer)
        fila.addWidget(self.bt_leer)
        raiz.addLayout(fila)

        self.barra = QProgressBar()
        self.barra.setRange(0, 0)
        self.barra.setFixedHeight(4)
        self.barra.hide()
        raiz.addWidget(self.barra)

        self.et_estado = QLabel("")
        self.et_estado.setObjectName("ayuda")
        self.et_estado.setWordWrap(True)
        raiz.addWidget(self.et_estado)

        self.canciones = QListWidget()
        self.canciones.setSelectionMode(QAbstractItemView.NoSelection)
        self.canciones.setAlternatingRowColors(False)
        raiz.addWidget(self.canciones, 1)

        fila2 = QHBoxLayout()
        self.casilla_todas = QCheckBox("Marcar todas")
        self.casilla_todas.setChecked(True)
        self.casilla_todas.toggled.connect(self._marcar_todas)
        self.casilla_todas.setEnabled(False)
        fila2.addWidget(self.casilla_todas)
        fila2.addStretch(1)

        self.bt_cancelar = QPushButton("Cerrar")
        self.bt_cancelar.clicked.connect(self.reject)
        fila2.addWidget(self.bt_cancelar)

        self.bt_descargar = QPushButton("  Descargar")
        self.bt_descargar.setObjectName("principal")
        self.bt_descargar.setIcon(iconos.icono("descargar", 16, "#04202A"))
        self.bt_descargar.setCursor(Qt.PointingHandCursor)
        self.bt_descargar.setEnabled(False)
        self.bt_descargar.clicked.connect(self._descargar)
        fila2.addWidget(self.bt_descargar)
        raiz.addLayout(fila2)

    # ------------------------------------------------------------ leer

    def _pegar(self):
        texto = QApplication.clipboard().text().strip()
        if texto:
            self.campo.setText(texto)
            self._leer()

    def _leer(self):
        url = self.campo.text().strip()
        if not url:
            return
        self.bt_leer.setEnabled(False)
        self.barra.show()
        self.et_estado.setText("Leyendo la lista...")
        self.canciones.clear()
        self.bt_descargar.setEnabled(False)
        self.casilla_todas.setEnabled(False)

        self.lector = Lector(url, self.ajustes)
        self.lector.listo.connect(self._pintar)
        self.lector.fallo.connect(self._fallo)
        self.lector.start()

    def _pintar(self, datos):
        self.lista = datos
        self.barra.hide()
        self.bt_leer.setEnabled(True)

        resumen = f"{datos['plataforma']}  ·  {datos['titulo']}  ·  {datos['total']} canciones"
        if datos.get("aviso"):
            resumen += f"\n{datos['aviso']}"
        self.et_estado.setText(resumen)

        for c in datos["canciones"]:
            partes = [c.get("artista", "")]
            if c.get("duracion"):
                partes.append(formato_tiempo(c["duracion"]))
            detalle = "  ·  ".join(x for x in partes if x)
            item = QListWidgetItem(f"{c['titulo']}\n{detalle}" if detalle else c["titulo"])
            item.setFlags(item.flags() | Qt.ItemIsUserCheckable)
            item.setCheckState(Qt.Checked)
            self.canciones.addItem(item)

        hay = datos["total"] > 0
        self.bt_descargar.setEnabled(hay)
        self.casilla_todas.setEnabled(hay)
        self.casilla_todas.setChecked(True)
        self._actualizar_boton()
        self.canciones.itemChanged.connect(self._actualizar_boton)

    def _fallo(self, mensaje):
        self.barra.hide()
        self.bt_leer.setEnabled(True)
        self.et_estado.setText(mensaje)
        self.et_estado.setStyleSheet(f"color:{C['error']};font-size:11px;")

    # ------------------------------------------------------------ elegir

    def _marcar_todas(self, valor):
        estado = Qt.Checked if valor else Qt.Unchecked
        for i in range(self.canciones.count()):
            self.canciones.item(i).setCheckState(estado)

    def _elegidas(self):
        if not self.lista:
            return []
        salida = []
        for i in range(self.canciones.count()):
            if self.canciones.item(i).checkState() == Qt.Checked:
                salida.append(self.lista["canciones"][i])
        return salida

    def _actualizar_boton(self, *_):
        n = len(self._elegidas())
        self.bt_descargar.setText(
            f"  Descargar {n}" if n else "  Descargar")
        self.bt_descargar.setEnabled(n > 0)

    def _descargar(self):
        elegidas = self._elegidas()
        if elegidas:
            self.descargar.emit(elegidas)
            self.accept()
