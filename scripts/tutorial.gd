class_name Tutorial
extends CanvasLayer
## Tutorial interactivo: una partida pequeña guiada paso a paso.
## Arriba sale un letrero con la instrucción y una flecha que salta señala dónde tocar.
## Avanza solo cuando el jugador hace lo que se le pide (escucha la señal "evento" de main.gd).
## En el tutorial el ejército rojo no se mueve, para aprender con calma.

## Mapa del tutorial (leyenda en game_map.gd).
const MAPA := [
	"............",
	"..c......b..",
	"H.....m....h",
	"............",
	"F..b.......f",
	"......m..c..",
	"..b.........",
	"............",
]
const CIUDAD := Vector2i(2, 1)
const POS_TANQUE := Vector2i(2, 3)
const POS_INFANTERIA := Vector2i(2, 4)
const POS_ENEMIGO := Vector2i(6, 3)

var main: Node
var paso := 0
var _tanque: Unidad
var _infanteria: Unidad
var _panel: PanelContainer
var _texto: Label
var _contador: Label
var _botones: HBoxContainer
var _flecha: Label
var _flecha_en_mapa := Vector2i(-1, -1)
var _flecha_en_boton := ""

## Cada paso: [texto, a dónde apunta la flecha ("unidad:tanque", "celda", "boton:Nombre" o "")]
var PASOS := [
	["¡Bienvenido! Tú eres el ejército AZUL. Lo que brilla es lo que todavía puedes usar. Toca tu TANQUE.", "tanque"],
	["Lo azul es a dónde se puede mover. El enemigo con borde rojo se puede atacar, y el número es el daño que le harás. ¡Tócalo!", "enemigo"],
	["¡Buen golpe! Ahora toca tu INFANTERÍA y llévala a la ciudad gris (la de la flecha).", "ciudad"],
	["Solo la infantería captura edificios. Toca «Capturar» en el menú.", ""],
	["Capturar una ciudad tarda 2 turnos. Las ciudades dan dinero, curan y protegen a quien esté adentro. Ahora abre la TIENDA.", "boton:BotonTienda"],
	["Toca una unidad para ver su ficha (contra quién es fuerte y cuánto daño hace) y luego «Comprar».", ""],
	["La unidad nueva aparece en tu base y actúa en el próximo turno. Toca TERMINAR TURNO.", "boton:BotonTerminar"],
	["En el tutorial el rojo se queda quieto. Termina la captura: toca tu infantería, tócala otra vez y elige «Capturar».", "infanteria"],
	["¡Ciudad tuya! Para GANAR: captura (3 turnos) o destruye (unos 6 golpes) el CENTRO URBANO enemigo, el de la estrella dorada, o acaba con su ejército. Mantén presionada una unidad para ver su ficha completa.", "centro"],
]


func preparar(main_ref: Node) -> void:
	main = main_ref
	layer = 6
	var mapa: GameMap = main.mapa
	mapa.cargar_desde_texto(MAPA)
	_tanque = mapa.crear_unidad("tanque", "azul", POS_TANQUE)
	_infanteria = mapa.crear_unidad("infanteria", "azul", POS_INFANTERIA)
	mapa.crear_unidad("artilleria", "azul", Vector2i(0, 5))
	mapa.crear_unidad("infanteria", "rojo", POS_ENEMIGO)
	mapa.crear_unidad("tanque", "rojo", Vector2i(10, 3))
	mapa.crear_unidad("artilleria", "rojo", Vector2i(11, 5))
	_construir()
	main.alto_barra = 128.0  # el mapa queda debajo del letrero del tutorial
	main.evento.connect(_on_evento)
	main._empezar_partida()
	_mostrar_paso()


func _construir() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.position = Vector2(40, 33)
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 2)
	_panel.add_child(caja)
	_contador = Label.new()
	_contador.add_theme_font_size_override("font_size", 8)
	_contador.modulate = Color(0.75, 0.85, 1)
	caja.add_child(_contador)
	_texto = Label.new()
	_texto.custom_minimum_size = Vector2(380, 0)
	_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_texto.add_theme_font_size_override("font_size", 10)
	caja.add_child(_texto)
	_botones = HBoxContainer.new()
	_botones.alignment = BoxContainer.ALIGNMENT_END
	caja.add_child(_botones)
	add_child(_panel)
	_flecha = Label.new()
	_flecha.text = "▼"
	_flecha.add_theme_font_size_override("font_size", 16)
	_flecha.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	_flecha.add_theme_color_override("font_outline_color", Color.BLACK)
	_flecha.add_theme_constant_override("outline_size", 5)
	_flecha.z_index = 30
	_flecha.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _mostrar_paso() -> void:
	_contador.text = "TUTORIAL · Paso %d de %d" % [paso + 1, PASOS.size()]
	_texto.text = PASOS[paso][0]
	for b in _botones.get_children():
		b.queue_free()
	if paso == PASOS.size() - 1:
		_boton("Jugar una partida", func():
			Config.tutorial = false
			main.get_tree().change_scene_to_file("res://scenes/main.tscn"))
		_boton("Menú principal", func():
			Config.tutorial = false
			main.get_tree().change_scene_to_file("res://scenes/menu_principal.tscn"))
	else:
		_boton("Saltar tutorial", func():
			Config.tutorial = false
			main.get_tree().change_scene_to_file("res://scenes/menu_principal.tscn"))
	_panel.reset_size()
	_apuntar_flecha(PASOS[paso][1])
	Sonido.reproducir("seleccion", -6.0)


func _boton(texto: String, accion: Callable) -> void:
	var b := Button.new()
	b.text = texto
	b.add_theme_font_size_override("font_size", 9)
	b.pressed.connect(accion)
	_botones.add_child(b)


func _apuntar_flecha(destino: String) -> void:
	if _flecha.get_parent():
		_flecha.get_parent().remove_child(_flecha)
	_flecha_en_mapa = Vector2i(-1, -1)
	_flecha_en_boton = ""
	var mapa: GameMap = main.mapa
	match destino:
		"tanque":
			_flecha_en_mapa = _tanque.celda if is_instance_valid(_tanque) else Vector2i(-1, -1)
		"infanteria":
			_flecha_en_mapa = _infanteria.celda if is_instance_valid(_infanteria) else Vector2i(-1, -1)
		"enemigo":
			var e := mapa.unidad_en(POS_ENEMIGO)
			_flecha_en_mapa = POS_ENEMIGO if e != null else Vector2i(-1, -1)
		"ciudad":
			_flecha_en_mapa = CIUDAD
		"centro":
			_flecha_en_mapa = mapa.buscar_edificio("cuartel", "rojo")
		_:
			if destino.begins_with("boton:"):
				_flecha_en_boton = destino.substr(6)
	if mapa.en_mapa(_flecha_en_mapa):
		mapa.add_child(_flecha)
	elif _flecha_en_boton != "":
		main.hud.add_child(_flecha)


func _process(_delta: float) -> void:
	if not is_instance_valid(_flecha) or _flecha.get_parent() == null:
		return
	var salto := absf(sin(Time.get_ticks_msec() / 180.0)) * 4.0
	if main.mapa.en_mapa(_flecha_en_mapa):
		_flecha.position = main.mapa.celda_a_pos(_flecha_en_mapa) + Vector2(-6, -40 - salto)
	elif _flecha_en_boton != "":
		var b: Control = main.hud.get_node("%" + _flecha_en_boton)
		_flecha.position = b.position + Vector2(b.size.x / 2.0 - 6, b.size.y + 2 + salto)
		_flecha.rotation = PI
		_flecha.pivot_offset = Vector2(6, 10)
	if _flecha_en_boton == "":
		_flecha.rotation = 0.0


## Avanza cuando el jugador hace lo que pide el paso actual.
func _on_evento(nombre: String, dato) -> void:
	var siguiente := false
	match paso:
		0:
			siguiente = nombre == "seleccion" and dato == _tanque
		1:
			siguiente = (nombre == "ataque" and dato == _tanque) or (nombre == "usada" and dato == _tanque)
		2:
			siguiente = nombre == "movida" and dato == _infanteria and _infanteria.celda == CIUDAD
		3:
			siguiente = nombre == "captura" and dato == _infanteria
		4:
			siguiente = nombre == "tienda"
		5:
			siguiente = nombre == "compra"
		6:
			siguiente = nombre == "turno_azul"
		7:
			siguiente = nombre == "capturada" and dato == "azul"
	if nombre == "movida" and paso == 2 and dato == _infanteria and _infanteria.celda != CIUDAD:
		_texto.text = "Casi: tiene que quedar justo encima de la ciudad gris. Puedes intentarlo en el próximo turno."
	if siguiente:
		paso += 1
		_mostrar_paso()


## En el tutorial el rojo no juega.
func ia_quieta() -> bool:
	return true
