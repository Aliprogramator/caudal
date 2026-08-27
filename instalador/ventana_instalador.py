# -*- coding: utf-8 -*-
"""Ventana del instalador de Caudal."""

import os
import subprocess
import sys

from PySide6.QtCore import Qt, QThread, Signal
from PySide6.QtGui import QColor, QPainter, QPainterPath, QPen, QPixmap
from PySide6.QtWidgets import (QApplication, QCheckBox, QFileDialog, QFrame,
                               QHBoxLayout, QLabel, QLineEdit, QProgressBar,
                               QPushButton, QVBoxLayout, QWidget)

import instalador

FONDO = "#0B0E14"
SUPERFICIE = "#141922"
SUPERFICIE2 = "#1C2230"
BORDE = "#232A36"
TEXTO = "#E8EBF1"
TEXTO2 = "#A8B2C4"
TEXTO3 = "#7C879B"
ACENTO = "#22D3EE"


def gota(tam=56):
    """El icono de la marca, dibujado sin depender de archivos."""
    pm = QPixmap(tam, tam)
    pm.fill(Qt.transparent)
    p = QPainter(pm)
    p.setRenderHint(QPainter.Antialiasing, True)
    p.setPen(Qt.NoPen)
    p.setBrush(QColor(ACENTO))
    p.drawRoundedRect(0, 0, tam, tam, tam * 0.24, tam * 0.24)

    e = tam / 64.0
    lapiz = QPen(QColor("#04202A"))
    lapiz.setWidthF(5.4 * e)
    lapiz.setCapStyle(Qt.RoundCap)
    lapiz.setJoinStyle(Qt.RoundJoin)
    p.setPen(lapiz)
    p.setBrush(Qt.NoBrush)
    from PySide6.QtCore import QPointF
    p.drawLine(QPointF(32 * e, 14 * e), QPointF(32 * e, 38 * e))
    p.drawPolyline([QPointF(21 * e, 28 * e), QPointF(32 * e, 39.5 * e),
                    QPointF(43 * e, 28 * e)])
    p.drawLine(QPointF(18 * e, 48 * e), QPointF(46 * e, 48 * e))
    p.end()
    return pm


class Trabajo(QThread):
    avance = Signal(float, str)
    terminado = Signal(str)
    fallo = Signal(str)

    def __init__(self, carpeta, con_escritorio):
        super().__init__()
        self.carpeta = carpeta
        self.con_escritorio = con_escritorio

    def run(self):
        try:
            ruta = instalador.instalar(
                self.carpeta,
                al_progresar=lambda p, t: self.avance.emit(p, t),
                crear_escritorio=self.con_escritorio,
            )
            self.terminado.emit(ruta)
        except Exception as e:
            self.fallo.emit(str(e))


class Ventana(QWidget):
    def __init__(self):
        super().__init__()
        self.ejecutable = ""
        self.trabajo = None

        self.setWindowTitle("Instalar Caudal")
        self.setFixedSize(560, 420)
        self.setStyleSheet(f"""
            QWidget {{ background:{FONDO}; color:{TEXTO};
                       font-family:"Segoe UI Variable","Segoe UI",sans-serif; }}
            QLabel#titulo {{ font-size:22px; font-weight:700; letter-spacing:-0.4px; }}
            QLabel#ayuda {{ color:{TEXTO3}; font-size:12px; }}
            QLineEdit {{ background:{SUPERFICIE2}; border:1px solid {BORDE};
                         border-radius:9px; padding:9px 12px; font-size:12.5px; }}
            QPushButton {{ background:{SUPERFICIE2}; border:1px solid {BORDE};
                           border-radius:9px; padding:9px 16px; color:{TEXTO}; }}
            QPushButton:hover {{ background:{BORDE}; }}
            QPushButton#principal {{ background:{ACENTO}; border:none; color:#04202A;
                                     font-weight:700; font-size:14px; padding:12px 26px;
                                     border-radius:11px; }}
            QPushButton#principal:disabled {{ background:{SUPERFICIE2}; color:{TEXTO3}; }}
            QProgressBar {{ background:{SUPERFICIE2}; border:none; border-radius:4px;
                            height:7px; text-align:center; color:transparent; }}
            QProgressBar::chunk {{ background:{ACENTO}; border-radius:4px; }}
            QCheckBox {{ color:{TEXTO2}; font-size:12.5px; spacing:9px; }}
            QCheckBox::indicator {{ width:17px; height:17px; border-radius:5px;
                                    border:1px solid {BORDE}; background:{SUPERFICIE2}; }}
            QCheckBox::indicator:checked {{ background:{ACENTO}; border-color:{ACENTO}; }}
        """)

        raiz = QVBoxLayout(self)
        raiz.setContentsMargins(34, 30, 34, 26)
        raiz.setSpacing(0)

        marca = QHBoxLayout()
        marca.setSpacing(14)
        logo = QLabel()
        logo.setPixmap(gota(52))
        marca.addWidget(logo)
        textos = QVBoxLayout()
        textos.setSpacing(2)
        t = QLabel("Caudal")
        t.setObjectName("titulo")
        textos.addWidget(t)
        self.et_version = QLabel(f"Version {instalador.leer_version()}")
        self.et_version.setObjectName("ayuda")
        textos.addWidget(self.et_version)
        marca.addLayout(textos)
        marca.addStretch(1)
        raiz.addLayout(marca)

        raiz.addSpacing(22)
        desc = QLabel("Descarga musica y videos, escuchalos sin conexion y conecta\n"
                      "tu telefono con tu cuenta.")
        desc.setStyleSheet(f"color:{TEXTO2};font-size:13px;line-height:1.5;")
        raiz.addWidget(desc)

        raiz.addSpacing(24)
        et = QLabel("Se instalara en")
        et.setObjectName("ayuda")
        raiz.addWidget(et)
        raiz.addSpacing(6)

        fila = QHBoxLayout()
        fila.setSpacing(8)
        self.campo = QLineEdit(instalador.destino_por_defecto())
        fila.addWidget(self.campo, 1)
        bt = QPushButton("Cambiar")
        bt.clicked.connect(self._elegir)
        fila.addWidget(bt)
        raiz.addLayout(fila)

        raiz.addSpacing(16)
        self.casilla = QCheckBox("Crear acceso directo en el escritorio")
        self.casilla.setChecked(True)
        raiz.addWidget(self.casilla)

        raiz.addStretch(1)

        self.barra = QProgressBar()
        self.barra.setRange(0, 100)
        self.barra.hide()
        raiz.addWidget(self.barra)
        raiz.addSpacing(8)

        self.et_estado = QLabel("")
        self.et_estado.setObjectName("ayuda")
        raiz.addWidget(self.et_estado)

        raiz.addSpacing(14)
        pie = QHBoxLayout()
        pie.addStretch(1)
        self.bt_cancelar = QPushButton("Cancelar")
        self.bt_cancelar.clicked.connect(self.close)
        pie.addWidget(self.bt_cancelar)
        self.bt_instalar = QPushButton("Instalar")
        self.bt_instalar.setObjectName("principal")
        self.bt_instalar.setCursor(Qt.PointingHandCursor)
        self.bt_instalar.clicked.connect(self._instalar)
        pie.addWidget(self.bt_instalar)
        raiz.addLayout(pie)

    def _elegir(self):
        carpeta = QFileDialog.getExistingDirectory(self, "Elegir carpeta",
                                                   self.campo.text())
        if carpeta:
            self.campo.setText(os.path.join(carpeta, "Caudal"))

    def _instalar(self):
        self.bt_instalar.setEnabled(False)
        self.bt_cancelar.setEnabled(False)
        self.campo.setEnabled(False)
        self.barra.show()
        self.barra.setValue(0)

        self.trabajo = Trabajo(self.campo.text().strip(), self.casilla.isChecked())
        self.trabajo.avance.connect(self._avance)
        self.trabajo.terminado.connect(self._listo)
        self.trabajo.fallo.connect(self._fallo)
        self.trabajo.start()

    def _avance(self, pct, texto):
        self.barra.setValue(int(pct))
        self.et_estado.setText(texto)

    def _listo(self, ruta):
        self.ejecutable = ruta
        self.barra.setValue(100)
        self.et_estado.setText("Instalado correctamente")
        self.bt_instalar.setText("Abrir Caudal")
        self.bt_instalar.setEnabled(True)
        self.bt_cancelar.setText("Cerrar")
        self.bt_cancelar.setEnabled(True)
        try:
            self.bt_instalar.clicked.disconnect()
        except RuntimeError:
            pass
        self.bt_instalar.clicked.connect(self._abrir)

    def _fallo(self, mensaje):
        self.et_estado.setText(mensaje[:110])
        self.barra.hide()
        self.bt_instalar.setEnabled(True)
        self.bt_cancelar.setEnabled(True)
        self.campo.setEnabled(True)

    def _abrir(self):
        if self.ejecutable and os.path.exists(self.ejecutable):
            subprocess.Popen([self.ejecutable], cwd=os.path.dirname(self.ejecutable))
        self.close()


def main():
    argumentos = [a.lower() for a in sys.argv[1:]]

    # actualizacion automatica: sin ventana, encima de lo que ya hay
    if "/actualizar" in argumentos:
        carpeta = os.path.dirname(os.path.abspath(sys.executable))
        if not os.path.exists(os.path.join(carpeta, "Caudal Escritorio.exe")):
            carpeta = instalador.destino_por_defecto()
        ruta = instalador.instalar(carpeta, crear_escritorio=False)
        subprocess.Popen([ruta], cwd=os.path.dirname(ruta))
        return 0

    if "/desinstalar" in argumentos:
        instalador.desinstalar(os.path.dirname(os.path.abspath(sys.executable)))
        return 0

    app = QApplication(sys.argv)
    v = Ventana()
    v.show()
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
