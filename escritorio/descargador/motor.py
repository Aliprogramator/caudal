# -*- coding: utf-8 -*-
"""Motor de descargas: analiza enlaces y los baja con yt-dlp o el modulo de Telegram."""

import os
import time
import uuid
from dataclasses import dataclass, field

import requests
from PySide6.QtCore import QObject, QRunnable, QThreadPool, Signal

from . import redes, telegram_dl
from .config import carpeta_caratulas, ruta_ffmpeg


EN_COLA, ANALIZANDO, DESCARGANDO, PROCESANDO = "en_cola", "analizando", "descargando", "procesando"
COMPLETADA, ERROR, CANCELADA, PAUSADA = "completada", "error", "cancelada", "pausada"

ACTIVOS = (ANALIZANDO, DESCARGANDO, PROCESANDO)
ETIQUETAS = {
    EN_COLA: "En cola", ANALIZANDO: "Analizando", DESCARGANDO: "Descargando",
    PROCESANDO: "Procesando", COMPLETADA: "Completada", ERROR: "Error",
    CANCELADA: "Cancelada", PAUSADA: "En pausa",
}


class Cancelado(Exception):
    pass


@dataclass
class Tarea:
    url: str
    ident: str = field(default_factory=lambda: uuid.uuid4().hex[:12])
    titulo: str = ""
    autor: str = ""
    plataforma: object = None
    duracion: int = 0
    estado: str = EN_COLA
    progreso: float = 0.0
    descargado: int = 0
    total: int = 0
    velocidad: float = 0.0
    eta: int = 0
    archivo: str = ""
    error: str = ""
    miniatura_url: str = ""
    miniatura_bytes: bytes = b""
    calidad: str = ""
    tipo_pedido: str = ""      # si viene, manda sobre el ajuste general
    calidad_pedida: str = ""
    analizada: bool = False
    cancelar: bool = False
    pausar: bool = False
    agregada: float = field(default_factory=time.time)

    def __post_init__(self):
        if self.plataforma is None:
            self.plataforma = redes.detectar(self.url)
        if not self.titulo:
            self.titulo = self.url

    @property
    def activa(self):
        return self.estado in ACTIVOS


# ---------------------------------------------------------------- utilidades

def formato_bytes(n):
    n = float(n or 0)
    for u in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or u == "TB":
            return f"{n:.0f} {u}" if u == "B" else f"{n:.1f} {u}"
        n /= 1024
    return f"{n:.1f} TB"


def formato_tiempo(s):
    s = int(s or 0)
    if s <= 0:
        return "--:--"
    h, resto = divmod(s, 3600)
    m, seg = divmod(resto, 60)
    return f"{h}:{m:02d}:{seg:02d}" if h else f"{m:02d}:{seg:02d}"


def selector_formato(calidad, contenedor="mp4", tipo="completo"):
    """Arma el selector de formatos de yt-dlp.

    tipo:
      "completo" -> imagen y sonido juntos (lo normal)
      "video"    -> solo la pista de imagen, sin sonido
      "audio"    -> solo la pista de sonido

    Con MP4 se prefieren H.264 y AAC: son los que reproduce cualquier movil o
    reproductor de Windows. AV1 u Opus dan archivos mas pequenos, pero muchos
    equipos no los abren. Si no existe esa combinacion, se cae a la mejor opcion.
    """
    if tipo == "audio" or calidad == "audio":
        return "ba/b"

    limite = ""
    if calidad != "mejor":
        try:
            limite = f"[height<={int(calidad)}]"
        except (TypeError, ValueError):
            limite = ""

    if tipo == "video":
        # bv* ya es una pista sin sonido; el respaldo evita quedarse sin nada
        generico = f"bv*{limite}/bv*" if limite else "bv*"
        if contenedor != "mp4":
            return generico
        return f"bv*{limite}[vcodec^=avc1]/{generico}"

    generico = f"bv*{limite}+ba/b{limite}/bv*+ba/b" if limite else "bv*+ba/b"
    if contenedor != "mp4":
        return generico
    compatible = f"bv*{limite}[vcodec^=avc1]+ba[acodec^=mp4a]"
    return f"{compatible}/{generico}"


# Modo musica: nivela a -9 LUFS y limita los picos, que es lo que de verdad
# hace que suene fuerte sin que se rompa el sonido.
FILTRO_SONORIDAD = "loudnorm=I=-9:TP=-1.0:LRA=9"


class _Silencio:
    """Logger de yt-dlp que guarda el ultimo error sin ensuciar la consola."""

    def __init__(self):
        self.ultimo_error = ""

    def debug(self, msg):
        pass

    def info(self, msg):
        pass

    def warning(self, msg):
        pass

    def error(self, msg):
        texto = str(msg).replace("ERROR:", "").strip()
        if texto:
            self.ultimo_error = texto


def mensaje_amable(texto, plataforma):
    t = (texto or "").lower()
    clave = getattr(plataforma, "clave", "")
    if "sign in" in t or "log in" in t or "login required" in t or "rate-limit" in t or "cookies" in t:
        return ("El contenido es privado o el sitio pide iniciar sesion. En Ajustes activa "
                "'Usar cookies del navegador' y vuelve a intentarlo.")
    if "unsupported url" in t:
        return "Ese enlace no esta soportado. Comprueba que apunte a una publicacion con video."
    if "unavailable" in t or "not available" in t or "has been removed" in t:
        return "El video ya no esta disponible, fue borrado o es privado."
    if "no video formats" in t or "requested format" in t:
        return "No hay ningun formato descargable en ese enlace."
    if "geo" in t and "block" in t:
        return "El contenido esta bloqueado en tu pais. Puedes probar con un proxy en Ajustes."
    if "age" in t and ("restrict" in t or "confirm" in t):
        return "Video con restriccion de edad: activa las cookies del navegador en Ajustes."
    if "ffmpeg" in t:
        return "Falta ffmpeg para unir video y audio. Revisa la carpeta bin de la aplicacion."
    if "private" in t:
        return "La publicacion es privada."
    if "404" in t:
        return "El enlace no existe (error 404)."
    if "timed out" in t or "timeout" in t or "connection" in t:
        return "Problema de conexion con el servidor. Reintenta en un momento."
    if clave == "instagram" and not t:
        return "Instagram bloqueo la peticion. Activa las cookies del navegador en Ajustes."
    return texto or "No se pudo completar la descarga."


def bajar_miniatura(url):
    if not url:
        return b""
    try:
        r = requests.get(url, timeout=12, headers={"User-Agent": telegram_dl.AGENTE})
        if r.status_code == 200 and len(r.content) < 6_000_000:
            return r.content
    except requests.RequestException:
        pass
    return b""


# ---------------------------------------------------------------- analisis

class SenalesAnalisis(QObject):
    listo = Signal(str, dict)
    fallo = Signal(str, str)
    playlist = Signal(str, list, str)


class TrabajoAnalisis(QRunnable):
    def __init__(self, tarea, ajustes):
        super().__init__()
        self.tarea = tarea
        self.ajustes = ajustes
        self.senales = SenalesAnalisis()
        self.registro = _Silencio()
        self._fallo_telegram = ""

    def run(self):
        t = self.tarea
        try:
            if t.plataforma.motor == "telegram":
                try:
                    info = telegram_dl.extraer_info(t.url)
                except telegram_dl.ErrorTelegram as e:
                    self._fallo_telegram = str(e)
                else:
                    self.senales.listo.emit(t.ident, {
                        "titulo": info["titulo"],
                        "autor": info["autor"],
                        "duracion": info.get("duracion", 0),
                        "miniatura_url": info.get("miniatura", ""),
                        "miniatura_bytes": bajar_miniatura(info.get("miniatura", "")),
                    })
                    return
                # si falla, seguimos con yt-dlp (tiene extractor de publicaciones incrustadas)

            import yt_dlp

            opciones = {
                "quiet": True, "no_warnings": True, "logger": self.registro,
                "skip_download": True, "noplaylist": not self.ajustes["playlist"],
                "extract_flat": "in_playlist", "socket_timeout": 25,
                "ignoreerrors": False, "no_color": True,
            }
            self._extras_red(opciones)

            with yt_dlp.YoutubeDL(opciones) as ydl:
                info = ydl.extract_info(t.url, download=False)

            if info and info.get("_type") == "playlist" and info.get("entries") is not None:
                entradas = self._entradas_playlist(info)
                if entradas:
                    self.senales.playlist.emit(t.ident, entradas, info.get("title") or "Lista")
                    return

            info = info or {}
            mini = info.get("thumbnail") or ""
            if not mini and info.get("thumbnails"):
                mini = info["thumbnails"][-1].get("url", "")
            self.senales.listo.emit(t.ident, {
                "titulo": info.get("title") or t.url,
                "autor": info.get("uploader") or info.get("channel") or info.get("uploader_id") or "",
                "duracion": int(info.get("duration") or 0),
                "miniatura_url": mini,
                "miniatura_bytes": bajar_miniatura(mini),
            })

        except telegram_dl.ErrorTelegram as e:
            self.senales.fallo.emit(t.ident, str(e))
        except Exception as e:
            if self._fallo_telegram:
                # el mensaje propio de Telegram explica mejor que el generico de yt-dlp
                self.senales.fallo.emit(t.ident, self._fallo_telegram)
            else:
                texto = self.registro.ultimo_error or str(e)
                self.senales.fallo.emit(t.ident, mensaje_amable(texto, t.plataforma))

    def _entradas_playlist(self, info):
        entradas = []
        limite = int(self.ajustes["limite_playlist"] or 0)
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
            entradas.append({
                "url": enlace,
                "titulo": e.get("title") or "",
                "duracion": int(e.get("duration") or 0),
                "miniatura": mini,
            })
            if limite and len(entradas) >= limite:
                break
        return entradas

    def _extras_red(self, opciones):
        nav = self.ajustes["navegador_cookies"]
        if nav and nav != "ninguno":
            opciones["cookiesfrombrowser"] = (nav,)
        archivo = self.ajustes["archivo_cookies"]
        if archivo and os.path.exists(archivo):
            opciones["cookiefile"] = archivo
        if self.ajustes["proxy"]:
            opciones["proxy"] = self.ajustes["proxy"]


# ---------------------------------------------------------------- descarga

class SenalesDescarga(QObject):
    progreso = Signal(str, dict)
    terminada = Signal(str, bool, str, str)


class TrabajoDescarga(QRunnable):
    def __init__(self, tarea, ajustes):
        super().__init__()
        self.tarea = tarea
        self.ajustes = ajustes
        self.senales = SenalesDescarga()
        self.registro = _Silencio()

    def _opciones(self, carpeta):
        a = self.ajustes
        # lo que se pidio para ESTA descarga manda sobre la preferencia general:
        # sin esto, pulsar "solo audio" y que el ajuste volviera a su sitio antes
        # de empezar hacia que se bajara el video entero
        tipo = self.tarea.tipo_pedido or a["tipo_descarga"]
        calidad = self.tarea.calidad_pedida or a["calidad"]
        if a["subcarpeta_por_red"]:
            carpeta = os.path.join(carpeta, self.tarea.plataforma.nombre.replace(" / ", "-"))

        opciones = {
            "outtmpl": os.path.join(carpeta, a["plantilla_nombre"]),
            "format": selector_formato(calidad, a["formato_salida"], tipo),
            "quiet": True, "no_warnings": True, "no_color": True,
            "logger": self.registro,
            "progress_hooks": [self._hook],
            "postprocessor_hooks": [self._hook_pp],
            "noplaylist": True,
            "continuedl": True,
            "retries": int(a["reintentos"]),
            "fragment_retries": int(a["reintentos"]),
            "concurrent_fragment_downloads": 4,
            "socket_timeout": 30,
            "ignoreerrors": False,
            "overwrites": False,
            "windowsfilenames": True,
            "postprocessors": [],
        }

        ff = ruta_ffmpeg()
        if ff:
            opciones["ffmpeg_location"] = ff

        solo_audio = tipo == "audio" or calidad == "audio"
        if solo_audio:
            opciones["postprocessors"].append({
                "key": "FFmpegExtractAudio",
                "preferredcodec": a["formato_audio"],
                "preferredquality": "0" if a["formato_audio"] in ("flac", "wav", "opus") else "192",
            })
            if a["modo_musica"]:
                opciones["postprocessor_args"] = {
                    "extractaudio": ["-af", FILTRO_SONORIDAD]}
        else:
            contenedor = a["formato_salida"]
            if contenedor in ("mp4", "mkv"):
                opciones["merge_output_format"] = contenedor
                opciones["postprocessors"].append({
                    "key": "FFmpegVideoRemuxer", "preferedformat": contenedor,
                })

        if a["subtitulos"]:
            idiomas = [x.strip() for x in str(a["idioma_subtitulos"]).split(",") if x.strip()]
            opciones["writesubtitles"] = True
            opciones["writeautomaticsub"] = True
            opciones["subtitleslangs"] = idiomas or ["es"]
            if a["incrustar_subtitulos"] and not solo_audio:
                opciones["postprocessors"].append({"key": "FFmpegEmbedSubtitle"})

        if a["metadatos"]:
            opciones["postprocessors"].append({
                "key": "FFmpegMetadata", "add_metadata": True, "add_chapters": True,
            })
        if a["miniatura"]:
            opciones["writethumbnail"] = True
            opciones["postprocessors"].append({
                "key": "EmbedThumbnail", "already_have_thumbnail": False,
            })

        nav = a["navegador_cookies"]
        if nav and nav != "ninguno":
            opciones["cookiesfrombrowser"] = (nav,)
        archivo = a["archivo_cookies"]
        if archivo and os.path.exists(archivo):
            opciones["cookiefile"] = archivo
        if a["proxy"]:
            opciones["proxy"] = a["proxy"]
        if a["limite_velocidad"]:
            opciones["ratelimit"] = int(a["limite_velocidad"]) * 1024

        return opciones, carpeta

    def _comprobar_corte(self):
        if self.tarea.cancelar or self.tarea.pausar:
            raise Cancelado()

    def _hook(self, d):
        self._comprobar_corte()
        estado = d.get("status")
        if estado == "downloading":
            total = d.get("total_bytes") or d.get("total_bytes_estimate") or 0
            hecho = d.get("downloaded_bytes") or 0
            self.senales.progreso.emit(self.tarea.ident, {
                "estado": DESCARGANDO,
                "descargado": hecho,
                "total": total,
                "velocidad": d.get("speed") or 0,
                "eta": d.get("eta") or 0,
                "progreso": (hecho / total * 100.0) if total else 0.0,
            })
        elif estado == "finished":
            self.senales.progreso.emit(self.tarea.ident, {
                "estado": PROCESANDO, "progreso": 100.0, "velocidad": 0, "eta": 0,
            })

    def _hook_pp(self, d):
        self._comprobar_corte()
        if d.get("status") == "started":
            self.senales.progreso.emit(self.tarea.ident, {"estado": PROCESANDO})

    def run(self):
        t = self.tarea
        carpeta = self.ajustes["carpeta"]
        try:
            os.makedirs(carpeta, exist_ok=True)
        except OSError as e:
            self.senales.terminada.emit(t.ident, False, "",
                                        f"No se pudo crear la carpeta destino: {e}")
            return
        try:
            if t.plataforma.motor == "telegram":
                self._descargar_telegram(carpeta)
            else:
                self._descargar_ytdlp(carpeta)
        except Cancelado:
            self.senales.terminada.emit(t.ident, False, "", "__cancelada__")
        except KeyboardInterrupt:
            self.senales.terminada.emit(t.ident, False, "", "__cancelada__")
        except Exception as e:
            texto = self.registro.ultimo_error or str(e)
            self.senales.terminada.emit(t.ident, False, "", mensaje_amable(texto, t.plataforma))

    def _descargar_ytdlp(self, carpeta):
        import yt_dlp

        t = self.tarea
        opciones, carpeta = self._opciones(carpeta)
        with yt_dlp.YoutubeDL(opciones) as ydl:
            info = ydl.extract_info(t.url, download=True)

        if info and info.get("_type") == "playlist":
            entradas = [e for e in (info.get("entries") or []) if e]
            info = entradas[0] if entradas else info
        info = info or {}

        archivo = ""
        pedidos = info.get("requested_downloads") or []
        if pedidos:
            archivo = pedidos[0].get("filepath") or pedidos[0].get("_filename") or ""
        if not archivo:
            archivo = info.get("filepath") or info.get("_filename") or ""
        if archivo and not os.path.exists(archivo):
            raiz = os.path.splitext(archivo)[0]
            for ext in (".mp4", ".mkv", ".webm", ".m4a", ".mp3", ".opus", ".flac", ".wav", ".ogg"):
                if os.path.exists(raiz + ext):
                    archivo = raiz + ext
                    break

        t.titulo = info.get("title") or t.titulo
        t.duracion = int(info.get("duration") or t.duracion or 0)
        tipo = t.tipo_pedido or self.ajustes["tipo_descarga"]
        if tipo == "audio":
            t.calidad = self.ajustes["formato_audio"].upper()
        elif info.get("height"):
            t.calidad = f"{info['height']}p"
            if tipo == "video":
                t.calidad += " sin audio"

        self.senales.terminada.emit(t.ident, True, archivo, "")

    def _descargar_telegram(self, carpeta):
        t = self.tarea
        if self.ajustes["subcarpeta_por_red"]:
            carpeta = os.path.join(carpeta, "Telegram")
        try:
            info = telegram_dl.extraer_info(t.url)
        except telegram_dl.ErrorTelegram:
            # yt-dlp trae un extractor de publicaciones incrustadas: lo usamos de respaldo
            self._descargar_ytdlp(self.ajustes["carpeta"])
            return
        t.titulo = info["titulo"]

        def progresar(d):
            total = d["total"]
            self.senales.progreso.emit(t.ident, {
                "estado": DESCARGANDO,
                "descargado": d["descargado"],
                "total": total,
                "velocidad": d["velocidad"],
                "eta": d["eta"],
                "progreso": (d["descargado"] / total * 100.0) if total else 0.0,
            })

        archivo = telegram_dl.descargar(
            info, carpeta, al_progresar=progresar,
            cancelado=lambda: t.cancelar or t.pausar,
            limite_kbs=int(self.ajustes["limite_velocidad"] or 0),
        )
        t.calidad = info["tipo"].capitalize()
        self.senales.terminada.emit(t.ident, True, archivo, "")


# ---------------------------------------------------------------- gestor

class Gestor(QObject):
    tarea_agregada = Signal(str)
    tarea_cambio = Signal(str)
    tarea_finalizada = Signal(str, bool)
    cola_cambio = Signal()

    def __init__(self, ajustes, historial, padre=None):
        super().__init__(padre)
        self.ajustes = ajustes
        self.historial = historial
        self.tareas = {}
        self.orden = []
        self.pool_analisis = QThreadPool()
        self.pool_analisis.setMaxThreadCount(4)
        self.pool_descarga = QThreadPool()
        self.pool_descarga.setMaxThreadCount(int(ajustes["simultaneas"]))
        self._activas = 0
        self._trabajos = {}
        self._analisis = {}

    def agregar(self, url, iniciar=True, datos_previos=None, tipo=None, calidad=None):
        url = redes.normalizar(url)
        if not url:
            return None
        tarea = Tarea(url=url, tipo_pedido=tipo or "", calidad_pedida=calidad or "")
        if datos_previos:
            tarea.titulo = datos_previos.get("titulo") or url
            tarea.duracion = datos_previos.get("duracion", 0)
            tarea.miniatura_url = datos_previos.get("miniatura", "")
        self.tareas[tarea.ident] = tarea
        self.orden.append(tarea.ident)
        self.tarea_agregada.emit(tarea.ident)
        self._analizar(tarea)
        if iniciar:
            self._bombear()
        return tarea

    def agregar_varias(self, urls):
        creadas = []
        for u in urls:
            t = self.agregar(u, iniciar=False)
            if t:
                creadas.append(t)
        self._bombear()
        return creadas

    def cancelar(self, ident):
        t = self.tareas.get(ident)
        if not t or t.estado in (COMPLETADA, ERROR, CANCELADA):
            return
        t.cancelar = True
        if t.estado in (EN_COLA, PAUSADA, ANALIZANDO):
            t.estado = CANCELADA
            self.tarea_cambio.emit(ident)
            self._bombear()

    def pausar(self, ident):
        t = self.tareas.get(ident)
        if not t or t.estado not in (DESCARGANDO, EN_COLA, ANALIZANDO, PROCESANDO):
            return
        if t.estado in (EN_COLA, ANALIZANDO):
            t.estado = PAUSADA
            self.tarea_cambio.emit(ident)
            return
        t.pausar = True

    def reanudar(self, ident):
        t = self.tareas.get(ident)
        if not t or t.estado not in (PAUSADA, ERROR, CANCELADA):
            return
        t.pausar = False
        t.cancelar = False
        t.error = ""
        t.estado = EN_COLA
        self.tarea_cambio.emit(ident)
        if not t.analizada:
            self._analizar(t)
        self._bombear()

    def quitar(self, ident):
        t = self.tareas.get(ident)
        if not t:
            return
        if t.activa:
            t.cancelar = True
        self.tareas.pop(ident, None)
        self._analisis.pop(ident, None)
        if ident in self.orden:
            self.orden.remove(ident)
        self.cola_cambio.emit()

    def limpiar_terminadas(self):
        for ident in list(self.orden):
            t = self.tareas.get(ident)
            if t and t.estado in (COMPLETADA, CANCELADA, ERROR):
                self.tareas.pop(ident, None)
                self.orden.remove(ident)
        self.cola_cambio.emit()

    def cancelar_todo(self):
        for ident in list(self.orden):
            self.cancelar(ident)

    def reanudar_todo(self):
        for ident in list(self.orden):
            t = self.tareas.get(ident)
            if t and t.estado in (PAUSADA, ERROR, CANCELADA):
                self.reanudar(ident)

    def actualizar_simultaneas(self, n):
        self.pool_descarga.setMaxThreadCount(max(1, int(n)))
        self._bombear()

    def lista(self):
        return [self.tareas[i] for i in self.orden if i in self.tareas]

    def hay_actividad(self):
        return any(t.activa or t.estado == EN_COLA for t in self.lista())

    def _analizar(self, tarea):
        if tarea.estado == EN_COLA:
            tarea.estado = ANALIZANDO
        trabajo = TrabajoAnalisis(tarea, self.ajustes)
        trabajo.senales.listo.connect(self._analisis_listo)
        trabajo.senales.fallo.connect(self._analisis_fallo)
        trabajo.senales.playlist.connect(self._analisis_playlist)
        self._analisis[tarea.ident] = trabajo
        self.pool_analisis.start(trabajo)
        self.tarea_cambio.emit(tarea.ident)

    def _analisis_listo(self, ident, datos):
        self._analisis.pop(ident, None)
        t = self.tareas.get(ident)
        if not t:
            return
        t.titulo = datos.get("titulo") or t.titulo
        t.autor = datos.get("autor") or ""
        t.duracion = datos.get("duracion") or 0
        t.miniatura_url = datos.get("miniatura_url") or ""
        t.miniatura_bytes = datos.get("miniatura_bytes") or b""
        t.analizada = True
        if t.estado == ANALIZANDO:
            t.estado = EN_COLA
        self.tarea_cambio.emit(ident)
        self._bombear()

    def _analisis_fallo(self, ident, mensaje):
        self._analisis.pop(ident, None)
        t = self.tareas.get(ident)
        if not t:
            return
        t.analizada = True
        if t.estado == ANALIZANDO:
            t.estado = EN_COLA
        t.error = mensaje
        self.tarea_cambio.emit(ident)
        self._bombear()

    def _analisis_playlist(self, ident, entradas, titulo_lista):
        self._analisis.pop(ident, None)
        t = self.tareas.get(ident)
        if not t:
            return
        self.quitar(ident)
        for e in entradas:
            self.agregar(e["url"], iniciar=False, datos_previos=e)
        self._bombear()

    def _bombear(self):
        libres = self.pool_descarga.maxThreadCount() - self._activas
        if libres <= 0:
            return
        for ident in list(self.orden):
            if libres <= 0:
                break
            t = self.tareas.get(ident)
            if not t or t.estado != EN_COLA or t.cancelar:
                continue
            if not t.analizada and (time.time() - t.agregada) < 15:
                continue
            self._lanzar(t)
            libres -= 1

    def _lanzar(self, tarea):
        tarea.estado = DESCARGANDO
        tarea.error = ""
        self._activas += 1
        trabajo = TrabajoDescarga(tarea, self.ajustes)
        trabajo.senales.progreso.connect(self._progreso)
        trabajo.senales.terminada.connect(self._terminada)
        self._trabajos[tarea.ident] = trabajo
        self.pool_descarga.start(trabajo)
        self.tarea_cambio.emit(tarea.ident)

    def _progreso(self, ident, d):
        t = self.tareas.get(ident)
        if not t:
            return
        t.estado = d.get("estado", t.estado)
        if "progreso" in d:
            t.progreso = d["progreso"]
        if "descargado" in d:
            t.descargado = d["descargado"]
        if "total" in d:
            t.total = d["total"]
        t.velocidad = d.get("velocidad", t.velocidad)
        t.eta = d.get("eta", t.eta)
        self.tarea_cambio.emit(ident)

    def _guardar_caratula(self, tarea):
        """Deja la miniatura en disco para que la biblioteca la ensene sin internet."""
        if not tarea.miniatura_bytes:
            return ""
        try:
            destino = carpeta_caratulas() / f"{tarea.ident}.img"
            destino.write_bytes(tarea.miniatura_bytes)
            return str(destino)
        except OSError:
            return ""

    def _terminada(self, ident, ok, archivo, mensaje):
        self._activas = max(0, self._activas - 1)
        self._trabajos.pop(ident, None)
        t = self.tareas.get(ident)
        if not t:
            self._bombear()
            return

        if ok:
            t.estado = COMPLETADA
            t.archivo = archivo
            t.progreso = 100.0
            t.velocidad = 0
            t.eta = 0
            if archivo and os.path.exists(archivo):
                t.total = os.path.getsize(archivo)
            self.historial.agregar(
                t.url, t.titulo, t.plataforma.nombre, archivo, t.total, t.duracion,
                t.calidad or self.ajustes["calidad"],
                caratula=self._guardar_caratula(t),
                es_audio=(t.tipo_pedido or self.ajustes["tipo_descarga"]) == "audio",
                autor=t.autor,
            )
        elif mensaje == "__cancelada__":
            t.estado = PAUSADA if t.pausar else CANCELADA
            t.velocidad = 0
            t.pausar = False
        else:
            t.estado = ERROR
            t.error = mensaje
            t.velocidad = 0
            self.historial.agregar(t.url, t.titulo, t.plataforma.nombre, "", 0,
                                   t.duracion, "", "error")

        self.tarea_cambio.emit(ident)
        self.tarea_finalizada.emit(ident, ok)
        self._bombear()
