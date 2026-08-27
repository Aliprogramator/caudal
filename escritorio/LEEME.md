# Descargador de Videos

Aplicación de escritorio para descargar videos y audio de YouTube, Instagram,
TikTok, X (Twitter), Facebook, Telegram y más de mil sitios web.

---

## Cómo se usa

1. Abre la aplicación (acceso directo del escritorio, `Descargador de Videos.bat`
   o el `.exe` de la carpeta `dist`).
2. Pega el enlace en el campo de arriba y pulsa **Descargar**.
3. Los videos se guardan en la carpeta que aparece indicada bajo los desplegables.

Puedes pegar **varios enlaces de golpe** (separados por espacios o saltos de
línea) o **arrastrarlos** hasta la ventana.

### Atajos

| Atajo | Qué hace |
|---|---|
| `Ctrl+V` | Pega el enlace del portapapeles y lo encola |
| `Ctrl+L` | Pone el cursor en el campo del enlace |
| `Ctrl+O` | Abre la carpeta de descargas |
| `Ctrl+Q` | Cierra la aplicación |

Clic derecho sobre cualquier descarga para reproducirla, verla en la carpeta,
copiar su enlace o reintentarla.

---

## Qué puede descargar

**Con extractor dedicado y probado:** YouTube, YouTube Music, Instagram, TikTok,
X (Twitter), Facebook, Telegram, Reddit, Twitch, Vimeo, Dailymotion, Pinterest,
Bluesky, Snapchat, Tumblr, Kick, Rumble, Bilibili, Douyin, VK, OK.ru, SoundCloud,
Bandcamp, Mixcloud, Imgur, Streamable, 9GAG, Niconico, Odysee, Weibo, LinkedIn,
Google Drive, Dropbox, Archive.org, TED, Coub, Newgrounds, Patreon, Likee,
Xiaohongshu, Substack.

**Sin extractor dedicado** (se intenta de forma genérica y puede no funcionar):
Threads y Triller.

Además funciona con cualquiera de los ~1750 sitios que soporta el motor yt-dlp.

### Qué descargar

El primer desplegable decide **qué** se baja:

| Opción | Qué obtienes |
|---|---|
| **Video con audio** | El video completo, como siempre |
| **Solo video (sin audio)** | Únicamente la imagen, sin pista de sonido (archivo más pequeño) |
| **Solo audio** | Únicamente el sonido, convertido a MP3, M4A, OPUS, FLAC o WAV |

Al elegir *Solo audio* se apagan los desplegables de resolución y contenedor,
porque no aplican, y se enciende el de formato de audio.

### Calidades

Mejor disponible, 4K, 2K, 1080p, 720p, 480p y 360p.

Con **MP4** se prefieren H.264 y AAC, que reproduce cualquier móvil o equipo con
Windows. Si eliges MKV se toma la mejor pista disponible aunque use códecs más
nuevos (AV1, Opus), que dan archivos más pequeños pero no los abre todo el mundo.

---

## Contenido que pide iniciar sesión

Instagram, X, Facebook y algunos videos de YouTube (con restricción de edad)
sólo se dejan descargar si la petición va acompañada de una sesión iniciada.

Para esos casos, en **Ajustes → Contenido que pide iniciar sesión**:

1. Elige el navegador donde ya tienes la sesión abierta (Chrome, Edge, Firefox…).
2. **Cierra por completo ese navegador** antes de descargar. Windows bloquea el
   archivo de cookies mientras el navegador está abierto y la lectura falla.
3. Vuelve a intentar la descarga.

Alternativa: exportar un `cookies.txt` con una extensión de navegador y
seleccionarlo en el mismo panel.

---

## Telegram

Funciona con publicaciones **públicas** de canales, con el formato
`https://t.me/canal/1234` (el enlace de una publicación concreta, no el del canal).

La app trae su propio extractor de Telegram, porque el motor yt-dlp no lo cubre
del todo; si ese extractor falla, se reintenta automáticamente con yt-dlp.

No puede descargar de chats privados ni de canales cerrados: ese contenido no es
accesible sin la cuenta.

---

## Ajustes que conviene conocer

| Ajuste | Para qué sirve |
|---|---|
| Descargas simultáneas | Cuántos videos se bajan a la vez (1–8) |
| Límite de velocidad | Deja ancho de banda libre para lo demás |
| Listas y perfiles completos | Al pegar una playlist, la expande en videos sueltos |
| Tope por lista | Evita encolar listas gigantes sin querer |
| Incrustar miniatura | Deja la portada dentro del archivo |
| Subtítulos | Los descarga y los mete dentro del video |
| Subcarpeta por red social | Ordena las descargas por plataforma |
| Nombre del archivo | Plantilla de yt-dlp: `%(title)s`, `%(id)s`, `%(uploader)s`, `%(ext)s` |
| Detectar enlaces copiados | Al copiar un enlace, lo pone en el campo listo para descargar |

Los ajustes y el historial se guardan en
`%APPDATA%\DescargadorVideos` (ajustes.json e historial.db).

---

## Pausar y reanudar

El botón de pausa detiene la descarga conservando lo bajado. Al reanudar,
continúa desde donde iba en lugar de empezar de cero. Lo mismo pasa si cierras
la aplicación a mitad de una descarga: al volver, pulsa reintentar.

---

## Si algo falla

| Mensaje | Qué hacer |
|---|---|
| «pide iniciar sesión» | Activa las cookies del navegador en Ajustes (y ciérralo antes) |
| «ya no está disponible» | El video fue borrado o es privado |
| «bloqueado en tu país» | Prueba con un proxy en Ajustes |
| «falta ffmpeg» | Comprueba que existe la carpeta `bin` junto a la aplicación |
| Un sitio deja de funcionar de golpe | **Ajustes → Actualizar motor yt-dlp**. Las webs cambian a menudo y el motor se actualiza cada pocos días |

---

## Estructura del proyecto

```
DescargadorVideos/
├── ejecutar.py              arranque
├── descargador/
│   ├── main.py              punto de entrada
│   ├── redes.py             detección de la red social por la URL
│   ├── motor.py             cola, hilos y descarga (yt-dlp)
│   ├── telegram_dl.py       extractor propio de Telegram
│   ├── config.py            ajustes persistentes
│   ├── historial.py         historial en SQLite
│   └── ui/
│       ├── ventana.py       ventana principal y pestañas
│       ├── tarjeta.py       tarjeta de cada descarga
│       ├── iconos.py        iconos dibujados a mano (sin archivos externos)
│       └── estilos.py       paleta y hoja de estilos
└── bin/                     ffmpeg y ffprobe
```

Para ejecutar desde el código fuente:

```
pip install -r requirements.txt
python ejecutar.py
```

---

## Nota de uso

Descarga contenido del que tengas los derechos o cuyo uso permita la licencia y
los términos del sitio. Respeta el trabajo de quien lo publicó.
