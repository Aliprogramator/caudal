# -*- coding: utf-8 -*-
"""API del servidor Caudal: cuentas, resolucion de enlaces y entrega de archivos."""

import ipaddress
import mimetypes
import os
import threading
import time

from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, StreamingResponse
from pydantic import BaseModel

from . import listas, motor
from .config import NOMBRE, Ajustes, ip_local, ruta_ffmpeg
from .cuentas import Cuentas, ErrorCuenta
from .listas import ErrorLista
from .emparejar import pagina_emparejar

ajustes = Ajustes()
cuentas = Cuentas()
gestor = motor.Gestor(ajustes)

app = FastAPI(title=f"{NOMBRE} · servidor", docs_url=None, redoc_url=None)
app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"],
)


# ---------------------------------------------------------------- seguridad

def es_de_casa(request: Request) -> bool:
    """True si la peticion viene de esta maquina o de la red local.

    Crear cuentas solo se permite desde aqui: si el servidor esta abierto a
    internet por un tunel, nadie de fuera puede darse de alta.
    """
    host = (request.client.host if request.client else "") or ""
    try:
        ip = ipaddress.ip_address(host)
    except ValueError:
        return False
    return ip.is_loopback or ip.is_private


def exigir_casa(request: Request):
    if not es_de_casa(request):
        raise HTTPException(
            403,
            "Las cuentas solo se crean desde la computadora o desde la misma red wifi.",
        )
    return True


def usuario_actual(x_caudal_token: str = Header(default="")):
    """Valida la sesion del dispositivo que llama."""
    usuario = cuentas.validar(x_caudal_token)
    if not usuario:
        raise HTTPException(401, "Tu sesion caduco o no es valida. Vuelve a iniciar sesion.")
    return usuario


# ---------------------------------------------------------------- modelos

class PeticionRegistro(BaseModel):
    usuario: str
    clave: str
    nombre: str = ""
    dispositivo: str = ""
    plataforma: str = ""


class PeticionEntrar(BaseModel):
    usuario: str
    clave: str
    dispositivo: str = ""
    plataforma: str = ""


class PeticionClave(BaseModel):
    clave_actual: str
    clave_nueva: str


class PeticionResolver(BaseModel):
    url: str


class PeticionLista(BaseModel):
    url: str


class PeticionTrabajo(BaseModel):
    url: str = ""
    busqueda: str = ""              # para canciones de una lista importada
    tipo: str = "completo"          # completo | video | audio
    calidad: str = "mejor"
    formato_audio: str = "mp3"
    contenedor: str = "mp4"
    refuerzo_audio: bool = False    # modo musica: que suene lo mas fuerte posible


# ---------------------------------------------------------------- publico

@app.get("/", response_class=HTMLResponse)
def inicio():
    """Pagina con el codigo QR para conectar el telefono."""
    return pagina_emparejar(
        ip_local(),
        ajustes["puerto"],
        publica=ajustes["direccion_publica"],
        hay_cuentas=cuentas.hay_alguien(),
    )


@app.get("/salud")
def salud(request: Request):
    return {
        "ok": True,
        "servidor": NOMBRE,
        "version": 2,
        "ffmpeg": bool(ruta_ffmpeg()),
        "equipo": os.environ.get("COMPUTERNAME", "servidor"),
        "hay_cuentas": cuentas.hay_alguien(),
        "puede_registrar": es_de_casa(request),
    }


# ---------------------------------------------------------------- cuentas

@app.post("/cuenta/registro")
def registro(peticion: PeticionRegistro, request: Request, _=Depends(exigir_casa)):
    try:
        cuentas.registrar(peticion.usuario, peticion.clave, peticion.nombre)
        sesion = cuentas.entrar(peticion.usuario, peticion.clave,
                                peticion.dispositivo, peticion.plataforma)
    except ErrorCuenta as e:
        raise HTTPException(422, str(e)) from e
    return sesion


@app.post("/cuenta/entrar")
def entrar(peticion: PeticionEntrar):
    try:
        return cuentas.entrar(peticion.usuario, peticion.clave,
                              peticion.dispositivo, peticion.plataforma)
    except ErrorCuenta as e:
        raise HTTPException(401, str(e)) from e


@app.post("/cuenta/salir")
def salir(x_caudal_token: str = Header(default=""), usuario=Depends(usuario_actual)):
    cuentas.salir(x_caudal_token)
    return {"ok": True}


@app.get("/cuenta/yo")
def quien_soy(x_caudal_token: str = Header(default=""), usuario=Depends(usuario_actual)):
    return {
        "usuario": usuario["usuario"],
        "nombre": usuario["nombre"],
        "dispositivos": cuentas.dispositivos(usuario["id"], x_caudal_token),
    }


@app.post("/cuenta/clave")
def cambiar_clave(peticion: PeticionClave, usuario=Depends(usuario_actual)):
    try:
        cuentas.cambiar_clave(usuario["usuario"], peticion.clave_actual, peticion.clave_nueva)
    except ErrorCuenta as e:
        raise HTTPException(422, str(e)) from e
    return {"ok": True}


@app.delete("/cuenta/dispositivos/{ident}")
def desvincular(ident: str, usuario=Depends(usuario_actual)):
    if not cuentas.desvincular(usuario["id"], ident):
        raise HTTPException(404, "Ese dispositivo ya no esta vinculado.")
    return {"ok": True}


# ---------------------------------------------------------------- contenido

@app.post("/resolver")
def resolver(peticion: PeticionResolver, usuario=Depends(usuario_actual)):
    url = (peticion.url or "").strip()
    if not url:
        raise HTTPException(400, "Falta el enlace.")
    try:
        return motor.resolver(url, ajustes)
    except ValueError as e:
        raise HTTPException(422, str(e)) from e


@app.get("/buscar")
def buscar(q: str = Query(""), limite: int = Query(0), usuario=Depends(usuario_actual)):
    tope = limite or int(ajustes["limite_busqueda"])
    try:
        return {"resultados": motor.buscar(q, min(max(tope, 1), 50), ajustes)}
    except ValueError as e:
        raise HTTPException(422, str(e)) from e


@app.post("/listas/leer", dependencies=[Depends(usuario_actual)])
def leer_lista(peticion: PeticionLista):
    """Lee que canciones tiene una lista de Spotify, Apple Music o YouTube."""
    try:
        return listas.leer(peticion.url, ajustes)
    except ErrorLista as e:
        raise HTTPException(422, str(e)) from e
    except ValueError as e:
        raise HTTPException(422, str(e)) from e


@app.post("/trabajos")
def crear_trabajo(peticion: PeticionTrabajo, usuario=Depends(usuario_actual)):
    url = (peticion.url or "").strip()
    busqueda = (peticion.busqueda or "").strip()
    if not url and busqueda:
        # sin enlace exacto (Spotify, Apple): se coge el primer resultado de YouTube
        url = f"ytsearch1:{busqueda}"
    if not url:
        raise HTTPException(400, "Falta el enlace o el texto a buscar.")
    if peticion.tipo not in ("completo", "video", "audio"):
        raise HTTPException(400, "Tipo de descarga desconocido.")
    t = gestor.crear(url, peticion.tipo, peticion.calidad, peticion.formato_audio,
                     peticion.contenedor, dueno=usuario["id"],
                     refuerzo=peticion.refuerzo_audio)
    return t.a_dict()


@app.get("/trabajos/{ident}")
def ver_trabajo(ident: str, usuario=Depends(usuario_actual)):
    t = _trabajo_de(ident, usuario)
    return t.a_dict()


@app.delete("/trabajos/{ident}")
def borrar_trabajo(ident: str, usuario=Depends(usuario_actual)):
    _trabajo_de(ident, usuario)
    gestor.cancelar(ident)
    return {"ok": True}


@app.get("/trabajos/{ident}/archivo")
def descargar(ident: str, request: Request, usuario=Depends(usuario_actual)):
    """Entrega el archivo admitiendo Range, para que el telefono pueda reanudar."""
    t = _trabajo_de(ident, usuario)
    if t.estado != motor.LISTO or not t.archivo or not os.path.exists(t.archivo):
        raise HTTPException(409, "El archivo todavia no esta listo.")

    total = os.path.getsize(t.archivo)
    tipo_mime = mimetypes.guess_type(t.nombre)[0] or "application/octet-stream"
    cabeceras = {
        "Accept-Ranges": "bytes",
        "Content-Disposition": f'attachment; filename="{t.id}{os.path.splitext(t.nombre)[1]}"',
        "X-Caudal-Nombre": t.nombre.encode("utf-8").hex(),
    }

    rango = request.headers.get("range") or request.headers.get("Range")
    inicio, fin = 0, total - 1
    codigo = 200
    if rango and rango.startswith("bytes="):
        partes = rango.replace("bytes=", "").split("-")
        try:
            if partes[0]:
                inicio = int(partes[0])
            if len(partes) > 1 and partes[1]:
                fin = int(partes[1])
        except ValueError:
            inicio, fin = 0, total - 1
        inicio = max(0, min(inicio, total - 1))
        fin = max(inicio, min(fin, total - 1))
        codigo = 206
        cabeceras["Content-Range"] = f"bytes {inicio}-{fin}/{total}"

    largo = fin - inicio + 1
    cabeceras["Content-Length"] = str(largo)

    def leer():
        restante = largo
        with open(t.archivo, "rb") as f:
            f.seek(inicio)
            while restante > 0:
                trozo = f.read(min(262144, restante))
                if not trozo:
                    break
                restante -= len(trozo)
                yield trozo

    return StreamingResponse(leer(), status_code=codigo, media_type=tipo_mime, headers=cabeceras)


def _trabajo_de(ident: str, usuario):
    """Un dispositivo solo puede tocar los trabajos de su propia cuenta."""
    t = gestor.obtener(ident)
    if not t:
        raise HTTPException(404, "Ese trabajo ya no existe.")
    if t.dueno is not None and t.dueno != usuario["id"]:
        raise HTTPException(404, "Ese trabajo ya no existe.")
    return t


@app.get("/ajustes")
def ver_ajustes(usuario=Depends(usuario_actual)):
    return {
        "max_simultaneas": ajustes["max_simultaneas"],
        "navegador_cookies": ajustes["navegador_cookies"],
        "horas_retencion": ajustes["horas_retencion"],
        "ffmpeg": ruta_ffmpeg(),
    }


# ---------------------------------------------------------------- limpieza

def _limpiador():
    while True:
        time.sleep(900)
        try:
            gestor.limpiar()
        except Exception:
            pass


@app.on_event("startup")
def arrancar_limpieza():
    hilo = threading.Thread(target=_limpiador, daemon=True, name="caudal-limpieza")
    hilo.start()
