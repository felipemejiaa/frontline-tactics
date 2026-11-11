class_name Resaltado
extends Node2D
## Dibuja las casillas resaltadas (a dónde se puede mover) y el cursor de selección.

const COLOR_MOVER := Color(0.25, 0.55, 1.0, 0.45)
const COLOR_ENEMIGO := Color(1.0, 0.25, 0.25, 0.4)
const TILE_CURSOR := Vector2i(7, 3)

var celdas: Array[Vector2i] = []
var color := COLOR_MOVER
var cursor := Vector2i(-1, -1)


func mostrar(lista: Array[Vector2i], nuevo_color: Color, celda_cursor: Vector2i) -> void:
	celdas = lista
	color = nuevo_color
	cursor = celda_cursor
	queue_redraw()


func limpiar() -> void:
	celdas = []
	cursor = Vector2i(-1, -1)
	queue_redraw()


func _draw() -> void:
	var t := Datos.TAM_CASILLA
	for c in celdas:
		draw_rect(Rect2(Vector2(c * t), Vector2(t, t)), color)
	if cursor.x >= 0:
		draw_texture_rect_region(Datos.ATLAS,
			Rect2(Vector2(cursor * t), Vector2(t, t)),
			Rect2(Vector2(TILE_CURSOR * t), Vector2(t, t)))
