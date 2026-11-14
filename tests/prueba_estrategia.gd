extends SceneTree
## Prueba automática de las mecánicas de estrategia: curación, población, veteranía, flanqueo,
## unidades nuevas, torreta, habilidades, zona de peligro, niebla, dificultades, cámara y estadísticas.
## Ejecutar: godot --headless --path . --script res://tests/prueba_estrategia.gd

var fallos := 0
var main: Node
var mapa: GameMap
var reglas: Reglas


func revisar(condicion: bool, mensaje: String) -> void:
	print("  OK   " if condicion else "  FALLA ", mensaje)
	if not condicion:
		fallos += 1


## Mapa pequeño de prueba. Leyenda en game_map.gd.
func preparar(lineas: Array) -> void:
	mapa.niebla_activa = false
	mapa.cargar_desde_texto(lineas)
	reglas.iniciar(mapa)
	await process_frame


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.modo_prueba = true
	root.add_child(main)
	await process_frame
	mapa = main.mapa
	reglas = main.reglas

	print("Curación")
	await preparar(["H.c.....h", "F.......f"])
	mapa.cambiar_dueno(Vector2i(2, 0), "azul")
	var herida := mapa.crear_unidad("tanque", "azul", Vector2i(2, 0))
	var afuera := mapa.crear_unidad("tanque", "azul", Vector2i(3, 0))
	mapa.crear_unidad("infanteria", "rojo", Vector2i(7, 0))
	herida.vida = 5
	afuera.vida = 5
	reglas.al_empezar_turno("azul")
	revisar(herida.vida == 7, "en un edificio propio se cura +2 (vida %d)" % herida.vida)
	revisar(afuera.vida == 5, "fuera de un edificio no se cura")

	print("Población")
	revisar(reglas.limite_poblacion("azul") == 5 + 3, "límite = 5 + 3 edificios = 8")
	reglas.creditos["azul"] = 99999
	var compradas := 0
	for i in 10:
		var base := reglas.celda_base("azul")
		if reglas.comprar("infanteria", "azul"):
			compradas += 1
			mapa.mover_registro(mapa.unidad_en(base), Vector2i(1 + i % 7, 1) if i < 7 else Vector2i(1, 0))
	revisar(reglas.poblacion("azul") == 8, "no se puede pasar del límite (%d unidades)" % reglas.poblacion("azul"))
	revisar(reglas.motivo_no_compra("infanteria", "azul") == "Población llena", "la tienda dice 'Población llena'")

	print("Veteranía y flanqueo")
	await preparar(["H.......h", "F.......f", "........."])
	var veterano := mapa.crear_unidad("tanque", "azul", Vector2i(3, 1))
	var novato := mapa.crear_unidad("tanque", "azul", Vector2i(3, 2))
	var blanco := mapa.crear_unidad("infanteria", "rojo", Vector2i(4, 1))
	mapa.crear_unidad("infanteria", "rojo", Vector2i(8, 2))
	var dano_novato: int = reglas.estimar(veterano, blanco, Vector2i(3, 1))["dano"]
	veterano.rango = 3
	var dano_veterano: int = reglas.estimar(veterano, blanco, Vector2i(3, 1))["dano"]
	revisar(dano_veterano > dano_novato, "con 3 estrellas pega más (%d > %d)" % [dano_veterano, dano_novato])
	veterano.rango = 0
	var sin_flanqueo := reglas.estimar(veterano, blanco, Vector2i(3, 1))
	mapa.mover_registro(novato, Vector2i(4, 2))
	var con_flanqueo := reglas.estimar(veterano, blanco, Vector2i(3, 1))
	revisar(con_flanqueo["flanqueo"] == 1 and con_flanqueo["dano"] >= sin_flanqueo["dano"], "un aliado pegado al enemigo da flanqueo")
	blanco.vida = 1
	reglas.atacar(veterano, blanco)
	await process_frame
	revisar(veterano.rango == 1, "destruir una unidad da una estrella")
	revisar(reglas.estadisticas["azul"]["destruidas"] == 1 and reglas.estadisticas["rojo"]["perdidas"] == 1, "se cuentan en las estadísticas")

	print("Helicóptero y antiaérea")
	await preparar(["H..~~m...h", "F..~~m...f"])
	var heli := mapa.crear_unidad("helicoptero", "azul", Vector2i(2, 0))
	mapa.crear_unidad("infanteria", "rojo", Vector2i(9, 1))
	var alc := mapa.calcular_alcance(heli)
	revisar(Vector2i(4, 0) in alc["destinos"] and Vector2i(5, 1) in alc["destinos"], "el helicóptero vuela sobre agua y montañas")
	var art := mapa.crear_unidad("artilleria", "rojo", Vector2i(2, 1) + Vector2i(2, 0))
	mapa.mover_registro(art, Vector2i(6, 0))
	mapa.mover_registro(heli, Vector2i(6, 1) + Vector2i(-2, 0))
	revisar(not reglas.puede_atacar_desde(art, art.celda, heli), "la artillería no puede atacar helicópteros")
	var aa := mapa.crear_unidad("antiaerea", "rojo", Vector2i(4, 0))
	var tanque_r := mapa.crear_unidad("tanque", "rojo", Vector2i(3, 1))
	var a_heli: int = reglas.estimar(aa, heli, aa.celda)["dano"]
	var tanque_heli: int = reglas.estimar(tanque_r, heli, tanque_r.celda)["dano"]
	revisar(a_heli > tanque_heli * 2, "la antiaérea destroza al helicóptero (%d vs %d del tanque)" % [a_heli, tanque_heli])
	revisar(reglas.estimar(heli, tanque_r, heli.celda)["dano"] >= 7, "el helicóptero le gana al tanque")

	print("Torreta")
	await preparar(["....H....h", "F........f", ".........."])
	mapa.crear_unidad("infanteria", "rojo", Vector2i(9, 2))
	reglas.creditos["azul"] = 9000
	var celdas := reglas.celdas_torreta("azul")
	var cerca := true
	for c in celdas:
		if mapa.distancia(c, Vector2i(4, 0)) > Datos.DISTANCIA_TORRETA:
			cerca = false
	revisar(not celdas.is_empty() and cerca, "solo se construye cerca del cuartel (%d casillas)" % celdas.size())
	revisar(not reglas.comprar("torreta", "azul", Vector2i(9, 1)), "no se puede construir lejos")
	revisar(reglas.comprar("torreta", "azul", Vector2i(4, 2)), "sí se puede construir junto al cuartel")
	var torreta := mapa.unidad_en(Vector2i(4, 2))
	torreta.reiniciar_turno()
	revisar(mapa.calcular_alcance(torreta)["destinos"] == [Vector2i(4, 2)], "la torreta no se mueve")
	var intruso := mapa.crear_unidad("infanteria", "rojo", Vector2i(6, 2))
	revisar(reglas.puede_atacar(torreta, intruso), "la torreta ataca a 2 casillas")

	print("Habilidades")
	await preparar(["H.......h", "F.......f", "........."])
	reglas.creditos["azul"] = 20000
	var mia := mapa.crear_unidad("tanque", "azul", Vector2i(2, 2))
	mia.vida = 3
	var precio1 := reglas.precio_habilidad("reparacion", "azul")
	revisar(reglas.usar_reparacion("azul", mia) and mia.vida == 8, "reparación da +5 de vida")
	revisar(reglas.precio_habilidad("reparacion", "azul") > precio1, "cada uso sube el precio")
	var e1 := mapa.crear_unidad("infanteria", "rojo", Vector2i(5, 1))
	var e2 := mapa.crear_unidad("tanque", "rojo", Vector2i(6, 2))
	e1.vida = 2
	revisar(reglas.usar_bombardeo("azul", Vector2i(5, 2)), "el bombardeo se puede usar")
	revisar(e1.vida == 1 and e2.vida == 7 and mia.vida == 8, "bombardeo: 3 de daño, no destruye y no le pega a lo tuyo")
	var mov_antes := mia.movimiento()
	reglas.usar_marcha("azul")
	revisar(mia.movimiento() == mov_antes + 2, "marcha forzada: +2 de movimiento")
	mia.reiniciar_turno()
	revisar(mia.movimiento() == mov_antes, "y se acaba al siguiente turno")

	print("Zona de peligro")
	await preparar(["H..........h", "F..........f", "............"])
	mapa.crear_unidad("tanque", "rojo", Vector2i(8, 1))
	mapa.crear_unidad("infanteria", "azul", Vector2i(0, 2))
	var zona: Dictionary = main.calcular_peligro("azul")
	revisar(zona.has(Vector2i(3, 1)) and not zona.has(Vector2i(1, 1)), "marca hasta donde llega el tanque (mov 5 + 1)")
	main._alternar_peligro()
	await create_timer(0.1).timeout
	revisar(not mapa.zona_peligro.is_empty(), "el botón Peligro la muestra en el mapa")
	main._alternar_peligro()

	print("Victoria por cuartel")
	await preparar(["H.......h", "F.......f"])
	mapa.crear_unidad("tanque", "azul", Vector2i(2, 1))
	mapa.crear_unidad("tanque", "rojo", Vector2i(6, 1))
	var inf := mapa.crear_unidad("infanteria", "azul", Vector2i(8, 0))
	reglas.capturar(inf)
	inf.reiniciar_turno()
	reglas.capturar(inf)
	await process_frame
	revisar(main.juego_terminado and "Unidades destruidas" in main.get_node("%EstadisticasFin").text, "capturar el cuartel gana y muestra estadísticas")
	main.juego_terminado = false
	main.hud.cerrar_todo()

	print("Niebla y emboscada")
	await preparar(["H..........h", "F..........f", "............"])
	var explorador := mapa.crear_unidad("tanque", "azul", Vector2i(2, 2))
	var escondido := mapa.crear_unidad("infanteria", "rojo", Vector2i(5, 2))
	var lejano := mapa.crear_unidad("tanque", "rojo", Vector2i(10, 2))
	mapa.niebla_activa = true
	mapa.actualizar_vision("azul")
	revisar(escondido.visible == false or mapa.distancia(explorador.celda, escondido.celda) <= 2, "el enemigo fuera de la vista no se ve")
	revisar(not lejano.visible and not mapa.explorado.has(Vector2i(10, 0)), "lo lejano está sin explorar")
	main.equipo_actual = "azul"
	explorador.reiniciar_turno()
	main.seleccionar(explorador)
	revisar(Vector2i(6, 2) in main.alcance["destinos"], "con niebla puedes intentar pasar por donde hay un enemigo escondido")
	main.mover(explorador, Vector2i(6, 2))
	await create_timer(0.6).timeout
	revisar(explorador.celda == Vector2i(4, 2) and explorador.ya_ataco, "emboscada: se detiene antes del enemigo y pierde el turno")
	mapa.actualizar_vision("azul")
	revisar(escondido.visible, "después de la emboscada el enemigo queda a la vista")
	mapa.niebla_activa = false
	mapa.actualizar_vision("azul")

	print("Cámara")
	main.modo_prueba = false
	main.nuevo_mapa(21)
	await create_timer(1.3).timeout
	var cam_antes: Vector2 = main.camara.position
	var vista := root.get_visible_rect().size
	await _arrastrar(Vector2(300, 150), Vector2(200, 150))
	revisar(main.camara.position.x > cam_antes.x, "arrastrar el dedo mueve el mapa")
	var una: Unidad = mapa.unidades_de("azul")[0]
	await main.enfocar(una)
	await _tocar(main.get_canvas_transform() * mapa.celda_a_pos(una.celda))
	revisar(main.seleccionada == una, "un toque corto sigue seleccionando")
	main.deseleccionar()
	revisar(mapa.ancho == 36 and mapa.alto == 20, "el mapa es de 36x20")

	print("Vista previa con botón Atacar")
	await preparar(["H..........h", "F..........f", "............", "............"])
	var yo := mapa.crear_unidad("tanque", "azul", Vector2i(3, 2))
	var r1 := mapa.crear_unidad("infanteria", "rojo", Vector2i(6, 2))
	var r2 := mapa.crear_unidad("infanteria", "rojo", Vector2i(6, 3))
	main.equipo_actual = "azul"
	main.deseleccionar()
	main.tocar_celda(yo.celda)
	main.tocar_celda(r1.celda)
	revisar(main.estado == main.Estado.PREVISION and main.menu.visible and r1.vida == 10, "un toque: vista previa con botón Atacar")
	main.tocar_celda(r2.celda)
	revisar(main._prevision["objetivo"] == r2, "tocar otro enemigo cambia la vista previa")
	main.tocar_celda(Vector2i(0, 3))
	revisar(main.estado == main.Estado.SELECCIONADA and main.seleccionada == yo, "tocar fuera cancela y deja la unidad seleccionada")
	main.tocar_celda(r1.celda)
	await main._confirmar_ataque()
	revisar(r1.vida < 10 or not is_instance_valid(r1), "el botón Atacar ataca")
	revisar(main.estado == main.Estado.LIBRE and not main.menu.visible, "y no queda nada abierto")

	print("Animaciones de habilidades")
	await preparar(["H..........h", "F..........f", "............", "............"])
	main.equipo_actual = "azul"
	reglas.creditos["azul"] = 50000
	var victima := mapa.crear_unidad("tanque", "rojo", Vector2i(6, 2))
	var propia := mapa.crear_unidad("tanque", "azul", Vector2i(2, 2))
	propia.vida = 4
	var vio_avion := [false]
	var revisar_avion := func():
		for h in mapa.get_children():
			if h is Sprite2D and not (h is Unidad) and h.z_index == 25:
				vio_avion[0] = true
	var inicio := Time.get_ticks_msec()
	var listo := [false]
	var bombardear := func():
		await main._bombardear(Vector2i(6, 2))
		listo[0] = true
	bombardear.call()
	var vida_al_ver_avion := -1
	while not listo[0]:
		revisar_avion.call()
		if vio_avion[0] and vida_al_ver_avion < 0:
			vida_al_ver_avion = victima.vida
		await process_frame
	revisar(vio_avion[0], "en el bombardeo aparece un avión")
	revisar(vida_al_ver_avion == 10, "el daño no llega antes de que caigan las bombas")
	revisar(victima.vida == 7, "después del avión, 3 de daño")
	revisar((Time.get_ticks_msec() - inicio) > 1000, "la animación dura más de un segundo")
	await main._reparar(propia.celda)
	revisar(propia.vida == 9, "reparar con animación da +5")
	main._usar_habilidad("marcha")
	await create_timer(0.8).timeout
	revisar(propia.bono_mov == 2 and main.estado == main.Estado.LIBRE, "marcha forzada con animación")
	main.hud.mostrar_aviso("prueba")
	await process_frame
	await process_frame
	main._alternar_peligro()
	await process_frame
	await process_frame
	var texto_aviso := ""
	for h in main.hud.get_children():
		if h is PanelContainer and h.get_child_count() > 0 and h.get_child(0) is Label and "peligro" in h.get_child(0).text.to_lower():
			texto_aviso = h.get_child(0).text
	revisar("enemigo te puede atacar" in texto_aviso, "al tocar Peligro aparece la explicación")
	main._alternar_peligro()

	print("Partidas completas en cada dificultad (con niebla)")
	Cinematica.activadas = false
	for dif in ["facil", "normal", "dificil"]:
		Config.dificultad = dif
		Config.niebla = true
		main.nuevo_mapa(100 + dif.length())
		await create_timer(1.2).timeout
		revisar(is_equal_approx(reglas.multiplicador_ingreso["rojo"], Datos.DIFICULTADES[dif]["ingreso"]), "%s: ingreso de la máquina x%.2f" % [dif, Datos.DIFICULTADES[dif]["ingreso"]])
		var turnos := 0
		for t in 25:
			if main.juego_terminado:
				break
			# El jugador avanza todo lo que puede hacia el enemigo y ataca si puede.
			for u in mapa.unidades_de("azul"):
				if not is_instance_valid(u) or main.juego_terminado:
					continue
				main.seleccionar(u)
				if not main.ataques_posibles.is_empty():
					var c: Vector2i = main.ataques_posibles.keys()[0]
					await main._mover_y_atacar(u, main.ataques_posibles[c], mapa.unidad_en(c))
				else:
					var destinos: Array = main.alcance["destinos"]
					var mejor: Vector2i = u.celda
					for d in destinos:
						if d.x > mejor.x and mapa.unidad_en(d) == null:
							mejor = d
					main.deseleccionar()
					if mejor != u.celda:
						await main.mover(u, mejor)
						main._cerrar_menu()
				main.deseleccionar()
			main.terminar_turno()
			while main.turno_ia or main.estado == main.Estado.MOVIENDO:
				await process_frame
			await create_timer(1.1).timeout
			turnos += 1
		print("    %s: %d turnos, azul %d unidades, rojo %d unidades, terminó: %s" % [dif, turnos,
			mapa.unidades_de("azul").size(), mapa.unidades_de("rojo").size(), main.juego_terminado])
		revisar(turnos >= 3, "%s: la partida corre sin errores" % dif)
		main.juego_terminado = false
		main.hud.cerrar_todo()
	Config.niebla = false
	Config.dificultad = "normal"

	print("\n%s" % ("TODO BIEN" if fallos == 0 else "%d FALLAS" % fallos))
	quit(fallos)


func _tocar(pos_juego: Vector2) -> void:
	var pos: Vector2 = root.get_final_transform() * pos_juego
	for presionado in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = presionado
		ev.position = pos
		ev.global_position = pos
		root.push_input(ev)
		await process_frame


func _arrastrar(desde: Vector2, hasta: Vector2) -> void:
	var t: Transform2D = root.get_final_transform()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = t * desde
	root.push_input(ev)
	await process_frame
	var pasos := 5
	for i in range(1, pasos + 1):
		var m := InputEventMouseMotion.new()
		m.position = t * desde.lerp(hasta, float(i) / pasos)
		m.relative = t.basis_xform((hasta - desde) / pasos)
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(m)
		await process_frame
	var fin := InputEventMouseButton.new()
	fin.button_index = MOUSE_BUTTON_LEFT
	fin.pressed = false
	fin.position = t * hasta
	root.push_input(fin)
	await process_frame
