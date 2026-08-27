# -*- coding: utf-8 -*-
"""Importar listas de reproduccion de Spotify, Apple Music y YouTube Music.

Se leen los datos publicos de la lista (que canciones tiene) y despues cada
cancion se busca y se descarga desde YouTube.

Cuantas canciones se pueden leer de cada sitio:
  * YouTube / YouTube Music -> la lista entera, sin limite.
  * Spotify -> 50 con la pagina publica; la lista completa si se configuran
    credenciales gratuitas de la API oficial.
  * Apple Music -> alrededor de 100, que es lo que trae su propia pagina.

Lo que NO hace, porque no se puede: convertir los archivos que Spotify, Apple
Music o YouTube Premium guardan en el telefono para escuchar sin conexion. Esos
archivos van cifrados con DRM y solo sirven dentro de su propia app.
"""

import base64
import html
import json
import re
import time
from urllib.parse import urlparse

import requests

AGENTE = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
          "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")
CABECERAS = {"User-Agent": AGENTE, "Accept-Language": "es-ES,es;q=0.9,en;q=0.8"}


class ErrorLista(Exception):
    """Problema contable al usuario."""


def _limpiar(texto):
    return html.unescape(re.sub(r"\s+", " ", str(texto or ""))).strip()


def detectar_plataforma(url: str) -> str:
    try:
        host = (urlparse(url).hostname or "").lower()
    except ValueError:
        return ""
    if "spotify" in host:
        return "spotify"
    if "music.apple" in host or "itunes.apple" in host:
        return "apple"
    if "youtube" in host or "youtu.be" in host:
        return "youtube"
    return ""


def es_lista_soportada(url: str) -> bool:
    return detectar_plataforma(url) != ""


def _buscar_clave(objeto, clave, profundidad=0):
    """Busca una clave a cualquier nivel del JSON, sin perderse en el camino."""
    if profundidad > 14:
        return None
    if isinstance(objeto, dict):
        if clave in objeto:
            return objeto[clave]
        for valor in objeto.values():
            hallado = _buscar_clave(valor, clave, profundidad + 1)
            if hallado is not None:
                return hallado
    elif isinstance(objeto, list):
        for valor in objeto[:60]:
            hallado = _buscar_clave(valor, clave, profundidad + 1)
            if hallado is not None:
                return hallado
    return None


# ---------------------------------------------------------------- Spotify

_token_spotify = {"valor": "", "caduca": 0}


def _token_api_spotify(ajustes):
    """Token de la API oficial. Hace falta un ID y un secreto gratuitos."""
    def _valor(clave):
        try:
            return (ajustes[clave] or "").strip() if ajustes else ""
        except (KeyError, TypeError):
            return ""

    ident = _valor("spotify_id")
    secreto = _valor("spotify_secreto")
    if not ident or not secreto:
        return ""

    if _token_spotify["valor"] and time.time() < _token_spotify["caduca"]:
        return _token_spotify["valor"]

    credencial = base64.b64encode(f"{ident}:{secreto}".encode()).decode()
    try:
        r = requests.post(
            "https://accounts.spotify.com/api/token",
            data={"grant_type": "client_credentials"},
            headers={"Authorization": f"Basic {credencial}"},
            timeout=20,
        )
    except requests.RequestException:
        return ""
    if r.status_code != 200:
        return ""

    datos = r.json()
    _token_spotify["valor"] = datos.get("access_token", "")
    _token_spotify["caduca"] = time.time() + int(datos.get("expires_in", 3600)) - 60
    return _token_spotify["valor"]


def _spotify_api(tipo, ident, token):
    """Lee la lista entera paginando de 100 en 100."""
    cab = {"Authorization": f"Bearer {token}"}
    base = "https://api.spotify.com/v1"

    if tipo == "track":
        r = requests.get(f"{base}/tracks/{ident}", headers=cab, timeout=25)
        if r.status_code != 200:
            raise ErrorLista("Spotify no devolvio esa cancion.")
        t = r.json()
        return {
            "titulo": _limpiar(t.get("name")),
            "autor": ", ".join(a.get("name", "") for a in t.get("artists", [])),
            "portada": (t.get("album", {}).get("images") or [{}])[0].get("url", ""),
            "canciones": [_cancion_spotify(t)],
        }

    r = requests.get(f"{base}/{tipo}s/{ident}", headers=cab, timeout=25)
    if r.status_code == 404:
        raise ErrorLista("Esa lista no existe o es privada.")
    if r.status_code != 200:
        raise ErrorLista("Spotify rechazo la peticion. Revisa las credenciales.")
    cabecera = r.json()

    canciones = []
    siguiente = f"{base}/{tipo}s/{ident}/tracks?limit=100"
    while siguiente and len(canciones) < 5000:
        rr = requests.get(siguiente, headers=cab, timeout=30)
        if rr.status_code != 200:
            break
        pagina = rr.json()
        for fila in pagina.get("items", []):
            pista = fila.get("track") if tipo == "playlist" else fila
            if isinstance(pista, dict) and pista.get("name"):
                canciones.append(_cancion_spotify(pista))
        siguiente = pagina.get("next")

    imagenes = cabecera.get("images") or []
    return {
        "titulo": _limpiar(cabecera.get("name")),
        "autor": _limpiar((cabecera.get("owner") or {}).get("display_name", "")),
        "portada": imagenes[0].get("url", "") if imagenes else "",
        "canciones": canciones,
    }


def _cancion_spotify(pista):
    return {
        "titulo": _limpiar(pista.get("name")),
        "artista": ", ".join(a.get("name", "") for a in pista.get("artists", [])),
        "duracion": int((pista.get("duration_ms") or 0) / 1000),
    }


def _spotify_pagina(tipo, ident):
    """Sin credenciales solo se puede leer lo que ensena la pagina publica."""
    try:
        r = requests.get(f"https://open.spotify.com/embed/{tipo}/{ident}",
                         headers=CABECERAS, timeout=25)
    except requests.RequestException as e:
        raise ErrorLista(f"No se pudo conectar con Spotify: {e}") from e
    if r.status_code != 200:
        raise ErrorLista("Spotify no devolvio esa lista. Comprueba que sea publica.")
    r.encoding = "utf-8"

    bloque = re.search(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', r.text, re.S)
    if not bloque:
        raise ErrorLista(
            "Spotify cambio su pagina y no se pudieron leer las canciones.")
    try:
        datos = json.loads(bloque.group(1))
    except json.JSONDecodeError as e:
        raise ErrorLista("La respuesta de Spotify no se entendio.") from e

    entidad = _buscar_clave(datos, "entity") or {}
    pistas = entidad.get("trackList") or _buscar_clave(datos, "trackList") or []
    if not pistas:
        raise ErrorLista("Esa lista de Spotify esta vacia o es privada.")

    canciones = []
    for p in pistas:
        titulo = _limpiar(p.get("title"))
        if titulo:
            canciones.append({
                "titulo": titulo,
                "artista": _limpiar(p.get("subtitle")),
                "duracion": int((p.get("duration") or 0) / 1000),
            })

    imagenes = (entidad.get("coverArt") or {}).get("sources") or []
    return {
        "titulo": _limpiar(entidad.get("name")) or "Lista de Spotify",
        "autor": _limpiar(entidad.get("subtitle")),
        "portada": imagenes[-1].get("url", "") if imagenes else "",
        "canciones": canciones,
    }


def _spotify(url: str, ajustes) -> dict:
    m = re.search(r"/(playlist|album|track)/([A-Za-z0-9]+)", url)
    if not m:
        raise ErrorLista("Ese enlace de Spotify no es de una lista, un album ni una cancion.")
    tipo, ident = m.group(1), m.group(2)

    token = _token_api_spotify(ajustes)
    if token:
        try:
            datos = _spotify_api(tipo, ident, token)
            datos["plataforma"] = "Spotify"
            datos["completa"] = True
            return datos
        except ErrorLista:
            raise
        except Exception:
            pass  # si la API falla, al menos damos lo de la pagina publica

    datos = _spotify_pagina(tipo, ident)
    datos["plataforma"] = "Spotify"
    datos["completa"] = len(datos["canciones"]) < 50
    if not datos["completa"]:
        datos["aviso"] = (
            "Spotify solo deja ver 50 canciones sin credenciales. Configura tu ID "
            "y secreto de Spotify en el servidor para traer la lista entera."
        )
    return datos


# ---------------------------------------------------------------- Apple Music

def _apple(url: str) -> dict:
    try:
        r = requests.get(url, headers=CABECERAS, timeout=25)
    except requests.RequestException as e:
        raise ErrorLista(f"No se pudo conectar con Apple Music: {e}") from e
    if r.status_code != 200:
        raise ErrorLista("Apple Music no devolvio esa lista. Comprueba que sea publica.")
    r.encoding = "utf-8"

    titulo, autor = _apple_titulo(r.text)
    canciones = _apple_del_bloque(r.text, titulo)
    if not canciones:
        canciones, titulo_ld, autor_ld = _apple_del_jsonld(r.text)
        titulo = titulo_ld or titulo
        autor = autor_ld or autor

    if not canciones:
        raise ErrorLista("Esa pagina de Apple Music no tiene canciones que leer.")

    return {
        "plataforma": "Apple Music",
        "titulo": titulo or "Lista de Apple Music",
        "autor": autor,
        "portada": _portada_apple(r.text),
        "canciones": canciones,
        "completa": False,
        "aviso": "Apple Music solo publica una parte de las listas largas en su "
                 "pagina; puede que falten canciones del final.",
    }


def _apple_del_bloque(pagina, titulo_lista=""):
    """La propia pagina lleva mas canciones que los datos para buscadores."""
    bloque = re.search(
        r'<script[^>]*id="serialized-server-data"[^>]*>(.*?)</script>', pagina, re.S)
    if not bloque:
        return []
    try:
        datos = json.loads(bloque.group(1))
    except json.JSONDecodeError:
        return []

    encontradas = []
    vistas = set()

    def recorrer(o, prof=0):
        if prof > 18:
            return
        if isinstance(o, dict):
            if o.get("kind") == "song" or ("title" in o and "subtitleLinks" in o):
                titulo = _limpiar(o.get("title") or o.get("name"))
                enlaces = o.get("subtitleLinks") or []
                artista = ", ".join(
                    _limpiar(a.get("title")) for a in enlaces if isinstance(a, dict))
                # la cabecera de la lista aparece con la misma forma que una
                # cancion: se descarta comparandola con el titulo de la pagina
                es_cabecera = (titulo_lista
                               and titulo.lower() == titulo_lista.lower())
                if (titulo and artista and not es_cabecera
                        and (titulo, artista) not in vistas):
                    vistas.add((titulo, artista))
                    encontradas.append({
                        "titulo": titulo, "artista": artista, "duracion": 0})
            for v in o.values():
                recorrer(v, prof + 1)
        elif isinstance(o, list):
            for v in o:
                recorrer(v, prof + 1)

    recorrer(datos)
    return encontradas


def _apple_del_jsonld(pagina):
    bloques = re.findall(
        r'<script[^>]*type="application/ld\+json"[^>]*>(.*?)</script>', pagina, re.S)
    for bruto in bloques:
        try:
            datos = json.loads(bruto)
        except json.JSONDecodeError:
            continue
        if datos.get("@type") not in ("MusicPlaylist", "MusicAlbum"):
            continue
        artista_album = _artista_de(datos.get("byArtist"))
        canciones = []
        for p in datos.get("track") or datos.get("tracks") or []:
            if isinstance(p, dict) and p.get("name"):
                canciones.append({
                    "titulo": _limpiar(p.get("name")),
                    "artista": _artista_de(p.get("byArtist")) or artista_album,
                    "duracion": _duracion_iso(p.get("duration")),
                })
        if canciones:
            return canciones, _limpiar(datos.get("name")), artista_album
    return [], "", ""


def _apple_titulo(pagina):
    m = re.search(r'<meta property="og:title" content="([^"]+)"', pagina)
    titulo = html.unescape(m.group(1)) if m else ""
    for coletilla in (" on Apple Music", " - Apple Music"):
        if titulo.endswith(coletilla):
            titulo = titulo[: -len(coletilla)]
    m2 = re.search(r'<meta property="og:description" content="([^"]{0,80})"', pagina)
    return titulo, html.unescape(m2.group(1)) if m2 else ""


def _artista_de(valor):
    if isinstance(valor, list):
        return ", ".join(_limpiar(a.get("name")) for a in valor if isinstance(a, dict))
    if isinstance(valor, dict):
        return _limpiar(valor.get("name"))
    return _limpiar(valor) if valor else ""


def _duracion_iso(texto):
    if not texto:
        return 0
    m = re.match(r"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", str(texto))
    if not m:
        return 0
    horas, minutos, segundos = (int(x) if x else 0 for x in m.groups())
    return horas * 3600 + minutos * 60 + segundos


def _portada_apple(pagina):
    m = re.search(r'<meta property="og:image" content="([^"]+)"', pagina)
    return html.unescape(m.group(1)) if m else ""


# ---------------------------------------------------------------- YouTube

def _youtube(url: str, ajustes) -> dict:
    """YouTube y YouTube Music, sin tope de canciones."""
    import yt_dlp

    opciones = {
        "quiet": True, "no_warnings": True, "skip_download": True,
        "extract_flat": "in_playlist", "socket_timeout": 30, "no_color": True,
        "ignoreerrors": True,
    }
    try:
        nav = (ajustes["navegador_cookies"] if ajustes else "ninguno") or "ninguno"
    except (KeyError, TypeError):
        nav = "ninguno"
    if nav and nav != "ninguno":
        opciones["cookiesfrombrowser"] = (nav,)

    try:
        with yt_dlp.YoutubeDL(opciones) as ydl:
            info = ydl.extract_info(url, download=False)
    except Exception as e:
        raise ErrorLista(f"No se pudo leer esa lista de YouTube: {str(e)[:90]}") from e

    info = info or {}
    if info.get("_type") != "playlist":
        return {
            "plataforma": "YouTube",
            "titulo": info.get("title", ""),
            "autor": info.get("uploader", ""),
            "portada": info.get("thumbnail", ""),
            "completa": True,
            "canciones": [{
                "titulo": info.get("title", ""),
                "artista": info.get("uploader", ""),
                "duracion": int(info.get("duration") or 0),
                "url": info.get("webpage_url") or url,
            }],
        }

    canciones = []
    for e in info.get("entries") or []:
        if not e:
            continue
        enlace = e.get("url") or e.get("webpage_url") or ""
        if e.get("ie_key") == "Youtube" and enlace and not enlace.startswith("http"):
            enlace = "https://www.youtube.com/watch?v=" + enlace
        if not enlace:
            continue
        mini = e.get("thumbnail") or ""
        if not mini and e.get("thumbnails"):
            mini = e["thumbnails"][-1].get("url", "")
        canciones.append({
            "titulo": e.get("title") or "",
            "artista": e.get("uploader") or e.get("channel") or "",
            "duracion": int(e.get("duration") or 0),
            "url": enlace,
            "miniatura": mini,
        })

    return {
        "plataforma": "YouTube",
        "titulo": info.get("title", "Lista"),
        "autor": info.get("uploader", "") or info.get("channel", ""),
        "portada": "",
        "completa": True,
        "canciones": canciones,
    }


# ---------------------------------------------------------------- publico

def leer(url: str, ajustes) -> dict:
    """Devuelve las canciones de una lista de Spotify, Apple Music o YouTube."""
    url = (url or "").strip()
    plataforma = detectar_plataforma(url)

    if plataforma == "spotify":
        resultado = _spotify(url, ajustes)
    elif plataforma == "apple":
        resultado = _apple(url)
    elif plataforma == "youtube":
        resultado = _youtube(url, ajustes)
    else:
        raise ErrorLista(
            "Pega el enlace de una lista de Spotify, Apple Music o YouTube Music.")

    for c in resultado["canciones"]:
        if not c.get("url"):
            c["busqueda"] = " ".join(x for x in [c.get("artista"), c.get("titulo")] if x)

    resultado["total"] = len(resultado["canciones"])
    resultado.setdefault("completa", True)
    resultado.setdefault("aviso", "")
    return resultado
