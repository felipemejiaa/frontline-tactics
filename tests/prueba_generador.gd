extends SceneTree
## Prueba automática del generador de mapas: genera muchos mapas y revisa que todos sirvan.
## Ejecutar: godot --headless --path . --script res://tests/prueba_generador.gd

const CUANTOS := 60
var fallos := 0


func revisar(condicion: bool, mensaje: String) -> void:
	if not condicion:
		print("  FALLA ", mensaje)
		fallos += 1


func _initialize() -> void:
	var distintos := {}
	var total_ciudades := 0
	for semilla in CUANTOS:
		var res := GeneradorMapa.new().generar(semilla)
		revisar(not res.is_empty(), "semilla %d: se generó" % semilla)
		if res.is_empty():
			continue
		var lineas: Array = res["lineas"]
		distintos["\n".join(lineas)] = true
		revisar(lineas.size() == GeneradorMapa.ALTO, "semilla %d: alto" % semilla)
		var mapa := GameMap.new()
		mapa.cargar_desde_texto(lineas)
		revisar(mapa.ancho == GeneradorMapa.ANCHO, "semilla %d: ancho" % semilla)
		for equipo in ["azul", "rojo"]:
			revisar(mapa.buscar_edificio("cuartel", equipo).x >= 0, "semilla %d: cuartel %s" % [semilla, equipo])
			revisar(mapa.buscar_edificio("base", equipo).x >= 0, "semilla %d: base %s" % [semilla, equipo])
		var ciudades := mapa.edificios_de("neutral").size()
		total_ciudades += ciudades
		revisar(ciudades >= 6, "semilla %d: al menos 6 ciudades (hay %d)" % [semilla, ciudades])

		# Simetría
		for y in mapa.alto:
			for x in mapa.ancho:
				var a := mapa.terreno_en(Vector2i(x, y))
				var b := mapa.terreno_en(Vector2i(mapa.ancho - 1 - x, y))
				if a != b:
					revisar(false, "semilla %d: no es simétrico en (%d,%d)" % [semilla, x, y])

		# Unidades: 3 por bando, en terreno válido y sin repetir casilla
		var unidades: Array = res["unidades"]
		revisar(unidades.size() == 6, "semilla %d: 6 unidades" % semilla)
		var usadas := {}
		for u in unidades:
			var costo: int = Datos.UNIDADES[u["tipo"]]["costo_terreno"][mapa.terreno_en(u["celda"])]
			revisar(costo >= 0, "semilla %d: %s en terreno válido" % [semilla, u["tipo"]])
			revisar(not usadas.has(u["celda"]), "semilla %d: casilla repetida" % semilla)
			revisar(mapa.dueno_en(u["celda"]) == "", "semilla %d: unidad encima de un edificio" % semilla)
			usadas[u["celda"]] = true

		# Un tanque puede llegar desde la base azul hasta el cuartel rojo
		revisar(_tanque_llega(mapa, mapa.buscar_edificio("base", "azul"), mapa.buscar_edificio("cuartel", "rojo")),
			"semilla %d: hay camino al cuartel rojo" % semilla)
		mapa.free()

	print("Mapas distintos: %d de %d   ciudades promedio: %.1f" % [distintos.size(), CUANTOS, float(total_ciudades) / CUANTOS])
	revisar(distintos.size() == CUANTOS, "todos los mapas son distintos")
	var a := GeneradorMapa.new().generar(1234)
	var b := GeneradorMapa.new().generar(1234)
	revisar(a["lineas"] == b["lineas"], "la misma semilla da el mismo mapa")

	print("\n%s" % ("TODO BIEN" if fallos == 0 else "%d FALLAS" % fallos))
	quit(fallos)


func _tanque_llega(mapa: GameMap, desde: Vector2i, hasta: Vector2i) -> bool:
	var costos: Dictionary = Datos.UNIDADES["tanque"]["costo_terreno"]
	var vistas := {desde: true}
	var cola: Array[Vector2i] = [desde]
	while not cola.is_empty():
		var c: Vector2i = cola.pop_front()
		if c == hasta:
			return true
		for d in GameMap.DIRECCIONES:
			var v: Vector2i = c + d
			if mapa.en_mapa(v) and not vistas.has(v) and costos[mapa.terreno_en(v)] >= 0:
				vistas[v] = true
				cola.append(v)
	return false
