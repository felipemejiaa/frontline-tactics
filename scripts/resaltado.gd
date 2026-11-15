class_name Resaltado
extends Node2D
## Dibuja las casillas resaltadas (a dónde se puede mover) y el cursor de selección.

const COLOR_MOVER := Color(0.25, 0.55, 1.0, 0.45)
const COLOR_ENEMIGO := Color(1.0, 0.25, 0.25, 0.4)
## Unidades enemigas: naranja = a dónde se mueve, rojo = hasta dónde puede atacar.
const COLOR_MOV_ENEMIGO := Color(1.0, 0.65, 0.2, 0.38)
const COLOR_ZONA_ATAQUE := Color(1.0, 0.15, 0.15, 0.32)
const TILE_CURSOR := Vector2i(7, 3)

var celdas: Array[Vector2i] = []
var color := COLOR_MOVER
var cursor := Vector2i(-1, -1)
## Casillas de enemigos que se pueden atacar (se marcan con un borde rojo).
var ataque: Array[Vector2i] = []
## Numerito sobre cada enemigo atacable con el daño que le harías: celda -> texto.
var etiquetas := {}
## Casillas que una unidad enemiga puede atacar pero a las que no se puede mover.
var zona_ataque: Array[Vector2i] = []


func mostrar(lista: Array[Vector2i], nuevo_color: Color, celda_cursor: Vector2i,
		lista_ataque: Array[Vector2i] = []) -> void:
	celdas = lista
	color = nuevo_color
	cursor = celda_cursor
	ataque = lista_ataque
	queue_redraw()


func limpiar() -> void:
	celdas = []
	ataque = []
	etiquetas = {}
	zona_ataque = []
	cursor = Vector2i(-1, -1)
	queue_redraw()


func _draw() -> void:
	var t := Datos.TAM_CASILLA
	for c in celdas:
		draw_rect(Rect2(Vector2(c * t), Vector2(t, t)), color)
	for c in zona_ataque:
		var r := Rect2(Vector2(c * t), Vector2(t, t))
		draw_rect(r, COLOR_ZONA_ATAQUE)
		draw_rect(r.grow(-1.0), Color(1, 0.2, 0.2, 0.6), false, 1.0)
	for c in ataque:
		var r := Rect2(Vector2(c * t), Vector2(t, t))
		draw_rect(r, Color(1, 0.2, 0.2, 0.35))
		draw_rect(r.grow(-0.5), Color(1, 0.25, 0.25), false, 1.0)
	var fuente := ThemeDB.fallback_font
	for c in etiquetas:
		var texto: String = etiquetas[c]
		var ancho := fuente.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		var pos := Vector2(c * t) + Vector2((t - ancho) / 2.0, -2)
		draw_string_outline(fuente, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, 4, Color.BLACK)
		draw_string(fuente, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 0.85, 0.3))
	if cursor.x >= 0:
		draw_texture_rect_region(Datos.ATLAS,
			Rect2(Vector2(cursor * t), Vector2(t, t)),
			Rect2(Vector2(TILE_CURSOR * t), Vector2(t, t)))
