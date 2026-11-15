extends Control
## Menú principal: muestra un mapa aleatorio de fondo y los botones Jugar, Cómo jugar y Salir.

@onready var mapa_fondo: GameMap = $MapaFondo


func _ready() -> void:
	# Conectar cada botón con la función que debe ejecutar al presionarlo.
	%BotonJugar.pressed.connect(_on_jugar)
	%BotonComoJugar.pressed.connect(_on_como_jugar)
	%BotonSalir.pressed.connect(_on_salir)
	_poner_mapa_de_fondo()
	Sonido.iniciar()


## Reutiliza el generador del juego para que el fondo sea distinto cada vez.
func _poner_mapa_de_fondo() -> void:
	var generado := GeneradorMapa.new().generar(randi())
	if generado.is_empty():
		return
	mapa_fondo.cargar_desde_texto(generado["lineas"])
	for u in generado["unidades"]:
		mapa_fondo.crear_unidad(u["tipo"], u["equipo"], u["celda"])
	var tamano := Vector2(mapa_fondo.ancho, mapa_fondo.alto) * Datos.TAM_CASILLA
	mapa_fondo.position = ((size - tamano) / 2.0).floor()


## "Jugar" abre el panel de nueva partida (dificultad y niebla).
func _on_jugar() -> void:
	if _panel_partida == null:
		_construir_panel_partida()
	_actualizar_opciones()
	_panel_partida.show()


func _empezar() -> void:
	Config.tutorial = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")


var _panel_partida: Control
var _boton_dificultad: Button
var _boton_niebla: Button
var _texto_dificultad: Label


func _construir_panel_partida() -> void:
	_panel_partida = ColorRect.new()
	_panel_partida.color = Color(0.05, 0.06, 0.1, 0.7)
	_panel_partida.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel_partida)
	var centro := CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel_partida.add_child(centro)
	var panel := PanelContainer.new()
	centro.add_child(panel)
	var lista := VBoxContainer.new()
	panel.add_child(lista)
	var titulo := Label.new()
	titulo.text = "Nueva partida"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", 16)
	lista.add_child(titulo)
	_boton_dificultad = _boton(lista, "", _cambiar_dificultad)
	_texto_dificultad = Label.new()
	_texto_dificultad.add_theme_font_size_override("font_size", 9)
	_texto_dificultad.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_texto_dificultad.custom_minimum_size = Vector2(220, 0)
	_texto_dificultad.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lista.add_child(_texto_dificultad)
	_boton_niebla = _boton(lista, "", _cambiar_niebla)
	_boton(lista, "¡Empezar!", _empezar)
	_boton(lista, "Volver", func(): _panel_partida.hide())


func _boton(padre: Control, texto: String, accion: Callable) -> Button:
	var b := Button.new()
	b.text = texto
	b.custom_minimum_size = Vector2(170, 24)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(accion)
	padre.add_child(b)
	return b


const ORDEN_DIFICULTAD := ["facil", "normal", "dificil"]
const EXPLICACION := {
	"facil": "La máquina gana menos dinero y a veces se equivoca.",
	"normal": "Un rival equilibrado.",
	"dificil": "Concentra el fuego, retira a sus heridos, usa habilidades y construye torretas.",
}


func _cambiar_dificultad() -> void:
	var i := ORDEN_DIFICULTAD.find(Config.dificultad)
	Config.dificultad = ORDEN_DIFICULTAD[(i + 1) % ORDEN_DIFICULTAD.size()]
	_actualizar_opciones()


func _cambiar_niebla() -> void:
	Config.niebla = not Config.niebla
	_actualizar_opciones()


func _actualizar_opciones() -> void:
	_boton_dificultad.text = "Dificultad: " + Datos.DIFICULTADES[Config.dificultad]["nombre"]
	_texto_dificultad.text = EXPLICACION[Config.dificultad]
	_boton_niebla.text = "Niebla de guerra: " + ("Sí" if Config.niebla else "No")


## "Cómo jugar" abre el tutorial interactivo (una partida guiada paso a paso).
func _on_como_jugar() -> void:
	Config.tutorial = true
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_salir() -> void:
	get_tree().quit()


## Botón "atrás" de Android: cierra la ayuda si está abierta; si no, sale del juego.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _panel_partida != null and _panel_partida.visible:
			_panel_partida.hide()
		else:
			_on_salir()
