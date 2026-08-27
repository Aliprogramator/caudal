# -*- coding: utf-8 -*-
"""Instalador de Caudal Escritorio.

Un solo .exe que lleva la aplicacion dentro. Instala en la carpeta del usuario
(sin pedir permisos de administrador), crea los accesos directos, se registra
en "Agregar o quitar programas" y deja un desinstalador.

Modos:
    (sin argumentos)   instalacion normal, con ventana
    /actualizar        silencioso, para cuando la propia app se actualiza
    /desinstalar       quita Caudal del equipo
"""

import os
import shutil
import subprocess
import sys
import tempfile
import time
import winreg
import zipfile

APP = "Caudal Escritorio"
CLAVE_REGISTRO = r"Software\Microsoft\Windows\CurrentVersion\Uninstall\CaudalEscritorio"
PAQUETE = "caudal_app.zip"          # va dentro del propio instalador


# ---------------------------------------------------------------- utilidades

def recursos():
    """Carpeta donde PyInstaller deja lo que va incrustado."""
    return getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))


def destino_por_defecto():
    base = os.environ.get("LOCALAPPDATA") or os.path.expanduser("~")
    return os.path.join(base, "Programas", "Caudal")


def leer_version():
    try:
        with open(os.path.join(recursos(), "version.txt"), encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return "1.0.0"


def cerrar_app():
    """Cierra Caudal y su navegador para poder sustituir los archivos."""
    banderas = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    for nombre in (f"{APP}.exe", "QtWebEngineProcess.exe"):
        subprocess.run(["taskkill", "/F", "/IM", nombre],
                       capture_output=True, creationflags=banderas)
    time.sleep(1.5)


def crear_acceso(ruta_lnk, destino, icono="", descripcion=""):
    """Crea un acceso directo sin depender de librerias externas."""
    guion = f'''
$ws = New-Object -ComObject WScript.Shell
$s = $ws.CreateShortcut("{ruta_lnk}")
$s.TargetPath = "{destino}"
$s.WorkingDirectory = "{os.path.dirname(destino)}"
$s.Description = "{descripcion}"
'''
    if icono:
        guion += f'$s.IconLocation = "{icono},0"\n'
    guion += "$s.Save()\n"

    banderas = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    subprocess.run(["powershell", "-NoProfile", "-NonInteractive", "-Command", guion],
                   capture_output=True, creationflags=banderas)


def registrar(carpeta, version):
    """Aparece en 'Agregar o quitar programas' como cualquier aplicacion."""
    try:
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER, CLAVE_REGISTRO) as clave:
            ejecutable = os.path.join(carpeta, f"{APP}.exe")
            winreg.SetValueEx(clave, "DisplayName", 0, winreg.REG_SZ, "Caudal")
            winreg.SetValueEx(clave, "DisplayVersion", 0, winreg.REG_SZ, version)
            winreg.SetValueEx(clave, "Publisher", 0, winreg.REG_SZ, "Kevin")
            winreg.SetValueEx(clave, "DisplayIcon", 0, winreg.REG_SZ, ejecutable)
            winreg.SetValueEx(clave, "InstallLocation", 0, winreg.REG_SZ, carpeta)
            winreg.SetValueEx(clave, "UninstallString", 0, winreg.REG_SZ,
                              f'"{os.path.join(carpeta, "Desinstalar Caudal.exe")}"')
            winreg.SetValueEx(clave, "NoModify", 0, winreg.REG_DWORD, 1)
            winreg.SetValueEx(clave, "NoRepair", 0, winreg.REG_DWORD, 1)
    except OSError:
        pass  # sin registro la app funciona igual, solo no sale en el listado


def borrar_registro():
    try:
        winreg.DeleteKey(winreg.HKEY_CURRENT_USER, CLAVE_REGISTRO)
    except OSError:
        pass


def carpeta_menu_inicio():
    base = os.environ.get("APPDATA") or os.path.expanduser("~")
    return os.path.join(base, "Microsoft", "Windows", "Start Menu", "Programs")


def escritorio():
    for candidata in (os.path.join(os.path.expanduser("~"), "OneDrive", "Desktop"),
                      os.path.join(os.path.expanduser("~"), "Desktop")):
        if os.path.isdir(candidata):
            return candidata
    return ""


# ---------------------------------------------------------------- instalar

def instalar(carpeta, al_progresar=None, crear_escritorio=True):
    """Copia la aplicacion y deja todo listo. Devuelve la ruta del ejecutable."""
    paquete = os.path.join(recursos(), PAQUETE)
    if not os.path.exists(paquete):
        raise RuntimeError("El instalador esta incompleto: falta el paquete de la app.")

    cerrar_app()

    if al_progresar:
        al_progresar(3, "Preparando la carpeta")

    os.makedirs(carpeta, exist_ok=True)

    # una instalacion anterior se sustituye, pero se respetan los datos del usuario
    for nombre in os.listdir(carpeta):
        if nombre.lower() in ("datos", "descargas"):
            continue
        ruta = os.path.join(carpeta, nombre)
        try:
            if os.path.isdir(ruta):
                shutil.rmtree(ruta, ignore_errors=True)
            else:
                os.remove(ruta)
        except OSError:
            pass

    if al_progresar:
        al_progresar(8, "Copiando los archivos")

    with zipfile.ZipFile(paquete) as z:
        miembros = z.infolist()
        total = len(miembros) or 1
        for i, miembro in enumerate(miembros):
            z.extract(miembro, carpeta)
            if al_progresar and i % 25 == 0:
                al_progresar(8 + (i / total) * 82, "Copiando los archivos")

    ejecutable = os.path.join(carpeta, f"{APP}.exe")
    if not os.path.exists(ejecutable):
        # el zip puede traer una carpeta raiz: la aplanamos
        for nombre in os.listdir(carpeta):
            posible = os.path.join(carpeta, nombre, f"{APP}.exe")
            if os.path.exists(posible):
                interior = os.path.join(carpeta, nombre)
                for suelto in os.listdir(interior):
                    shutil.move(os.path.join(interior, suelto),
                                os.path.join(carpeta, suelto))
                shutil.rmtree(interior, ignore_errors=True)
                break
        ejecutable = os.path.join(carpeta, f"{APP}.exe")

    if not os.path.exists(ejecutable):
        raise RuntimeError("Algo fallo al copiar: no aparece el programa principal.")

    if al_progresar:
        al_progresar(92, "Creando los accesos directos")

    # el propio instalador queda como desinstalador
    desinstalador = os.path.join(carpeta, "Desinstalar Caudal.exe")
    try:
        shutil.copy2(sys.executable if getattr(sys, "frozen", False) else __file__,
                     desinstalador)
    except OSError:
        pass

    if crear_escritorio and escritorio():
        crear_acceso(os.path.join(escritorio(), "Caudal.lnk"), ejecutable,
                     ejecutable, "Descarga musica y videos, y conecta tu telefono")

    menu = carpeta_menu_inicio()
    if os.path.isdir(menu):
        crear_acceso(os.path.join(menu, "Caudal.lnk"), ejecutable, ejecutable, "Caudal")

    registrar(carpeta, leer_version())

    if al_progresar:
        al_progresar(100, "Listo")
    return ejecutable


def desinstalar(carpeta):
    cerrar_app()
    for sitio in (escritorio(), carpeta_menu_inicio()):
        if sitio:
            lnk = os.path.join(sitio, "Caudal.lnk")
            if os.path.exists(lnk):
                try:
                    os.remove(lnk)
                except OSError:
                    pass
    borrar_registro()

    # no se puede borrar la carpeta desde dentro: lo hace un script al salir
    guion = os.path.join(tempfile.gettempdir(), "quitar_caudal.bat")
    with open(guion, "w", encoding="utf-8") as f:
        f.write("@echo off\r\n")
        f.write("timeout /t 2 /nobreak >nul\r\n")
        f.write(f'rmdir /s /q "{carpeta}"\r\n')
        f.write(f'del "%~f0"\r\n')
    subprocess.Popen(["cmd", "/c", guion],
                     creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
