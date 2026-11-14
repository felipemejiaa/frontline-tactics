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
	revisar(main.estado == main.Estado.LIBRE and not main.menu.visible and mi_inf.ya_ataco,
		"sin enemigos cerca, la unidad termina sola (sin tener que darle Esperar)")
	mi_inf.reiniciar_turno()
	var vecino := mapa.crear_unidad("artilleria", "rojo", Vector2i(4, 6))
	main.tocar_celda(mi_inf.celda)
	main.tocar_celda(Vector2i(3, 6))
	await create_timer(0.6).timeout
	var textos := []
	for b in main.caja_menu.get_children():
		textos.append(b.text)
	revisar(main.estado == main.Estado.MENU and "Atacar" in textos and "Esperar" in textos,
		"con un enemigo al lado sale el menú con Atacar: %s" % [textos])
	main._accion_esperar()
	revisar(main.estado == main.Estado.LIBRE and mi_inf.ya_ataco, "Esperar cierra el menú y la deja usada")

	print("Atacar tocando al enemigo")
	mi_inf.reiniciar_turno()
	main.tocar_celda(mi_inf.celda)
	revisar(main.ataques_posibles.has(vecino.celda), "al seleccionar, el enemigo atacable queda marcado")
	revisar(main.get_node("%PanelInfo").visible, "se muestra el panel de información")
	var vida_antes := vecino.vida
	main.tocar_celda(vecino.celda)
	revisar(vecino.vida == vida_antes and main.get_node("%PanelInfo").visible and "Harás" in main.get_node("%TextoInfo").text,
		"el primer toque muestra la vista previa del daño sin atacar")
	main.tocar_celda(vecino.celda)
	await create_timer(0.3).timeout
	revisar(not is_instance_valid(vecino) or vecino.vida < vida_antes, "tocar al enemigo lo ataca directamente")
	revisar(mi_inf.ya_ataco and main.estado == main.Estado.LIBRE and not main.menu.visible, "después del ataque no queda ningún menú abierto")
	revisar(not main.get_node("%PanelInfo").visible, "el panel de información se cierra")
	var numeros := 0
	for h in mapa.get_children():
		if h is Label and h.text.begins_with("-"):
			numeros += 1
	revisar(numeros >= 1, "aparece el número de daño flotando")
	if is_instance_valid(vecino):
		mapa.eliminar_unidad(vecino)
	await create_timer(1.0).timeout

	print("Artillería")
	var art: Unidad = mapa.unidad_en(Vector2i(1, 6))
	var lejos := mapa.crear_unidad("tanque", "rojo", Vector2i(3, 6))
	var pegado := mapa.crear_unidad("infanteria", "rojo", Vector2i(1, 7))
	main.tocar_celda(art.celda)
	revisar(main.ataques_posibles.has(lejos.celda) and main.ataques_posibles[lejos.celda] == art.celda, "la artillería ataca de lejos sin moverse")
	revisar(not main.ataques_posibles.has(pegado.celda), "la artillería no puede atacar a una unidad pegada")
	main.deseleccionar()
	mapa.eliminar_unidad(lejos)
	mapa.eliminar_unidad(pegado)
	await process_frame

	print("Captura")
	mapa.cargar_desde_texto(["H..c...h", "F......f"])
	var capturadora := mapa.crear_unidad("infanteria", "azul", Vector2i(3, 0))
	mapa.crear_unidad("infanteria", "rojo", Vector2i(6, 1))
	reglas.iniciar(mapa)
	revisar(reglas.puede_capturar(capturadora), "la infantería puede capturar la ciudad")
	reglas.capturar(capturadora)
	revisar(mapa.dueno_en(Vector2i(3, 0)) == "neutral", "con 10 de vida no alcanza en un turno")
	revisar(mapa.progreso_captura.has(Vector2i(3, 0)) and is_equal_approx(mapa.progreso_captura[Vector2i(3, 0)][0], 0.5),
		"la barra de captura muestra la mitad")
	capturadora.reiniciar_turno()
	reglas.capturar(capturadora)
	revisar(mapa.dueno_en(Vector2i(3, 0)) == "azul", "al segundo turno la ciudad es azul")
	revisar(not mapa.progreso_captura.has(Vector2i(3, 0)), "al terminar, la barra desaparece")
	revisar(mapa.ingreso_de("azul") == 3 * 500, "cada edificio da $500 (3 edificios = $1500)")

	print("Compra")
	revisar(not reglas.comprar("tanque", "azul"), "sin créditos suficientes no se puede comprar un tanque")
	reglas.creditos["azul"] = 5000
	var antes: int = reglas.creditos["azul"]
	revisar(reglas.comprar("tanque", "azul"), "se puede comprar un tanque en la base")
	revisar(mapa.unidad_en(Vector2i(0, 1)) != null and mapa.unidad_en(Vector2i(0, 1)).tipo == "tanque", "el tanque aparece en la base")
	revisar(reglas.creditos["azul"] == antes - 3000, "se cobraron 3000")
	revisar(not reglas.comprar("infanteria", "azul"), "no se puede comprar con la base ocupada")

	print("Suerte")
	var a := mapa.crear_unidad("tanque", "azul", Vector2i(5, 0))
	var resultados := {}
	for i in 40:
		var b := mapa.crear_unidad("infanteria", "rojo", Vector2i(5, 1))
		a.reiniciar_turno()
		a.vida = 10
		var estimado := reglas.calcular_dano(a, b)
		reglas.atacar(a, b)
		var real := 10 - b.vida if is_instance_valid(b) and b.vida > 0 else -1
		if real > 0:
			resultados[real - estimado] = true
			if absi(real - estimado) > Reglas.SUERTE:
				revisar(false, "el daño (%d) no se aleja más de 1 del estimado (%d)" % [real, estimado])
		if is_instance_valid(b):
			mapa.eliminar_unidad(b)
		await process_frame
	revisar(resultados.size() >= 2, "el daño varía un poco entre ataques (%s)" % [resultados.keys()])
	mapa.eliminar_unidad(a)
	await process_frame

	print("Victoria")
	for u in mapa.unidades_de("rojo"):
		mapa.eliminar_unidad(u)
	await process_frame
	reglas.revisar_victoria()
	revisar(not main.juego_terminado, "sin unidades pero con base y dinero, el rojo todavía no pierde")
	reglas.creditos["rojo"] = 0
	reglas.multiplicador_ingreso["rojo"] = 0.0
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
