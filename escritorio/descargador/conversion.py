# -*- coding: utf-8 -*-
"""Convertir archivos que ya estan en el disco, sin volver a descargarlos."""

import os
import subprocess

from .config import ruta_ffmpeg


class ErrorConversion(Exception):
    """Fallo que se le puede contar al usuario tal cual."""


def _ffmpeg():
    carpeta = ruta_ffmpeg()
    if not carpeta:
        raise ErrorConversion(
            "Falta ffmpeg. Comprueba que exista la carpeta bin junto a la aplicacion.")
    return os.path.join(carpeta, "ffmpeg.exe")


def ruta_libre(carpeta, nombre, extension):
    destino = os.path.join(carpeta, f"{nombre}.{extension}")
    n = 1
    while os.path.exists(destino):
        destino = os.path.join(carpeta, f"{nombre} ({n}).{extension}")
        n += 1
    return destino


def extraer_audio(origen, formato="mp3", reforzar=False, carpeta_destino=None):
    """Saca la pista de sonido de un video. Devuelve la ruta del archivo nuevo.

    Con [reforzar] se nivela el volumen igual que en el modo musica.
    """
    if not origen or not os.path.exists(origen):
        raise ErrorConversion("Ese archivo ya no esta en el disco.")

    carpeta = carpeta_destino or os.path.dirname(origen)
    os.makedirs(carpeta, exist_ok=True)
    nombre = os.path.splitext(os.path.basename(origen))[0]
    destino = ruta_libre(carpeta, nombre, formato)

    orden = [_ffmpeg(), "-y", "-i", origen, "-vn"]
    if reforzar:
        orden += ["-af", "loudnorm=I=-9:TP=-1.0:LRA=9"]
    if formato == "mp3":
        orden += ["-c:a", "libmp3lame", "-b:a", "192k"]
    elif formato == "m4a":
        # si ya viene en AAC se copia tal cual: es instantaneo y sin perdida
        orden += ["-c:a", "copy"] if not reforzar else ["-c:a", "aac", "-b:a", "192k"]
    elif formato == "flac":
        orden += ["-c:a", "flac"]
    elif formato == "wav":
        orden += ["-c:a", "pcm_s16le"]
    orden.append(destino)

    banderas = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    r = subprocess.run(orden, capture_output=True, text=True, encoding="utf-8",
                       errors="replace", creationflags=banderas)

    if r.returncode != 0 or not os.path.exists(destino):
        # copiar la pista puede fallar si el contenedor no la admite: reintentamos
        if formato == "m4a" and "-c:a" in orden:
            return extraer_audio(origen, "mp3", reforzar, carpeta_destino)
        detalle = (r.stderr or "").strip().splitlines()
        raise ErrorConversion(
            "No se pudo extraer el audio." + (f"\n{detalle[-1][:120]}" if detalle else ""))

    return destino


def duracion(archivo):
    """Segundos que dura un archivo, para guardarlo en la biblioteca."""
    carpeta = ruta_ffmpeg()
    if not carpeta:
        return 0
    r = subprocess.run(
        [os.path.join(carpeta, "ffprobe.exe"), "-v", "error", "-show_entries",
         "format=duration", "-of", "csv=p=0", archivo],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    try:
        return int(float((r.stdout or "0").strip()))
    except ValueError:
        return 0
