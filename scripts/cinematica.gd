class_name Cinematica
extends CanvasLayer
## Mini cinemática de combate, estilo Advanced Wars.
## La pantalla se divide en dos: el azul a la izquierda y el rojo a la derecha.
## Cada unidad se ve como un grupo de soldados o vehículos (más vida = más figuras).
## El que ataca dispara, al otro le baja la vida y pierde figuras; si sobrevive, contraataca.
## Tocar la pantalla la salta.
##
## Uso:  var cine := Cinematica.new(); add_child(cine)
##       await cine.reproducir(info_azul, info_rojo, eventos)

## Se puede apagar desde el menú de pausa.
static var activadas := true

const ESCALA := 2.5
const ALTO_PANEL := 200.0
const ANCHO_PANEL := 237.0
const Y_PANEL := 35.0
const Y_SUELO := 150.0
## Posiciones de las figuras (lado izquierdo; el derecho es su espejo).
const FORMACION := [Vector2(190, 156), Vector2(165, 130), Vector2(135, 156), Vector2(110, 130), Vector2(80, 156)]

var saltando := false
var _raiz: Control
var _lados := {}


## info: {tipo, equipo, vida, terreno, adorno}
## eventos: [{lado: "izq"/"der" (quién dispara), dano, vida_final}]
func reproducir(info_azul: Dictionary, info_rojo: Dictionary, eventos: Array) -> void:
	layer = 10
	_construir()
	_armar_lado("izq", info_azul)
	_armar_lado("der", info_rojo)

	_raiz.modulate.a = 0.0
	_raiz.create_tween().tween_property(_raiz, "modulate:a", 1.0, 0.2)
	await _pausa(0.35)
	for ev in eventos:
		await _disparar(ev["lado"], ev["dano"], ev["vida_final"])
		await _pausa(0.2)
	await _pausa(0.4)
	_raiz.create_tween().tween_property(_raiz, "modulate:a", 0.0, 0.2)
	await _pausa(0.2)
	queue_free()


func _pausa(segundos: float) -> void:
	if saltando:
		return
	await get_tree().create_timer(segundos).timeout


# ---------------------------------------------------------------- armado de la escena

func _construir() -> void:
	_raiz = Control.new()
	_raiz.size = Vector2(480, 270)
	_raiz.mouse_filter = Control.MOUSE_FILTER_STOP
	_raiz.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			saltando = true)
	add_child(_raiz)
	var fondo := ColorRect.new()
	fondo.color = Color(0.03, 0.03, 0.06, 0.92)
	fondo.size = _raiz.size
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.add_child(fondo)
	var aviso := Label.new()
	aviso.text = "Toca para saltar"
	aviso.add_theme_font_size_override("font_size", 9)
	aviso.modulate = Color(1, 1, 1, 0.6)
	aviso.position = Vector2(206, 252)
	_raiz.add_child(aviso)


func _armar_lado(lado: String, info: Dictionary) -> void:
	var izq := lado == "izq"
	var panel := Control.new()
	panel.clip_contents = true
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(2 if izq else 241, Y_PANEL)
	panel.size = Vector2(ANCHO_PANEL, ALTO_PANEL)
	_raiz.add_child(panel)

	var cielo := ColorRect.new()
	cielo.color = Color(0.45, 0.62, 0.9) if izq else Color(0.9, 0.55, 0.5)
	cielo.size = panel.size
	cielo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(cielo)

	var suelo := Suelo.new()
	suelo.tile = Datos.TERRENOS[info["terreno"]]["tile"]
	suelo.scale = Vector2.ONE * ESCALA
	suelo.position = Vector2(0, Y_SUELO)
	panel.add_child(suelo)

	# Adorno del terreno al fondo (árboles, rocas o el edificio), para dar contexto.
	if info["adorno"].x >= 0:
		var deco := _sprite(info["adorno"], not izq)
		deco.position = Vector2(32.0 if izq else ANCHO_PANEL - 32.0, Y_SUELO - 22)
		deco.scale = Vector2.ONE * 3.0
		deco.modulate = Color(0.75, 0.75, 0.8)
		panel.add_child(deco)

	var figuras: Array[Sprite2D] = []
	var tile := Datos.tile_unidad(info["tipo"], info["equipo"])
	var en_el_aire: bool = Datos.UNIDADES[info["tipo"]].get("aerea", false)
	for i in _cantidad_figuras(info["vida"]):
		var s := _sprite(tile, not izq and not Datos.UNIDADES[info["tipo"]].get("construccion", false))
		var p: Vector2 = FORMACION[i]
		s.position = Vector2(p.x if izq else ANCHO_PANEL - p.x, p.y - (45.0 if en_el_aire else 0.0))
		panel.add_child(s)
		figuras.append(s)

	var barra_fondo := ColorRect.new()
	barra_fondo.color = Color(0, 0, 0, 0.6)
	barra_fondo.position = Vector2(8, 26)
	barra_fondo.size = Vector2(124, 10)
	panel.add_child(barra_fondo)
	var barra := ColorRect.new()
	barra.position = Vector2(10, 28)
	barra.size = Vector2(12.0 * info["vida"], 6)
	barra.color = _color_vida(info["vida"])
	panel.add_child(barra)
	var nombre := Label.new()
	nombre.text = info.get("nombre", Datos.UNIDADES[info["tipo"]]["nombre"])
	nombre.position = Vector2(8, 4)
	nombre.add_theme_font_size_override("font_size", 13)
	nombre.add_theme_color_override("font_outline_color", Color.BLACK)
	nombre.add_theme_constant_override("outline_size", 4)
	panel.add_child(nombre)
	var numero := Label.new()
	numero.text = str(info["vida"])
	numero.position = Vector2(138, 19)
	numero.add_theme_font_size_override("font_size", 13)
	numero.add_theme_color_override("font_outline_color", Color.BLACK)
	numero.add_theme_constant_override("outline_size", 4)
	panel.add_child(numero)

	_lados[lado] = {"panel": panel, "figuras": figuras, "barra": barra, "numero": numero,
		"vida": info["vida"], "tipo": info["tipo"]}


func _sprite(tile: Vector2i, mirar_izquierda: bool) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = Datos.ATLAS
	s.region_enabled = true
	s.region_rect = Rect2(Vector2(tile * Datos.TAM_CASILLA), Vector2.ONE * Datos.TAM_CASILLA)
	s.scale = Vector2.ONE * ESCALA
	s.flip_h = mirar_izquierda
	return s


static func _cantidad_figuras(vida: int) -> int:
	return clampi(ceili(vida / 2.0), 0, 5)


static func _color_vida(vida: int) -> Color:
	if vida > 6:
		return Color(0.35, 0.9, 0.4)
	if vida > 3:
		return Color(1, 0.8, 0.25)
	return Color(1, 0.3, 0.25)


# ---------------------------------------------------------------- el combate

func _disparar(lado: String, dano: int, vida_final: int) -> void:
	var tirador: Dictionary = _lados[lado]
	var blanco: Dictionary = _lados["der" if lado == "izq" else "izq"]
	var hacia := 1.0 if lado == "izq" else -1.0
	var es_canon: bool = tirador["tipo"] != "infanteria"

	# 1. Los atacantes retroceden por el disparo y sale un fogonazo.
	Sonido.reproducir("canon" if es_canon else "disparo")
	for f in tirador["figuras"]:
		var origen: Vector2 = f.position
		var tw: Tween = f.create_tween()
		tw.tween_property(f, "position:x", origen.x - 5 * hacia, 0.05)
		tw.tween_property(f, "position:x", origen.x, 0.12)
		Efectos.chispas(tirador["panel"], origen + Vector2(22 * hacia, -4), 6, 1.5, Color(1, 0.95, 0.6))

	# 2. Las balas cruzan la pantalla.
	var objetivos: Array = blanco["figuras"]
	for f in tirador["figuras"]:
		if objetivos.is_empty():
			break
		var bala := ColorRect.new()
		bala.color = Color(1, 0.9, 0.4)
		bala.size = Vector2(7, 4) if es_canon else Vector2(5, 2)
		bala.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var desde: Vector2 = tirador["panel"].position + f.position + Vector2(20 * hacia, -4)
		var destino_fig: Sprite2D = objetivos[randi() % objetivos.size()]
		var hasta: Vector2 = blanco["panel"].position + destino_fig.position
		bala.position = desde
		_raiz.add_child(bala)
		var tw: Tween = bala.create_tween()
		tw.tween_property(bala, "position", hasta, 0.28 if es_canon else 0.2).set_delay(randf() * 0.08)
		tw.tween_callback(bala.queue_free)
	await _pausa(0.32)

	# 3. Impacto: chispas, temblor, baja la barra de vida y caen figuras.
	Sonido.reproducir("golpe")
	for f in blanco["figuras"]:
		Efectos.chispas(blanco["panel"], f.position + Vector2(randf_range(-8, 8), randf_range(-8, 4)), 8, 1.5)
		var origen: Vector2 = f.position
		var tw: Tween = f.create_tween()
		tw.tween_property(f, "position:x", origen.x + 3, 0.04)
		tw.tween_property(f, "position:x", origen.x - 3, 0.04)
		tw.tween_property(f, "position:x", origen.x, 0.04)
	_numero_dano(blanco, dano)
	var vida_nueva := maxi(0, vida_final)
	blanco["barra"].create_tween().tween_property(blanco["barra"], "size:x", 12.0 * vida_nueva, 0.35)
	blanco["barra"].color = _color_vida(vida_nueva)
	blanco["numero"].text = str(vida_nueva)
	blanco["vida"] = vida_nueva

	var quedan := _cantidad_figuras(vida_nueva)
	var figuras: Array[Sprite2D] = blanco["figuras"]
	if quedan < figuras.size():
		Sonido.reproducir("explosion", -3.0 if quedan > 0 else 0.0)
	while figuras.size() > quedan:
		var caida: Sprite2D = figuras.pop_back()
		Efectos.explosion(blanco["panel"], caida.position, 2.5)
		caida.create_tween().tween_property(caida, "modulate:a", 0.0, 0.25)
	await _pausa(0.35)


func _numero_dano(lado: Dictionary, dano: int) -> void:
	var etiqueta := Label.new()
	etiqueta.text = "-%d" % dano
	etiqueta.add_theme_font_size_override("font_size", 22)
	etiqueta.add_theme_color_override("font_color", Color(1, 0.35, 0.3))
	etiqueta.add_theme_color_override("font_outline_color", Color.BLACK)
	etiqueta.add_theme_constant_override("outline_size", 6)
	etiqueta.position = Vector2(ANCHO_PANEL / 2.0 - 15, 60)
	lado["panel"].add_child(etiqueta)
	var tw: Tween = etiqueta.create_tween()
	tw.tween_property(etiqueta, "position:y", 40.0, 0.6)
	tw.parallel().tween_property(etiqueta, "modulate:a", 0.0, 0.6).set_delay(0.3)
	tw.tween_callback(etiqueta.queue_free)


## Dibuja el suelo repitiendo una casilla del terreno.
class Suelo extends Node2D:
	var tile := Vector2i(1, 0)

	func _draw() -> void:
		var t := Datos.TAM_CASILLA
		for x in 6:
			for y in 2:
				draw_texture_rect_region(Datos.ATLAS, Rect2(x * t, y * t, t, t),
					Rect2(Vector2(tile * t), Vector2(t, t)))
