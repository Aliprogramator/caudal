# -*- coding: utf-8 -*-
"""Panel de Caudal: enciende el servidor, crea la cuenta y conecta el telefono."""

import io
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

from PySide6.QtCore import Qt, QThread, Signal
from PySide6.QtGui import QPixmap
from PySide6.QtWidgets import (QCheckBox, QFrame, QGridLayout, QHBoxLayout, QLabel,
                               QLineEdit, QMessageBox, QPushButton, QScrollArea,
                               QVBoxLayout, QWidget)

from .estilos import C
from . import iconos

RAIZ_SERVIDOR = Path.home() / "Caudal" / "servidor"
PUERTO = 8770
BASE = f"http://127.0.0.1:{PUERTO}"


# ---------------------------------------------------------------- red

def pedir(ruta, metodo="GET", cuerpo=None, token=None, espera=25):
    """Peticion al servidor local. Las esperas cortas evitan colgar la ventana."""
    datos = json.dumps(cuerpo).encode() if cuerpo is not None else None
    req = urllib.request.Request(BASE + ruta, data=datos, method=metodo)
    if datos:
        req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("X-Caudal-Token", token)
    with urllib.request.urlopen(req, timeout=espera) as r:
        texto = r.read().decode()
        return json.loads(texto) if texto else {}


def detalle_error(e):
    try:
        return json.loads(e.read()).get("detail", "")
    except Exception:
        return ""


class Tarea(QThread):
    """Trabajo en segundo plano para no congelar la ventana."""
    listo = Signal(object)
    fallo = Signal(str)

    def __init__(self, funcion):
        super().__init__()
        self.funcion = funcion

    def run(self):
        try:
            self.listo.emit(self.funcion())
        except urllib.error.HTTPError as e:
            self.fallo.emit(detalle_error(e) or f"El servidor respondio {e.code}.")
        except Exception as e:
            self.fallo.emit(str(e))


# ---------------------------------------------------------------- panel

class PanelCaudal(QWidget):
    """Todo lo del telefono en un sitio: servidor, cuenta y codigo QR."""

    def __init__(self, ajustes=None, padre=None):
        super().__init__(padre)
        self.ajustes = ajustes
        self.proceso = None
        # si la sesion quedo guardada, se entra sin escribir nada
        self.token = (ajustes["sesion_token"] if ajustes else "") or ""
        self.usuario = (ajustes["sesion_usuario"] if ajustes else "") or ""
        self.tareas = []

        area = QScrollArea(self)
        area.setObjectName("lienzo")
        area.setWidgetResizable(True)
        area.viewport().setAutoFillBackground(False)

        interior = QWidget()
        self.caja = QVBoxLayout(interior)
        self.caja.setContentsMargins(0, 8, 8, 8)
        self.caja.setSpacing(12)

        self.caja.addWidget(self._panel_servidor())
        self.caja.addWidget(self._panel_cuenta())
        self.caja.addWidget(self._panel_qr())
        self.caja.addStretch(1)

        area.setWidget(interior)
        raiz = QVBoxLayout(self)
        raiz.setContentsMargins(0, 0, 0, 0)
        raiz.addWidget(area)

        self.refrescar()

    # ------------------------------------------------------------ secciones

    def _marco(self, titulo):
        marco = QFrame()
        marco.setObjectName("panel")
        v = QVBoxLayout(marco)
        v.setContentsMargins(18, 15, 18, 17)
        v.setSpacing(12)
        et = QLabel(titulo)
        et.setObjectName("seccion")
        v.addWidget(et)
        return marco, v

    def _panel_servidor(self):
        marco, v = self._marco("SERVIDOR")

        fila = QHBoxLayout()
        self.punto = QLabel("●")
        self.punto.setStyleSheet(f"color:{C['error']};font-size:15px;")
        fila.addWidget(self.punto)

        self.et_estado = QLabel("Comprobando...")
        self.et_estado.setStyleSheet("font-size:14px;font-weight:600;")
        fila.addWidget(self.et_estado)
        fila.addStretch(1)

        self.bt_servidor = QPushButton("  Encender")
        self.bt_servidor.setIcon(iconos.icono("reproducir", 16))
        self.bt_servidor.setCursor(Qt.PointingHandCursor)
        self.bt_servidor.clicked.connect(self._alternar_servidor)
        fila.addWidget(self.bt_servidor)
        v.addLayout(fila)

        self.et_direcciones = QLabel("")
        self.et_direcciones.setObjectName("ayuda")
        self.et_direcciones.setTextInteractionFlags(Qt.TextSelectableByMouse)
        self.et_direcciones.setWordWrap(True)
        v.addWidget(self.et_direcciones)

        fila2 = QHBoxLayout()
        self.bt_tunel = QPushButton("  Permitir uso desde la calle")
        self.bt_tunel.setIcon(iconos.icono("abrir", 16))
        self.bt_tunel.setCursor(Qt.PointingHandCursor)
        self.bt_tunel.clicked.connect(self._alternar_tunel)
        fila2.addWidget(self.bt_tunel)
        fila2.addStretch(1)
        v.addLayout(fila2)

        return marco

    def _panel_cuenta(self):
        marco, v = self._marco("TU CUENTA")

        self.et_cuenta = QLabel("")
        self.et_cuenta.setObjectName("ayuda")
        self.et_cuenta.setWordWrap(True)
        v.addWidget(self.et_cuenta)

        rejilla = QGridLayout()
        rejilla.setColumnStretch(1, 1)
        rejilla.setColumnMinimumWidth(0, 110)
        rejilla.setVerticalSpacing(9)

        self.campo_usuario = QLineEdit()
        self.campo_usuario.setPlaceholderText("kevin")
        rejilla.addWidget(QLabel("Usuario"), 0, 0)
        rejilla.addWidget(self.campo_usuario, 0, 1)

        self.campo_clave = QLineEdit()
        self.campo_clave.setEchoMode(QLineEdit.Password)
        self.campo_clave.setPlaceholderText("Al menos 6 caracteres")
        self.campo_clave.returnPressed.connect(self._entrar)
        rejilla.addWidget(QLabel("Contrasena"), 1, 0)
        rejilla.addWidget(self.campo_clave, 1, 1)
        v.addLayout(rejilla)

        fila = QHBoxLayout()
        self.bt_crear = QPushButton("  Crear cuenta")
        self.bt_crear.setIcon(iconos.icono("mas", 16))
        self.bt_crear.setObjectName("principal")
        self.bt_crear.setCursor(Qt.PointingHandCursor)
        self.bt_crear.clicked.connect(self._crear_cuenta)
        fila.addWidget(self.bt_crear)

        self.bt_entrar = QPushButton("  Entrar")
        self.bt_entrar.setIcon(iconos.icono("listo", 16))
        self.bt_entrar.setCursor(Qt.PointingHandCursor)
        self.bt_entrar.clicked.connect(self._entrar)
        fila.addWidget(self.bt_entrar)
        fila.addStretch(1)
        v.addLayout(fila)

        self.casilla_mantener = QCheckBox("Mantener la sesion iniciada")
        self.casilla_mantener.setChecked(
            bool(self.ajustes["mantener_sesion"]) if self.ajustes else True)
        self.casilla_mantener.toggled.connect(self._guardar_mantener)
        v.addWidget(self.casilla_mantener)

        self.et_dispositivos = QLabel("")
        self.et_dispositivos.setObjectName("ayuda")
        self.et_dispositivos.setWordWrap(True)
        v.addWidget(self.et_dispositivos)

        self.bt_salir = QPushButton("  Cerrar sesion")
        self.bt_salir.setIcon(iconos.icono("cerrar", 15))
        self.bt_salir.setObjectName("peligro")
        self.bt_salir.setCursor(Qt.PointingHandCursor)
        self.bt_salir.clicked.connect(self._salir)
        self.bt_salir.hide()
        v.addWidget(self.bt_salir)

        return marco

    def _guardar_mantener(self, valor):
        if self.ajustes is not None:
            self.ajustes["mantener_sesion"] = bool(valor)
            if not valor:
                self.ajustes["sesion_token"] = ""
                self.ajustes["sesion_usuario"] = ""
            elif self.token:
                self.ajustes["sesion_token"] = self.token
                self.ajustes["sesion_usuario"] = self.usuario
            self.ajustes.guardar()

    def _salir(self):
        self.token = ""
        self.usuario = ""
        if self.ajustes is not None:
            self.ajustes["sesion_token"] = ""
            self.ajustes["sesion_usuario"] = ""
            self.ajustes.guardar()
        self.refrescar()

    def _panel_qr(self):
        marco, v = self._marco("CONECTAR EL TELEFONO")

        self.et_qr = QLabel()
        self.et_qr.setAlignment(Qt.AlignCenter)
        self.et_qr.setMinimumHeight(210)
        v.addWidget(self.et_qr)

        ayuda = QLabel(
            "Abre Caudal en el telefono, pulsa Escanear y apunta a este codigo. "
            "Despues entra con tu usuario y contrasena."
        )
        ayuda.setObjectName("ayuda")
        ayuda.setWordWrap(True)
        ayuda.setAlignment(Qt.AlignCenter)
        v.addWidget(ayuda)

        return marco

    # ------------------------------------------------------------ servidor

    def _servidor_vivo(self):
        # espera muy corta: es local, y si no contesta ya, es que esta apagado
        try:
            return pedir("/salud", espera=1.2)
        except Exception:
            return None

    def _alternar_servidor(self):
        if self._servidor_vivo():
            self._apagar_servidor()
        else:
            self._encender_servidor()

    def _encender_servidor(self):
        guion = RAIZ_SERVIDOR / "ejecutar.py"
        if not guion.exists():
            QMessageBox.warning(self, "Caudal",
                                f"No encuentro el servidor en:\n{guion}")
            return
        banderas = getattr(subprocess, "CREATE_NO_WINDOW", 0)
        self.proceso = subprocess.Popen(
            [sys.executable, str(guion), "--sin-navegador"],
            cwd=str(RAIZ_SERVIDOR), creationflags=banderas,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        self.bt_servidor.setEnabled(False)
        self.et_estado.setText("Encendiendo...")
        self._lanzar(self._esperar_arranque, self._tras_arranque, self._error)

    def _esperar_arranque(self):
        import time
        for _ in range(30):
            time.sleep(1)
            salud = self._servidor_vivo()
            if salud:
                return salud
        raise RuntimeError("El servidor no arranco. Revisa que Python tenga sus dependencias.")

    def _tras_arranque(self, _salud):
        self.bt_servidor.setEnabled(True)
        self.refrescar()

    def _apagar_servidor(self):
        try:
            r = subprocess.run(["netstat", "-ano", "-p", "TCP"],
                               capture_output=True, text=True,
                               creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            for linea in r.stdout.splitlines():
                if f":{PUERTO}" in linea and "LISTENING" in linea:
                    subprocess.run(["taskkill", "/F", "/PID", linea.split()[-1]],
                                   capture_output=True,
                                   creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        except OSError:
            pass
        self.proceso = None
        self.token = ""
        self.refrescar()

    def _alternar_tunel(self):
        QMessageBox.information(
            self, "Caudal",
            "El acceso desde la calle se enciende con el propio servidor.\n\n"
            "Abre una consola en la carpeta del servidor y ejecuta:\n"
            "   python -c \"from caudal.tunel import Tunel; "
            "t=Tunel(8770); print(t.iniciar()); input()\"\n\n"
            "La direccion que salga es la que funciona desde fuera de casa.")

    # ------------------------------------------------------------ cuenta

    def _crear_cuenta(self):
        usuario = self.campo_usuario.text().strip()
        clave = self.campo_clave.text()
        if not usuario or not clave:
            QMessageBox.warning(self, "Caudal", "Escribe un usuario y una contrasena.")
            return
        self._lanzar(
            lambda: pedir("/cuenta/registro", "POST",
                          {"usuario": usuario, "clave": clave,
                           "dispositivo": os.environ.get("COMPUTERNAME", "Esta PC"),
                           "plataforma": "windows"}),
            self._tras_sesion, self._error)

    def _entrar(self):
        usuario = self.campo_usuario.text().strip()
        clave = self.campo_clave.text()
        if not usuario or not clave:
            QMessageBox.warning(self, "Caudal", "Escribe tu usuario y contrasena.")
            return
        self._lanzar(
            lambda: pedir("/cuenta/entrar", "POST",
                          {"usuario": usuario, "clave": clave,
                           "dispositivo": os.environ.get("COMPUTERNAME", "Esta PC"),
                           "plataforma": "windows"}),
            self._tras_sesion, self._error)

    def _tras_sesion(self, sesion):
        self.token = sesion.get("token", "")
        self.usuario = sesion.get("usuario", "")
        self.campo_clave.clear()
        if self.ajustes is not None and self.casilla_mantener.isChecked():
            self.ajustes["sesion_token"] = self.token
            self.ajustes["sesion_usuario"] = self.usuario
            self.ajustes.guardar()
        self.refrescar()

    def _error(self, mensaje):
        self.bt_servidor.setEnabled(True)
        QMessageBox.warning(self, "Caudal", mensaje or "Algo no salio bien.")
        self.refrescar()

    # ------------------------------------------------------------ pintado

    def refrescar(self):
        salud = self._servidor_vivo()
        encendido = bool(salud)

        self.punto.setStyleSheet(
            f"color:{C['exito'] if encendido else C['error']};font-size:15px;")
        self.et_estado.setText("Servidor encendido" if encendido else "Servidor apagado")
        self.bt_servidor.setText("  Apagar" if encendido else "  Encender")
        self.bt_servidor.setIcon(iconos.icono("pausa" if encendido else "reproducir", 16))

        for w in (self.campo_usuario, self.campo_clave, self.bt_crear, self.bt_entrar):
            w.setEnabled(encendido and not self.token)
        self.bt_tunel.setEnabled(encendido)

        if not encendido:
            self.et_direcciones.setText("Enciendelo para conectar el telefono.")
            self.et_cuenta.setText("Primero enciende el servidor.")
            self.et_dispositivos.setText("")
            self.et_qr.clear()
            return

        local, publica = self._direcciones()
        texto = f"En casa:  {local}"
        if publica:
            texto += f"\nDesde la calle:  {publica}"
        self.et_direcciones.setText(texto)

        self.bt_salir.setVisible(bool(self.token))
        if self.token:
            self.et_cuenta.setText(f"Sesion iniciada como {self.usuario}.")
            self._cargar_dispositivos()
        elif salud.get("hay_cuentas"):
            self.et_cuenta.setText("Entra con tu cuenta para ver los telefonos conectados.")
            self.bt_crear.setEnabled(False)
            self.et_dispositivos.setText("")
        else:
            self.et_cuenta.setText(
                "Todavia no hay ninguna cuenta. Crea la tuya: es la que usaras "
                "tambien en el telefono.")
            self.et_dispositivos.setText("")

        self._pintar_qr(local, publica)

    def _direcciones(self):
        try:
            sys.path.insert(0, str(RAIZ_SERVIDOR))
            from caudal.config import Ajustes, ip_local
            a = Ajustes()
            return f"http://{ip_local()}:{PUERTO}", a["direccion_publica"]
        except Exception:
            return BASE, ""

    def _cargar_dispositivos(self):
        self._lanzar(lambda: pedir("/cuenta/yo", token=self.token),
                     self._pintar_dispositivos, lambda m: None)

    def _pintar_dispositivos(self, datos):
        lista = datos.get("dispositivos", [])
        if not lista:
            self.et_dispositivos.setText("")
            return
        lineas = ["Dispositivos con tu cuenta:"]
        for d in lista:
            marca = "  (este)" if d.get("es_este") else ""
            lineas.append(f"   · {d.get('dispositivo','')}{marca}")
        self.et_dispositivos.setText("\n".join(lineas))

    def _pintar_qr(self, local, publica):
        try:
            import qrcode
            carga = json.dumps({"servidor": local, "publico": publica or ""},
                               ensure_ascii=False)
            qr = qrcode.QRCode(box_size=6, border=2)
            qr.add_data(carga)
            qr.make(fit=True)
            imagen = qr.make_image(fill_color="#0B0E14", back_color="#FFFFFF")
            buffer = io.BytesIO()
            imagen.save(buffer, format="PNG")
            pm = QPixmap()
            pm.loadFromData(buffer.getvalue())
            self.et_qr.setPixmap(pm)
        except Exception:
            self.et_qr.setText("Abre " + local + " en el navegador para ver el codigo QR.")

    # ------------------------------------------------------------ hilos

    def _lanzar(self, funcion, al_terminar, al_fallar):
        t = Tarea(funcion)
        t.listo.connect(al_terminar)
        t.fallo.connect(al_fallar)
        t.finished.connect(lambda: self.tareas.remove(t) if t in self.tareas else None)
        self.tareas.append(t)
        t.start()
