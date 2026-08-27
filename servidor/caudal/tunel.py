# -*- coding: utf-8 -*-
"""Tunel de Cloudflare para llegar al servidor desde fuera de casa.

Levanta `cloudflared` apuntando al puerto local y saca la direccion publica que
devuelve. No hace falta tocar el router ni abrir puertos, ni tener cuenta.

Que quede abierto a internet es seguro porque la API exige iniciar sesion y las
cuentas solo se pueden crear desde la red de casa.
"""

import os
import re
import subprocess
import threading
import time
from pathlib import Path
from shutil import which

from .config import raiz

DIRECCION = re.compile(r"https://[a-z0-9][a-z0-9-]*\.trycloudflare\.com")
DESCARGA = ("https://github.com/cloudflare/cloudflared/releases/latest/download/"
            "cloudflared-windows-amd64.exe")


def ruta_cloudflared() -> str:
    """Busca el programa del tunel: primero el nuestro, luego el del sistema."""
    candidatas = [
        raiz() / "bin" / "cloudflared.exe",
        raiz() / "_internal" / "bin" / "cloudflared.exe",
        raiz() / "bin" / "cloudflared",
    ]
    for c in candidatas:
        if c.exists():
            return str(c)
    hallado = which("cloudflared")
    return hallado or ""


def descargar_cloudflared(al_progresar=None) -> str:
    """Trae el programa del tunel si no esta. Devuelve su ruta."""
    ya = ruta_cloudflared()
    if ya:
        return ya

    import requests

    destino = raiz() / "bin"
    destino.mkdir(parents=True, exist_ok=True)
    archivo = destino / "cloudflared.exe"
    parcial = destino / "cloudflared.part"

    with requests.get(DESCARGA, stream=True, timeout=60) as r:
        r.raise_for_status()
        total = int(r.headers.get("Content-Length", 0))
        hecho = 0
        with open(parcial, "wb") as f:
            for trozo in r.iter_content(chunk_size=262144):
                if not trozo:
                    continue
                f.write(trozo)
                hecho += len(trozo)
                if al_progresar and total:
                    al_progresar(hecho / total * 100)
    os.replace(parcial, archivo)
    return str(archivo)


class Tunel:
    """Un tunel vivo. Se le pregunta la direccion cuando esta listo."""

    def __init__(self, puerto: int):
        self.puerto = puerto
        self.proceso = None
        self.url = ""
        self.error = ""
        self._hilo = None
        self._salida = []

    @property
    def activo(self) -> bool:
        return self.proceso is not None and self.proceso.poll() is None

    def iniciar(self, espera=45) -> str:
        """Levanta el tunel y espera a que Cloudflare de la direccion."""
        if self.activo:
            return self.url

        programa = ruta_cloudflared()
        if not programa:
            raise RuntimeError(
                "Falta cloudflared. Descargalo desde la app de escritorio o ponlo "
                "en la carpeta bin del servidor."
            )

        self.url = ""
        self.error = ""
        self._salida = []

        banderas = getattr(subprocess, "CREATE_NO_WINDOW", 0)
        self.proceso = subprocess.Popen(
            [programa, "tunnel", "--no-autoupdate", "--url", f"http://127.0.0.1:{self.puerto}"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            creationflags=banderas,
        )

        self._hilo = threading.Thread(target=self._leer, daemon=True, name="caudal-tunel")
        self._hilo.start()

        limite = time.time() + espera
        while time.time() < limite:
            if self.url:
                return self.url
            if not self.activo:
                break
            time.sleep(0.3)

        if not self.url:
            self.detener()
            detalle = " ".join(self._salida[-3:])[:200] if self._salida else ""
            raise RuntimeError(
                "El tunel no llego a levantarse. Comprueba tu conexion a internet."
                + (f"\n{detalle}" if detalle else "")
            )
        return self.url

    def _leer(self):
        """cloudflared anuncia la direccion en su propia salida."""
        try:
            for linea in self.proceso.stdout:
                linea = linea.strip()
                if not linea:
                    continue
                self._salida.append(linea)
                if len(self._salida) > 60:
                    self._salida.pop(0)
                if not self.url:
                    encontrada = DIRECCION.search(linea)
                    if encontrada:
                        self.url = encontrada.group(0)
        except (ValueError, OSError):
            # el proceso se cerro mientras leiamos
            pass

    def detener(self):
        if self.proceso is not None:
            try:
                self.proceso.terminate()
                self.proceso.wait(timeout=6)
            except (subprocess.TimeoutExpired, OSError):
                try:
                    self.proceso.kill()
                except OSError:
                    pass
            self.proceso = None
        self.url = ""
