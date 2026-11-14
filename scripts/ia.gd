class_name IA
extends Node
## Inteligencia artificial del enemigo. Juega el turno completo de su equipo:
## por cada unidad, si puede atacar a alguien ataca; si no, se acerca al objetivo más cercano.

## Se emite cuando la IA decide atacar (ya se movió a la casilla desde donde ataca).
## Persona 1: conectar esta señal a la función de combate.
signal ataque_elegido(atacante: Unidad, objetivo: Unidad)

const PAUSA := 0.25  # segundos entre unidad y unidad, para que el jugador alcance a ver
const MAX_UNIDADES := 8  # la IA no compra más si ya tiene tantas

@export var equipo := "rojo"

@onready var main: Node = get_parent()
@onready var mapa: GameMap = get_parent().get_node("GameMap")


## Juega todas las unidades del equipo. Usar con: await ia.jugar_turno()
func jugar_turno() -> void:
	for u in mapa.unidades_de(equipo):
		if not is_instance_valid(u) or u.ya_se_movio:
			continue
		await _jugar_unidad(u)
		await get_tree().create_timer(PAUSA).timeout
	# Se compra al final: así la base ya quedó libre si una unidad salió de ella.
	_comprar_unidad()


func _jugar_unidad(u: Unidad) -> void:
	var alcance := mapa.calcular_alcance(u)
	var destinos: Array[Vector2i] = alcance["destinos"]

	# 1. ¿Puede atacar a alguien este turno?
	var ataque := _mejor_ataque(u, destinos)
	if not ataque.is_empty():
		await main.mover(u, ataque["desde"])
		ataque_elegido.emit(u, ataque["objetivo"])
		return

	# 2. Si no, acercarse lo más posible al objetivo más cercano.
	var destino := _mejor_acercamiento(u, destinos)
	await main.mover(u, destino)
	# 3. Si terminó sobre un edificio que no es suyo, lo captura.
	if is_instance_valid(u) and main.reglas.puede_capturar(u):
		main.reglas.capturar(u)


## Compra una unidad: la que le gana al tipo de enemigo más común; si no alcanza, infantería.
func _comprar_unidad() -> void:
	if mapa.unidades_de(equipo).size() >= MAX_UNIDADES:
		return
	var conteo := {}
	for r in mapa.unidades_de(_equipo_rival()):
		conteo[r.tipo] = conteo.get(r.tipo, 0) + 1
	var mas_comun := ""
	var cantidad := 0
	for t in conteo:
		if conteo[t] > cantidad:
			cantidad = conteo[t]
			mas_comun = t
	var preferidos: Array[String] = []
	for t in Datos.LE_GANA_A:
		if Datos.LE_GANA_A[t] == mas_comun:
			preferidos.append(t)
	preferidos.append("infanteria")
	for t in preferidos:
		if main.reglas.comprar(t, equipo):
			return


## Busca la mejor combinación (casilla desde donde atacar, enemigo a atacar).
## Devuelve {} si no puede atacar a nadie.
func _mejor_ataque(u: Unidad, destinos: Array[Vector2i]) -> Dictionary:
	var datos := u.datos()
	var mejor := {}
	var mejor_puntaje := -INF
	for objetivo in _enemigos_de(u):
		for desde in destinos:
			# La artillería solo ataca sin moverse (como en Advanced Wars).
			if datos["rango_min"] > 1 and desde != u.celda:
				continue
			var d := mapa.distancia(desde, objetivo.celda)
			if d < datos["rango_min"] or d > datos["rango_max"]:
				continue
			var puntaje := _puntaje_ataque(u, objetivo, desde)
			if puntaje > mejor_puntaje:
				mejor_puntaje = puntaje
				mejor = {"desde": desde, "objetivo": objetivo}
	return mejor


## Entre más alto, mejor ataque. Prefiere: ganarle en piedra-papel-tijera,
## rematar enemigos débiles y atacar desde terreno con defensa.
func _puntaje_ataque(u: Unidad, objetivo: Unidad, desde: Vector2i) -> float:
	var puntaje := 0.0
	if Datos.LE_GANA_A[u.tipo] == objetivo.tipo:
		puntaje += 10
	if Datos.LE_GANA_A[objetivo.tipo] == u.tipo:
		puntaje -= 6
	puntaje += (10 - objetivo.vida)  # rematar
	puntaje += Datos.TERRENOS[mapa.terreno_en(desde)]["defensa"]
	return puntaje


## Escoge la casilla alcanzable que queda más cerca (por camino real, no en línea recta)
## de su objetivo:
## - Infantería: edificios que no son suyos (ciudades para capturar y el cuartel enemigo).
## - Tanques y artillería: unidades enemigas.
func _mejor_acercamiento(u: Unidad, destinos: Array[Vector2i]) -> Vector2i:
	var objetivos: Array[Vector2i] = []
	if u.tipo == "infanteria":
		for c in mapa.duenos:
			if mapa.dueno_en(c) != equipo and mapa.terreno_en(c) != "base":
				var ocupante := mapa.unidad_en(c)
				if ocupante == null or ocupante == u:
					objetivos.append(c)
	if objetivos.is_empty():
		for e in _enemigos_de(u):
			objetivos.append(e.celda)
	if objetivos.is_empty():
		return u.celda

	var distancias := _distancias_desde(objetivos, u)
	var mejor := u.celda
	var mejor_dist: int = distancias.get(u.celda, 9999)
	for c in destinos:
		var d: int = distancias.get(c, 9999)
		if d < mejor_dist:
			mejor_dist = d
			mejor = c
	return mejor


## Mapa de "qué tan lejos está cada casilla de los objetivos" para el tipo de unidad u,
## teniendo en cuenta el terreno (ej. rodear montañas y agua). Ignora las otras unidades.
func _distancias_desde(objetivos: Array[Vector2i], u: Unidad) -> Dictionary:
	var costos_terreno: Dictionary = u.datos()["costo_terreno"]
	var dist := {}
	var pendientes: Array[Vector2i] = []
	for o in objetivos:
		dist[o] = 0
		pendientes.append(o)
	while not pendientes.is_empty():
		var idx := 0
		for i in range(1, pendientes.size()):
			if dist[pendientes[i]] < dist[pendientes[idx]]:
				idx = i
		var actual: Vector2i = pendientes.pop_at(idx)
		for dir in GameMap.DIRECCIONES:
			var vecino: Vector2i = actual + dir
			if not mapa.en_mapa(vecino):
				continue
			var paso: int = costos_terreno[mapa.terreno_en(vecino)]
			if paso < 0:
				continue
			var nuevo: int = dist[actual] + paso
			if not dist.has(vecino) or nuevo < dist[vecino]:
				dist[vecino] = nuevo
				if not pendientes.has(vecino):
					pendientes.append(vecino)
	return dist


func _enemigos_de(u: Unidad) -> Array[Unidad]:
	return mapa.unidades_de(_equipo_rival() if u.equipo == equipo else equipo)


func _equipo_rival() -> String:
	return "azul" if equipo == "rojo" else "rojo"
