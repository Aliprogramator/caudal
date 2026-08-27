# -*- coding: utf-8 -*-
"""Iconos dibujados con QPainter: sin archivos ni dependencias externas."""

from PySide6.QtCore import QPointF, QRectF, Qt
from PySide6.QtGui import QColor, QIcon, QPainter, QPainterPath, QPen, QPixmap

from .estilos import C

_CACHE = {}


def _lienzo(tam):
    pm = QPixmap(tam, tam)
    pm.fill(Qt.transparent)
    p = QPainter(pm)
    p.setRenderHint(QPainter.Antialiasing, True)
    return pm, p


def _pluma(p, color, grosor=1.9):
    lapiz = QPen(QColor(color))
    lapiz.setWidthF(grosor)
    lapiz.setCapStyle(Qt.RoundCap)
    lapiz.setJoinStyle(Qt.RoundJoin)
    p.setPen(lapiz)
    p.setBrush(Qt.NoBrush)
    return lapiz


def pixmap(nombre, tam=20, color=None):
    color = color or C["texto2"]
    clave = (nombre, tam, color)
    if clave in _CACHE:
        return _CACHE[clave]

    pm, p = _lienzo(tam)
    e = tam / 24.0  # escala respecto a un lienzo de 24
    _pluma(p, color)

    if nombre == "descargar":
        p.drawLine(QPointF(12 * e, 3 * e), QPointF(12 * e, 15 * e))
        p.drawPolyline([QPointF(7 * e, 10.5 * e), QPointF(12 * e, 15.5 * e), QPointF(17 * e, 10.5 * e)])
        p.drawPolyline([QPointF(4 * e, 19 * e), QPointF(4 * e, 21 * e), QPointF(20 * e, 21 * e),
                        QPointF(20 * e, 19 * e)])

    elif nombre == "pausa":
        p.setBrush(QColor(color))
        p.setPen(Qt.NoPen)
        p.drawRoundedRect(QRectF(7.5 * e, 5 * e, 3.4 * e, 14 * e), 1.4 * e, 1.4 * e)
        p.drawRoundedRect(QRectF(13.1 * e, 5 * e, 3.4 * e, 14 * e), 1.4 * e, 1.4 * e)

    elif nombre == "reproducir":
        p.setBrush(QColor(color))
        p.setPen(Qt.NoPen)
        ruta = QPainterPath()
        ruta.moveTo(8 * e, 5 * e)
        ruta.lineTo(19 * e, 12 * e)
        ruta.lineTo(8 * e, 19 * e)
        ruta.closeSubpath()
        p.drawPath(ruta)

    elif nombre == "cerrar":
        p.drawLine(QPointF(6.5 * e, 6.5 * e), QPointF(17.5 * e, 17.5 * e))
        p.drawLine(QPointF(17.5 * e, 6.5 * e), QPointF(6.5 * e, 17.5 * e))

    elif nombre == "carpeta":
        ruta = QPainterPath()
        ruta.moveTo(3 * e, 7 * e)
        ruta.lineTo(9.5 * e, 7 * e)
        ruta.lineTo(11.5 * e, 9.5 * e)
        ruta.lineTo(21 * e, 9.5 * e)
        ruta.lineTo(21 * e, 19 * e)
        ruta.lineTo(3 * e, 19 * e)
        ruta.closeSubpath()
        p.drawPath(ruta)

    elif nombre == "reintentar":
        p.drawArc(QRectF(4.5 * e, 4.5 * e, 15 * e, 15 * e), 60 * 16, 280 * 16)
        p.setBrush(QColor(color))
        p.setPen(Qt.NoPen)
        ruta = QPainterPath()
        ruta.moveTo(19.5 * e, 3 * e)
        ruta.lineTo(19.5 * e, 9.5 * e)
        ruta.lineTo(13.5 * e, 9 * e)
        ruta.closeSubpath()
        p.drawPath(ruta)

    elif nombre == "papelera":
        p.drawLine(QPointF(4 * e, 6.5 * e), QPointF(20 * e, 6.5 * e))
        p.drawPolyline([QPointF(9 * e, 6.5 * e), QPointF(9 * e, 4 * e), QPointF(15 * e, 4 * e),
                        QPointF(15 * e, 6.5 * e)])
        p.drawPolyline([QPointF(6 * e, 6.5 * e), QPointF(7 * e, 20.5 * e), QPointF(17 * e, 20.5 * e),
                        QPointF(18 * e, 6.5 * e)])
        p.drawLine(QPointF(10 * e, 10 * e), QPointF(10.4 * e, 17 * e))
        p.drawLine(QPointF(14 * e, 10 * e), QPointF(13.6 * e, 17 * e))

    elif nombre == "pegar":
        p.drawRoundedRect(QRectF(5 * e, 5 * e, 11 * e, 14 * e), 2 * e, 2 * e)
        p.drawRoundedRect(QRectF(8.5 * e, 2.5 * e, 4 * e, 3.4 * e), 1 * e, 1 * e)
        p.drawRoundedRect(QRectF(10 * e, 9 * e, 9 * e, 12 * e), 2 * e, 2 * e)

    elif nombre == "engranaje":
        p.drawEllipse(QPointF(12 * e, 12 * e), 3.2 * e, 3.2 * e)
        p.drawEllipse(QPointF(12 * e, 12 * e), 7.6 * e, 7.6 * e)
        import math
        for i in range(8):
            ang = math.radians(i * 45)
            x1, y1 = 12 * e + 7.6 * e * math.cos(ang), 12 * e + 7.6 * e * math.sin(ang)
            x2, y2 = 12 * e + 10 * e * math.cos(ang), 12 * e + 10 * e * math.sin(ang)
            p.drawLine(QPointF(x1, y1), QPointF(x2, y2))

    elif nombre == "reloj":
        p.drawEllipse(QPointF(12 * e, 12 * e), 8.5 * e, 8.5 * e)
        p.drawPolyline([QPointF(12 * e, 7 * e), QPointF(12 * e, 12.4 * e), QPointF(16 * e, 14.5 * e)])

    elif nombre == "lupa":
        p.drawEllipse(QPointF(10.5 * e, 10.5 * e), 6.5 * e, 6.5 * e)
        p.drawLine(QPointF(15.4 * e, 15.4 * e), QPointF(20.5 * e, 20.5 * e))

    elif nombre == "abrir":
        p.drawPolyline([QPointF(14 * e, 4 * e), QPointF(20 * e, 4 * e), QPointF(20 * e, 10 * e)])
        p.drawLine(QPointF(20 * e, 4 * e), QPointF(11 * e, 13 * e))
        p.drawPolyline([QPointF(17 * e, 14 * e), QPointF(17 * e, 20 * e), QPointF(4 * e, 20 * e),
                        QPointF(4 * e, 7 * e), QPointF(10 * e, 7 * e)])

    elif nombre == "listo":
        p.drawPolyline([QPointF(5.5 * e, 12.5 * e), QPointF(10 * e, 17 * e), QPointF(18.5 * e, 7 * e)])

    elif nombre == "aviso":
        ruta = QPainterPath()
        ruta.moveTo(12 * e, 3.5 * e)
        ruta.lineTo(21.5 * e, 20 * e)
        ruta.lineTo(2.5 * e, 20 * e)
        ruta.closeSubpath()
        p.drawPath(ruta)
        p.drawLine(QPointF(12 * e, 10 * e), QPointF(12 * e, 14.5 * e))
        p.setBrush(QColor(color))
        p.setPen(Qt.NoPen)
        p.drawEllipse(QPointF(12 * e, 17.3 * e), 1 * e, 1 * e)

    elif nombre == "video":
        p.drawRoundedRect(QRectF(2.5 * e, 6 * e, 13 * e, 12 * e), 2.4 * e, 2.4 * e)
        ruta = QPainterPath()
        ruta.moveTo(16.5 * e, 11 * e)
        ruta.lineTo(21.5 * e, 7.5 * e)
        ruta.lineTo(21.5 * e, 16.5 * e)
        ruta.lineTo(16.5 * e, 13 * e)
        ruta.closeSubpath()
        p.drawPath(ruta)

    elif nombre == "musica":
        p.drawEllipse(QPointF(7 * e, 17.5 * e), 3.2 * e, 2.8 * e)
        p.drawEllipse(QPointF(17.5 * e, 15.5 * e), 3.2 * e, 2.8 * e)
        p.drawLine(QPointF(10.2 * e, 17.5 * e), QPointF(10.2 * e, 6.5 * e))
        p.drawLine(QPointF(20.7 * e, 15.5 * e), QPointF(20.7 * e, 4.5 * e))
        p.drawLine(QPointF(10.2 * e, 6.5 * e), QPointF(20.7 * e, 4.5 * e))


    elif nombre == "atras":
        p.drawPolyline([QPointF(14.5 * e, 5 * e), QPointF(8 * e, 12 * e),
                        QPointF(14.5 * e, 19 * e)])

    elif nombre == "adelante":
        p.drawPolyline([QPointF(9.5 * e, 5 * e), QPointF(16 * e, 12 * e),
                        QPointF(9.5 * e, 19 * e)])

    elif nombre == "casa":
        p.drawPolyline([QPointF(3.5 * e, 11 * e), QPointF(12 * e, 4 * e),
                        QPointF(20.5 * e, 11 * e)])
        p.drawPolyline([QPointF(5.5 * e, 10 * e), QPointF(5.5 * e, 20 * e),
                        QPointF(18.5 * e, 20 * e), QPointF(18.5 * e, 10 * e)])

    elif nombre == "anterior":
        p.setBrush(QColor(color))
        p.setPen(Qt.NoPen)
        ruta = QPainterPath()
        ruta.moveTo(18 * e, 5 * e)
        ruta.lineTo(18 * e, 19 * e)
        ruta.lineTo(8 * e, 12 * e)
        ruta.closeSubpath()
        p.drawPath(ruta)
        p.drawRoundedRect(QRectF(5 * e, 5 * e, 2.4 * e, 14 * e), 1.2 * e, 1.2 * e)

    elif nombre == "siguiente":
        p.setBrush(QColor(color))
        p.setPen(Qt.NoPen)
        ruta = QPainterPath()
        ruta.moveTo(6 * e, 5 * e)
        ruta.lineTo(6 * e, 19 * e)
        ruta.lineTo(16 * e, 12 * e)
        ruta.closeSubpath()
        p.drawPath(ruta)
        p.drawRoundedRect(QRectF(16.6 * e, 5 * e, 2.4 * e, 14 * e), 1.2 * e, 1.2 * e)

    elif nombre == "aleatorio":
        p.drawPolyline([QPointF(3 * e, 7 * e), QPointF(8 * e, 7 * e),
                        QPointF(16 * e, 17 * e), QPointF(21 * e, 17 * e)])
        p.drawPolyline([QPointF(3 * e, 17 * e), QPointF(8 * e, 17 * e),
                        QPointF(16 * e, 7 * e), QPointF(21 * e, 7 * e)])
        p.setBrush(QColor(color))
        p.setPen(Qt.NoPen)
        for y in (7, 17):
            ruta = QPainterPath()
            ruta.moveTo(18 * e, (y - 3) * e)
            ruta.lineTo(22 * e, y * e)
            ruta.lineTo(18 * e, (y + 3) * e)
            ruta.closeSubpath()
            p.drawPath(ruta)

    elif nombre == "globo":
        p.drawEllipse(QPointF(12 * e, 12 * e), 8.5 * e, 8.5 * e)
        p.drawEllipse(QPointF(12 * e, 12 * e), 3.6 * e, 8.5 * e)
        p.drawLine(QPointF(3.5 * e, 12 * e), QPointF(20.5 * e, 12 * e))

    elif nombre == "telefono":
        p.drawRoundedRect(QRectF(7 * e, 2.5 * e, 10 * e, 19 * e), 2.4 * e, 2.4 * e)
        p.setBrush(QColor(color))
        p.setPen(Qt.NoPen)
        p.drawEllipse(QPointF(12 * e, 18.5 * e), 0.9 * e, 0.9 * e)


    elif nombre in ("altavoz", "altavoz_fuerte"):
        p.setBrush(QColor(color))
        p.setPen(Qt.NoPen)
        cuerpo = QPainterPath()
        cuerpo.moveTo(3 * e, 9 * e)
        cuerpo.lineTo(7 * e, 9 * e)
        cuerpo.lineTo(12 * e, 4.5 * e)
        cuerpo.lineTo(12 * e, 19.5 * e)
        cuerpo.lineTo(7 * e, 15 * e)
        cuerpo.lineTo(3 * e, 15 * e)
        cuerpo.closeSubpath()
        p.drawPath(cuerpo)
        _pluma(p, color, 1.8)
        if nombre == "altavoz_fuerte":
            p.drawArc(QRectF(12.5 * e, 8 * e, 5 * e, 8 * e), -70 * 16, 140 * 16)
            p.drawArc(QRectF(13.5 * e, 5 * e, 8 * e, 14 * e), -70 * 16, 140 * 16)
        else:
            p.drawArc(QRectF(12.5 * e, 8 * e, 5 * e, 8 * e), -70 * 16, 140 * 16)

    elif nombre == "mas":
        p.drawLine(QPointF(12 * e, 5 * e), QPointF(12 * e, 19 * e))
        p.drawLine(QPointF(5 * e, 12 * e), QPointF(19 * e, 12 * e))

    p.end()
    _CACHE[clave] = pm
    return pm


def icono(nombre, tam=20, color=None):
    return QIcon(pixmap(nombre, tam, color))


def chip_plataforma(plataforma, tam=34):
    """Cuadro redondeado con el color e inicial de la red social."""
    clave = ("chip", plataforma.clave, tam)
    if clave in _CACHE:
        return _CACHE[clave]

    pm, p = _lienzo(tam)
    color = QColor(plataforma.color)
    p.setPen(Qt.NoPen)
    p.setBrush(color)
    p.drawRoundedRect(QRectF(0, 0, tam, tam), tam * 0.29, tam * 0.29)

    # texto legible sobre el color de marca
    luminancia = (0.299 * color.red() + 0.587 * color.green() + 0.114 * color.blue()) / 255
    p.setPen(QColor("#0B0D12") if luminancia > 0.62 else QColor("#FFFFFF"))
    fuente = p.font()
    texto = plataforma.icono
    fuente.setPointSizeF(tam * (0.40 if len(texto) == 1 else 0.30))
    fuente.setBold(True)
    p.setFont(fuente)
    p.drawText(QRectF(0, 0, tam, tam), Qt.AlignCenter, texto)
    p.end()

    _CACHE[clave] = pm
    return pm


def miniatura_redondeada(datos, ancho=124, alto=70, radio=9):
    """Convierte bytes de imagen en un pixmap recortado con esquinas redondeadas."""
    origen = QPixmap()
    if datos:
        origen.loadFromData(datos)
    destino = QPixmap(ancho, alto)
    destino.fill(Qt.transparent)

    p = QPainter(destino)
    p.setRenderHint(QPainter.Antialiasing, True)
    p.setRenderHint(QPainter.SmoothPixmapTransform, True)
    ruta = QPainterPath()
    ruta.addRoundedRect(QRectF(0, 0, ancho, alto), radio, radio)
    p.setClipPath(ruta)

    if origen.isNull():
        p.fillRect(0, 0, ancho, alto, QColor(C["superficie3"]))
        p.setPen(QColor(C["texto3"]))
        p.drawPixmap(int(ancho / 2 - 11), int(alto / 2 - 11),
                     pixmap("video", 22, C["texto3"]))
    else:
        escalada = origen.scaled(ancho, alto, Qt.KeepAspectRatioByExpanding, Qt.SmoothTransformation)
        x = (escalada.width() - ancho) // 2
        y = (escalada.height() - alto) // 2
        p.drawPixmap(0, 0, escalada, x, y, ancho, alto)
    p.end()
    return destino


def icono_plataforma(clave, tam=20):
    """El chip de color de una red, como QIcon para los botones."""
    from .. import redes
    return QIcon(chip_plataforma(redes.plataforma_por_clave(clave), tam))


def flechas_qss():
    """Dibuja las flechas de los desplegables y devuelve sus rutas para el QSS.

    Qt no sabe formar triangulos con bordes CSS, asi que se generan como PNG.
    """
    from ..config import carpeta_datos

    destino = carpeta_datos() / "tema"
    destino.mkdir(parents=True, exist_ok=True)
    rutas = {}
    for nombre, hacia, color in (("abajo", "abajo", C["texto2"]),
                                 ("abajo_claro", "abajo", C["texto"]),
                                 ("arriba", "arriba", C["texto2"])):
        archivo = destino / f"flecha_{nombre}.png"
        pm = QPixmap(20, 20)
        pm.fill(Qt.transparent)
        p = QPainter(pm)
        p.setRenderHint(QPainter.Antialiasing, True)
        p.setPen(Qt.NoPen)
        p.setBrush(QColor(color))
        ruta = QPainterPath()
        if hacia == "abajo":
            ruta.moveTo(5, 8)
            ruta.lineTo(15, 8)
            ruta.lineTo(10, 13.5)
        else:
            ruta.moveTo(5, 12)
            ruta.lineTo(15, 12)
            ruta.lineTo(10, 6.5)
        ruta.closeSubpath()
        p.drawPath(ruta)
        p.end()
        pm.save(str(archivo))
        rutas[nombre] = str(archivo).replace("\\", "/")
    return rutas


def icono_app(tam=64):
    """Icono de la aplicacion: flecha de descarga sobre fondo indigo."""
    pm, p = _lienzo(tam)
    e = tam / 64.0
    p.setPen(Qt.NoPen)
    p.setBrush(QColor(C["acento"]))
    p.drawRoundedRect(QRectF(0, 0, tam, tam), 15 * e, 15 * e)

    lapiz = QPen(QColor("#FFFFFF"))
    lapiz.setWidthF(5.4 * e)
    lapiz.setCapStyle(Qt.RoundCap)
    lapiz.setJoinStyle(Qt.RoundJoin)
    p.setPen(lapiz)
    p.setBrush(Qt.NoBrush)
    p.drawLine(QPointF(32 * e, 14 * e), QPointF(32 * e, 38 * e))
    p.drawPolyline([QPointF(21 * e, 28 * e), QPointF(32 * e, 39.5 * e), QPointF(43 * e, 28 * e)])
    p.drawLine(QPointF(18 * e, 48 * e), QPointF(46 * e, 48 * e))
    p.end()
    return pm
