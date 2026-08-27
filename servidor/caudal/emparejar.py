# -*- coding: utf-8 -*-
"""Pagina de conexion: el QR que lee la app del telefono para saber donde esta
el servidor. Las credenciales no viajan aqui: se escriben al iniciar sesion."""

import base64
import io
import json


def _qr_base64(texto: str) -> str:
    import qrcode

    qr = qrcode.QRCode(version=None, error_correction=qrcode.constants.ERROR_CORRECT_M,
                       box_size=9, border=2)
    qr.add_data(texto)
    qr.make(fit=True)
    imagen = qr.make_image(fill_color="#0B0E14", back_color="#FFFFFF")
    buffer = io.BytesIO()
    imagen.save(buffer, format="PNG")
    return base64.b64encode(buffer.getvalue()).decode()


def pagina_emparejar(ip: str, puerto: int, publica: str = "", hay_cuentas: bool = False) -> str:
    servidor = f"http://{ip}:{puerto}"
    carga = json.dumps(
        {"servidor": servidor, "publico": publica or ""},
        ensure_ascii=False,
    )
    qr = _qr_base64(carga)

    bloque_publica = ""
    if publica:
        bloque_publica = f"""
      <div class="fila">
        <span class="etiqueta">Desde la calle</span>
        <span class="valor">{publica}</span>
      </div>"""

    if hay_cuentas:
        paso = """Abre <b>Caudal</b> en el telefono, pulsa <b>Escanear</b> y apunta aqui.<br>
        Despues inicia sesion con tu usuario y contrasena."""
        nota = ("El telefono y esta computadora deben estar en la <b>misma red wifi</b> "
                "la primera vez. Tu contrasena no viaja en el codigo: solo la direccion.")
    else:
        paso = """Todavia no has creado ninguna cuenta.<br>
        Hazlo en la app de escritorio, en <b>Cuenta</b>, y vuelve aqui."""
        nota = ("Las cuentas solo se crean desde esta computadora o desde tu propia red, "
                "nunca desde internet.")

    return f"""<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Caudal · conectar el telefono</title>
<style>
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{
    font-family: "Segoe UI Variable", "Segoe UI", system-ui, sans-serif;
    background: #0B0E14; color: #E8EBF1;
    min-height: 100vh; display: grid; place-items: center; padding: 32px 20px;
  }}
  .tarjeta {{
    width: min(560px, 100%); background: #141922; border: 1px solid #232A36;
    border-radius: 22px; padding: 34px; text-align: center;
  }}
  .marca {{ display: flex; align-items: center; justify-content: center; gap: 12px; margin-bottom: 6px; }}
  .gota {{
    width: 40px; height: 40px; border-radius: 13px;
    background: linear-gradient(150deg, #22D3EE, #6366F1);
    display: grid; place-items: center; font-size: 20px;
  }}
  h1 {{ font-size: 25px; letter-spacing: -0.4px; }}
  .lema {{ color: #7C879B; font-size: 13px; margin-bottom: 26px; }}
  .qr {{
    background: #fff; padding: 14px; border-radius: 18px; display: inline-block;
    line-height: 0; box-shadow: 0 10px 40px rgba(34, 211, 238, .12);
  }}
  .qr img {{ width: 236px; height: 236px; display: block; }}
  .paso {{ color: #A8B2C4; font-size: 14.5px; margin: 24px 0 20px; line-height: 1.6; }}
  .paso b {{ color: #E8EBF1; }}
  .datos {{ border-top: 1px solid #232A36; padding-top: 20px; margin-top: 4px; text-align: left; }}
  .fila {{ display: flex; justify-content: space-between; align-items: center; gap: 14px; padding: 9px 0; }}
  .etiqueta {{ color: #7C879B; font-size: 12.5px; white-space: nowrap; }}
  .valor {{
    font-family: "Cascadia Mono", Consolas, monospace; font-size: 13px;
    background: #1C2230; padding: 7px 11px; border-radius: 8px;
    border: 1px solid #2A3140; user-select: all; word-break: break-all;
  }}
  .aviso {{
    margin-top: 22px; padding: 13px 15px; background: rgba(34, 211, 238, .07);
    border: 1px solid rgba(34, 211, 238, .22); border-radius: 12px;
    color: #A8B2C4; font-size: 12.5px; line-height: 1.55; text-align: left;
  }}
</style>
</head>
<body>
  <div class="tarjeta">
    <div class="marca">
      <div class="gota">💧</div>
      <h1>Caudal</h1>
    </div>
    <p class="lema">El servidor esta funcionando</p>

    <div class="qr"><img src="data:image/png;base64,{qr}" alt="Codigo QR para conectar"></div>

    <p class="paso">{paso}</p>

    <div class="datos">
      <div class="fila"><span class="etiqueta">En casa</span><span class="valor">{servidor}</span></div>{bloque_publica}
    </div>

    <div class="aviso">{nota}</div>
  </div>
</body>
</html>"""
