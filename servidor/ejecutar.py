# -*- coding: utf-8 -*-
"""Arranca el servidor Caudal y muestra como conectar el telefono."""

import os
import sys
import webbrowser


def main():
    # la consola de Windows usa cp1252: sin esto, cualquier tilde rompe el arranque
    for flujo in (sys.stdout, sys.stderr):
        try:
            flujo.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, OSError):
            pass

    raiz = os.path.dirname(os.path.abspath(__file__))
    if raiz not in sys.path:
        sys.path.insert(0, raiz)

    from caudal.config import Ajustes, ip_local, ruta_ffmpeg
    import uvicorn

    ajustes = Ajustes()
    puerto = int(ajustes["puerto"])
    ip = ip_local()
    direccion = f"http://{ip}:{puerto}"

    linea = "-" * 58
    print(f"\n  {linea}")
    print("   CAUDAL · servidor de descargas")
    print(f"  {linea}")
    print(f"   Direccion   {direccion}")
    print(f"   Token       {ajustes['token']}")
    print(f"   ffmpeg      {ruta_ffmpeg() or 'NO ENCONTRADO (hace falta para unir y convertir)'}")
    print(f"  {linea}")
    print("   Abre esa direccion en el navegador para ver el codigo QR")
    print("   y escanearlo desde la app Caudal del telefono.")
    print("   El telefono debe estar en la misma red wifi.")
    print(f"  {linea}")
    print("   Para detenerlo: Ctrl+C\n")

    if "--sin-navegador" not in sys.argv:
        try:
            webbrowser.open(direccion)
        except Exception:
            pass

    uvicorn.run("caudal.principal:app", host="0.0.0.0", port=puerto,
                log_level="warning", access_log=False)


if __name__ == "__main__":
    main()
