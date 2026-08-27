# -*- coding: utf-8 -*-
"""Cuentas de usuario y sesiones de los dispositivos.

La contrasena nunca se guarda: se guarda su huella scrypt con una sal propia.
Los tokens de sesion tampoco: se guarda su sha256, asi un vistazo a la base de
datos no sirve para entrar.
"""

import hashlib
import os
import re
import secrets
import sqlite3
import time

from .config import carpeta_datos

DIAS_SESION = 120           # cuanto dura la sesion de un dispositivo sin usarse
MIN_USUARIO = 3
MIN_CLAVE = 6


class ErrorCuenta(Exception):
    """Problema que se le puede contar tal cual al usuario."""


def _huella_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _cifrar_clave(clave: str, sal: bytes = None) -> tuple:
    sal = sal or os.urandom(16)
    huella = hashlib.scrypt(clave.encode("utf-8"), salt=sal, n=2 ** 14, r=8, p=1, dklen=32)
    return huella.hex(), sal.hex()


def normalizar_usuario(usuario: str) -> str:
    return (usuario or "").strip().lower()


class Cuentas:
    def __init__(self):
        self.archivo = carpeta_datos() / "cuentas.db"
        self.con = sqlite3.connect(str(self.archivo), check_same_thread=False)
        self.con.row_factory = sqlite3.Row
        self._crear()

    def _crear(self):
        self.con.execute(
            """CREATE TABLE IF NOT EXISTS usuarios (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                usuario TEXT NOT NULL UNIQUE,
                nombre TEXT,
                huella TEXT NOT NULL,
                sal TEXT NOT NULL,
                creado REAL
            )"""
        )
        self.con.execute(
            """CREATE TABLE IF NOT EXISTS sesiones (
                huella_token TEXT PRIMARY KEY,
                usuario_id INTEGER NOT NULL,
                dispositivo TEXT,
                plataforma TEXT,
                creada REAL,
                ultimo_uso REAL,
                FOREIGN KEY (usuario_id) REFERENCES usuarios(id) ON DELETE CASCADE
            )"""
        )
        self.con.execute("CREATE INDEX IF NOT EXISTS idx_sesion_usuario ON sesiones(usuario_id)")
        self.con.commit()

    # ------------------------------------------------------------ usuarios

    def hay_alguien(self) -> bool:
        """Si no hay ninguna cuenta, la app de escritorio ofrece crear la primera."""
        cur = self.con.execute("SELECT COUNT(*) n FROM usuarios")
        return cur.fetchone()["n"] > 0

    def registrar(self, usuario: str, clave: str, nombre: str = "") -> dict:
        usuario = normalizar_usuario(usuario)

        if len(usuario) < MIN_USUARIO:
            raise ErrorCuenta(f"El usuario necesita al menos {MIN_USUARIO} letras.")
        if not re.fullmatch(r"[a-z0-9._-]+", usuario):
            raise ErrorCuenta("El usuario solo puede llevar letras, numeros, punto, guion y guion bajo.")
        if len(clave or "") < MIN_CLAVE:
            raise ErrorCuenta(f"La contrasena necesita al menos {MIN_CLAVE} caracteres.")

        if self.buscar(usuario):
            raise ErrorCuenta("Ese usuario ya existe. Elige otro o inicia sesion.")

        huella, sal = _cifrar_clave(clave)
        cur = self.con.execute(
            "INSERT INTO usuarios (usuario, nombre, huella, sal, creado) VALUES (?,?,?,?,?)",
            (usuario, (nombre or usuario).strip(), huella, sal, time.time()),
        )
        self.con.commit()
        return {"id": cur.lastrowid, "usuario": usuario, "nombre": (nombre or usuario).strip()}

    def buscar(self, usuario: str):
        cur = self.con.execute(
            "SELECT * FROM usuarios WHERE usuario = ?", (normalizar_usuario(usuario),))
        return cur.fetchone()

    def comprobar_clave(self, usuario: str, clave: str):
        fila = self.buscar(usuario)
        if not fila:
            return None
        huella, _ = _cifrar_clave(clave or "", bytes.fromhex(fila["sal"]))
        # comparacion en tiempo constante: no delata cuanto coincide
        if secrets.compare_digest(huella, fila["huella"]):
            return fila
        return None

    def cambiar_clave(self, usuario: str, clave_actual: str, clave_nueva: str):
        fila = self.comprobar_clave(usuario, clave_actual)
        if not fila:
            raise ErrorCuenta("La contrasena actual no es correcta.")
        if len(clave_nueva or "") < MIN_CLAVE:
            raise ErrorCuenta(f"La contrasena nueva necesita al menos {MIN_CLAVE} caracteres.")
        huella, sal = _cifrar_clave(clave_nueva)
        self.con.execute("UPDATE usuarios SET huella = ?, sal = ? WHERE id = ?",
                         (huella, sal, fila["id"]))
        # al cambiar la clave se cierran las demas sesiones
        self.con.execute("DELETE FROM sesiones WHERE usuario_id = ?", (fila["id"],))
        self.con.commit()

    def borrar_usuario(self, usuario: str):
        fila = self.buscar(usuario)
        if not fila:
            return
        self.con.execute("DELETE FROM sesiones WHERE usuario_id = ?", (fila["id"],))
        self.con.execute("DELETE FROM usuarios WHERE id = ?", (fila["id"],))
        self.con.commit()

    def listar_usuarios(self):
        cur = self.con.execute("SELECT usuario, nombre, creado FROM usuarios ORDER BY creado")
        return [dict(f) for f in cur.fetchall()]

    # ------------------------------------------------------------ sesiones

    def entrar(self, usuario: str, clave: str, dispositivo: str = "", plataforma: str = "") -> dict:
        """Comprueba la clave y devuelve un token para ese dispositivo."""
        fila = self.comprobar_clave(usuario, clave)
        if not fila:
            raise ErrorCuenta("Usuario o contrasena incorrectos.")

        token = secrets.token_urlsafe(32)
        ahora = time.time()
        self.con.execute(
            "INSERT INTO sesiones (huella_token, usuario_id, dispositivo, plataforma, creada, ultimo_uso)"
            " VALUES (?,?,?,?,?,?)",
            (_huella_token(token), fila["id"], (dispositivo or "Dispositivo").strip()[:60],
             (plataforma or "").strip()[:30], ahora, ahora),
        )
        self.con.commit()
        return {
            "token": token,
            "usuario": fila["usuario"],
            "nombre": fila["nombre"] or fila["usuario"],
        }

    def validar(self, token: str):
        """Devuelve el usuario dueno del token, o None si no vale."""
        if not token:
            return None
        cur = self.con.execute(
            "SELECT s.huella_token, s.ultimo_uso, u.id, u.usuario, u.nombre"
            " FROM sesiones s JOIN usuarios u ON u.id = s.usuario_id"
            " WHERE s.huella_token = ?", (_huella_token(token),))
        fila = cur.fetchone()
        if not fila:
            return None

        if time.time() - (fila["ultimo_uso"] or 0) > DIAS_SESION * 86400:
            self.con.execute("DELETE FROM sesiones WHERE huella_token = ?", (fila["huella_token"],))
            self.con.commit()
            return None

        # se refresca como mucho una vez por hora, para no escribir en cada peticion
        if time.time() - (fila["ultimo_uso"] or 0) > 3600:
            self.con.execute("UPDATE sesiones SET ultimo_uso = ? WHERE huella_token = ?",
                             (time.time(), fila["huella_token"]))
            self.con.commit()

        return {"id": fila["id"], "usuario": fila["usuario"], "nombre": fila["nombre"]}

    def salir(self, token: str):
        self.con.execute("DELETE FROM sesiones WHERE huella_token = ?", (_huella_token(token),))
        self.con.commit()

    def dispositivos(self, usuario_id: int, token_actual: str = ""):
        cur = self.con.execute(
            "SELECT huella_token, dispositivo, plataforma, creada, ultimo_uso"
            " FROM sesiones WHERE usuario_id = ? ORDER BY ultimo_uso DESC", (usuario_id,))
        huella_actual = _huella_token(token_actual) if token_actual else ""
        salida = []
        for f in cur.fetchall():
            salida.append({
                "id": f["huella_token"][:12],
                "dispositivo": f["dispositivo"],
                "plataforma": f["plataforma"],
                "desde": f["creada"],
                "ultimo_uso": f["ultimo_uso"],
                "es_este": f["huella_token"] == huella_actual,
            })
        return salida

    def desvincular(self, usuario_id: int, id_corto: str) -> bool:
        cur = self.con.execute(
            "SELECT huella_token FROM sesiones WHERE usuario_id = ?", (usuario_id,))
        for f in cur.fetchall():
            if f["huella_token"].startswith(id_corto):
                self.con.execute("DELETE FROM sesiones WHERE huella_token = ?", (f["huella_token"],))
                self.con.commit()
                return True
        return False

    def cerrar_todas(self, usuario_id: int, salvo_token: str = ""):
        if salvo_token:
            self.con.execute("DELETE FROM sesiones WHERE usuario_id = ? AND huella_token != ?",
                             (usuario_id, _huella_token(salvo_token)))
        else:
            self.con.execute("DELETE FROM sesiones WHERE usuario_id = ?", (usuario_id,))
        self.con.commit()
