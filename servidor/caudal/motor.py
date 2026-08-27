# -*- coding: utf-8 -*-
"""Motor del servidor: resuelve enlaces, busca y prepara los archivos con yt-dlp."""

import os
import re
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor

from .config import carpeta_trabajo, ruta_ffmpeg

ESPERANDO, PREPARANDO, LISTO, ERROR, CANCELADO = "esperando", "preparando", "listo", "error", "cancelado"


class Cancelado(Exception):
    pass


class _Registro:
    """Logger de yt-dlp que se queda con el ultimo error."""

    def __init__(self):
        self.ultimo_error = ""

    def debug(self, m):
        pass

    def info(self, m):
        pass

    def warning(self, m):
        pass

    def error(self, m):
        texto = str(m).replace("ERROR:", "").strip()
        if texto:
            self.ultimo_error = texto


def mensaje_amable(texto):
    t = (texto or "").lower()
    if "sign in" in t or "log in" in t or "login required" in t or "cookies" in t or "bot" in t:
        return ("El sitio pide iniciar sesion para ver esto. Configura las cookies del "
                "navegador en el servidor.")
    if "unavailable" in t or "not available" in t or "has been removed" in t:
        return "El contenido ya no esta disponible, fue borrado o es privado."
    if "private" in t:
        return "La publicacion es privada."
    if "unsupported url" in t:
        return "Ese enlace no esta soportado."
    if "geo" in t and "block" in t:
        return "El contenido esta bloqueado en el pais del servidor."
    if "404" in t:
        return "El enlace no existe."
    if "timed out" in t or "timeout" in t:
        return "El servidor tardo demasiado en responder. Reintenta."
    if "no video formats" in t or "requested format" in t:
        return "No hay ningun formato descargable en ese enlace."
    return texto or "No se pudo preparar la descarga."


def nombre_seguro(nombre, limite=110):
    nombre = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", nombre or "")
    nombre = re.sub(r"\s+", " ", nombre).strip(" .")
    return nombre[:limite].strip() or "descarga"


def selector_formato(calidad, tipo="completo", contenedor="mp4"):
    """Mismo criterio que la app de escritorio: MP4 prefiere H.264 + AAC."""
    if tipo == "audio":
        return "ba/b"

    limite = ""
    if calidad and calidad != "mejor":
        try:
            limite = f"[height<={int(calidad)}]"
        except (TypeError, ValueError):
            limite = ""

    if tipo == "video":
        generico = f"bv*{limite}/bv*" if limite else "bv*"
        if contenedor != "mp4":
            return generico
        return f"bv*{limite}[vcodec^=avc1]/{generico}"

    generico = f"bv*{limite}+ba/b{limite}/bv*+ba/b" if limite else "bv*+ba/b"
    if contenedor != "mp4":
        return generico
    return f"bv*{limite}[vcodec^=avc1]+ba[acodec^=mp4a]/{generico}"


# Modo musica: normaliza a un nivel alto (-9 LUFS, mas que el de las plataformas
# de streaming) y limita los picos a -1 dB para que suba el volumen percibido sin
# que se rompa el sonido. Es lo que hace que suene fuerte de verdad, mas que
# subir el volumen del reproductor.
FILTRO_SONORIDAD = "loudnorm=I=-9:TP=-1.0:LRA=9"


def _opciones_red(ajustes):
    op = {}
    nav = ajustes["navegador_cookies"]
    if nav and nav != "ninguno":
        op["cookiesfrombrowser"] = (nav,)
    archivo = ajustes["archivo_cookies"]
    if archivo and os.path.exists(archivo):
        op["cookiefile"] = archivo
    return op


def _duracion_legible(segundos):
    s = int(segundos or 0)
    if s <= 0:
        return ""
    h, resto = divmod(s, 3600)
    m, seg = divmod(resto, 60)
    return f"{h}:{m:02d}:{seg:02d}" if h else f"{m}:{seg:02d}"


def _mejor_miniatura(info):
    mini = info.get("thumbnail") or ""
    if not mini and info.get("thumbnails"):
        mini = info["thumbnails"][-1].get("url", "")
    return mini


# ---------------------------------------------------------------- resolver

def resolver(url, ajustes):
    """Devuelve metadatos y calidades disponibles de un enlace."""
    import yt_dlp

    registro = _Registro()
    opciones = {
        "quiet": True, "no_warnings": True, "logger": registro, "skip_download": True,
        "noplaylist": True, "socket_timeout": 25, "no_color": True, "extract_flat": "in_playlist",
    }
    opciones.update(_opciones_red(ajustes))

    try:
        with yt_dlp.YoutubeDL(opciones) as ydl:
            info = ydl.extract_info(url, download=False)
    except Exception as e:
        raise ValueError(mensaje_amable(registro.ultimo_error or str(e))) from e

    info = info or {}

    if info.get("_type") == "playlist" and info.get("entries") is not None:
        entradas = []
        for e in info["entries"]:
            if not e:
                continue
            enlace = e.get("url") or e.get("webpage_url") or ""
            if e.get("ie_key") == "Youtube" and enlace and not enlace.startswith("http"):
                enlace = "https://www.youtube.com/watch?v=" + enlace
            if not enlace:
                continue
            entradas.append({
                "url": enlace,
                "titulo": e.get("title") or "",
                "autor": e.get("uploader") or e.get("channel") or "",
                "duracion": int(e.get("duration") or 0),
                "duracion_texto": _duracion_legible(e.get("duration")),
                "miniatura": _mejor_miniatura(e),
            })
        return {
            "es_lista": True,
            "titulo": info.get("title") or "Lista",
            "autor": info.get("uploader") or info.get("channel") or "",
            "total": len(entradas),
            "elementos": entradas,
        }

    alturas, tiene_audio = set(), False
    for f in info.get("formats") or []:
        if f.get("vcodec") and f["vcodec"] != "none" and f.get("height"):
            alturas.add(int(f["height"]))
        if f.get("acodec") and f["acodec"] != "none":
            tiene_audio = True

    calidades = []
    etiquetas = {2160: "4K", 1440: "2K", 1080: "Full HD", 720: "HD", 480: "SD", 360: "Ligero"}
    for alto in sorted(alturas, reverse=True):
        nombre = "8K" if alto >= 4320 else etiquetas.get(alto)
        # sin nombre comercial basta con la resolucion: evita el feo "240p · 240p"
        etiqueta = f"{nombre} · {alto}p" if nombre else f"{alto}p"
        calidades.append({"valor": str(alto), "etiqueta": etiqueta, "altura": alto})

    return {
        "es_lista": False,
        "url": info.get("webpage_url") or url,
        "titulo": info.get("title") or url,
        "autor": info.get("uploader") or info.get("channel") or info.get("uploader_id") or "",
        "duracion": int(info.get("duration") or 0),
        "duracion_texto": _duracion_legible(info.get("duration")),
        "miniatura": _mejor_miniatura(info),
        "plataforma": (info.get("extractor_key") or "").replace("Generic", "Web"),
        "tiene_video": bool(alturas),
        "tiene_audio": tiene_audio,
        "calidades": calidades,
        "es_directo": bool(info.get("is_live")),
    }


# ---------------------------------------------------------------- buscar

def buscar(consulta, limite, ajustes):
    """Busca en YouTube. Pensado para encontrar musica por nombre."""
    import yt_dlp

    consulta = (consulta or "").strip()
    if not consulta:
        return []

    registro = _Registro()
    opciones = {
        "quiet": True, "no_warnings": True, "logger": registro, "skip_download": True,
        "extract_flat": True, "socket_timeout": 20, "no_color": True,
    }
    opciones.update(_opciones_red(ajustes))

    try:
        with yt_dlp.YoutubeDL(opciones) as ydl:
            info = ydl.extract_info(f"ytsearch{int(limite)}:{consulta}", download=False)
    except Exception as e:
        raise ValueError(mensaje_amable(registro.ultimo_error or str(e))) from e

    salida = []
    for e in (info or {}).get("entries") or []:
        if not e:
            continue
        enlace = e.get("url") or ""
        if enlace and not enlace.startswith("http"):
            enlace = "https://www.youtube.com/watch?v=" + enlace
        salida.append({
            "url": enlace,
            "titulo": e.get("title") or "",
            "autor": e.get("uploader") or e.get("channel") or "",
            "duracion": int(e.get("duration") or 0),
            "duracion_texto": _duracion_legible(e.get("duration")),
            "miniatura": _mejor_miniatura(e),
            "vistas": int(e.get("view_count") or 0),
        })
    return salida


# ---------------------------------------------------------------- trabajos

class Trabajo:
    def __init__(self, url, tipo, calidad, formato_audio, contenedor, dueno=None,
                 refuerzo=False):
        self.id = uuid.uuid4().hex[:14]
        self.dueno = dueno          # id del usuario que lo pidio
        self.refuerzo = refuerzo    # modo musica: sube la sonoridad al convertir
        self.url = url
        self.tipo = tipo
        self.calidad = calidad
        self.formato_audio = formato_audio
        self.contenedor = contenedor
        self.estado = ESPERANDO
        self.progreso = 0.0
        self.mensaje = "En cola"
        self.error = ""
        self.archivo = ""
        self.nombre = ""
        self.tamano = 0
        self.titulo = ""
        self.autor = ""
        self.miniatura = ""
        self.duracion = 0
        self.creado = time.time()
        self.cancelar = False

    def a_dict(self):
        return {
            "id": self.id,
            "estado": self.estado,
            "progreso": round(self.progreso, 1),
            "mensaje": self.mensaje,
            "error": self.error,
            "titulo": self.titulo,
            "autor": self.autor,
            "miniatura": self.miniatura,
            "duracion": self.duracion,
            "nombre": self.nombre,
            "tamano": self.tamano,
            "tipo": self.tipo,
            "refuerzo": self.refuerzo,
        }


class Gestor:
    def __init__(self, ajustes):
        self.ajustes = ajustes
        self.trabajos = {}
        self.lock = threading.Lock()
        self.pool = ThreadPoolExecutor(max_workers=int(ajustes["max_simultaneas"]),
                                       thread_name_prefix="caudal")

    def crear(self, url, tipo="completo", calidad="mejor", formato_audio="mp3",
              contenedor="mp4", dueno=None, refuerzo=False):
        t = Trabajo(url, tipo, calidad, formato_audio, contenedor, dueno, refuerzo)
        with self.lock:
            self.trabajos[t.id] = t
        self.pool.submit(self._ejecutar, t)
        return t

    def obtener(self, ident):
        with self.lock:
            return self.trabajos.get(ident)

    def cancelar(self, ident):
        t = self.obtener(ident)
        if not t:
            return False
        t.cancelar = True
        if t.estado in (ESPERANDO, PREPARANDO):
            t.estado = CANCELADO
            t.mensaje = "Cancelado"
        self._borrar_archivo(t)
        return True

    def _borrar_archivo(self, t):
        if t.archivo and os.path.exists(t.archivo):
            try:
                os.remove(t.archivo)
            except OSError:
                pass

    def limpiar(self):
        """Borra lo viejo y controla el tamano total de la carpeta temporal."""
        limite = float(self.ajustes["horas_retencion"]) * 3600
        ahora = time.time()
        with self.lock:
            viejos = [t for t in self.trabajos.values() if ahora - t.creado > limite]
        for t in viejos:
            self._borrar_archivo(t)
            with self.lock:
                self.trabajos.pop(t.id, None)

        carpeta = carpeta_trabajo()
        try:
            archivos = [(os.path.join(carpeta, f), os.path.getmtime(os.path.join(carpeta, f)),
                         os.path.getsize(os.path.join(carpeta, f)))
                        for f in os.listdir(carpeta)]
        except OSError:
            return
        total = sum(a[2] for a in archivos)
        tope = float(self.ajustes["max_gb_temporal"]) * 1024 ** 3
        for ruta, _mtime, tam in sorted(archivos, key=lambda x: x[1]):
            if total <= tope:
                break
            try:
                os.remove(ruta)
                total -= tam
            except OSError:
                pass

    # -- ejecucion
    def _ejecutar(self, t):
        import yt_dlp

        if t.cancelar:
            return
        t.estado = PREPARANDO
        t.mensaje = "Buscando el contenido"
        registro = _Registro()

        salida = carpeta_trabajo() / f"{t.id}.%(ext)s"

        def gancho(d):
            if t.cancelar:
                raise Cancelado()
            if d.get("status") == "downloading":
                total = d.get("total_bytes") or d.get("total_bytes_estimate") or 0
                hecho = d.get("downloaded_bytes") or 0
                # dejamos el ultimo 8% para el procesado con ffmpeg
                t.progreso = (hecho / total * 92.0) if total else 0.0
                t.mensaje = "Descargando en el servidor"
            elif d.get("status") == "finished":
                t.progreso = 93.0
                t.mensaje = "Uniendo pistas"

        def gancho_pp(d):
            if t.cancelar:
                raise Cancelado()
            if d.get("status") == "started":
                t.progreso = max(t.progreso, 94.0)
                t.mensaje = "Convirtiendo"

        opciones = {
            "outtmpl": str(salida),
            "format": selector_formato(t.calidad, t.tipo, t.contenedor),
            "quiet": True, "no_warnings": True, "no_color": True, "logger": registro,
            "progress_hooks": [gancho], "postprocessor_hooks": [gancho_pp],
            "noplaylist": True, "retries": 5, "fragment_retries": 5,
            "concurrent_fragment_downloads": 4, "socket_timeout": 30,
            "overwrites": True, "postprocessors": [],
        }
        opciones.update(_opciones_red(self.ajustes))

        ff = ruta_ffmpeg()
        if ff:
            opciones["ffmpeg_location"] = ff

        if t.tipo == "audio":
            opciones["postprocessors"].append({
                "key": "FFmpegExtractAudio",
                "preferredcodec": t.formato_audio,
                "preferredquality": "0" if t.formato_audio in ("flac", "wav", "opus") else "192",
            })
            if t.refuerzo:
                opciones["postprocessor_args"] = {"extractaudio": ["-af", FILTRO_SONORIDAD]}
        elif t.contenedor in ("mp4", "mkv"):
            opciones["merge_output_format"] = t.contenedor
            opciones["postprocessors"].append({
                "key": "FFmpegVideoRemuxer", "preferedformat": t.contenedor,
            })

        opciones["writethumbnail"] = True
        opciones["postprocessors"].append({"key": "EmbedThumbnail", "already_have_thumbnail": False})
        opciones["postprocessors"].append({"key": "FFmpegMetadata", "add_metadata": True})

        try:
            with yt_dlp.YoutubeDL(opciones) as ydl:
                info = ydl.extract_info(t.url, download=True)
            info = info or {}

            t.titulo = info.get("title") or t.titulo or "descarga"
            t.autor = info.get("uploader") or info.get("channel") or ""
            t.duracion = int(info.get("duration") or 0)
            t.miniatura = _mejor_miniatura(info)

            archivo = ""
            pedidos = info.get("requested_downloads") or []
            if pedidos:
                archivo = pedidos[0].get("filepath") or ""
            if not archivo or not os.path.exists(archivo):
                # los postprocesadores cambian la extension: buscamos por el id del trabajo
                carpeta = carpeta_trabajo()
                candidatos = [os.path.join(carpeta, f) for f in os.listdir(carpeta)
                              if f.startswith(t.id) and not f.endswith((".part", ".ytdl", ".webp", ".jpg", ".png"))]
                if candidatos:
                    archivo = max(candidatos, key=os.path.getsize)

            if not archivo or not os.path.exists(archivo):
                raise ValueError("El servidor no encontro el archivo resultante.")

            extension = os.path.splitext(archivo)[1] or ".bin"
            t.archivo = archivo
            t.nombre = nombre_seguro(f"{t.titulo}") + extension
            t.tamano = os.path.getsize(archivo)
            t.progreso = 100.0
            t.estado = LISTO
            t.mensaje = "Listo para descargar"

            # las miniaturas sueltas que deja yt-dlp no hacen falta
            carpeta = carpeta_trabajo()
            for f in os.listdir(carpeta):
                if f.startswith(t.id) and f.endswith((".webp", ".jpg", ".png")):
                    try:
                        os.remove(os.path.join(carpeta, f))
                    except OSError:
                        pass

        except Cancelado:
            t.estado = CANCELADO
            t.mensaje = "Cancelado"
            self._borrar_archivo(t)
        except Exception as e:
            t.estado = ERROR
            t.error = mensaje_amable(registro.ultimo_error or str(e))
            t.mensaje = "Error"
