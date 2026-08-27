# -*- coding: utf-8 -*-
"""Configuracion del servidor Caudal."""

import json
import os
import secrets
import socket
import sys
from pathlib import Path
from shutil import which

NOMBRE = "Caudal"
PUERTO_DEFECTO = 8770


def raiz() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent.parent


def carpeta_datos() -> Path:
    base = os.environ.get("APPDATA") or str(Path.home())
    ruta = Path(base) / "Caudal"
    ruta.mkdir(parents=True, exist_ok=True)
    return ruta


def carpeta_trabajo() -> Path:
    ruta = carpeta_datos() / "temporal"
    ruta.mkdir(parents=True, exist_ok=True)
    return ruta


def ruta_ffmpeg() -> str:
    """Busca ffmpeg: primero el propio, luego el del descargador de escritorio."""
    candidatas = [
        raiz() / "bin",
        raiz() / "_internal" / "bin",
        Path.home() / "Caudal" / "escritorio" / "bin",
        Path.home() / "DescargadorVideos" / "bin",   # ubicacion anterior
    ]
    for c in candidatas:
        if (c / "ffmpeg.exe").exists() or (c / "ffmpeg").exists():
            return str(c)
    hallado = which("ffmpeg")
    return str(Path(hallado).parent) if hallado else ""


def ip_local() -> str:
    """IP de esta maquina en la red local (la que ve el telefono)."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))       # no envia nada, solo elige la interfaz
        ip = s.getsockname()[0]
        s.close()
        return ip
    except OSError:
        try:
            return socket.gethostbyname(socket.gethostname())
        except OSError:
            return "127.0.0.1"


DEFECTOS = {
    "token": "",
    "puerto": PUERTO_DEFECTO,
    "direccion_publica": "",       # la que da el tunel, para usarlo desde la calle
    "tunel_automatico": False,     # levantar el tunel al arrancar
    "max_simultaneas": 3,
    "horas_retencion": 6,
    "max_gb_temporal": 12,
    "navegador_cookies": "ninguno",
    "archivo_cookies": "",
    "limite_busqueda": 25,
    # opcionales y gratuitos (developer.spotify.com): sin ellos Spotify
    # solo deja leer 50 canciones por lista
    "spotify_id": "",
    "spotify_secreto": "",
}


class Ajustes:
    def __init__(self):
        self.archivo = carpeta_datos() / "servidor.json"
        self.datos = dict(DEFECTOS)
        self.cargar()
        if not self.datos.get("token"):
            self.datos["token"] = secrets.token_urlsafe(18)
            self.guardar()

    def cargar(self):
        try:
            if self.archivo.exists():
                for k, v in json.loads(self.archivo.read_text(encoding="utf-8")).items():
                    if k in DEFECTOS:
                        self.datos[k] = v
        except (OSError, ValueError):
            pass

    def guardar(self):
        try:
            self.archivo.write_text(json.dumps(self.datos, indent=2, ensure_ascii=False),
                                    encoding="utf-8")
        except OSError:
            pass

    def __getitem__(self, clave):
        return self.datos.get(clave, DEFECTOS.get(clave))

    def __setitem__(self, clave, valor):
        self.datos[clave] = valor
