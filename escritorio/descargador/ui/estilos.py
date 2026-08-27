# -*- coding: utf-8 -*-
"""Paleta y hoja de estilos de la aplicacion."""

C = {
    "fondo":       "#0E1015",
    "superficie":  "#161A22",
    "superficie2": "#1D222C",
    "superficie3": "#252B37",
    "borde":       "#2A303C",
    "borde_claro": "#39404F",
    "texto":       "#E8EBF1",
    "texto2":      "#98A1B3",
    "texto3":      "#6B7486",
    "acento":      "#22D3EE",
    "acento_alto": "#67E8F9",
    "acento_bajo": "#06B6D4",
    "exito":       "#22C55E",
    "error":       "#EF4444",
    "aviso":       "#F59E0B",
    "cian":        "#6366F1",
}


def hoja(flechas=None):
    flechas = flechas or {}
    fl_abajo = flechas.get("abajo", "")
    fl_arriba = flechas.get("arriba", "")
    img_abajo = f"image: url({fl_abajo});" if fl_abajo else "image: none;"
    img_arriba = f"image: url({fl_arriba});" if fl_arriba else "image: none;"
    return f"""
* {{
    font-family: "Segoe UI Variable", "Segoe UI", system-ui, sans-serif;
    outline: none;
}}
QWidget#raiz {{
    background: {C['fondo']};
}}
QWidget {{
    color: {C['texto']};
    font-size: 13px;
}}

/* ---------- cabecera ---------- */
QFrame#cabecera {{
    background: {C['superficie']};
    border-bottom: 1px solid {C['borde']};
}}
QLabel#marca {{
    font-size: 17px;
    font-weight: 700;
    letter-spacing: -0.3px;
}}
QLabel#lema {{
    color: {C['texto3']};
    font-size: 11px;
}}

/* ---------- campo de URL ---------- */
QLineEdit#url {{
    background: {C['superficie2']};
    border: 1px solid {C['borde']};
    border-radius: 11px;
    padding: 11px 14px;
    font-size: 14px;
    selection-background-color: {C['acento']};
}}
QLineEdit#url:focus {{
    border: 1px solid {C['acento']};
    background: {C['superficie3']};
}}
QLineEdit, QSpinBox, QComboBox {{
    background: {C['superficie2']};
    border: 1px solid {C['borde']};
    border-radius: 8px;
    padding: 7px 10px;
    selection-background-color: {C['acento']};
}}
QLineEdit:focus, QSpinBox:focus, QComboBox:focus {{
    border: 1px solid {C['acento']};
}}
QLineEdit:disabled, QComboBox:disabled, QSpinBox:disabled {{
    color: {C['texto3']};
    background: {C['superficie']};
}}
QComboBox::drop-down {{
    border: none;
    width: 22px;
}}
QComboBox::down-arrow {{
    {img_abajo}
    width: 18px;
    height: 18px;
    margin-right: 6px;
}}
QComboBox QAbstractItemView {{
    background: {C['superficie2']};
    border: 1px solid {C['borde_claro']};
    border-radius: 8px;
    padding: 4px;
    selection-background-color: {C['acento']};
    outline: none;
}}
QSpinBox::up-button {{
    subcontrol-origin: border;
    subcontrol-position: top right;
    width: 22px;
    height: 15px;
    background: transparent;
    border: none;
    border-top-right-radius: 8px;
    {img_arriba}
}}
QSpinBox::down-button {{
    subcontrol-origin: border;
    subcontrol-position: bottom right;
    width: 22px;
    height: 15px;
    background: transparent;
    border: none;
    border-bottom-right-radius: 8px;
    {img_abajo}
}}
QSpinBox::up-button:hover, QSpinBox::down-button:hover {{
    background: {C['superficie3']};
}}

/* ---------- botones ---------- */
QPushButton {{
    background: {C['superficie2']};
    border: 1px solid {C['borde']};
    border-radius: 9px;
    padding: 8px 14px;
    color: {C['texto']};
}}
QPushButton:hover {{
    background: {C['superficie3']};
    border-color: {C['borde_claro']};
}}
QPushButton:pressed {{
    background: {C['superficie']};
}}
QPushButton:disabled {{
    color: {C['texto3']};
    background: {C['superficie']};
    border-color: {C['borde']};
}}
QPushButton#principal {{
    background: {C['acento']};
    border: 1px solid {C['acento']};
    color: #04202A;
    font-weight: 600;
    padding: 11px 22px;
    border-radius: 11px;
    font-size: 14px;
}}
QPushButton#principal:hover {{
    background: {C['acento_alto']};
    border-color: {C['acento_alto']};
}}
QPushButton#principal:pressed {{
    background: {C['acento_bajo']};
}}
QPushButton#principal:disabled {{
    background: {C['superficie3']};
    border-color: {C['borde']};
    color: {C['texto3']};
}}
QPushButton#icono {{
    background: transparent;
    border: 1px solid transparent;
    border-radius: 8px;
    padding: 6px;
}}
QPushButton#icono:hover {{
    background: {C['superficie3']};
    border-color: {C['borde']};
}}
QPushButton#peligro:hover {{
    background: rgba(239, 68, 68, 0.16);
    border-color: {C['error']};
}}
QPushButton#enlace {{
    background: transparent;
    border: none;
    color: {C['acento_alto']};
    padding: 4px 6px;
    text-align: left;
}}
QPushButton#enlace:hover {{
    color: {C['texto']};
}}

/* ---------- pestanas ---------- */
QTabWidget::pane {{
    border: none;
    background: {C['fondo']};
}}
QTabBar {{
    qproperty-drawBase: 0;
}}
QTabBar::tab {{
    background: transparent;
    color: {C['texto2']};
    padding: 9px 18px;
    margin-right: 4px;
    border: none;
    border-bottom: 2px solid transparent;
    font-weight: 600;
}}
QTabBar::tab:hover {{
    color: {C['texto']};
}}
QTabBar::tab:selected {{
    color: {C['texto']};
    border-bottom: 2px solid {C['acento']};
}}

/* ---------- tarjetas ---------- */
QFrame#tarjeta {{
    background: {C['superficie']};
    border: 1px solid {C['borde']};
    border-radius: 14px;
}}
QFrame#tarjeta:hover {{
    border-color: {C['borde_claro']};
    background: {C['superficie2']};
}}
QLabel#titulo_tarjeta {{
    font-size: 13.5px;
    font-weight: 600;
}}
QLabel#meta {{
    color: {C['texto2']};
    font-size: 11.5px;
}}
QLabel#estado_err {{
    color: {C['error']};
    font-size: 11.5px;
}}
QLabel#estado_ok {{
    color: {C['exito']};
    font-size: 11.5px;
    font-weight: 600;
}}

/* ---------- paneles ---------- */
QFrame#panel {{
    background: {C['superficie']};
    border: 1px solid {C['borde']};
    border-radius: 14px;
}}
QLabel#seccion {{
    font-size: 12px;
    font-weight: 700;
    color: {C['texto2']};
    letter-spacing: 0.6px;
}}
QLabel#ayuda {{
    color: {C['texto3']};
    font-size: 11px;
}}
QFrame#separador {{
    background: {C['borde']};
    max-height: 1px;
    border: none;
}}

/* ---------- barra de progreso ---------- */
QProgressBar {{
    background: {C['superficie3']};
    border: none;
    border-radius: 4px;
    height: 7px;
    text-align: center;
    color: transparent;
}}
QProgressBar::chunk {{
    background: {C['acento']};
    border-radius: 4px;
}}

/* ---------- listas y tablas ---------- */
QScrollArea {{
    border: none;
    background: transparent;
}}
QScrollArea#lienzo, QScrollArea#lienzo > QWidget, QScrollArea#lienzo > QWidget > QWidget {{
    background: transparent;
    border: none;
}}
QScrollBar:vertical {{
    background: transparent;
    width: 11px;
    margin: 2px;
}}
QScrollBar::handle:vertical {{
    background: {C['superficie3']};
    border-radius: 5px;
    min-height: 40px;
}}
QScrollBar::handle:vertical:hover {{
    background: {C['borde_claro']};
}}
QScrollBar::add-line, QScrollBar::sub-line, QScrollBar::add-page, QScrollBar::sub-page {{
    height: 0;
    background: none;
    border: none;
}}
QScrollBar:horizontal {{
    background: transparent;
    height: 11px;
    margin: 2px;
}}
QScrollBar::handle:horizontal {{
    background: {C['superficie3']};
    border-radius: 5px;
    min-width: 40px;
}}
QTableWidget {{
    background: {C['superficie']};
    border: 1px solid {C['borde']};
    border-radius: 12px;
    gridline-color: transparent;
    selection-background-color: {C['superficie3']};
    selection-color: {C['texto']};
}}
QTableWidget::item {{
    padding: 9px 8px;
    border-bottom: 1px solid {C['borde']};
}}
QTableWidget::item:selected {{
    background: {C['superficie3']};
}}
QHeaderView::section {{
    background: {C['superficie2']};
    color: {C['texto2']};
    padding: 9px 8px;
    border: none;
    border-bottom: 1px solid {C['borde']};
    font-weight: 600;
    font-size: 11.5px;
}}
QHeaderView::section:first {{
    border-top-left-radius: 12px;
}}
QHeaderView::section:last {{
    border-top-right-radius: 12px;
}}
QTableCornerButton::section {{
    background: {C['superficie2']};
    border: none;
}}

/* ---------- casillas ---------- */
QCheckBox {{
    spacing: 9px;
    padding: 3px 0;
}}
QCheckBox::indicator {{
    width: 17px;
    height: 17px;
    border-radius: 5px;
    border: 1px solid {C['borde_claro']};
    background: {C['superficie2']};
}}
QCheckBox::indicator:hover {{
    border-color: {C['acento']};
}}
QCheckBox::indicator:checked {{
    background: {C['acento']};
    border-color: {C['acento']};
    image: none;
}}
QCheckBox:disabled {{
    color: {C['texto3']};
}}

/* ---------- barra lateral ---------- */
QFrame#lateral {{
    background: {C['superficie']};
    border-right: 1px solid {C['borde']};
}}
QPushButton#seccion_lateral {{
    background: transparent;
    border: none;
    border-left: 3px solid transparent;
    border-radius: 9px;
    padding: 11px 12px;
    text-align: left;
    color: {C['texto2']};
    font-size: 13.5px;
    font-weight: 600;
}}
QPushButton#seccion_lateral:hover {{
    background: {C['superficie2']};
    color: {C['texto']};
}}
QPushButton#seccion_lateral:checked {{
    background: {C['superficie3']};
    border-left: 3px solid {C['acento']};
    color: {C['texto']};
}}

/* ---------- biblioteca ---------- */
QFrame#tarjeta_album {{
    background: {C['superficie']};
    border: 1px solid {C['borde']};
    border-radius: 14px;
}}
QFrame#tarjeta_album:hover {{
    background: {C['superficie3']};
    border-color: {C['acento']};
}}
QPushButton#filtro {{
    background: transparent;
    border: 1px solid {C['borde']};
    border-radius: 14px;
    padding: 6px 16px;
    color: {C['texto2']};
    font-size: 12.5px;
    font-weight: 600;
}}
QPushButton#filtro:checked {{
    background: {C['acento']};
    border-color: {C['acento']};
    color: #04202A;
}}

/* ---------- reproductor ---------- */
QFrame#reproductor {{
    background: {C['superficie']};
    border-top: 1px solid {C['borde']};
}}
QPushButton#play {{
    background: {C['acento']};
    border: none;
    border-radius: 20px;
}}
QPushButton#play:hover {{
    background: {C['acento_alto']};
}}
QSlider::groove:horizontal {{
    height: 4px;
    background: {C['superficie3']};
    border-radius: 2px;
}}
QSlider::sub-page:horizontal {{
    background: {C['acento']};
    border-radius: 2px;
}}
QSlider::handle:horizontal {{
    background: {C['texto']};
    width: 11px;
    height: 11px;
    margin: -4px 0;
    border-radius: 5px;
}}

/* ---------- navegador ---------- */
QFrame#cabecera_nav {{
    background: {C['superficie']};
    border-bottom: 1px solid {C['borde']};
}}
QFrame#cabecera_nav QLineEdit {{
    border-radius: 16px;
    padding: 8px 16px;
    background: {C['superficie2']};
}}
QFrame#cabecera_nav QLineEdit:focus {{
    background: {C['superficie3']};
}}
QPushButton#acceso_web {{
    background: {C['superficie']};
    border: 1px solid {C['borde']};
    border-radius: 14px;
    padding: 16px 12px;
    color: {C['texto2']};
    font-size: 12.5px;
    font-weight: 600;
    text-align: center;
}}
QPushButton#acceso_web:hover {{
    background: {C['superficie2']};
    border-color: {C['acento']};
    color: {C['texto']};
}}
QFrame#barra_descarga {{
    background: {C['superficie2']};
    border-top: 1px solid {C['acento']};
}}

/* ---------- varios ---------- */
QToolTip {{
    background: {C['superficie3']};
    color: {C['texto']};
    border: 1px solid {C['borde_claro']};
    border-radius: 7px;
    padding: 6px 9px;
}}
QMenu {{
    background: {C['superficie2']};
    border: 1px solid {C['borde_claro']};
    border-radius: 9px;
    padding: 5px;
}}
QMenu::item {{
    padding: 8px 22px 8px 14px;
    border-radius: 6px;
}}
QMenu::item:selected {{
    background: {C['acento']};
}}
QMenu::separator {{
    height: 1px;
    background: {C['borde']};
    margin: 5px 8px;
}}
QFrame#barra_estado {{
    background: {C['superficie']};
    border-top: 1px solid {C['borde']};
}}
QLabel#estadistica {{
    color: {C['texto2']};
    font-size: 11.5px;
}}
"""
