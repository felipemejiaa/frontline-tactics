extends SceneTree
## Prueba automática de los ajustes finales: halo, área con confirmación, aviso al pasar turno,
## fichas en la tienda, defensa en edificios propios, Centro Urbano (capturar y destruir),
## base temporal y el truco del dinero.
## Ejecutar: godot --headless --path . --script res://tests/prueba_ajustes.gd

var fallos := 0
var main: Node
var mapa: GameMap
var reglas: Reglas


func revisar(condicion: bool, mensaje: String) -> void:
	print("  OK   " if condicion else "  FALLA ", mensaje)
	if not condicion:
		fallos += 1


func preparar(lineas: Array) -> void:
	main._cerrar_menu()
	main.deseleccionar()
	mapa.niebla_activa = false
	mapa.cargar_desde_texto(lineas)
	reglas.iniciar(mapa)
	main.equipo_actual = "azul"
	main.juego_terminado = false
	main.hud.cerrar_todo()
	await process_frame


func textos_menu() -> Array:
	var t := []
	for h in main.caja_menu.get_children():
		t.append(h.text)
	return t


func _initialize() -> void:
	Config.tutorial = false
	main = load("res://scenes/main.tscn").instantiate()
	main.modo_prueba = true
	root.add_child(main)
	await process_frame
	mapa = main.mapa
	reglas = main.reglas

	print("Halo en lo que se puede usar")
	await preparar(["H.......h", "F.......f", "........."])
	var a := mapa.crear_unidad("tanque", "azul", Vector2i(2, 2))
	var b := mapa.crear_unidad("infanteria", "azul", Vector2i(1, 2))
	mapa.crear_unidad("infanteria", "rojo", Vector2i(8, 2))
	reglas.marcar_lista(b)
	main._reloj_fin = 0.0
	await create_timer(0.3).timeout
	revisar(a.halo and not b.halo, "brilla la unidad que puede actuar, no la que ya actuó")
	revisar(mapa.puntos_compra.has(reglas.celda_compra("azul")), "la base brilla si alcanza para comprar")

	print("Aviso antes de pasar turno")
	main.modo_prueba = false
	main._pedir_terminar_turno()
	var t := " ".join(textos_menu())
	revisar("Aún tienes" in t and "1 unidad sin usar" in t, "avisa que quedan unidades sin usar: %s" % t)
	revisar("Terminar turno igual" in t and "Seguir jugando" in t, "deja elegir terminar igual o seguir")
	revisar(main.equipo_actual == "azul", "no pasa el turno sin confirmar")
	main._cerrar_menu()
	main.modo_prueba = true

	print("Fichas en la tienda")
	reglas.creditos["azul"] = 9000
	main._abrir_compra()
	main._menu_unidades()
	main._detalle_unidad("antiaerea")
	t = " ".join(textos_menu())
	revisar("Fuerte contra" in t and "Helicóptero" in t and "Débil contra" in t, "la ficha dice contra quién es fuerte y débil")
	revisar("Helicóptero 12 (18)" in t, "muestra el daño y el crítico contra cada unidad")
	revisar(mapa.unidades_de("azul").size() == 2, "ver la ficha no compra nada")
	main._detalle_habilidad("nuclear")
	t = " ".join(textos_menu())
	revisar("Centro: 10" in t and "Usar $15000" in t, "las habilidades también tienen ficha")
	main._cerrar_menu()

	print("Habilidades de área: ver el área y confirmar")
	await preparar(["H..........h", "F..........f", "............", "............", "............"])
	reglas.creditos["azul"] = 20000
	var e1 := mapa.crear_unidad("tanque", "rojo", Vector2i(6, 2))
	mapa.crear_unidad("infanteria", "azul", Vector2i(1, 4))
	main._usar_habilidad("bombardeo")
	main.tocar_celda(Vector2i(6, 2))
	revisar(main.estado == main.Estado.APUNTAR and main._celda_prevista == Vector2i(6, 2), "primer toque: muestra el área")
	revisar(main.resaltado.celdas.size() == 9 and main.resaltado.etiquetas.has(e1.celda), "se ven las 9 casillas y el daño sobre el enemigo")
	revisar(e1.vida == 10 and reglas.creditos["azul"] == 20000, "todavía no se lanza ni se cobra")
	main.tocar_celda(Vector2i(7, 3))
	revisar(main._celda_prevista == Vector2i(7, 3), "tocar otra casilla mueve el área")
	main.tocar_celda(Vector2i(7, 3))
	while main.estado == main.Estado.MOVIENDO or reglas.creditos["azul"] == 20000:
		await process_frame
	revisar(e1.vida == 7, "segundo toque en la misma casilla: lanza el bombardeo")

	print("Defensa en edificios propios")
	await preparar(["H.c.....h", "F.c.....f", "........."])
	mapa.cambiar_dueno(Vector2i(2, 0), "azul")
	var atacante := mapa.crear_unidad("tanque", "rojo", Vector2i(3, 0))
	var en_propia := mapa.crear_unidad("infanteria", "azul", Vector2i(2, 0))
	var en_neutral := mapa.crear_unidad("infanteria", "azul", Vector2i(2, 1))
	revisar(reglas.nivel_defensa(en_propia, en_propia.celda) == 4 and reglas.nivel_defensa(en_neutral, en_neutral.celda) == 2,
		"infantería en ciudad propia: defensa 2 + 2 de bono")
	var d_propia := reglas.calcular_dano(atacante, en_propia)
	mapa.mover_registro(atacante, Vector2i(3, 1))
	var d_neutral := reglas.calcular_dano(atacante, en_neutral)
	revisar(d_propia < d_neutral, "recibe menos daño en su ciudad (%d) que en una neutral (%d)" % [d_propia, d_neutral])
	var tanque_def := mapa.crear_unidad("tanque", "azul", Vector2i(0, 0))
	revisar(reglas.nivel_defensa(tanque_def, Vector2i(0, 0)) == 3 + 1, "un tanque en su Centro Urbano: 3 + 1")

	print("Centro Urbano: capturar en 3 turnos")
	await preparar(["H.......h", "F.......f"])
	mapa.crear_unidad("tanque", "rojo", Vector2i(6, 1))
	mapa.crear_unidad("tanque", "azul", Vector2i(2, 1))
	var inf := mapa.crear_unidad("infanteria", "azul", Vector2i(8, 0))
	for turno in 2:
		reglas.capturar(inf)
		inf.reiniciar_turno()
	revisar(not main.juego_terminado and mapa.dueno_en(Vector2i(8, 0)) == "rojo", "con 2 turnos no alcanza")
	reglas.capturar(inf)
	await process_frame
	revisar(main.juego_terminado, "al tercer turno lo captura y gana")

	print("Centro Urbano: destruirlo a golpes")
	await preparar(["H.......h", "F.......f", "........."])
	mapa.crear_unidad("tanque", "rojo", Vector2i(5, 2))
	var golpeador := mapa.crear_unidad("tanque", "azul", Vector2i(7, 0))
	revisar(reglas.puede_atacar_centro_desde(golpeador, golpeador.celda), "un tanque al lado puede golpearlo")
	main.equipo_actual = "azul"
	main.seleccionar(golpeador)
	revisar(main.ataques_posibles.has(Vector2i(8, 0)) and main.resaltado.etiquetas.has(Vector2i(8, 0)), "aparece marcado como blanco con su daño")
	main.deseleccionar()
	var golpes := 0
	while not main.juego_terminado and golpes < 20:
		golpeador.reiniciar_turno()
		reglas.atacar_centro(golpeador)
		golpes += 1
		await process_frame
	revisar(main.juego_terminado and golpes == 6, "destruirlo toma 6 golpes de tanque (%d)" % golpes)
	await preparar(["H.......h", "F.......f", "........."])
	mapa.crear_unidad("tanque", "rojo", Vector2i(8, 0))
	var g2 := mapa.crear_unidad("tanque", "azul", Vector2i(7, 0))
	revisar(not reglas.puede_atacar_centro_desde(g2, g2.celda), "con una unidad encima no se le puede pegar al edificio")

	print("Base temporal")
	await preparar(["H..c...h", "F..c...f", "........"])
	mapa.cambiar_dueno(Vector2i(3, 0), "azul")
	mapa.cambiar_dueno(Vector2i(3, 1), "azul")
	mapa.crear_unidad("infanteria", "rojo", Vector2i(0, 1))  # el rojo está capturando mi base
	mapa.crear_unidad("tanque", "azul", Vector2i(5, 2))
	reglas.creditos["azul"] = 5000
	var temporal := reglas.celda_compra("azul")
	revisar(temporal in [Vector2i(3, 0), Vector2i(3, 1)], "con la base ocupada por el enemigo, se compra en una ciudad propia")
	revisar(reglas.comprar("infanteria", "azul") and mapa.unidad_en(temporal) != null, "y la unidad aparece ahí")
	revisar(reglas.celda_compra("azul") != temporal, "si esa también se ocupa, se elige otra")

	print("Truco del dinero")
	await preparar(["H.......h", "F.......f"])
	mapa.crear_unidad("tanque", "rojo", Vector2i(6, 1))
	reglas.creditos["azul"] = 3500
	main._alternar_dinero_infinito()
	revisar(reglas.creditos["azul"] == Reglas.DINERO_TRUCO, "activado: dinero infinito")
	main._alternar_dinero_infinito()
	revisar(reglas.creditos["azul"] == 3500 and reglas.limite_poblacion("azul") < 99, "desactivado: vuelve al dinero de antes ($%d)" % reglas.creditos["azul"])

	print("\n%s" % ("TODO BIEN" if fallos == 0 else "%d FALLAS" % fallos))
	quit(fallos)
