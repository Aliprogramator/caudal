# -*- coding: utf-8 -*-
"""Construye el instalador de Caudal: un solo .exe con la aplicacion dentro.

    python crear_instalador.py

Antes hay que tener compilada la app en escritorio/salida/Caudal Escritorio.
El resultado queda en instalador/CaudalInstalador.exe, listo para publicar.
"""

import os
import shutil
import subprocess
import sys
import time
import zipfile

AQUI = os.path.dirname(os.path.abspath(__file__))
PROYECTO = os.path.dirname(AQUI)
APP = os.path.join(PROYECTO, "escritorio", "salida", "Caudal Escritorio")
ZIP = os.path.join(AQUI, "caudal_app.zip")
VERSION_TXT = os.path.join(AQUI, "version.txt")


def leer_version():
    """La version manda desde el codigo de la app, para no repetirla en dos sitios."""
    ruta = os.path.join(PROYECTO, "escritorio", "descargador", "version.py")
    with open(ruta, encoding="utf-8") as f:
        for linea in f:
            if linea.startswith("VERSION"):
                return linea.split("=")[1].strip().strip('"').strip("'")
    return "1.0.0"


def tamano(ruta):
    return os.path.getsize(ruta) / 1024 / 1024


def comprimir():
    if not os.path.isdir(APP):
        raise SystemExit(
            f"No encuentro la app compilada en:\n  {APP}\n\n"
            "Compilala antes con:\n"
            "  cd escritorio\n"
            '  python -m PyInstaller --noconfirm --windowed --onedir '
            '--name "Caudal Escritorio" --icon icono.ico --distpath salida '
            '--add-data "bin;bin" --collect-all yt_dlp ejecutar.py'
        )

    if os.path.exists(ZIP):
        os.remove(ZIP)

    print("Comprimiendo la aplicacion (tarda un par de minutos)...", flush=True)
    inicio = time.time()
    total = sum(len(f) for _, _, f in os.walk(APP))
    hechos = 0

    with zipfile.ZipFile(ZIP, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for raiz, _, archivos in os.walk(APP):
            for a in archivos:
                completo = os.path.join(raiz, a)
                z.write(completo, os.path.relpath(completo, APP))
                hechos += 1
                if hechos % 200 == 0:
                    print(f"   {hechos}/{total} archivos", flush=True)

    print(f"Paquete listo: {tamano(ZIP):.0f} MB en {time.time() - inicio:.0f}s", flush=True)


def construir(version):
    with open(VERSION_TXT, "w", encoding="utf-8") as f:
        f.write(version)

    icono = os.path.join(PROYECTO, "escritorio", "icono.ico")
    orden = [
        sys.executable, "-m", "PyInstaller", "--noconfirm", "--windowed", "--onefile",
        "--name", "CaudalInstalador",
        "--distpath", AQUI,
        "--workpath", os.path.join(AQUI, "temporal"),
        "--specpath", os.path.join(AQUI, "temporal"),
        "--add-data", f"{ZIP};.",
        "--add-data", f"{VERSION_TXT};.",
        "--paths", AQUI,
        "--hidden-import", "instalador",
        "--exclude-module", "tkinter",
        "--exclude-module", "matplotlib",
        "--exclude-module", "numpy",
        "--exclude-module", "yt_dlp",
    ]
    if os.path.exists(icono):
        orden += ["--icon", icono]
    orden.append(os.path.join(AQUI, "ventana_instalador.py"))

    print("Construyendo el instalador...", flush=True)
    r = subprocess.run(orden, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    if r.returncode != 0:
        print(r.stdout[-1500:])
        print(r.stderr[-1500:])
        raise SystemExit("PyInstaller fallo al construir el instalador.")


def limpiar():
    for basura in (os.path.join(AQUI, "temporal"),):
        shutil.rmtree(basura, ignore_errors=True)
    if os.path.exists(ZIP):
        os.remove(ZIP)


def main():
    version = leer_version()
    print(f"=== Instalador de Caudal {version} ===", flush=True)
    comprimir()
    construir(version)

    resultado = os.path.join(AQUI, "CaudalInstalador.exe")
    if not os.path.exists(resultado):
        raise SystemExit("No se genero el instalador.")

    limpiar()
    print(f"\nLISTO: {resultado}")
    print(f"       {tamano(resultado):.0f} MB")
    print("\nSubelo como adjunto de la release en GitHub y las apps instaladas")
    print("se actualizaran solas.")


if __name__ == "__main__":
    main()
