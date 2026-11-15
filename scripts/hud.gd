class_name HUD
extends CanvasLayer
## Interfaz dentro de la partida: barra de arriba, menú de pausa y pantalla de fin.
## No sabe nada de las reglas del juego: solo muestra cosas y avisa con señales
## cuando el jugador presiona un botón. main.gd escucha esas señales.

signal terminar_turno_pedido
signal nuevo_mapa_pedido
signal tienda_pedida
signal truco_dinero  # 5 toques seguidos en el texto del dinero

const ESCENA_MENU := "res://scenes/menu_principal.tscn"


## Explicación de cada botón de arriba (se ve manteniéndolo presionado).
const AYUDAS := {
	"BotonTienda": "Comprar unidades y habilidades",
	"BotonMenu": "Pausa y opciones",
	"BotonTerminar": "Pasar el turno a la máquina",
}
const TIEMPO_AYUDA := 0.45

var _ayuda: PanelContainer
var _boton_presionado: Button
var _tiempo_boton := 0.0
var _ayuda_mostrada := false
var _tween_terminar: Tween


var _toques_truco: Array[float] = []


func _ready() -> void:
	# Truco secreto: 5 toques rápidos en el texto de arriba a la izquierda.
	var etiqueta: Label = %EtiquetaTurno
	etiqueta.mouse_filter = Control.MOUSE_FILTER_STOP
	etiqueta.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			var ahora := Time.get_ticks_msec() / 1000.0
			_toques_truco.append(ahora)
			_toques_truco = _toques_truco.filter(func(t): return ahora - t < 2.5)
			if _toques_truco.size() >= 5:
				_toques_truco.clear()
				truco_dinero.emit())
	# Mantener presionado un botón muestra su explicación (y no lo activa).
	for nombre in AYUDAS:
		var b: Button = get_node("%" + nombre)
		b.tooltip_text = AYUDAS[nombre]
		b.button_down.connect(func():
			_boton_presionado = b
			_tiempo_boton = 0.0
			_ayuda_mostrada = false)
		b.button_up.connect(func(): _boton_presionado = null)
	%BotonTerminar.pressed.connect(func(): if not _ayuda_mostrada: terminar_turno_pedido.emit())
	%BotonMenu.pressed.connect(func(): if not _ayuda_mostrada: abrir_pausa())
	%BotonTienda.pressed.connect(func(): if not _ayuda_mostrada: tienda_pedida.emit())
	%BotonCinematicas.pressed.connect(_alternar_cinematicas)
	%BotonSonido.pressed.connect(_alternar_sonido)
	_actualizar_opciones()
	%BotonContinuar.pressed.connect(cerrar_pausa)
	%BotonNuevoMapa.pressed.connect(_pedir_nuevo_mapa)
	%BotonMenuPrincipal.pressed.connect(ir_al_menu_principal)
	%BotonJugarOtraVez.pressed.connect(_pedir_nuevo_mapa)
	%BotonSalirAlMenu.pressed.connect(ir_al_menu_principal)


## creditos: diccionario {"azul": 3000, "rojo": 2000}
func mostrar_turno(equipo: String, creditos: Dictionary = {}) -> void:
	var texto := "Turno: " + ("Azul" if equipo == "azul" else "Rojo")
	if not creditos.is_empty():
		texto += "  |  Azul: $%d  Rojo: $%d" % [creditos.get("azul", 0), creditos.get("rojo", 0)]
	%EtiquetaTurno.text = texto


## Mientras juega la máquina no se puede terminar turno ni abrir el menú.
func bloquear_botones(bloquear: bool) -> void:
	%BotonTerminar.disabled = bloquear
	%BotonMenu.disabled = bloquear
	%BotonTienda.disabled = bloquear


## Fichita con la información de la unidad, en la esquina de abajo contraria a ella.
func mostrar_info(texto: String, a_la_derecha: bool) -> void:
	var panel: PanelContainer = %PanelInfo
	if not panel.has_theme_stylebox_override("panel"):
		var estilo: StyleBoxFlat = panel.get_theme_stylebox("panel").duplicate()
		estilo.content_margin_left = 5
		estilo.content_margin_right = 5
		estilo.content_margin_top = 3
		estilo.content_margin_bottom = 3
		estilo.border_width_left = 1
		estilo.border_width_top = 1
		estilo.border_width_right = 1
		estilo.border_width_bottom = 1
		panel.add_theme_stylebox_override("panel", estilo)
	%TextoInfo.text = texto
	panel.size = Vector2.ZERO
	panel.reset_size()
	var ancho_pantalla := panel.get_viewport_rect().size.x
	panel.position = Vector2(ancho_pantalla - panel.size.x - 4 if a_la_derecha else 4.0, 270 - panel.size.y - 4)
	panel.show()


## Mensaje corto abajo en el centro que desaparece solo (por ejemplo, qué hace un botón).
func mostrar_aviso(texto: String, segundos := 4.0) -> void:
	if _aviso != null and is_instance_valid(_aviso):
		_aviso.queue_free()
	_aviso = PanelContainer.new()
	_aviso.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var etiqueta := Label.new()
	etiqueta.text = texto
	etiqueta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	etiqueta.custom_minimum_size = Vector2(minf(300, texto.length() * 6.0 + 10), 0)
	etiqueta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	etiqueta.add_theme_font_size_override("font_size", 9)
	_aviso.add_child(etiqueta)
	add_child(_aviso)
	move_child(_aviso, %MenuPausa.get_index())
	_aviso.reset_size()
	await get_tree().process_frame
	if not is_instance_valid(_aviso):
		return
	_aviso.reset_size()
	_aviso.position = Vector2((480 - _aviso.size.x) / 2.0, 270 - _aviso.size.y - 8)
	var este := _aviso
	var tw := este.create_tween()
	tw.tween_interval(segundos)
	tw.tween_property(este, "modulate:a", 0.0, 0.4)
	tw.tween_callback(este.queue_free)


var _aviso: PanelContainer


func ocultar_info() -> void:
	%PanelInfo.hide()


## Letrero que cruza la pantalla ("TU TURNO", "TURNO DEL ROJO"). Se puede esperar con await.
func mostrar_cartel(texto: String, color: Color) -> void:
	Sonido.reproducir("turno")
	var franja := ColorRect.new()
	franja.color = Color(color, 0.85)
	franja.size = Vector2(480, 40)
	franja.position = Vector2(-480, 115)
	franja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var etiqueta := Label.new()
	etiqueta.text = texto
	etiqueta.size = franja.size
	etiqueta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	etiqueta.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	etiqueta.add_theme_font_size_override("font_size", 22)
	etiqueta.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	etiqueta.add_theme_constant_override("outline_size", 6)
	franja.add_child(etiqueta)
	# Bloquea los toques mientras pasa, para no mover nada sin querer.
	var bloqueo := Control.new()
	bloqueo.size = Vector2(480, 270)
	bloqueo.mouse_filter = Control.MOUSE_FILTER_STOP
	bloqueo.add_child(franja)
	add_child(bloqueo)
	move_child(bloqueo, %MenuPausa.get_index())
	var tw := create_tween()
	tw.tween_property(franja, "position:x", 0.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.55)
	tw.tween_property(franja, "position:x", 480.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tw.finished
	bloqueo.queue_free()


func _alternar_cinematicas() -> void:
	Cinematica.activadas = not Cinematica.activadas
	_actualizar_opciones()


func _alternar_sonido() -> void:
	Sonido.activado = not Sonido.activado
	_actualizar_opciones()


func _actualizar_opciones() -> void:
	%BotonCinematicas.text = "Cinemáticas: " + ("Sí" if Cinematica.activadas else "No")
	%BotonSonido.text = "Sonido: " + ("Sí" if Sonido.activado else "No")


func hay_menu_abierto() -> bool:
	return %MenuPausa.visible or %PantallaFin.visible


func abrir_pausa() -> void:
	if not %PantallaFin.visible:
		%MenuPausa.show()


func cerrar_pausa() -> void:
	%MenuPausa.hide()


## Persona 1: llamar esto (a través de main.terminar_partida) cuando alguien gane.
func _process(delta: float) -> void:
	if _boton_presionado != null and not _ayuda_mostrada:
		_tiempo_boton += delta
		if _tiempo_boton >= TIEMPO_AYUDA:
			_ayuda_mostrada = true
			_mostrar_ayuda(_boton_presionado)


## Globito pequeño debajo del botón con su explicación.
func _mostrar_ayuda(boton: Button) -> void:
	if _ayuda != null and is_instance_valid(_ayuda):
		_ayuda.queue_free()
	_ayuda = PanelContainer.new()
	_ayuda.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var etiqueta := Label.new()
	etiqueta.text = AYUDAS[boton.name]
	etiqueta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	etiqueta.custom_minimum_size = Vector2(150, 0)
	etiqueta.add_theme_font_size_override("font_size", 9)
	_ayuda.add_child(etiqueta)
	add_child(_ayuda)
	_ayuda.reset_size()
	_ayuda.position = Vector2(clampf(boton.position.x + boton.size.x / 2.0 - 85, 4, 480 - 178), boton.position.y + boton.size.y + 4)
	var este := _ayuda
	var tw := este.create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(este, "modulate:a", 0.0, 0.3)
	tw.tween_callback(este.queue_free)
	Sonido.reproducir("seleccion", -8.0)


## El botón "Terminar turno" brilla cuando ya no te queda nada por hacer.
func resaltar_terminar(activo: bool) -> void:
	var b: Button = %BotonTerminar
	if activo and _tween_terminar == null:
		_tween_terminar = create_tween().set_loops()
		_tween_terminar.tween_property(b, "modulate", Color(1.4, 1.3, 0.6), 0.5)
		_tween_terminar.tween_property(b, "modulate", Color.WHITE, 0.5)
	elif not activo and _tween_terminar != null:
		_tween_terminar.kill()
		_tween_terminar = null
		b.modulate = Color.WHITE


## Texto de la barra de arriba (turno, dinero, población).
func mostrar_estado(texto: String) -> void:
	%EtiquetaTurno.text = texto




func mostrar_fin(ganador: String, estadisticas := "") -> void:
	%EstadisticasFin.text = estadisticas
	%EstadisticasFin.visible = estadisticas != ""
	%MenuPausa.hide()
	Sonido.reproducir("victoria" if ganador == "azul" else "derrota")
	if ganador == "azul":
		%TituloFin.text = "¡VICTORIA!"
		%MensajeFin.text = "Derrotaste al ejército rojo."
	else:
		%TituloFin.text = "DERROTA"
		%MensajeFin.text = "El ejército rojo te venció."
	%PantallaFin.show()


## Oculta la pausa y la pantalla de fin (al empezar una partida nueva).
func cerrar_todo() -> void:
	%MenuPausa.hide()
	%PantallaFin.hide()


func _pedir_nuevo_mapa() -> void:
	%MenuPausa.hide()
	%PantallaFin.hide()
	nuevo_mapa_pedido.emit()


func ir_al_menu_principal() -> void:
	get_tree().change_scene_to_file(ESCENA_MENU)
