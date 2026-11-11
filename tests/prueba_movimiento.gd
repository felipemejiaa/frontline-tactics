extends SceneTree
## Prueba automática del mapa y el movimiento.
## Ejecutar: godot --headless --path . --script res://tests/prueba_movimiento.gd

var fallos := 0


func revisar(condicion: bool, mensaje: String) -> void:
	if condicion:
		print("  OK   ", mensaje)
	else:
		print("  FALLA ", mensaje)
		fallos += 1


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var mapa: GameMap = main.mapa

	print("Mapa")
	for fila in GameMap.MAPA:
		revisar(fila.length() == mapa.ancho, "fila de %d casillas" % fila.length())
	revisar(mapa.buscar_edificio("cuartel", "azul") != Vector2i(-1, -1), "hay cuartel azul")
	revisar(mapa.buscar_edificio("cuartel", "rojo") != Vector2i(-1, -1), "hay cuartel rojo")
	for u in mapa.unidades.values():
		var costo: int = u.datos()["costo_terreno"][mapa.terreno_en(u.celda)]
		revisar(costo >= 0, "%s %s empieza en terreno válido %s" % [u.tipo, u.equipo, u.celda])

	print("Alcance")
	var tanque: Unidad = mapa.unidad_en(Vector2i(3, 2))
	var alc := mapa.calcular_alcance(tanque)
	var destinos: Array[Vector2i] = alc["destinos"]
	revisar(tanque.celda in destinos, "puede quedarse en su sitio")
	var montanas_ok := true
	var rango_ok := true
	for c in destinos:
		if mapa.terreno_en(c) in ["montana", "agua"]:
			montanas_ok = false
		if mapa.distancia(c, tanque.celda) > 5:
			rango_ok = false
		var camino := mapa.camino_hasta(alc, c)
		var gasto := 0
		for paso in camino:
			gasto += tanque.datos()["costo_terreno"][mapa.terreno_en(paso)]
		if gasto > 5:
			rango_ok = false
	revisar(montanas_ok, "el tanque no entra a montaña ni agua")
	revisar(rango_ok, "ningún camino gasta más de 5 de movimiento")

	var inf: Unidad = mapa.unidad_en(Vector2i(2, 4))
	var alc_inf := mapa.calcular_alcance(inf)
	revisar(not (Vector2i(3, 2) in alc_inf["destinos"]), "no puede terminar encima de un aliado")

	# Un enemigo bloquea el paso
	var bloqueador := mapa.crear_unidad("infanteria", "rojo", Vector2i(3, 4))
	var alc_bloq := mapa.calcular_alcance(inf)
	revisar(not (Vector2i(3, 4) in alc_bloq["destinos"]), "no puede entrar a la casilla de un enemigo")
	mapa.eliminar_unidad(bloqueador)
	await process_frame

	print("Toques")
	main.tocar_celda(Vector2i(2, 4))
	revisar(main.seleccionada == inf, "tocar la infantería la selecciona")
	main.tocar_celda(Vector2i(4, 5))
	revisar(main.estado == main.Estado.MOVIENDO, "tocar una casilla válida empieza a moverla")
	await create_timer(1.0).timeout
	revisar(inf.celda == Vector2i(4, 5) and mapa.unidad_en(Vector2i(4, 5)) == inf, "llegó a (4,5)")
	revisar(inf.position == mapa.celda_a_pos(Vector2i(4, 5)), "la animación terminó en el lugar correcto")
	revisar(inf.ya_se_movio, "queda marcada como movida")
	main.tocar_celda(Vector2i(4, 5))
	main.tocar_celda(Vector2i(5, 5))
	await create_timer(0.5).timeout
	revisar(inf.celda == Vector2i(4, 5), "no se puede mover dos veces en el mismo turno")
	main.deseleccionar()

	main.tocar_celda(Vector2i(12, 2))
	main.tocar_celda(Vector2i(11, 2))
	await create_timer(0.5).timeout
	revisar(mapa.unidad_en(Vector2i(12, 2)) != null, "no puede mover unidades enemigas")
	main.deseleccionar()

	main.terminar_turno()
	revisar(main.equipo_actual == "rojo" and main.turno_ia, "terminar turno pasa a la máquina")
	main.tocar_celda(Vector2i(4, 5))
	revisar(main.seleccionada == null, "durante el turno de la máquina se ignoran los toques")
	while main.turno_ia:
		await process_frame
	revisar(main.equipo_actual == "azul", "después de la IA vuelve el turno al azul")
	revisar(not inf.ya_se_movio, "al volver el turno la unidad se puede mover otra vez")

	print("\n%s" % ("TODO BIEN" if fallos == 0 else "%d FALLAS" % fallos))
	quit(fallos)
