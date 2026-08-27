# -*- coding: utf-8 -*-
"""Deteccion de la red social a partir de la URL."""

import re
from dataclasses import dataclass
from urllib.parse import urlparse


@dataclass(frozen=True)
class Plataforma:
    clave: str
    nombre: str
    color: str          # color de marca para el chip
    icono: str          # letra o simbolo mostrado en el chip
    motor: str = "ytdlp"  # "ytdlp" o "telegram"


DESCONOCIDA = Plataforma("web", "Enlace web", "#6B7280", "@")

# clave -> (nombre, color, icono, dominios)
_CATALOGO = [
    ("youtube",   "YouTube",     "#FF0033", "Y", ["youtube.com", "youtu.be", "youtube-nocookie.com", "m.youtube.com"]),
    ("ytmusic",   "YouTube Music", "#FF0033", "M", ["music.youtube.com"]),
    ("instagram", "Instagram",   "#E1306C", "I", ["instagram.com", "instagr.am", "ddinstagram.com"]),
    ("tiktok",    "TikTok",      "#00F2EA", "T", ["tiktok.com", "vm.tiktok.com", "vt.tiktok.com"]),
    ("twitter",   "X / Twitter", "#1D9BF0", "X", ["twitter.com", "x.com", "t.co", "fxtwitter.com", "vxtwitter.com"]),
    ("facebook",  "Facebook",    "#1877F2", "F", ["facebook.com", "fb.watch", "fb.com", "m.facebook.com"]),
    ("telegram",  "Telegram",    "#2AABEE", "TG", ["t.me", "telegram.me", "telegram.dog"]),
    ("reddit",    "Reddit",      "#FF4500", "R", ["reddit.com", "redd.it", "v.redd.it", "old.reddit.com"]),
    ("twitch",    "Twitch",      "#9146FF", "TW", ["twitch.tv", "clips.twitch.tv"]),
    ("vimeo",     "Vimeo",       "#1AB7EA", "V", ["vimeo.com", "player.vimeo.com"]),
    ("dailymotion", "Dailymotion", "#0066DC", "D", ["dailymotion.com", "dai.ly"]),
    ("pinterest", "Pinterest",   "#E60023", "P", ["pinterest.com", "pin.it", "pinterest.es"]),
    ("threads",   "Threads",     "#8A8A8A", "TH", ["threads.net", "threads.com"]),
    ("bluesky",   "Bluesky",     "#0085FF", "B", ["bsky.app"]),
    ("snapchat",  "Snapchat",    "#FFFC00", "S", ["snapchat.com"]),
    ("linkedin",  "LinkedIn",    "#0A66C2", "in", ["linkedin.com", "lnkd.in"]),
    ("tumblr",    "Tumblr",      "#36465D", "TB", ["tumblr.com"]),
    ("kick",      "Kick",        "#53FC18", "K", ["kick.com"]),
    ("rumble",    "Rumble",      "#85C742", "RB", ["rumble.com"]),
    ("odysee",    "Odysee",      "#EF1970", "O", ["odysee.com", "lbry.tv"]),
    ("bilibili",  "Bilibili",    "#00A1D6", "BL", ["bilibili.com", "b23.tv"]),
    ("douyin",    "Douyin",      "#FE2C55", "DY", ["douyin.com", "iesdouyin.com"]),
    ("weibo",     "Weibo",       "#E6162D", "W", ["weibo.com", "weibo.cn"]),
    ("xiaohongshu", "Xiaohongshu", "#FF2442", "XH", ["xiaohongshu.com", "xhslink.com"]),
    ("niconico",  "Niconico",    "#252525", "N", ["nicovideo.jp", "nico.ms"]),
    ("vk",        "VK",          "#0077FF", "VK", ["vk.com", "vkvideo.ru", "vk.ru"]),
    ("ok",        "OK.ru",       "#EE8208", "OK", ["ok.ru", "odnoklassniki.ru"]),
    ("soundcloud", "SoundCloud", "#FF5500", "SC", ["soundcloud.com", "on.soundcloud.com", "snd.sc"]),
    ("bandcamp",  "Bandcamp",    "#629AA9", "BC", ["bandcamp.com"]),
    ("mixcloud",  "Mixcloud",    "#5000FF", "MC", ["mixcloud.com"]),
    ("imgur",     "Imgur",       "#1BB76E", "IM", ["imgur.com", "i.imgur.com"]),
    ("streamable", "Streamable", "#0F90FA", "ST", ["streamable.com"]),
    ("9gag",      "9GAG",        "#000000", "9", ["9gag.com"]),
    ("likee",     "Likee",       "#F8CB00", "L", ["likee.video", "l.likee.video"]),
    ("triller",   "Triller",     "#FF0050", "TR", ["triller.co"]),
    ("dropbox",   "Dropbox",     "#0061FF", "DB", ["dropbox.com"]),
    ("drive",     "Google Drive", "#1FA463", "GD", ["drive.google.com", "docs.google.com"]),
    ("archive",   "Archive.org", "#666666", "AR", ["archive.org"]),
    ("ted",       "TED",         "#E62B1E", "TE", ["ted.com"]),
    ("coub",      "Coub",        "#0F3A5E", "CB", ["coub.com"]),
    ("newgrounds", "Newgrounds", "#FFB300", "NG", ["newgrounds.com"]),
    ("patreon",   "Patreon",     "#FF424D", "PT", ["patreon.com"]),
    ("substack",  "Substack",    "#FF6719", "SB", ["substack.com"]),
]

_INDICE = {}
_PLATAFORMAS = {}
for _clave, _nombre, _color, _icono, _dominios in _CATALOGO:
    _motor = "telegram" if _clave == "telegram" else "ytdlp"
    _p = Plataforma(_clave, _nombre, _color, _icono, _motor)
    _PLATAFORMAS[_clave] = _p
    for _d in _dominios:
        _INDICE[_d] = _p


def normalizar(url: str) -> str:
    """Limpia espacios y agrega esquema si falta."""
    url = (url or "").strip().strip('"').strip("'")
    if not url:
        return ""
    if url.startswith("//"):
        url = "https:" + url
    elif not re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*://", url):
        url = "https://" + url
    return url


def detectar(url: str) -> Plataforma:
    """Devuelve la plataforma correspondiente a la URL."""
    url = normalizar(url)
    if not url:
        return DESCONOCIDA
    try:
        host = (urlparse(url).hostname or "").lower()
    except ValueError:
        return DESCONOCIDA
    if host.startswith("www."):
        host = host[4:]
    if host in _INDICE:
        return _INDICE[host]
    # subdominios: foo.bar.youtube.com -> youtube.com
    partes = host.split(".")
    for i in range(1, len(partes) - 1):
        cand = ".".join(partes[i:])
        if cand in _INDICE:
            return _INDICE[cand]
    return DESCONOCIDA


def plataforma_por_clave(clave: str) -> Plataforma:
    return _PLATAFORMAS.get(clave, DESCONOCIDA)


def es_url(texto: str) -> bool:
    """Comprueba si un texto suelto parece una URL descargable."""
    texto = (texto or "").strip()
    if not texto or " " in texto or "\n" in texto:
        return False
    if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*://", texto):
        return True
    return bool(re.match(r"^[\w-]+(\.[\w-]+)+(/|$|\?)", texto))


def extraer_urls(texto: str) -> list:
    """Saca todas las URLs de un bloque de texto pegado."""
    encontrados = []
    for linea in re.split(r"[\s,;]+", texto or ""):
        linea = linea.strip().strip('.,;)"\'')
        if es_url(linea):
            u = normalizar(linea)
            if u not in encontrados:
                encontrados.append(u)
    return encontrados


def nombres_soportados() -> list:
    """Lista legible de plataformas destacadas."""
    vistos, salida = set(), []
    for clave, nombre, *_ in _CATALOGO:
        if nombre not in vistos:
            vistos.add(nombre)
            salida.append(nombre)
    return salida


# ---------------------------------------------------------------- descargable

# Rutas que corresponden a una publicacion concreta, no a una portada o un perfil.
_RUTAS = {
    "youtube": [r"^/watch", r"^/shorts/[\w-]+", r"^/live/[\w-]+", r"^/embed/[\w-]+",
                r"^/playlist"],
    "ytmusic": [r"^/watch", r"^/playlist"],
    "instagram": [r"^/reels?/[\w-]+", r"^/p/[\w-]+", r"^/tv/[\w-]+",
                  r"^/[\w.]+/reels?/[\w-]+"],
    "tiktok": [r"^/@[\w.-]+/video/\d+", r"^/v/\d+", r"^/t/\w+", r"^/\w+$"],
    "twitter": [r"^/\w+/status/\d+"],
    "facebook": [r"^/watch", r"^/reel/\d+", r"^/[\w.]+/videos/", r"^/video", r"^/\w+$"],
    "telegram": [r"/\d+"],
    "reddit": [r"/comments/\w+", r"^/\w+$"],
    "twitch": [r"^/videos/\d+", r"^/\w+/clip/", r"^/\w+$"],
    "vimeo": [r"^/\d+"],
    "dailymotion": [r"^/video/\w+", r"^/\w+$"],
    "kick": [r"^/\w+/videos/", r"^/video/"],
    "rumble": [r"^/v\w+"],
    "odysee": [r"^/@?[^/]+/[^/]+"],
    "bilibili": [r"^/video/\w+", r"^/\w+$"],
    "niconico": [r"^/watch/\w+"],
    "vk": [r"^/video"],
    "ok": [r"^/video/\d+"],
    "bluesky": [r"^/profile/[^/]+/post/\w+"],
    "threads": [r"^/@[\w.]+/post/\w+"],
    "snapchat": [r"^/spotlight/\w+"],
    "pinterest": [r"^/pin/\d+", r"^/\w+$"],
    "streamable": [r"^/\w+"],
    "9gag": [r"^/gag/\w+"],
    "imgur": [r"^/gallery/\w+", r"^/a/\w+"],
    "coub": [r"^/view/\w+"],
    "ted": [r"^/talks/\w+"],
    "tumblr": [r"/post/\d+"],
    "linkedin": [r"^/posts/"],
    "weibo": [r"^/tv/", r"^/\d+/\w+"],
    "douyin": [r"^/video/\d+"],
    "xiaohongshu": [r"^/explore/\w+"],
    "newgrounds": [r"^/portal/view/\d+"],
    "archive": [r"^/details/"],
    "soundcloud": [r"^/[^/]+/[^/]+"],
    "bandcamp": [r"^/track/", r"^/album/"],
    "mixcloud": [r"^/[^/]+/[^/]+"],
    "likee": [r"^/@?[\w.-]+/video/", r"^/v/"],
    "drive": [r"^/file/d/"],
    "dropbox": [r"^/s/", r"^/scl/"],
    "patreon": [r"^/posts/"],
    "substack": [r"^/p/"],
}

_EXTENSIONES = re.compile(
    r"\.(mp4|m4v|mov|mkv|webm|avi|flv|m3u8|mpd|mp3|m4a|aac|ogg|opus|flac|wav)(\?|$)",
    re.IGNORECASE)


def parece_descargable(url: str) -> bool:
    """True si la direccion apunta a algo que se puede bajar.

    Sirve para ensenar los botones en el navegador sin preguntar antes al motor.
    """
    url = (url or "").strip()
    if not url:
        return False
    try:
        partes = urlparse(normalizar(url))
    except ValueError:
        return False
    if partes.scheme not in ("http", "https"):
        return False

    if _EXTENSIONES.search(partes.path or ""):
        return True

    plataforma = detectar(url)
    if plataforma is DESCONOCIDA:
        return False

    ruta = partes.path or "/"
    for patron in _RUTAS.get(plataforma.clave, []):
        if re.search(patron, ruta):
            return True
    return False
