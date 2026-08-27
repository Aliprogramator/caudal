# -*- coding: utf-8 -*-
"""Historial de descargas en SQLite."""

import sqlite3
import time
from pathlib import Path

from .config import carpeta_datos


class Historial:
    def __init__(self):
        self.archivo = carpeta_datos() / "historial.db"
        self.con = sqlite3.connect(str(self.archivo), check_same_thread=False)
        self.con.row_factory = sqlite3.Row
        self._crear()

    def _crear(self):
        self.con.execute(
            """CREATE TABLE IF NOT EXISTS descargas (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                url TEXT NOT NULL,
                titulo TEXT,
                plataforma TEXT,
                archivo TEXT,
                tamano INTEGER DEFAULT 0,
                duracion INTEGER DEFAULT 0,
                calidad TEXT,
                estado TEXT,
                fecha REAL,
                caratula TEXT,
                es_audio INTEGER DEFAULT 0,
                autor TEXT
            )"""
        )
        self._migrar()
        self.con.execute("CREATE INDEX IF NOT EXISTS idx_fecha ON descargas(fecha DESC)")
        self.con.execute(
            """CREATE TABLE IF NOT EXISTS listas (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                nombre TEXT NOT NULL,
                creada REAL
            )"""
        )
        self.con.execute(
            """CREATE TABLE IF NOT EXISTS lista_canciones (
                lista_id INTEGER NOT NULL,
                descarga_id INTEGER NOT NULL,
                orden INTEGER DEFAULT 0,
                PRIMARY KEY (lista_id, descarga_id)
            )"""
        )
        self.con.commit()

    def _migrar(self):
        """Anade las columnas nuevas a bases de datos de versiones anteriores."""
        cur = self.con.execute("PRAGMA table_info(descargas)")
        existentes = {f["name"] for f in cur.fetchall()}
        for columna, tipo in (("caratula", "TEXT"), ("es_audio", "INTEGER DEFAULT 0"),
                              ("autor", "TEXT")):
            if columna not in existentes:
                self.con.execute(f"ALTER TABLE descargas ADD COLUMN {columna} {tipo}")
        self.con.commit()

    def agregar(self, url, titulo, plataforma, archivo, tamano=0, duracion=0,
                calidad="", estado="completada", caratula="", es_audio=False, autor=""):
        cur = self.con.execute(
            "INSERT INTO descargas (url,titulo,plataforma,archivo,tamano,duracion,calidad,"
            "estado,fecha,caratula,es_audio,autor)"
            " VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
            (url, titulo, plataforma, archivo, int(tamano or 0), int(duracion or 0),
             calidad, estado, time.time(), caratula, 1 if es_audio else 0, autor),
        )
        self.con.commit()
        return cur.lastrowid

    def biblioteca(self, solo_audio=None, filtro=""):
        """Lo descargado que sigue existiendo, para la vista de biblioteca."""
        donde = ["estado = 'completada'", "archivo IS NOT NULL", "archivo != ''"]
        args = []
        if solo_audio is not None:
            donde.append("es_audio = ?")
            args.append(1 if solo_audio else 0)
        if filtro.strip():
            donde.append("(titulo LIKE ? OR autor LIKE ? OR plataforma LIKE ?)")
            patron = f"%{filtro.strip()}%"
            args += [patron, patron, patron]
        cur = self.con.execute(
            f"SELECT * FROM descargas WHERE {' AND '.join(donde)} ORDER BY fecha DESC",
            args)
        salida = []
        for f in cur.fetchall():
            fila = dict(f)
            if fila.get("archivo") and Path(fila["archivo"]).exists():
                salida.append(fila)
        return salida

    def listar(self, limite=500, filtro=""):
        if filtro:
            patron = f"%{filtro}%"
            cur = self.con.execute(
                "SELECT * FROM descargas WHERE titulo LIKE ? OR url LIKE ? OR plataforma LIKE ?"
                " ORDER BY fecha DESC LIMIT ?", (patron, patron, patron, limite))
        else:
            cur = self.con.execute("SELECT * FROM descargas ORDER BY fecha DESC LIMIT ?", (limite,))
        return [dict(f) for f in cur.fetchall()]

    def borrar(self, ident):
        self.con.execute("DELETE FROM descargas WHERE id=?", (ident,))
        self.con.commit()

    def vaciar(self):
        self.con.execute("DELETE FROM descargas")
        self.con.commit()

    # ------------------------------------------------------------ listas

    def crear_lista(self, nombre):
        nombre = (nombre or "").strip()
        if not nombre:
            raise ValueError("La lista necesita un nombre.")
        cur = self.con.execute("SELECT id FROM listas WHERE nombre = ?", (nombre,))
        if cur.fetchone():
            raise ValueError("Ya tienes una lista con ese nombre.")
        cur = self.con.execute(
            "INSERT INTO listas (nombre, creada) VALUES (?,?)", (nombre, time.time()))
        self.con.commit()
        return cur.lastrowid

    def borrar_lista(self, lista_id):
        self.con.execute("DELETE FROM lista_canciones WHERE lista_id = ?", (lista_id,))
        self.con.execute("DELETE FROM listas WHERE id = ?", (lista_id,))
        self.con.commit()

    def renombrar_lista(self, lista_id, nombre):
        nombre = (nombre or "").strip()
        if not nombre:
            raise ValueError("La lista necesita un nombre.")
        self.con.execute("UPDATE listas SET nombre = ? WHERE id = ?", (nombre, lista_id))
        self.con.commit()

    def listas(self, filtro=""):
        """Las listas con cuantas canciones tiene cada una."""
        sql = (
            "SELECT l.id, l.nombre, l.creada, COUNT(c.descarga_id) n "
            "FROM listas l LEFT JOIN lista_canciones c ON c.lista_id = l.id "
        )
        args = []
        if filtro.strip():
            sql += "WHERE l.nombre LIKE ? "
            args.append(f"%{filtro.strip()}%")
        sql += "GROUP BY l.id ORDER BY l.nombre COLLATE NOCASE"
        return [dict(f) for f in self.con.execute(sql, args).fetchall()]

    def agregar_a_lista(self, lista_id, descarga_id):
        cur = self.con.execute(
            "SELECT COALESCE(MAX(orden), 0) + 1 s FROM lista_canciones WHERE lista_id = ?",
            (lista_id,))
        orden = cur.fetchone()["s"]
        self.con.execute(
            "INSERT OR IGNORE INTO lista_canciones (lista_id, descarga_id, orden)"
            " VALUES (?,?,?)", (lista_id, descarga_id, orden))
        self.con.commit()

    def quitar_de_lista(self, lista_id, descarga_id):
        self.con.execute(
            "DELETE FROM lista_canciones WHERE lista_id = ? AND descarga_id = ?",
            (lista_id, descarga_id))
        self.con.commit()

    def canciones_de(self, lista_id, filtro=""):
        sql = (
            "SELECT d.* FROM lista_canciones c JOIN descargas d ON d.id = c.descarga_id "
            "WHERE c.lista_id = ? AND d.estado = 'completada' "
        )
        args = [lista_id]
        if filtro.strip():
            sql += "AND (d.titulo LIKE ? OR d.autor LIKE ?) "
            patron = f"%{filtro.strip()}%"
            args += [patron, patron]
        sql += "ORDER BY c.orden"
        salida = []
        for f in self.con.execute(sql, args).fetchall():
            fila = dict(f)
            if fila.get("archivo") and Path(fila["archivo"]).exists():
                salida.append(fila)
        return salida

    def listas_de_cancion(self, descarga_id):
        cur = self.con.execute(
            "SELECT lista_id FROM lista_canciones WHERE descarga_id = ?", (descarga_id,))
        return {f["lista_id"] for f in cur.fetchall()}

    def estadisticas(self):
        cur = self.con.execute(
            "SELECT COUNT(*) n, COALESCE(SUM(tamano),0) bytes FROM descargas WHERE estado='completada'")
        f = cur.fetchone()
        return {"total": f["n"], "bytes": f["bytes"]}

    def ya_descargado(self, url):
        cur = self.con.execute(
            "SELECT archivo FROM descargas WHERE url=? AND estado='completada' ORDER BY fecha DESC LIMIT 1",
            (url,))
        f = cur.fetchone()
        if f and f["archivo"] and Path(f["archivo"]).exists():
            return f["archivo"]
        return None
