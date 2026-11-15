class_name Unidad
extends Sprite2D
## Una unidad del juego. Guarda su estado y sabe animarse al moverse.

const MAX_RANGO := 3

var tipo := "infanteria"   # ver Datos.UNIDADES
var equipo := "azul"       # "azul" (jugador) o "rojo" (máquina)
var celda := Vector2i.ZERO
var vida := 10:
	set(valor):
		vida = valor
		queue_redraw()  # para actualizar el número de vida
var ya_se_movio := false
var ya_ataco := false
## Veteranía: sube 1 cada vez que destruye una unidad enemiga (máximo 3). Cada rango pega +10 %.
var rango := 0:
	set(valor):
		rango = clampi(valor, 0, MAX_RANGO)
		queue_redraw()
## Movimiento extra de este turno (habilidad Marcha forzada).
var bono_mov := 0
## Halo que late: "con esta unidad todavía puedes hacer algo".
var halo := false:
	set(valor):
		if halo != valor:
			halo = valor
			queue_redraw()


func _ready() -> void:
	var datos: Dictionary = Datos.UNIDADES[tipo]
	vida = datos["vida_max"]
	texture = Datos.ATLAS
	region_enabled = true
	var t := Datos.TAM_CASILLA
	region_rect = Rect2(Vector2(Datos.tile_unidad(tipo, equipo) * t), Vector2(t, t))
	flip_h = equipo == "rojo" and not datos.get("construccion", false)  # los rojos miran a la izquierda


func datos() -> Dictionary:
	return Datos.UNIDADES[tipo]


func movimiento() -> int:
	return datos()["movimiento"] + bono_mov if datos()["movimiento"] > 0 else 0


func es_aerea() -> bool:
	return datos().get("aerea", false)


func nombre_con_rango() -> String:
	return datos()["nombre"] + (" " + "★".repeat(rango) if rango > 0 else "")


## Anima la unidad pasando por cada punto. Usar con: await unidad.recorrer(puntos)
func recorrer(puntos: Array[Vector2]) -> void:
	if puntos.is_empty():
		return
	var tween := create_tween()
	for p in puntos:
		tween.tween_callback(Sonido.reproducir.bind("paso", -6.0))
		tween.tween_property(self, "position", p, 0.08)
	await tween.finished


## Dibuja la vida (como en Advanced Wars) solo cuando la unidad está herida,
## y unas rayitas doradas arriba según su veteranía.
func _process(_delta: float) -> void:
	if halo:
		queue_redraw()


func _draw() -> void:
	var t := Datos.TAM_CASILLA
	if halo:
		var latido := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 220.0)
		draw_rect(Rect2(-8, -8, 16, 16).grow(0.5 + latido), Color(1, 1, 0.75, 0.35 + 0.55 * latido), false, 1.0)
	if vida > 0 and vida < datos()["vida_max"]:
		# Los números 0-9 están en la fila 10 de la hoja de gráficos de Kenney.
		draw_texture_rect_region(Datos.ATLAS, Rect2(0, 0, 9, 9), Rect2(vida * t, 10 * t, t, t))
	for i in rango:
		var x := -7.0 + i * 3.0
		draw_rect(Rect2(x - 0.5, -8.5, 3, 3), Color.BLACK)
		draw_rect(Rect2(x, -8, 2, 2), Color(1, 0.85, 0.2))


## Parpadeo de un color (rojo al recibir un golpe, verde al curarse).
func destello(color := Color(1, 0.3, 0.3)) -> void:
	var tween := create_tween()
	for i in 2:
		tween.tween_property(self, "self_modulate", color, 0.08)
		tween.tween_property(self, "self_modulate", Color.WHITE, 0.08)


## Gris = ya actuó este turno.
func marcar_usada(usada: bool) -> void:
	modulate = Color(0.5, 0.5, 0.5) if usada else Color.WHITE


func reiniciar_turno() -> void:
	ya_se_movio = false
	ya_ataco = false
	bono_mov = 0
	marcar_usada(false)
