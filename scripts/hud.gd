class_name HUD
extends CanvasLayer
## Interfaz dentro de la partida: barra de arriba, menú de pausa y pantalla de fin.
## No sabe nada de las reglas del juego: solo muestra cosas y avisa con señales
## cuando el jugador presiona un botón. main.gd escucha esas señales.

signal terminar_turno_pedido
signal nuevo_mapa_pedido
signal tienda_pedida
signal peligro_alternado

const ESCENA_MENU := "res://scenes/menu_principal.tscn"


func _ready() -> void:
	%BotonTerminar.pressed.connect(func(): terminar_turno_pedido.emit())
	%BotonMenu.pressed.connect(abrir_pausa)
	%BotonTienda.pressed.connect(func(): tienda_pedida.emit())
	%BotonPeligro.pressed.connect(func(): peligro_alternado.emit())
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
	%BotonPeligro.disabled = bloquear


## Panel con la información de la unidad seleccionada, del lado contrario a ella.
func mostrar_info(texto: String, a_la_derecha: bool) -> void:
	%TextoInfo.text = texto
	var panel: Control = %PanelInfo
	panel.reset_size()
	var ancho_pantalla := panel.get_viewport_rect().size.x
	panel.position = Vector2(ancho_pantalla - panel.size.x - 6 if a_la_derecha else 6.0, 270 - panel.size.y - 6)
	panel.show()


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
## Texto de la barra de arriba (turno, dinero, población).
func mostrar_estado(texto: String) -> void:
	%EtiquetaTurno.text = texto


## El botón Peligro se ve "presionado" mientras la zona está activa.
func marcar_peligro(activo: bool) -> void:
	%BotonPeligro.modulate = Color(1, 0.55, 0.5) if activo else Color.WHITE


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
