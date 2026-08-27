# -*- coding: utf-8 -*-
"""Tarjeta visual de una descarga."""

from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QPainter, QPixmap
from PySide6.QtWidgets import (QFrame, QHBoxLayout, QLabel, QProgressBar,
                               QPushButton, QSizePolicy, QVBoxLayout, QWidget)

from .. import motor
from .estilos import C
from . import iconos


class EtiquetaElidida(QLabel):
    """Etiqueta que recorta el texto con puntos suspensivos segun su ancho."""

    def __init__(self, texto="", padre=None):
        super().__init__(padre)
        self._texto = texto
        self.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Preferred)
        self.setText(texto)

    def definir(self, texto):
        if texto != self._texto:
            self._texto = texto
            self.setToolTip(texto)
            self._pintar()

    def _pintar(self):
        metrica = self.fontMetrics()
        super().setText(metrica.elidedText(self._texto, Qt.ElideRight, max(self.width() - 4, 40)))

    def resizeEvent(self, evento):
        super().resizeEvent(evento)
        self._pintar()


class Miniatura(QLabel):
    """Miniatura con el chip de la red social superpuesto."""

    ANCHO, ALTO = 124, 70

    def __init__(self, padre=None):
        super().__init__(padre)
        self.setFixedSize(self.ANCHO, self.ALTO)
        self._datos = b""
        self._plataforma = None

    def definir(self, datos, plataforma):
        if datos == self._datos and plataforma is self._plataforma:
            return
        self._datos, self._plataforma = datos, plataforma
        base = iconos.miniatura_redondeada(datos, self.ANCHO, self.ALTO)
        if plataforma is not None:
            chip = iconos.chip_plataforma(plataforma, 26)
            p = QPainter(base)
            p.setRenderHint(QPainter.Antialiasing, True)
            p.drawPixmap(6, self.ALTO - 32, chip)
            p.end()
        self.setPixmap(base)


class TarjetaDescarga(QFrame):
    accion_principal = Signal(str)   # pausar / reanudar / reintentar
    accion_abrir = Signal(str)
    accion_quitar = Signal(str)
    accion_menu = Signal(str, object)

    def __init__(self, tarea, padre=None):
        super().__init__(padre)
        self.setObjectName("tarjeta")
        self.ident = tarea.ident
        self._ultimo_estado = None
        self.setContextMenuPolicy(Qt.CustomContextMenu)
        self.customContextMenuRequested.connect(
            lambda pos: self.accion_menu.emit(self.ident, self.mapToGlobal(pos)))

        raiz = QHBoxLayout(self)
        raiz.setContentsMargins(12, 12, 12, 12)
        raiz.setSpacing(14)

        self.miniatura = Miniatura()
        raiz.addWidget(self.miniatura)

        centro = QVBoxLayout()
        centro.setSpacing(6)
        centro.setContentsMargins(0, 2, 0, 2)

        self.titulo = EtiquetaElidida("")
        self.titulo.setObjectName("titulo_tarjeta")
        centro.addWidget(self.titulo)

        self.meta = EtiquetaElidida("")
        self.meta.setObjectName("meta")
        centro.addWidget(self.meta)

        centro.addStretch(1)

        self.barra = QProgressBar()
        self.barra.setTextVisible(False)
        self.barra.setFixedHeight(7)
        centro.addWidget(self.barra)

        self.estado = EtiquetaElidida("")
        self.estado.setObjectName("meta")
        centro.addWidget(self.estado)

        raiz.addLayout(centro, 1)

        botones = QHBoxLayout()
        botones.setSpacing(2)
        botones.setAlignment(Qt.AlignVCenter)

        self.bt_principal = self._boton("pausa", "Pausar")
        self.bt_principal.clicked.connect(lambda: self.accion_principal.emit(self.ident))
        botones.addWidget(self.bt_principal)

        self.bt_abrir = self._boton("carpeta", "Abrir carpeta")
        self.bt_abrir.clicked.connect(lambda: self.accion_abrir.emit(self.ident))
        botones.addWidget(self.bt_abrir)

        self.bt_quitar = self._boton("cerrar", "Quitar de la lista")
        self.bt_quitar.setObjectName("peligro")
        self.bt_quitar.clicked.connect(lambda: self.accion_quitar.emit(self.ident))
        botones.addWidget(self.bt_quitar)

        contenedor = QWidget()
        contenedor.setLayout(botones)
        raiz.addWidget(contenedor, 0, Qt.AlignVCenter)

        self.actualizar(tarea)

    def _boton(self, nombre_icono, ayuda):
        b = QPushButton()
        b.setObjectName("icono")
        b.setIcon(iconos.icono(nombre_icono, 19))
        b.setFixedSize(34, 34)
        b.setToolTip(ayuda)
        b.setCursor(Qt.PointingHandCursor)
        return b

    # ------------------------------------------------------------ pintado
    def actualizar(self, t):
        self.titulo.definir(t.titulo or t.url)
        self.miniatura.definir(t.miniatura_bytes, t.plataforma)

        partes = []
        if t.autor:
            partes.append(t.autor)
        partes.append(t.plataforma.nombre)
        if t.duracion:
            partes.append(motor.formato_tiempo(t.duracion))
        if t.calidad:
            partes.append(t.calidad)
        self.meta.definir("  ·  ".join(partes))

        self._pintar_progreso(t)
        self._pintar_botones(t)

    def _pintar_progreso(self, t):
        e = t.estado
        if e == motor.ANALIZANDO:
            self.barra.setRange(0, 0)
        else:
            self.barra.setRange(0, 100)
            self.barra.setValue(int(t.progreso))

        color = {
            motor.COMPLETADA: C["exito"],
            motor.ERROR: C["error"],
            motor.CANCELADA: C["texto3"],
            motor.PAUSADA: C["aviso"],
            motor.PROCESANDO: C["cian"],
        }.get(e, C["acento"])
        self.barra.setStyleSheet(
            f"QProgressBar {{background:{C['superficie3']};border:none;border-radius:4px;}}"
            f"QProgressBar::chunk {{background:{color};border-radius:4px;}}")

        self.estado.setObjectName("meta")
        if e == motor.DESCARGANDO:
            trozos = [f"{t.progreso:.1f}%"]
            if t.total:
                trozos.append(f"{motor.formato_bytes(t.descargado)} de {motor.formato_bytes(t.total)}")
            elif t.descargado:
                trozos.append(motor.formato_bytes(t.descargado))
            if t.velocidad:
                trozos.append(f"{motor.formato_bytes(t.velocidad)}/s")
            if t.eta:
                trozos.append(f"quedan {motor.formato_tiempo(t.eta)}")
            texto = "  ·  ".join(trozos)
        elif e == motor.ANALIZANDO:
            texto = "Analizando el enlace..."
        elif e == motor.PROCESANDO:
            texto = "Uniendo pistas y aplicando ajustes..."
        elif e == motor.EN_COLA:
            texto = "En cola"
        elif e == motor.PAUSADA:
            texto = f"En pausa  ·  {t.progreso:.0f}% descargado"
        elif e == motor.CANCELADA:
            texto = "Cancelada"
        elif e == motor.COMPLETADA:
            self.estado.setObjectName("estado_ok")
            texto = "Listo"
            if t.total:
                texto += f"  ·  {motor.formato_bytes(t.total)}"
            if t.archivo:
                import os
                texto += f"  ·  {os.path.basename(t.archivo)}"
        elif e == motor.ERROR:
            self.estado.setObjectName("estado_err")
            texto = t.error or "No se pudo descargar"
        else:
            texto = motor.ETIQUETAS.get(e, e)

        if e != motor.ERROR and t.error and e not in (motor.COMPLETADA,):
            texto += f"   ({t.error})"

        self.estado.definir(texto)
        self.estado.style().unpolish(self.estado)
        self.estado.style().polish(self.estado)

    def _pintar_botones(self, t):
        e = t.estado
        if e == self._ultimo_estado:
            return
        self._ultimo_estado = e

        if e in (motor.DESCARGANDO, motor.PROCESANDO, motor.EN_COLA, motor.ANALIZANDO):
            self.bt_principal.setIcon(iconos.icono("pausa", 19))
            self.bt_principal.setToolTip("Pausar")
            self.bt_principal.setEnabled(e != motor.PROCESANDO)
        elif e == motor.PAUSADA:
            self.bt_principal.setIcon(iconos.icono("reproducir", 19, C["exito"]))
            self.bt_principal.setToolTip("Reanudar")
            self.bt_principal.setEnabled(True)
        elif e in (motor.ERROR, motor.CANCELADA):
            self.bt_principal.setIcon(iconos.icono("reintentar", 19, C["acento_alto"]))
            self.bt_principal.setToolTip("Reintentar")
            self.bt_principal.setEnabled(True)
        else:  # completada
            self.bt_principal.setIcon(iconos.icono("reproducir", 19, C["exito"]))
            self.bt_principal.setToolTip("Reproducir archivo")
            self.bt_principal.setEnabled(bool(t.archivo))

        self.bt_abrir.setEnabled(e == motor.COMPLETADA and bool(t.archivo))
