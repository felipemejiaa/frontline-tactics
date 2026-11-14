extends SceneTree
## Prueba automática de los menús, haciendo "clics" de verdad en la pantalla.
## Ejecutar: godot --headless --path . --script res://tests/prueba_menus.gd

var fallos := 0


func revisar(condicion: bool, mensaje: String) -> void:
	print("  OK   " if condicion else "  FALLA ", mensaje)
	if not condicion:
		fallos += 1


## Simula un toque (presionar y soltar) en una posición del juego (coordenadas de 480x270).
## La ventana real es más grande, así que se convierte con la escala de la pantalla.
func tocar(pos_juego: Vector2) -> void:
	var pos: Vector2 = root.get_final_transform() * pos_juego
	for presionado in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = presionado
		ev.position = pos
		ev.global_position = pos
		root.push_input(ev)
		await process_frame


func centro_de(control: Control) -> Vector2:
	return control.get_global_rect().get_center()


func _initialize() -> void:
	print("Menú principal")
	var menu: Control = load("res://scenes/menu_principal.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	await process_frame
	revisar(menu.mapa_fondo.unidades.size() == 6, "hay un mapa con unidades de fondo")
	await tocar(centro_de(menu.get_node("%BotonComoJugar")))
	revisar(menu.ayuda.visible, "Cómo jugar abre la ayuda")
	await tocar(centro_de(menu.get_node("%BotonVolver")))
	revisar(not menu.ayuda.visible, "Volver cierra la ayuda")
	await tocar(centro_de(menu.get_node("%BotonJugar")))
	for i in 5:
		await process_frame
	var main: Node = current_scene
	revisar(main != null and main.name == "Main", "Jugar abre la partida")
	await create_timer(1.3).timeout  # esperar a que pase el letrero "TU TURNO"

	print("Partida")
	var hud: HUD = main.hud
	var unidad: Unidad = main.mapa.unidades_de("azul")[0]
	var pos_unidad: Vector2 = main.mapa.position + main.mapa.celda_a_pos(unidad.celda)
	await tocar(pos_unidad)
	revisar(main.seleccionada == unidad, "tocar una unidad en la pantalla la selecciona")
	main.deseleccionar()

	await tocar(centro_de(main.get_node("%BotonMenu")))
	revisar(main.get_node("%MenuPausa").visible, "el botón Menú abre la pausa")
	await tocar(pos_unidad)
	revisar(main.seleccionada == null, "con la pausa abierta no se puede tocar el mapa")
	await tocar(centro_de(main.get_node("%BotonContinuar")))
	revisar(not main.get_node("%MenuPausa").visible, "Continuar cierra la pausa")

	var mapa_antes: int = main.semilla
	await tocar(centro_de(main.get_node("%BotonMenu")))
	await tocar(centro_de(main.get_node("%BotonNuevoMapa")))
	revisar(main.semilla != mapa_antes and not hud.hay_menu_abierto(), "Nuevo mapa cambia el mapa y cierra el menú")
	await create_timer(1.3).timeout

	main.terminar_partida("azul")
	revisar(main.get_node("%PantallaFin").visible and main.get_node("%TituloFin").text == "¡VICTORIA!", "pantalla de victoria")
	unidad = main.mapa.unidades_de("azul")[0]
	main.tocar_celda(unidad.celda)
	revisar(main.seleccionada == null, "con la partida terminada no se pueden mover unidades")
	await process_frame
	await tocar(centro_de(main.get_node("%BotonJugarOtraVez")))
	revisar(not main.juego_terminado and not hud.hay_menu_abierto(), "Jugar otra vez empieza una partida nueva")
	await create_timer(1.3).timeout

	main.terminar_partida("rojo")
	await process_frame
	revisar(main.get_node("%TituloFin").text == "DERROTA", "pantalla de derrota")
	await tocar(centro_de(main.get_node("%BotonSalirAlMenu")))
	for i in 5:
		await process_frame
	revisar(current_scene != null and current_scene.name == "MenuPrincipal", "Menú principal vuelve al inicio")

	print("\n%s" % ("TODO BIEN" if fallos == 0 else "%d FALLAS" % fallos))
	quit(fallos)
