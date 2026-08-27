# -*- coding: utf-8 -*-
"""Ajustes persistentes de la aplicacion."""

import json
import os
import sys
from pathlib import Path


APP_NOMBRE = "Caudal"


def raiz_app() -> Path:
    """Carpeta donde vive la aplicacion (soporta PyInstaller)."""
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent.parent


def carpeta_datos() -> Path:
    base = os.environ.get("APPDATA") or str(Path.home())
    ruta = Path(base) / "DescargadorVideos"
    ruta.mkdir(parents=True, exist_ok=True)
    return ruta


def carpeta_caratulas() -> Path:
    ruta = carpeta_datos() / "caratulas"
    ruta.mkdir(parents=True, exist_ok=True)
    return ruta


def ruta_ffmpeg() -> str:
    """Devuelve la carpeta con ffmpeg.exe, o cadena vacia si no esta."""
    candidatas = [raiz_app() / "bin", raiz_app() / "_internal" / "bin", carpeta_datos() / "bin"]
    for c in candidatas:
        if (c / "ffmpeg.exe").exists() or (c / "ffmpeg").exists():
            return str(c)
    # ffmpeg del sistema
    from shutil import which
    hallado = which("ffmpeg")
    if hallado:
        return str(Path(hallado).parent)
    return ""


def carpeta_descargas_por_defecto() -> str:
    for nombre in ("Downloads", "Descargas"):
        p = Path.home() / nombre
        if p.exists():
            return str(p / "Videos Descargados")
    return str(Path.home() / "Videos Descargados")


DEFECTOS = {
    "carpeta": carpeta_descargas_por_defecto(),
    "calidad": "mejor",
    "tipo_descarga": "completo",   # completo | video | audio
    "modo_musica": False,          # nivela el audio para que suene mas fuerte
    "sesion_token": "",            # sesion guardada del servidor
    "sesion_usuario": "",
    "mantener_sesion": True,
    "formato_salida": "mp4",
    "formato_audio": "mp3",
    "simultaneas": 2,
    "playlist": False,
    "limite_playlist": 50,
    "subtitulos": False,
    "idioma_subtitulos": "es",
    "incrustar_subtitulos": True,
    "miniatura": True,
    "metadatos": True,
    "navegador_cookies": "ninguno",
    "archivo_cookies": "",
    "plantilla_nombre": "%(title).150B [%(id)s].%(ext)s",
    "subcarpeta_por_red": False,
    "limite_velocidad": 0,          # KB/s, 0 = sin limite
    "reintentos": 6,
    "proxy": "",
    "vigilar_portapapeles": False,
    "notificar_al_terminar": True,
    "abrir_al_terminar": False,
    "geometria": "",
}


class Ajustes:
    def __init__(self):
        self.archivo = carpeta_datos() / "ajustes.json"
        self.datos = dict(DEFECTOS)
        self.cargar()

    def cargar(self):
        try:
            if self.archivo.exists():
                guardado = json.loads(self.archivo.read_text(encoding="utf-8"))
                for k, v in guardado.items():
                    if k in DEFECTOS:
                        self.datos[k] = v
        except Exception:
            pass

    def guardar(self):
        try:
            self.archivo.write_text(
                json.dumps(self.datos, indent=2, ensure_ascii=False), encoding="utf-8"
            )
        except Exception:
            pass

    def __getitem__(self, clave):
        return self.datos.get(clave, DEFECTOS.get(clave))

    def __setitem__(self, clave, valor):
        self.datos[clave] = valor

    def get(self, clave, defecto=None):
        return self.datos.get(clave, defecto if defecto is not None else DEFECTOS.get(clave))
