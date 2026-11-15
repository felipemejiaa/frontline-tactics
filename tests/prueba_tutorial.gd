extends SceneTree
## Prueba automática del tutorial: lo juega completo, como lo haría una persona.
## Ejecutar: godot --headless --path . --script res://tests/prueba_tutorial.gd

var fallos := 0


func revisar(condicion: bool, mensaje: String) -> void:
	print("  OK   " if condicion else "  FALLA ", mensaje)
	if not condicion:
		fallos += 1


func esperar_quieto(main: Node) -> void:
	await process_frame
	while main.estado == main.Estado.MOVIENDO or main.turno_ia:
		await process_frame
	await create_timer(0.2).timeout


func _initialize() -> void:
	Config.tutorial = true
	Cinematica.activadas = false
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	await create_timer(1.3).timeout
	var t: Tutorial = main.tutorial
	revisar(t != null and t.paso == 0, "Cómo jugar abre el tutorial en el paso 1")
	revisar("TANQUE" in t._texto.text and t._flecha.get_parent() != null, "dice qué tocar y una flecha lo señala")
	revisar(main.mapa.ancho == 12, "usa su propio mapa pequeño")

	main.tocar_celda(t._tanque.celda)
	revisar(t.paso == 1, "paso 2: después de tocar el tanque")
	revisar(main.ataques_posibles.has(Tutorial.POS_ENEMIGO), "el enemigo está al alcance para el primer ataque")
	main.tocar_celda(Tutorial.POS_ENEMIGO)
	await esperar_quieto(main)
	revisar(t.paso == 2, "paso 3: después de atacar")

	main.tocar_celda(t._infanteria.celda)
	revisar(Tutorial.CIUDAD in main.alcance["destinos"], "la infantería alcanza la ciudad")
	main.tocar_celda(Tutorial.CIUDAD)
	await esperar_quieto(main)
	revisar(t.paso == 3, "paso 4: la infantería llegó a la ciudad")
	var boton_capturar: Button = null
	for b in main.caja_menu.get_children():
		if b is Button and b.text.begins_with("Capturar"):
			boton_capturar = b
	revisar(boton_capturar != null, "aparece el botón Capturar")
	boton_capturar.pressed.emit()
	revisar(t.paso == 4, "paso 5: después de empezar la captura")

	main.hud.get_node("%BotonTienda").pressed.emit()
	await process_frame
	revisar(t.paso == 5, "paso 6: la tienda está abierta")
	main._menu_unidades()
	main._detalle_unidad("infanteria")
	var comprar: Button = null
	for b in main.caja_menu.get_children():
		if b is Button and b.text.begins_with("Comprar"):
			comprar = b
	revisar(comprar != null and not comprar.disabled, "la ficha tiene el botón Comprar")
	comprar.pressed.emit()
	revisar(t.paso == 6, "paso 7: después de comprar")

	var rojos_antes := {}
	for u in main.mapa.unidades_de("rojo"):
		rojos_antes[u] = u.celda
	main.hud.get_node("%BotonTerminar").pressed.emit()
	await esperar_quieto(main)
	await create_timer(1.3).timeout
	revisar(t.paso == 7, "paso 8: volvió el turno del jugador")
	var quietos := true
	for u in rojos_antes:
		if is_instance_valid(u) and u.celda != rojos_antes[u]:
			quietos = false
	revisar(quietos, "en el tutorial el rojo no se mueve")

	main.tocar_celda(t._infanteria.celda)
	main.tocar_celda(t._infanteria.celda)
	await process_frame
	for b in main.caja_menu.get_children():
		if b is Button and b.text.begins_with("Capturar"):
			b.pressed.emit()
	await process_frame
	revisar(main.mapa.dueno_en(Tutorial.CIUDAD) == "azul", "la ciudad quedó capturada")
	revisar(t.paso == 8, "último paso: cómo ganar")
	var textos := []
	for b in t._botones.get_children():
		textos.append(b.text)
	revisar("Jugar una partida" in textos and "Menú principal" in textos, "al final ofrece jugar o volver al menú")

	print("\n%s" % ("TODO BIEN" if fallos == 0 else "%d FALLAS" % fallos))
	quit(fallos)
