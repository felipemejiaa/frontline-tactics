class_name Unidad
extends Sprite2D
## Una unidad del juego. Guarda su estado y sabe animarse al moverse.

var tipo := "infanteria"   # "infanteria", "tanque" o "artilleria"
var equipo := "azul"       # "azul" (jugador) o "rojo" (máquina)
var celda := Vector2i.ZERO
var vida := 10:
	set(valor):
		vida = valor
		queue_redraw()  # para actualizar el número de vida
var ya_se_movio := false
var ya_ataco := false


func _ready() -> void:
	var datos: Dictionary = Datos.UNIDADES[tipo]
	vida = datos["vida_max"]
	texture = Datos.ATLAS
	region_enabled = true
	var t := Datos.TAM_CASILLA
	region_rect = Rect2(datos["columna"] * t, Datos.FILA_EQUIPO[equipo] * t, t, t)
	flip_h = equipo == "rojo"  # que los rojos miren hacia la izquierda


func datos() -> Dictionary:
	return Datos.UNIDADES[tipo]


## Anima la unidad pasando por cada punto. Usar con: await unidad.recorrer(puntos)
func recorrer(puntos: Array[Vector2]) -> void:
	if puntos.is_empty():
		return
	var tween := create_tween()
	for p in puntos:
		tween.tween_callback(Sonido.reproducir.bind("paso", -6.0))
		tween.tween_property(self, "position", p, 0.08)
	await tween.finished


## Dibuja la vida (como en Advanced Wars) solo cuando la unidad está herida.
func _draw() -> void:
	if vida <= 0 or vida >= datos()["vida_max"]:
		return
	# Los números 0-9 están en la fila 10 de la hoja de gráficos de Kenney.
	var t := Datos.TAM_CASILLA
	draw_texture_rect_region(Datos.ATLAS, Rect2(0, 0, 9, 9), Rect2(vida * t, 10 * t, t, t))


## Parpadeo en rojo al recibir un golpe.
func destello() -> void:
	var tween := create_tween()
	tween.tween_property(self, "self_modulate", Color(1, 0.3, 0.3), 0.08)
	tween.tween_property(self, "self_modulate", Color.WHITE, 0.08)
	tween.tween_property(self, "self_modulate", Color(1, 0.3, 0.3), 0.08)
	tween.tween_property(self, "self_modulate", Color.WHITE, 0.08)


## Gris = ya actuó este turno.
func marcar_usada(usada: bool) -> void:
	modulate = Color(0.5, 0.5, 0.5) if usada else Color.WHITE


func reiniciar_turno() -> void:
	ya_se_movio = false
	ya_ataco = false
	marcar_usada(false)
