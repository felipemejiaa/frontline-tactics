class_name Efectos
extends RefCounted
## Efectos visuales reutilizables: chispas y explosiones hechas con partículas.
## Se usan tanto en el mapa como en la cinemática de combate.


## Chispas pequeñas (impacto de un disparo).
static func chispas(padre: Node, pos: Vector2, cantidad := 10, tamano := 1.0,
		color := Color(1, 0.85, 0.3), subir := false) -> void:
	var p := _particulas(cantidad, 0.6 if subir else 0.35, tamano, color)
	p.position = pos
	if subir:  # brillitos que suben (curación)
		p.gravity = Vector2(0, -40 * tamano)
		p.spread = 50.0
	p.initial_velocity_min = 30 * tamano
	p.initial_velocity_max = 70 * tamano
	_lanzar(padre, p)


## Explosión: fuego naranja y humo gris.
static func explosion(padre: Node, pos: Vector2, tamano := 1.0) -> void:
	var fuego := _particulas(int(22 * tamano) + 6, 0.55, tamano * 1.6, Color(1, 0.55, 0.15))
	fuego.position = pos
	fuego.initial_velocity_min = 15 * tamano
	fuego.initial_velocity_max = 55 * tamano
	fuego.gravity = Vector2(0, -20 * tamano)
	_lanzar(padre, fuego)
	var humo := _particulas(int(12 * tamano) + 4, 0.9, tamano * 2.2, Color(0.45, 0.42, 0.4))
	humo.position = pos
	humo.initial_velocity_min = 5 * tamano
	humo.initial_velocity_max = 25 * tamano
	humo.gravity = Vector2(0, -35 * tamano)
	_lanzar(padre, humo)


## Onda que crece desde un punto (radar).
static func onda(padre: Node, pos: Vector2, radio: float, color: Color, duracion := 1.0) -> void:
	var o := Onda.new()
	o.position = pos
	o.color = color
	o.z_index = 22
	padre.add_child(o)
	var tw := o.create_tween()
	tw.tween_property(o, "radio", radio, duracion)
	tw.parallel().tween_property(o, "modulate:a", 0.0, duracion).set_ease(Tween.EASE_IN)
	tw.tween_callback(o.queue_free)


class Onda extends Node2D:
	var color := Color.GREEN
	var radio := 1.0:
		set(valor):
			radio = valor
			queue_redraw()

	func _draw() -> void:
		draw_arc(Vector2.ZERO, radio, 0, TAU, 48, color, 2.0)
		draw_arc(Vector2.ZERO, radio * 0.92, 0, TAU, 48, Color(color, 0.35), 1.0)


static func _particulas(cantidad: int, vida: float, tamano: float, color: Color) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = cantidad
	p.lifetime = vida
	p.explosiveness = 1.0
	p.direction = Vector2.UP
	p.spread = 180.0
	p.gravity = Vector2(0, 120 * tamano)
	p.scale_amount_min = tamano
	p.scale_amount_max = tamano * 2.0
	var rampa := Gradient.new()
	rampa.set_color(0, color)
	rampa.set_color(1, Color(color, 0.0))
	p.color_ramp = rampa
	p.z_index = 20
	return p


static func _lanzar(padre: Node, p: CPUParticles2D) -> void:
	padre.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
