# Caudal

App móvil (Android e iPhone) para descargar música y videos desde su propio
navegador, apoyada en un servidor que corre en tu computadora.

---

## Por qué hay un servidor

El motor que entiende YouTube, Instagram, TikTok y ~1750 sitios más es **yt-dlp**,
escrito en Python. En Android se podría incrustar con mucho esfuerzo, pero **en
iPhone es imposible**: Apple no permite ejecutar ese tipo de código dentro de una app.

Por eso Caudal se divide en dos piezas:

```
   TELÉFONO                              COMPUTADORA
┌──────────────┐                      ┌──────────────────┐
│  App Caudal  │ ──── enlace ───────► │  Servidor Caudal │
│              │                      │   yt-dlp+ffmpeg  │
│  navegador   │ ◄─── archivo ─────── │   resuelve y     │
│  biblioteca  │                      │   convierte      │
└──────────────┘                      └──────────────────┘
        misma red wifi
```

La ventaja: **funciona igual en Android y en iPhone**, y el motor se actualiza en
un solo sitio cuando las webs cambian.

---

## Puesta en marcha

### 1. Enciende el servidor (en la computadora)

```
C:\Users\USER\Caudal\servidor\IniciarServidor.bat
```

Se abrirá una página en el navegador con un **código QR**. Déjala abierta.

La ventana del servidor muestra la dirección (por ejemplo `http://192.168.18.170:8770`)
y el token de acceso, por si prefieres escribirlos a mano.

### 2. Instala la app (en el teléfono)

Pasa el APK al teléfono y ábrelo:

```
C:\Users\USER\Caudal\app\build\app\outputs\flutter-apk\app-release.apk
```

Android pedirá permitir la instalación de orígenes desconocidos: es normal al
instalar fuera de Play Store.

### 3. Crea tu cuenta y entra

Abre Caudal → **Escanear código QR** → apunta a la pantalla de la computadora.
Después crea tu usuario y contraseña, y ya estás dentro.

Con esa misma cuenta entras desde cualquier teléfono: no hay que volver a
escanear nada. En **Ajustes → Tu cuenta** ves qué dispositivos tienen acceso y
puedes quitarle el acceso a cualquiera.

> La primera vez, el teléfono y la computadora deben estar en la **misma red
> wifi**. Las cuentas solo se crean desde tu red, nunca desde internet.

### Usarlo desde la calle

El servidor puede abrir un túnel seguro para que llegues a él desde fuera de
casa, sin tocar el router. La app guarda las dos direcciones y usa la de casa
cuando estás en ella (más rápida) y la de internet cuando no.

Para entrar desde fuera hace falta tu usuario y contraseña, igual que en casa;
crear cuentas nuevas sigue bloqueado desde internet.

---

## Cómo se usa

| Quiero... | Hago... |
|---|---|
| Bajar una canción | Pestaña **Buscar** → escribo el nombre → toco el resultado |
| Bajar de una web concreta | Pestaña **Navegador** → abro el video → salen solos **Video** y **Audio** |
| Bajar un enlace copiado | Pestaña **Buscar** → botón de pegar |
| Escuchar sin conexión | Pestaña **Biblioteca** → toco la canción |
| Ver un video descargado | Pestaña **Biblioteca** → pestaña Videos |

### El navegador reconoce los videos solo

Cuando entras a un video (YouTube, Instagram, TikTok, X…), aparece sola una barra
abajo con la miniatura, el título y dos botones:

- **Video** — lo baja en la mejor calidad disponible (la barra indica cuál: *hasta 1080p*)
- **Audio** — baja solo el sonido en MP3

Un toque y ya está: no hay menús de por medio. Si quieres elegir otra calidad u
otro formato, el botón de la derecha (**⚙**) abre las opciones completas.

En sitios de música (YouTube Music, SoundCloud, Bandcamp) el botón de audio va
primero, porque es lo que sueles querer ahí.

La detección funciona también cuando YouTube cambia de video **sin recargar la
página**, y no aparece en portadas, perfiles ni búsquedas, para no molestar.

Si un sitio no se reconoce, el botón de descarga de la barra inferior sigue
sirviendo para probar con la página actual.

### Modo música: que suene más fuerte

En **Ajustes → Modo música** se activa el volumen alto. Hace dos cosas:

1. El audio se **nivela al descargarlo** (normalización a -9 LUFS con los picos
   limitados). Medido sobre la misma canción: pasa de -26,2 dB a -13,5 dB de
   volumen medio, o sea unas cuatro veces más fuerte, sin llegar a saturar.
2. El reproductor **empuja el volumen** por encima del máximo normal, con un
   control deslizante por si quieres más o menos.

En el reproductor hay un botón de altavoz para encenderlo y apagarlo al vuelo.
Lo ya descargado conserva su volumen: para que suene más fuerte hay que volver a
bajarlo con el modo puesto.

### Traer tus listas de Spotify, Apple Music y YouTube Music

En **Buscar → Traer una lista** pegas el enlace de una lista o un álbum público
y Caudal lee sus canciones, te deja elegir cuáles quieres y las descarga en MP3.

Funciona con listas y álbumes de **Spotify**, **Apple Music** y **YouTube
Music**. Las canciones se buscan por «artista + título», así que alguna puede
salir en otra versión: por eso puedes desmarcar las que no quieras.

> **Lo que no se puede hacer:** convertir la música que ya tienes descargada
> *dentro* de Spotify, Apple Music o YouTube Premium. Esos archivos van cifrados
> con DRM y solo funcionan dentro de su app; además dejan de servir si cancelas la
> suscripción. Por eso Caudal parte de la lista y baja las canciones aparte.

### Elegir a mano

En cada descarga puedes elegir **qué bajar**: video con audio, solo video (sin
sonido) o solo audio (MP3, M4A, FLAC o WAV), y en qué calidad.

La música sigue sonando con la pantalla apagada y se controla desde la
notificación y los botones del auricular.

---

## Dónde quedan los archivos

Por defecto en la carpeta pública, para que tus otras apps los vean:

```
Descargas/Caudal/Musica
Descargas/Caudal/Videos
```

Si prefieres que queden dentro de la app (y se borren al desinstalarla), apaga
esa opción en **Ajustes → Guardar en la carpeta Descargas**.

---

## La versión de iPhone

El proyecto ya está preparado, pero **compilar para iPhone exige un Mac**. Como no
tienes uno, se compila en la nube:

1. Sube la carpeta `app/` a un repositorio de GitHub.
2. Entra en [codemagic.io](https://codemagic.io) y conecta ese repositorio.
3. Lanza el flujo **`ios`** del archivo `codemagic.yaml` que ya está incluido.
4. Te devuelve un `.ipa` sin firmar: se instala en el iPhone con **Sideloadly** o
   **AltStore** (hay que renovarlo cada 7 días con cuenta gratuita de Apple).

Si tienes cuenta de desarrollador de Apple (99 USD/año), usa el flujo
**`ios_firmado`** y la instalación es directa y sin caducidad.

---

## Aviso sobre las tiendas de apps

Ni App Store ni Google Play aceptan apps cuyo propósito sea descargar de YouTube:
va contra los términos de esos servicios. Caudal está pensada para **uso personal
por instalación directa** (APK en Android, sideload en iPhone), no para publicarse.

---

## Estructura

```
Caudal/
├── servidor/                    la parte que corre en la computadora
│   ├── caudal/
│   │   ├── principal.py         la API (FastAPI)
│   │   ├── motor.py             yt-dlp: resolver, buscar, convertir
│   │   ├── emparejar.py         página del código QR
│   │   └── config.py            token, rutas, ffmpeg
│   ├── ejecutar.py
│   └── IniciarServidor.bat
│
└── app/                         la app del teléfono (Flutter)
    ├── lib/
    │   ├── main.dart            arranque y servicios
    │   ├── nucleo/
    │   │   ├── servidor.dart    cliente del servidor
    │   │   ├── descargas.dart   cola, progreso, pausa y reanudación
    │   │   ├── almacen.dart     biblioteca (SQLite)
    │   │   ├── ajustes.dart     preferencias
    │   │   ├── modelos.dart     tipos de datos
    │   │   ├── formato.dart     tamaños, tiempos, enlaces
    │   │   └── tema.dart        colores y estilos
    │   ├── pantallas/           buscar, navegador, descargas, biblioteca...
    │   ├── widgets/             piezas de interfaz reutilizables
    │   └── reproduccion/        reproductor de música en segundo plano
    ├── test/                    pruebas de la lógica
    └── codemagic.yaml           compilación en la nube (Android e iOS)
```

---

## La API del servidor

Por si quieres usarla desde otro sitio. Todo pide la cabecera `X-Caudal-Token`
salvo `/` y `/salud`.

| Ruta | Qué hace |
|---|---|
| `GET /salud` | Comprueba que el servidor responde |
| `POST /resolver` | Datos y calidades de un enlace |
| `GET /buscar?q=` | Busca en YouTube por nombre |
| `POST /trabajos` | Encarga una descarga |
| `GET /trabajos/{id}` | Progreso de la preparación |
| `GET /trabajos/{id}/archivo` | Baja el resultado (admite reanudación) |
| `DELETE /trabajos/{id}` | Cancela y limpia |

Los archivos temporales del servidor se borran solos a las 6 horas.

---

## Si algo falla

| Síntoma | Qué mirar |
|---|---|
| «No se llega al servidor» | ¿Está encendido? ¿Mismo wifi? ¿El firewall de Windows bloquea el puerto 8770? |
| «El sitio pide iniciar sesión» | Instagram o X lo hacen a menudo; configura cookies en `%APPDATA%\Caudal\servidor.json` |
| Un sitio deja de funcionar | Actualiza el motor: `pip install --upgrade yt-dlp` |
| Las descargas no aparecen en otras apps | Activa «Guardar en la carpeta Descargas» y concede el permiso |

---

## Nota de uso

Descarga solo contenido del que tengas los derechos o cuyo uso permitan la
licencia y los términos del sitio.
