<h1 align="center">Caudal</h1>

<p align="center">
Descarga música y videos en tu computadora, tu Android o tu iPhone.<br>
Con su propio navegador, su biblioteca y su reproductor.
</p>

<p align="center">
  <a href="https://github.com/Aliprogramator/caudal/releases/latest">
    <b>Descargar la última versión</b>
  </a>
</p>

---

## Qué hace

- **Navegador propio.** Entras a YouTube, Instagram, TikTok o donde sea y aparecen
  los botones de descargar video y descargar audio, sin salir de la app.
- **Eliges qué bajar.** Video con sonido, solo video o solo audio, siempre en la
  mejor calidad disponible.
- **Listas completas.** Pega el enlace de una lista de Spotify, Apple Music o
  YouTube Music y se descargan todas sus canciones.
- **Biblioteca sin conexión.** Lo descargado se queda en tu dispositivo y suena
  aunque no tengas internet.
- **Modo música.** Nivela el volumen para que todo suene igual de fuerte.
- **Tus dispositivos conectados.** Una cuenta enlaza la computadora y el teléfono.

## Las tres piezas

| Carpeta | Qué es |
|---|---|
| `escritorio/` | La aplicación de Windows, escrita en Python con PySide6. |
| `app/` | La aplicación de Android e iPhone, escrita en Flutter. |
| `servidor/` | La API de cuentas y el resolvedor de enlaces, en FastAPI. |
| `instalador/` | El instalador de Windows, escrito para este proyecto. |

## Instalar

**Windows** — baja `CaudalInstalador.exe` de la
[última versión](https://github.com/Aliprogramator/caudal/releases/latest) y ábrelo.
Si ya tenías Caudal, se actualiza encima y conserva tus descargas y ajustes.

**Android** — baja el APK y ábrelo desde el teléfono. `Caudal.apk` es el ligero;
`Caudal-universal.apk` funciona en cualquier teléfono aunque pese más.

**iPhone** — se compila en Codemagic con el `codemagic.yaml` que está en el
repositorio y se instala por sideload.

La aplicación avisa sola cuando hay una versión nueva.

## Dónde se guardan las descargas

Dentro de tu propio dispositivo. El servidor solo administra las cuentas: nunca
guarda tus archivos.

## Para desarrollarlo

```
escritorio/   pip install -r requirements.txt && python ejecutar.py
app/          flutter pub get && flutter run
servidor/     pip install -r requirements.txt && python -m caudal
```

Hace falta **ffmpeg** en `escritorio/bin` para unir video y audio y para convertir.

Los detalles de por qué está partido así están en [LEEME.md](LEEME.md).
