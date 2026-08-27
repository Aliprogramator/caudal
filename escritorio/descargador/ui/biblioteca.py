# -*- coding: utf-8 -*-
"""Biblioteca: lo descargado, con sus portadas, listo para reproducir sin internet."""

import os
import subprocess
import sys

from PySide6.QtCore import Qt, QTimer, Signal
from PySide6.QtWidgets import (QApplication, QFrame, QGridLayout, QHBoxLayout,
                               QInputDialog, QLabel,
                               QLineEdit, QMenu, QMessageBox, QPushButton, QScrollArea,
                               QVBoxLayout, QWidget)

from ..conversion import ErrorConversion, duracion, extraer_audio
from ..motor import formato_bytes, formato_tiempo
from .estilos import C
from . import iconos
from .reproductor import caratula_pixmap

LADO = 152          # lado de cada portada de la cuadricula


class Tarjeta(QFrame):
    """Una portada con su titulo, como en cualquier app de musica."""

    pulsada = Signal(dict)
    menu_pedido = Signal(dict, object)

    def __init__(self, fila, padre=None):
        super().__init__(padre)
        self.fila = fila
        self.setObjectName("tarjeta_album")
        self.setFixedWidth(LADO + 20)
        self.setCursor(Qt.PointingHandCursor)
        self.setContextMenuPolicy(Qt.CustomContextMenu)
        self.customContextMenuRequested.connect(
            lambda pos: self.menu_pedido.emit(self.fila, self.mapToGlobal(pos)))

        v = QVBoxLayout(self)
        v.setContentsMargins(10, 10, 10, 12)
        v.setSpacing(9)

        portada = QLabel()
        portada.setPixmap(caratula_pixmap(fila, LADO, 10))
        portada.setFixedSize(LADO, LADO)
        v.addWidget(portada)

        titulo = QLabel(fila.get("titulo") or "Sin titulo")
        titulo.setWordWrap(True)
        titulo.setStyleSheet("font-size:12.5px;font-weight:600;")
        titulo.setMaximumHeight(34)
        v.addWidget(titulo)

        detalle = []
        if fila.get("autor"):
            detalle.append(fila["autor"])
        elif fila.get("plataforma"):
            detalle.append(fila["plataforma"])
        if fila.get("duracion"):
            detalle.append(formato_tiempo(fila["duracion"]))
        sub = QLabel("  ·  ".join(detalle))
        sub.setObjectName("ayuda")
        v.addWidget(sub)

    def mousePressEvent(self, evento):
        if evento.button() == Qt.LeftButton:
            self.pulsada.emit(self.fila)
        super().mousePressEvent(evento)


class TarjetaLista(QFrame):
    """Una lista propia, con su nombre y cuantas canciones tiene."""

    pulsada = Signal(dict)
    menu_pedido = Signal(dict, object)

    def __init__(self, lista, padre=None):
        super().__init__(padre)
        self.lista = lista
        self.setObjectName("tarjeta_album")
        self.setFixedWidth(LADO + 20)
        self.setCursor(Qt.PointingHandCursor)
        self.setContextMenuPolicy(Qt.CustomContextMenu)
        self.customContextMenuRequested.connect(
            lambda pos: self.menu_pedido.emit(self.lista, self.mapToGlobal(pos)))

        v = QVBoxLayout(self)
        v.setContentsMargins(10, 10, 10, 12)
        v.setSpacing(9)

        portada = QLabel()
        portada.setFixedSize(LADO, LADO)
        portada.setAlignment(Qt.AlignCenter)
        portada.setPixmap(iconos.pixmap("musica", 54, C["acento"]))
        portada.setStyleSheet("background:" + C["superficie2"] + ";border-radius:10px;")
        v.addWidget(portada)

        nombre = QLabel(lista.get("nombre", ""))
        nombre.setWordWrap(True)
        nombre.setStyleSheet("font-size:12.5px;font-weight:600;")
        nombre.setMaximumHeight(34)
        v.addWidget(nombre)

        n = lista.get("n", 0)
        sub = QLabel(str(n) + (" cancion" if n == 1 else " canciones"))
        sub.setObjectName("ayuda")
        v.addWidget(sub)

    def mousePressEvent(self, evento):
        if evento.button() == Qt.LeftButton:
            self.pulsada.emit(self.lista)
        super().mousePressEvent(evento)


class VistaBiblioteca(QWidget):
    """Cuadricula con todo lo guardado."""

    reproducir = Signal(list, int)
    ver_video = Signal(dict)
    aviso = Signal(str)
    traer_lista = Signal()

    def __init__(self, historial, padre=None):
        super().__init__(padre)
        self.historial = historial
        self.filtro = ""
        self.solo = None          # None = todo, True = musica, False = videos
        self.viendo_listas = False
        self.lista_abierta = None      # {id, nombre} cuando entras en una lista
        self.elementos = []
        self._columnas = 0
        self._reordenar = QTimer(self)
        self._reordenar.setSingleShot(True)
        self._reordenar.setInterval(160)
        self._reordenar.timeout.connect(self.refrescar)

        raiz = QVBoxLayout(self)
        raiz.setContentsMargins(0, 0, 0, 0)
        raiz.setSpacing(14)

        raiz.addWidget(self._cabecera())

        self.area = QScrollArea()
        self.area.setObjectName("lienzo")
        self.area.setWidgetResizable(True)
        self.area.viewport().setAutoFillBackground(False)
        interior = QWidget()
        self.rejilla = QGridLayout(interior)
        self.rejilla.setContentsMargins(0, 0, 10, 20)
        self.rejilla.setSpacing(14)
        self.rejilla.setAlignment(Qt.AlignTop | Qt.AlignLeft)
        self.area.setWidget(interior)
        raiz.addWidget(self.area, 1)

        self.vacio = self._panel_vacio()
        raiz.addWidget(self.vacio, 1)

        self.refrescar()

    # ------------------------------------------------------------ interfaz

    def _cabecera(self):
        marco = QWidget()
        v = QVBoxLayout(marco)
        v.setContentsMargins(0, 0, 0, 0)
        v.setSpacing(12)

        fila = QHBoxLayout()
        self.bt_volver = QPushButton()
        self.bt_volver.setObjectName("icono")
        self.bt_volver.setIcon(iconos.icono("atras", 18))
        self.bt_volver.setFixedSize(32, 32)
        self.bt_volver.setToolTip("Volver a mis listas")
        self.bt_volver.setCursor(Qt.PointingHandCursor)
        self.bt_volver.clicked.connect(self._ver_listas)
        self.bt_volver.hide()
        fila.addWidget(self.bt_volver)

        self.et_titulo = QLabel("Tu biblioteca")
        self.et_titulo.setStyleSheet(
            "font-size:23px;font-weight:700;letter-spacing:-0.4px;")
        fila.addWidget(self.et_titulo)
        fila.addStretch(1)

        self.bt_todo = self._filtro("Todo", None)
        self.bt_musica = self._filtro("Musica", True)
        self.bt_videos = self._filtro("Videos", False)
        self.bt_listas = QPushButton("Mis listas")
        self.bt_listas.setObjectName("filtro")
        self.bt_listas.setCheckable(True)
        self.bt_listas.setCursor(Qt.PointingHandCursor)
        self.bt_listas.clicked.connect(self._ver_listas)
        for b in (self.bt_todo, self.bt_musica, self.bt_videos, self.bt_listas):
            fila.addWidget(b)
        v.addLayout(fila)

        fila2 = QHBoxLayout()
        fila2.setSpacing(9)
        self.buscar = QLineEdit()
        self.buscar.setPlaceholderText("Buscar por titulo, artista o lista")
        self.buscar.setClearButtonEnabled(True)
        self.buscar.textChanged.connect(self._al_buscar)
        fila2.addWidget(self.buscar, 1)

        self.bt_reproducir = QPushButton("  Reproducir todo")
        self.bt_reproducir.setObjectName("principal")
        self.bt_reproducir.setIcon(iconos.icono("reproducir", 16, "#04202A"))
        self.bt_reproducir.setCursor(Qt.PointingHandCursor)
        self.bt_reproducir.clicked.connect(
            lambda: self.reproducir.emit(self.elementos, 0) if self.elementos else None)
        fila2.addWidget(self.bt_reproducir)

        self.bt_traer = QPushButton("  Traer lista")
        self.bt_traer.setIcon(iconos.icono("descargar", 16))
        self.bt_traer.setToolTip("Traer una lista de Spotify, Apple Music o YouTube Music")
        self.bt_traer.setCursor(Qt.PointingHandCursor)
        self.bt_traer.clicked.connect(self.traer_lista.emit)
        fila2.addWidget(self.bt_traer)

        self.bt_nueva = QPushButton("  Nueva lista")
        self.bt_nueva.setIcon(iconos.icono("mas", 16))
        self.bt_nueva.setCursor(Qt.PointingHandCursor)
        self.bt_nueva.clicked.connect(self._crear_lista)
        fila2.addWidget(self.bt_nueva)

        bt_carpeta = QPushButton()
        bt_carpeta.setIcon(iconos.icono("carpeta", 17))
        bt_carpeta.setToolTip("Abrir la carpeta de descargas")
        bt_carpeta.setCursor(Qt.PointingHandCursor)
        bt_carpeta.clicked.connect(self._abrir_carpeta)
        fila2.addWidget(bt_carpeta)
        v.addLayout(fila2)

        return marco

    def _filtro(self, texto, valor):
        b = QPushButton(texto)
        b.setCheckable(True)
        b.setObjectName("filtro")
        b.setCursor(Qt.PointingHandCursor)
        b.setChecked(valor is None)
        b.clicked.connect(lambda: self._cambiar_filtro(valor))
        return b

    def _cambiar_filtro(self, valor):
        self.solo = valor
        self.viendo_listas = False
        self.lista_abierta = None
        for b, v in ((self.bt_todo, None), (self.bt_musica, True), (self.bt_videos, False)):
            b.setChecked(v == valor)
        self.bt_listas.setChecked(False)
        self.refrescar()

    def _ver_listas(self):
        self.viendo_listas = True
        self.lista_abierta = None
        for b in (self.bt_todo, self.bt_musica, self.bt_videos):
            b.setChecked(False)
        self.bt_listas.setChecked(True)
        self.refrescar()

    def _crear_lista(self):
        nombre, ok = QInputDialog.getText(self, "Nueva lista", "Nombre de la lista:")
        if not ok:
            return
        try:
            self.historial.crear_lista(nombre)
        except ValueError as e:
            QMessageBox.warning(self, "Caudal", str(e))
            return
        self._ver_listas()

    def _abrir_lista(self, lista):
        self.lista_abierta = lista
        self.refrescar()

    def _menu_lista(self, lista, posicion):
        menu = QMenu(self)
        menu.addAction("Abrir", lambda: self._abrir_lista(lista))
        menu.addAction("Reproducir", lambda: self._reproducir_lista(lista))
        menu.addAction("Cambiar el nombre", lambda: self._renombrar(lista))
        menu.addSeparator()
        menu.addAction("Borrar la lista", lambda: self._borrar_lista(lista))
        menu.exec(posicion)

    def _reproducir_lista(self, lista):
        canciones = self.historial.canciones_de(lista["id"])
        if canciones:
            self.reproducir.emit(canciones, 0)

    def _renombrar(self, lista):
        nombre, ok = QInputDialog.getText(self, "Cambiar el nombre", "Nombre:",
                                          text=lista["nombre"])
        if ok and nombre.strip():
            try:
                self.historial.renombrar_lista(lista["id"], nombre)
            except ValueError as e:
                QMessageBox.warning(self, "Caudal", str(e))
            self.refrescar()

    def _borrar_lista(self, lista):
        aviso = "Se borra la lista. Las canciones NO se borran del disco."
        if QMessageBox.question(self, "Caudal", aviso) == QMessageBox.Yes:
            self.historial.borrar_lista(lista["id"])
            self.lista_abierta = None
            self.refrescar()

    def _anadir_a_lista(self, fila):
        """Anade una cancion a una lista, creandola alli mismo si hace falta."""
        listas = self.historial.listas()
        NUEVA = "+  Crear una lista nueva..."
        opciones = [NUEVA] + [l["nombre"] for l in listas]

        elegido, ok = QInputDialog.getItem(
            self, "Anadir a una lista",
            f"Donde quieres guardar \"{(fila.get('titulo') or '')[:40]}\":",
            opciones, 0, False)
        if not ok or not elegido:
            return

        if elegido == NUEVA:
            nombre, ok2 = QInputDialog.getText(self, "Nueva lista", "Nombre de la lista:")
            if not ok2 or not nombre.strip():
                return
            try:
                lista_id = self.historial.crear_lista(nombre)
            except ValueError as e:
                QMessageBox.warning(self, "Caudal", str(e))
                return
            nombre_final = nombre.strip()
        else:
            elegida = next(l for l in listas if l["nombre"] == elegido)
            lista_id = elegida["id"]
            nombre_final = elegido

        self.historial.agregar_a_lista(lista_id, fila["id"])
        self.aviso.emit(f"Anadido a \"{nombre_final}\"")
        if self.lista_abierta:
            self.refrescar()

    def _extraer_audio(self, fila):
        """Saca el MP3 de un video que ya esta descargado."""
        from ..config import Ajustes
        ajustes = Ajustes()
        self.aviso.emit("Extrayendo el audio...")
        QApplication.setOverrideCursor(Qt.WaitCursor)
        try:
            destino = extraer_audio(
                fila.get("archivo", ""),
                formato=ajustes["formato_audio"],
                reforzar=bool(ajustes["modo_musica"]),
            )
        except ErrorConversion as e:
            QApplication.restoreOverrideCursor()
            QMessageBox.warning(self, "Caudal", str(e))
            self.aviso.emit("")
            return
        finally:
            QApplication.restoreOverrideCursor()

        self.historial.agregar(
            fila.get("url", ""), fila.get("titulo", ""), fila.get("plataforma", ""),
            destino, os.path.getsize(destino), duracion(destino),
            ajustes["formato_audio"].upper(), caratula=fila.get("caratula", ""),
            es_audio=True, autor=fila.get("autor", ""))
        self.aviso.emit("Audio extraido y guardado en tu musica")
        self._cambiar_filtro(True)

    def _quitar_de_lista(self, fila):
        if self.lista_abierta:
            self.historial.quitar_de_lista(self.lista_abierta["id"], fila["id"])
            self.refrescar()

    def _al_buscar(self, texto):
        self.filtro = texto
        self.refrescar()

    def _panel_vacio(self):
        marco = QFrame()
        marco.setObjectName("panel")
        v = QVBoxLayout(marco)
        v.setAlignment(Qt.AlignCenter)
        v.setSpacing(13)

        icono = QLabel()
        icono.setPixmap(iconos.pixmap("musica", 48, C["texto3"]))
        icono.setAlignment(Qt.AlignCenter)
        v.addWidget(icono)

        t = QLabel("Todavia no has descargado nada")
        t.setAlignment(Qt.AlignCenter)
        t.setStyleSheet(f"font-size:16px;font-weight:600;color:{C['texto']};")
        v.addWidget(t)

        s = QLabel("Busca una cancion o pega un enlace, y aparecera aqui\n"
                   "listo para escuchar aunque te quedes sin internet.")
        s.setAlignment(Qt.AlignCenter)
        s.setObjectName("ayuda")
        v.addWidget(s)
        return marco

    # ------------------------------------------------------------ datos

    def refrescar(self):
        self._pintar_cabecera()
        if self.lista_abierta:
            self.elementos = self.historial.canciones_de(
                self.lista_abierta["id"], self.filtro)
        elif self.viendo_listas:
            self.elementos = []
        else:
            self.elementos = self.historial.biblioteca(
                solo_audio=self.solo, filtro=self.filtro)

        while self.rejilla.count():
            item = self.rejilla.takeAt(0)
            if item.widget():
                item.widget().deleteLater()

        if self.viendo_listas and not self.lista_abierta:
            self._pintar_listas()
            return

        hay = bool(self.elementos)
        self.area.setVisible(hay)
        self.vacio.setVisible(not hay)
        self.bt_reproducir.setEnabled(hay)

        if not hay:
            return

        columnas = max(1, (self.width() - 40) // (LADO + 34))
        self._columnas = columnas
        for i, fila in enumerate(self.elementos):
            tarjeta = Tarjeta(fila)
            tarjeta.pulsada.connect(self._al_pulsar)
            tarjeta.menu_pedido.connect(self._menu)
            self.rejilla.addWidget(tarjeta, i // columnas, i % columnas)

    def _pintar_cabecera(self):
        """El titulo dice donde estas: la biblioteca, tus listas o una en concreto."""
        if self.lista_abierta:
            self.et_titulo.setText(self.lista_abierta.get("nombre", "Lista"))
            self.bt_volver.show()
            self.bt_nueva.hide()
        elif self.viendo_listas:
            self.et_titulo.setText("Mis listas")
            self.bt_volver.hide()
            self.bt_nueva.show()
        else:
            self.et_titulo.setText("Tu biblioteca")
            self.bt_volver.hide()
            self.bt_nueva.show()

    def _pintar_listas(self):
        listas = self.historial.listas(self.filtro)
        self.area.setVisible(bool(listas))
        self.vacio.setVisible(not listas)
        self.bt_reproducir.setEnabled(False)
        if not listas:
            return

        columnas = max(1, (self.width() - 40) // (LADO + 34))
        for i, lista in enumerate(listas):
            tarjeta = TarjetaLista(lista)
            tarjeta.pulsada.connect(self._abrir_lista)
            tarjeta.menu_pedido.connect(self._menu_lista)
            self.rejilla.addWidget(tarjeta, i // columnas, i % columnas)

    def resizeEvent(self, evento):
        super().resizeEvent(evento)
        # rehacer las tarjetas en cada pixel de arrastre se comia la CPU:
        # solo se rehace cuando cambia el numero de columnas, y con un respiro
        nuevas = max(1, (self.width() - 40) // (LADO + 34))
        if nuevas != self._columnas:
            self._columnas = nuevas
            self._reordenar.start()

    def _al_pulsar(self, fila):
        indice = next((i for i, f in enumerate(self.elementos)
                       if f.get("id") == fila.get("id")), 0)
        if fila.get("es_audio"):
            self.reproducir.emit(self.elementos, indice)
        else:
            self.ver_video.emit(fila)

    def _menu(self, fila, posicion):
        menu = QMenu(self)
        menu.addAction("Reproducir", lambda: self._al_pulsar(fila))
        menu.addAction("Anadir a una lista", lambda: self._anadir_a_lista(fila))
        if not fila.get("es_audio"):
            menu.addAction("Extraer el audio (MP3)", lambda: self._extraer_audio(fila))
        if self.lista_abierta:
            menu.addAction("Quitar de esta lista", lambda: self._quitar_de_lista(fila))
        menu.addAction("Ver en la carpeta", lambda: self._mostrar(fila))
        menu.addAction("Abrir con otra app", lambda: self._abrir_fuera(fila))
        menu.addSeparator()
        menu.addAction("Borrar del disco", lambda: self._borrar(fila))
        menu.exec(posicion)

    def _mostrar(self, fila):
        archivo = fila.get("archivo") or ""
        if archivo and os.path.exists(archivo):
            subprocess.Popen(["explorer", "/select,", os.path.normpath(archivo)])

    def _abrir_fuera(self, fila):
        archivo = fila.get("archivo") or ""
        if archivo and os.path.exists(archivo):
            try:
                os.startfile(archivo)  # noqa: S606
            except OSError:
                pass

    def _abrir_carpeta(self):
        from ..config import Ajustes
        carpeta = Ajustes()["carpeta"]
        if os.path.isdir(carpeta):
            os.startfile(carpeta)  # noqa: S606

    def _borrar(self, fila):
        r = QMessageBox.question(
            self, "Caudal",
            f"Se borrara del disco:\n\n{fila.get('titulo','')}\n\nNo se puede deshacer.")
        if r != QMessageBox.Yes:
            return
        archivo = fila.get("archivo") or ""
        if archivo and os.path.exists(archivo):
            try:
                os.remove(archivo)
            except OSError:
                QMessageBox.warning(self, "Caudal",
                                    "No se pudo borrar: puede estar sonando ahora mismo.")
                return
        self.historial.borrar(fila.get("id"))
        self.refrescar()
