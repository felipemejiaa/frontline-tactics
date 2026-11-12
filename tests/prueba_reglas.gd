extends SceneTree
## Prueba automática de las reglas: combate, captura, compra, victoria y una partida larga.
## Ejecutar: godot --headless --path . --script res://tests/prueba_reglas.gd

var fallos := 0


func revisar(condicion: bool, mensaje: String) -> void:
	print("  OK   " if condicion else "  FALLA ", mensaje)
	if not condicion:
		fallos += 1


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.modo_prueba = true
	root.add_child(main)
	await process_frame
	var mapa: GameMap = main.mapa
	var reglas: Reglas = main.reglas

	print("Créditos")
	revisar(reglas.creditos["azul"] == Reglas.CREDITOS_INICIALES + mapa.ingreso_de("azul"), "el azul cobra al empezar")

	print("Combate (piedra, papel o tijera)")
	var tanque := mapa.crear_unidad("tanque", "azul", Vector2i(6, 6))
	var inf := mapa.crear_unidad("infanteria", "rojo", Vector2i(7, 6))
	var d_ventaja := reglas.calcular_dano(tanque, inf)
	var d_desventaja := reglas.calcular_dano(inf, tanque)
	revisar(d_ventaja > d_desventaja, "el tanque le pega más a la infantería (%d) que al revés (%d)" % [d_ventaja, d_desventaja])
	reglas.atacar(tanque, inf)
	revisar(inf.vida < 10, "la infantería recibió daño")
	revisar(tanque.vida < 10, "hubo contraataque")
	revisar(tanque.ya_ataco, "el tanque queda usado")
	tanque.reiniciar_turno()
	reglas.atacar(tanque, inf)
	await process_frame
	revisar(not is_instance_valid(inf) or mapa.unidad_en(Vector2i(7, 6)) == null, "con la vida en 0 la unidad desaparece")
	mapa.eliminar_unidad(tanque)
	await process_frame

	print("Menú de acciones con toques")
	var mi_inf: Unidad = mapa.unidad_en(Vector2i(2, 4))
	main.tocar_celda(mi_inf.celda)
	main.tocar_celda(Vector2i(3, 5))
	await create_timer(0.6).timeout
	revisar(main.estado == main.Estado.MENU and main.menu.visible, "al moverse aparece el menú de acciones")
	var textos := []
	for b in main.caja_menu.get_children():
		textos.append(b.text)
	revisar("Esperar" in textos, "el menú tiene Esperar: %s" % [textos])
	main._accion_esperar()
	revisar(main.estado == main.Estado.LIBRE and mi_inf.ya_ataco, "Esperar cierra el menú y la deja usada")

	print("Captura")
	mapa.cargar_desde_texto(["H..c...h", "F......f"])
	var capturadora := mapa.crear_unidad("infanteria", "azul", Vector2i(3, 0))
	mapa.crear_unidad("infanteria", "rojo", Vector2i(6, 1))
	reglas.iniciar(mapa)
	revisar(reglas.puede_capturar(capturadora), "la infantería puede capturar la ciudad")
	reglas.capturar(capturadora)
	revisar(mapa.dueno_en(Vector2i(3, 0)) == "neutral", "con 10 de vida no alcanza en un turno")
	capturadora.reiniciar_turno()
	reglas.capturar(capturadora)
	revisar(mapa.dueno_en(Vector2i(3, 0)) == "azul", "al segundo turno la ciudad es azul")

	print("Compra")
	revisar(not reglas.comprar("tanque", "azul"), "sin créditos suficientes no se puede comprar un tanque")
	reglas.creditos["azul"] = 5000
	var antes: int = reglas.creditos["azul"]
	revisar(reglas.comprar("tanque", "azul"), "se puede comprar un tanque en la base")
	revisar(mapa.unidad_en(Vector2i(0, 1)) != null and mapa.unidad_en(Vector2i(0, 1)).tipo == "tanque", "el tanque aparece en la base")
	revisar(reglas.creditos["azul"] == antes - 3000, "se cobraron 3000")
	revisar(not reglas.comprar("infanteria", "azul"), "no se puede comprar con la base ocupada")

	print("Victoria")
	for u in mapa.unidades_de("rojo"):
		mapa.eliminar_unidad(u)
	reglas.revisar_victoria()
	await process_frame
	revisar(main.juego_terminado and main.get_node("%PantallaFin").visible and main.get_node("%TituloFin").text == "¡VICTORIA!", "sin unidades rojas sale la pantalla de victoria")

	print("Partida larga en mapa aleatorio (30 turnos de la IA)")
	main.modo_prueba = false
	main.nuevo_mapa(99)
	await process_frame
	revisar(not main.juego_terminado and not main.get_node("%PantallaFin").visible, "nuevo mapa reinicia la partida")
	var turnos := 0
	for t in 30:
		if main.juego_terminado:
			break
		main.terminar_turno()
		while main.turno_ia:
			await process_frame
		turnos += 1
	print("    turnos jugados: %d, unidades rojas: %d, edificios rojos: %d, terminó: %s" % [turnos, mapa.unidades_de("rojo").size(), mapa.edificios_de("rojo").size(), main.juego_terminado])
	revisar(mapa.edificios_de("rojo").size() > 2, "la IA capturó ciudades")

	print("\n%s" % ("TODO BIEN" if fallos == 0 else "%d FALLAS" % fallos))
	quit(fallos)
