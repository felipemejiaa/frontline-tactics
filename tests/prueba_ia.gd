extends SceneTree
## Prueba automática de la IA.
## Ejecutar: godot --headless --path . --script res://tests/prueba_ia.gd

var fallos := 0
var ataques: Array = []


func revisar(condicion: bool, mensaje: String) -> void:
	print("  OK   " if condicion else "  FALLA ", mensaje)
	if not condicion:
		fallos += 1


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var mapa: GameMap = main.mapa
	var ia: IA = main.ia
	ia.ataque_elegido.connect(func(a, o): ataques.append([a, o]))

	print("Acercamiento")
	var antes := {}
	for u in mapa.unidades_de("rojo"):
		antes[u] = _dist_al_azul_mas_cercano(mapa, u.celda)
	main.terminar_turno()
	while main.turno_ia:
		await process_frame
	var se_acercaron := 0
	for u in mapa.unidades_de("rojo"):
		var costo: int = u.datos()["costo_terreno"][mapa.terreno_en(u.celda)]
		revisar(costo >= 0, "%s rojo terminó en terreno válido %s" % [u.tipo, u.celda])
		if _dist_al_azul_mas_cercano(mapa, u.celda) < antes[u]:
			se_acercaron += 1
	revisar(se_acercaron >= 2, "las unidades rojas se acercaron al jugador (%d de 3)" % se_acercaron)
	revisar(mapa.unidades.size() == 6, "no se perdió ni se duplicó ninguna unidad")
	revisar(main.equipo_actual == "azul", "el turno volvió al jugador")

	print("Ataque")
	# Poner una infantería azul justo al lado del tanque rojo: el tanque le gana, debe atacarla.
	var tanque_rojo: Unidad = null
	for u in mapa.unidades_de("rojo"):
		if u.tipo == "tanque":
			tanque_rojo = u
	var celda_victima := Vector2i(-1, -1)
	for dir in GameMap.DIRECCIONES:
		var c: Vector2i = tanque_rojo.celda + dir
		if mapa.en_mapa(c) and mapa.unidad_en(c) == null and mapa.terreno_en(c) in ["llanura", "bosque"]:
			celda_victima = c
			break
	var victima := mapa.crear_unidad("infanteria", "azul", celda_victima)
	ataques.clear()
	main.terminar_turno()
	while main.turno_ia:
		await process_frame
	var ataco_al_tanque := false
	for par in ataques:
		if par[0] == tanque_rojo and par[1] == victima:
			ataco_al_tanque = true
			revisar(mapa.distancia(tanque_rojo.celda, victima.celda) == 1, "atacó desde una casilla vecina")
	revisar(ataco_al_tanque, "el tanque rojo eligió atacar a la infantería")

	print("\n%s" % ("TODO BIEN" if fallos == 0 else "%d FALLAS" % fallos))
	quit(fallos)


func _dist_al_azul_mas_cercano(mapa: GameMap, celda: Vector2i) -> int:
	var mejor := 9999
	for u in mapa.unidades_de("azul"):
		mejor = mini(mejor, mapa.distancia(celda, u.celda))
	return mejor
