extends SceneTree
## Prueba automática de las animaciones de ataque, la cinemática, el letrero de turno y el sonido.
## Ejecutar: godot --headless --path . --script res://tests/prueba_animaciones.gd

var fallos := 0


func revisar(condicion: bool, mensaje: String) -> void:
	print("  OK   " if condicion else "  FALLA ", mensaje)
	if not condicion:
		fallos += 1


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


func cinematica_abierta(main: Node) -> bool:
	for h in main.get_children():
		if h is Cinematica:
			return true
	return false


func preparar_duelo(main: Node) -> Array:
	var mapa: GameMap = main.mapa
	for u in mapa.unidades.values():
		mapa.eliminar_unidad(u)
	await process_frame
	var a := mapa.crear_unidad("tanque", "azul", Vector2i(5, 5))
	var b := mapa.crear_unidad("infanteria", "rojo", Vector2i(6, 5))
	mapa.crear_unidad("infanteria", "rojo", Vector2i(20, 12))  # para que no se acabe la partida
	return [a, b]


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	main.nuevo_mapa(5)
	await process_frame

	print("Sonido y letrero")
	await create_timer(0.3).timeout
	revisar(is_instance_valid(Sonido._yo) and Sonido._yo.is_inside_tree(), "el reproductor de sonido existe")
	var letrero := false
	for h in main.hud.get_children():
		if h is Control and h.mouse_filter == Control.MOUSE_FILTER_STOP and h.get_child_count() > 0 and h.get_child(0) is ColorRect:
			letrero = true
	revisar(letrero, "al empezar aparece el letrero TU TURNO")
	await create_timer(1.2).timeout

	print("Cinemática")
	Cinematica.activadas = true
	var duelo := await preparar_duelo(main)
	var a: Unidad = duelo[0]
	var b: Unidad = duelo[1]
	var inicio := Time.get_ticks_msec()
	var ataque_hecho := [false]
	var f := func(x: Unidad, y: Unidad):
		await main.ejecutar_ataque(x, y)
		ataque_hecho[0] = true
	f.call(a, b)
	await create_timer(0.4).timeout
	revisar(cinematica_abierta(main), "se abre la cinemática")
	revisar(b.vida < 10, "el daño ya se aplicó")
	while not ataque_hecho[0]:
		await process_frame
	var duracion := (Time.get_ticks_msec() - inicio) / 1000.0
	revisar(duracion > 1.5 and duracion < 5.0, "la cinemática dura un par de segundos (%.1f s)" % duracion)
	await process_frame
	revisar(not cinematica_abierta(main), "la cinemática se cierra sola")

	print("Saltar la cinemática")
	a.reiniciar_turno()
	a.vida = 10
	inicio = Time.get_ticks_msec()
	ataque_hecho[0] = false
	f.call(a, b)
	await create_timer(0.3).timeout
	await tocar(Vector2(240, 135))
	while not ataque_hecho[0]:
		await process_frame
	duracion = (Time.get_ticks_msec() - inicio) / 1000.0
	revisar(duracion < 1.4, "tocando la pantalla se salta (%.1f s)" % duracion)

	print("Animación rápida en el mapa")
	Cinematica.activadas = false
	duelo = await preparar_duelo(main)
	a = duelo[0]
	b = duelo[1]
	var pos_original := a.position
	ataque_hecho[0] = false
	f.call(a, b)
	await create_timer(0.04).timeout
	revisar(a.position != pos_original, "el atacante se lanza hacia el enemigo")
	while not ataque_hecho[0]:
		await process_frame
	revisar(a.position == pos_original, "y vuelve a su casilla")
	revisar(not cinematica_abierta(main), "sin cinemática")
	b.vida = 1
	a.reiniciar_turno()
	ataque_hecho[0] = false
	f.call(a, b)
	while not ataque_hecho[0]:
		await process_frame
	var particulas := 0
	for h in main.mapa.get_children():
		if h is CPUParticles2D:
			particulas += 1
	revisar(particulas >= 2, "al destruir una unidad sale una explosión")

	print("Opciones en la pausa")
	await create_timer(0.8).timeout
	main.hud.abrir_pausa()
	await process_frame
	await tocar(main.get_node("%BotonCinematicas").get_global_rect().get_center())
	revisar(Cinematica.activadas, "el botón vuelve a activar las cinemáticas")
	await tocar(main.get_node("%BotonSonido").get_global_rect().get_center())
	revisar(not Sonido.activado and main.get_node("%BotonSonido").text == "Sonido: No", "el botón apaga el sonido")
	await tocar(main.get_node("%BotonSonido").get_global_rect().get_center())
	main.hud.cerrar_pausa()

	print("Turno de la IA con cinemáticas")
	Cinematica.activadas = true
	main.nuevo_mapa(11)
	await create_timer(1.3).timeout
	var mapa: GameMap = main.mapa
	var azul: Unidad = mapa.unidades_de("azul")[0]
	var rojo: Unidad = mapa.unidades_de("rojo")[0]
	var libre := Vector2i(-1, -1)
	for d in GameMap.DIRECCIONES:
		var c: Vector2i = rojo.celda + d
		if mapa.en_mapa(c) and mapa.unidad_en(c) == null and mapa.terreno_en(c) in ["llanura", "ciudad"]:
			libre = c
	mapa.mover_registro(azul, libre)
	azul.position = mapa.celda_a_pos(libre)
	main.terminar_turno()
	var vio_cinematica := false
	while main.turno_ia:
		if cinematica_abierta(main):
			vio_cinematica = true
		await process_frame
	revisar(vio_cinematica, "cuando ataca la máquina también se ve la cinemática")
	revisar(main.equipo_actual == "azul" or main.juego_terminado, "el turno vuelve al jugador")

	print("\n%s" % ("TODO BIEN" if fallos == 0 else "%d FALLAS" % fallos))
	quit(fallos)
