# -*- coding: utf-8 -*-
"""Extractor y descargador para publicaciones publicas de Telegram (t.me).

yt-dlp no soporta Telegram, asi que aqui se resuelve el enlace del medio
leyendo la version incrustada (embed) de la publicacion.
"""

import html
import os
import re
import time
from urllib.parse import urlparse, urlunparse

import requests


AGENTE = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
          "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")


class ErrorTelegram(Exception):
    pass


def _url_embed(url: str) -> str:
    p = urlparse(url)
    ruta = p.path
    # t.me/s/canal/123 -> t.me/canal/123
    if ruta.startswith("/s/"):
        ruta = "/" + ruta[3:]
    return urlunparse((p.scheme or "https", p.netloc, ruta, "", "embed=1&mode=tme", ""))


def _limpiar_texto(bruto: str) -> str:
    texto = re.sub(r"<br\s*/?>", " ", bruto or "")
    texto = re.sub(r"<[^>]+>", "", texto)
    return html.unescape(texto).strip()


def _nombre_seguro(nombre: str, limite=120) -> str:
    nombre = re.sub(r'[<>:"/\|?*\x00-\x1f]', "_", nombre or "")
    nombre = re.sub(r"\s+", " ", nombre).strip(" .")
    return (nombre[:limite].strip() or "telegram")


def extraer_info(url: str, tiempo_espera=25) -> dict:
    """Devuelve datos del medio publico de una publicacion de Telegram."""
    if not re.search(r"/\d+", urlparse(url).path or ""):
        raise ErrorTelegram(
            "Ese enlace apunta a un canal completo. Abre la publicacion concreta "
            "y copia su enlace (por ejemplo https://t.me/canal/1234)."
        )

    cab = {"User-Agent": AGENTE, "Accept-Language": "es-ES,es;q=0.9,en;q=0.8"}
    try:
        r = requests.get(_url_embed(url), headers=cab, timeout=tiempo_espera)
    except requests.RequestException as e:
        raise ErrorTelegram(f"No se pudo conectar con Telegram: {e}") from e
    if r.status_code != 200:
        raise ErrorTelegram(f"Telegram respondio {r.status_code}")
    pagina = r.text

    if "tgme_widget_message" not in pagina:
        raise ErrorTelegram(
            "La publicacion no es publica o fue borrada. Telegram solo permite "
            "descargar contenido de canales publicos por enlace."
        )

    autor = ""
    m = re.search(r'tgme_widget_message_author_name[^>]*>(.*?)</a>', pagina, re.S)
    if not m:
        m = re.search(r'tgme_widget_message_owner_name[^>]*>(.*?)</a>', pagina, re.S)
    if m:
        autor = _limpiar_texto(m.group(1))

    texto = ""
    m = re.search(r'class="tgme_widget_message_text[^"]*"[^>]*>(.*?)</div>', pagina, re.S)
    if m:
        texto = _limpiar_texto(m.group(1))

    miniatura = ""
    m = re.search(r'tgme_widget_message_video_thumb[^"]*"[^>]*style="[^"]*url\(\'([^\']+)\'\)', pagina)
    if m:
        miniatura = html.unescape(m.group(1))

    duracion = 0
    m = re.search(r'tgme_widget_message_video_duration[^>]*>([\d:]+)<', pagina)
    if m:
        partes = [int(x) for x in m.group(1).split(":")]
        for x in partes:
            duracion = duracion * 60 + x

    # 1) video normal o video redondo
    directo, tipo, ext = "", "", ""
    m = re.search(r'<video[^>]+src="([^"]+)"', pagina)
    if m:
        directo, tipo, ext = html.unescape(m.group(1)), "video", "mp4"

    # 2) documento adjunto (archivos, gifs grandes, audio)
    if not directo:
        m = re.search(r'tgme_widget_message_document_wrap"[^>]*href="([^"]+)"', pagina)
        if m:
            directo = html.unescape(m.group(1))
            tipo = "documento"
            ext = os.path.splitext(urlparse(directo).path)[1].lstrip(".") or "bin"

    # 3) audio / nota de voz
    if not directo:
        m = re.search(r'<audio[^>]+src="([^"]+)"', pagina)
        if m:
            directo, tipo, ext = html.unescape(m.group(1)), "audio", "ogg"

    # 4) foto
    if not directo:
        m = re.search(r'tgme_widget_message_photo_wrap[^"]*"[^>]*style="[^"]*url\(\'([^\']+)\'\)', pagina)
        if m:
            directo, tipo, ext = html.unescape(m.group(1)), "foto", "jpg"

    if not directo:
        raise ErrorTelegram(
            "La publicacion no contiene ningun archivo descargable (parece ser solo texto)."
        )

    if not miniatura and tipo == "foto":
        miniatura = directo

    titulo_base = texto or f"{autor} - publicacion" if autor else texto
    if not titulo_base:
        titulo_base = "Telegram " + (urlparse(url).path.strip("/").replace("/", " ") or "media")

    return {
        "titulo": _nombre_seguro(titulo_base),
        "autor": autor or "Telegram",
        "url_directa": directo,
        "tipo": tipo,
        "ext": ext,
        "miniatura": miniatura,
        "duracion": duracion,
        "texto": texto,
    }


def descargar(info: dict, destino_carpeta: str, al_progresar=None, cancelado=None,
              limite_kbs=0) -> str:
    """Descarga el medio con reanudacion. Devuelve la ruta final del archivo."""
    os.makedirs(destino_carpeta, exist_ok=True)
    nombre = f"{info['titulo']}.{info['ext']}"
    destino = os.path.join(destino_carpeta, nombre)

    # evitar pisar un archivo existente
    contador = 1
    raiz, extension = os.path.splitext(destino)
    while os.path.exists(destino):
        destino = f"{raiz} ({contador}){extension}"
        contador += 1

    parcial = destino + ".part"
    ya = os.path.getsize(parcial) if os.path.exists(parcial) else 0

    cab = {"User-Agent": AGENTE, "Referer": "https://t.me/"}
    if ya:
        cab["Range"] = f"bytes={ya}-"

    r = requests.get(info["url_directa"], headers=cab, stream=True, timeout=30)
    if r.status_code not in (200, 206):
        raise ErrorTelegram(f"El servidor de Telegram respondio {r.status_code}")
    if r.status_code == 200:
        ya = 0  # el servidor ignoro el rango: empezamos de cero

    total = int(r.headers.get("Content-Length", 0)) + ya
    descargado = ya
    inicio = time.time()
    ultimo_aviso = 0.0

    modo = "ab" if ya else "wb"
    with open(parcial, modo) as f:
        for trozo in r.iter_content(chunk_size=262144):
            if cancelado and cancelado():
                r.close()
                raise KeyboardInterrupt("cancelado")
            if not trozo:
                continue
            f.write(trozo)
            descargado += len(trozo)

            if limite_kbs:
                esperado = (descargado - ya) / (limite_kbs * 1024.0)
                real = time.time() - inicio
                if esperado > real:
                    time.sleep(min(esperado - real, 1.0))

            ahora = time.time()
            if al_progresar and (ahora - ultimo_aviso > 0.25):
                ultimo_aviso = ahora
                transcurrido = max(ahora - inicio, 0.001)
                velocidad = (descargado - ya) / transcurrido
                eta = int((total - descargado) / velocidad) if velocidad > 0 and total else 0
                al_progresar({
                    "descargado": descargado,
                    "total": total,
                    "velocidad": velocidad,
                    "eta": eta,
                })

    os.replace(parcial, destino)
    if al_progresar:
        al_progresar({"descargado": descargado, "total": total or descargado,
                      "velocidad": 0, "eta": 0})
    return destino
