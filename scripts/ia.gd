class_name IA
extends Node
## Inteligencia artificial del enemigo. Juega el turno completo de su equipo:
## por cada unidad, si le conviene atacar ataca; si no, avanza hacia su objetivo.
## Cómo juega depende de la dificultad (ver Datos.DIFICULTADES):
## - Fácil: gana menos dinero y a veces elige ataques al azar.
## - Difícil: concentra el fuego, retira a sus heridos a curarse, usa habilidades y construye torretas.
## La IA ve todo el mapa aunque haya niebla (hace "trampa" para que alcance el tiempo).

## Se emite cuando la IA decide atacar (ya se movió a la casilla desde donde ataca).
signal ataque_elegido(atacante: Unidad, objetivo: Unidad)

const PAUSA := 0.15  # segundos entre unidad y unidad, para que el jugador alcance a ver
const VIDA_PARA_RETIRARSE := 4

@export var equipo := "rojo"
var dificultad := "normal"

@onready var main: Node = get_parent()
@onready var mapa: GameMap = get_parent().get_node("GameMap")


func config() -> Dictionary:
	return Datos.DIFICULTADES[dificultad]


## Juega todas las unidades del equipo. Usar con: await ia.jugar_turno()
func jugar_turno() -> void:
	if config()["habilidades"]:
		await _usar_habilidades()
	for u in mapa.unidades_de(equipo):
		if not is_instance_valid(u) or u.ya_se_movio or main.juego_terminado:
			continue
		if main.has_method("enfocar"):
			await main.enfocar(u)
		await _jugar_unidad(u)
		await get_tree().create_timer(PAUSA).timeout
	# Se compra al final: así la base ya quedó libre si una unidad salió de ella.
	if not main.juego_terminado:
		_comprar_unidades()


func _jugar_unidad(u: Unidad) -> void:
	var alcance := mapa.calcular_alcance(u)
	var destinos: Array[Vector2i] = alcance["destinos"]
	var herida: bool = u.vida <= VIDA_PARA_RETIRARSE and u.datos()["movimiento"] > 0

	# 1. ¿Le conviene atacar a alguien este turno?
	var ataque := _elegir_ataque(u, destinos)
	var retirarse: bool = config()["retirada"] and herida and (ataque.is_empty() or not ataque["destruye"])
	if not ataque.is_empty() and not retirarse:
		await main.mover(u, ataque["desde"])
		if not is_instance_valid(u):
			return
		if ataque["objetivo"] is String:  # el Centro Urbano del jugador
			await main.atacar_centro_animado(u)
		elif is_instance_valid(ataque["objetivo"]):
			ataque_elegido.emit(u, ataque["objetivo"])
			await main.ejecutar_ataque(u, ataque["objetivo"])
		return

	# 2. Si no, avanzar (o retirarse a curarse si está muy herida en difícil).
	var destino := _mejor_retirada(u, destinos) if retirarse else _mejor_acercamiento(u, destinos)
	await main.mover(u, destino)
	# 3. Si terminó sobre un edificio que no es suyo, lo captura.
	if is_instance_valid(u) and main.reglas.puede_capturar(u):
		main.reglas.capturar(u)


# ---------------------------------------------------------------- ataque

## Elige el ataque. Usa la misma vista previa del daño que ve el jugador.
## Devuelve {} si no le conviene atacar a nadie.
func _elegir_ataque(u: Unidad, destinos: Array[Vector2i]) -> Dictionary:
	var opciones := []
	for objetivo in _enemigos_de(u):
		for desde in destinos:
			# La artillería solo ataca sin moverse (como en Advanced Wars).
			if u.datos()["rango_min"] > 1 and desde != u.celda:
				continue
			if not main.reglas.puede_atacar_desde(u, desde, objetivo):
				continue
			var est: Dictionary = main.reglas.estimar(u, objetivo, desde)
			opciones.append({"desde": desde, "objetivo": objetivo, "destruye": est["destruye"],
				"puntaje": _puntaje_ataque(u, objetivo, desde, est)})
	# Golpear el Centro Urbano del jugador si está vacío y al alcance.
	var centro: Vector2i = main.reglas.centro_rival(equipo)
	if mapa.en_mapa(centro):
		for desde in destinos:
			if u.datos()["rango_min"] > 1 and desde != u.celda:
				continue
			if main.reglas.puede_atacar_centro_desde(u, desde):
				var golpe: int = main.reglas.dano_estructura(u)
				var vida_c: int = main.reglas.vida_centro.get(_equipo_rival(), 99)
				opciones.append({"desde": desde, "objetivo": "centro", "destruye": golpe >= vida_c,
					"puntaje": golpe * 2.0 + 4.0 + (40.0 if golpe >= vida_c else 0.0)})
	if opciones.is_empty():
		return {}
	if randf() < config()["torpeza"]:
		return opciones.pick_random()
	opciones.sort_custom(func(a, b): return a["puntaje"] > b["puntaje"])
	# Un ataque muy malo (pierde mucho más de lo que hace) no vale la pena.
	return opciones[0] if opciones[0]["puntaje"] > -5 else {}


## Entre más alto, mejor ataque: hacer mucho daño, recibir poco, rematar (sobre todo veteranos),
## atacar desde terreno con defensa. En difícil le da todavía más valor a rematar.
func _puntaje_ataque(_u: Unidad, objetivo: Unidad, desde: Vector2i, est: Dictionary) -> float:
	var puntaje: float = est["dano"] * 2.0 - est["contra"] * 1.5
	if est["destruye"]:
		puntaje += 12.0 + objetivo.rango * 3.0
		if dificultad == "dificil":
			puntaje += 8.0
	if est["muere"]:
		puntaje -= 15.0
	if objetivo.datos().get("construccion", false):
		puntaje -= 3.0  # las torretas no se mueven: mejor pelear con lo que avanza
	puntaje += Datos.TERRENOS[mapa.terreno_en(desde)]["defensa"]
	return puntaje


# ---------------------------------------------------------------- movimiento

## Escoge la casilla alcanzable que queda más cerca (por camino real, no en línea recta)
## de su objetivo:
## - Infantería: edificios que no son suyos (ciudades para capturar y la base o cuartel enemigo).
## - Las demás: unidades enemigas.
func _mejor_acercamiento(u: Unidad, destinos: Array[Vector2i]) -> Vector2i:
	if u.datos()["movimiento"] == 0:
		return u.celda
	var objetivos: Array[Vector2i] = []
	if u.tipo == "infanteria":
		for c in mapa.duenos:
			if mapa.dueno_en(c) != equipo:
				var ocupante := mapa.unidad_en(c)
				if ocupante == null or ocupante == u:
					objetivos.append(c)
	if objetivos.is_empty():
		for e in _enemigos_de(u):
			objetivos.append(e.celda)
		var centro: Vector2i = main.reglas.centro_rival(equipo)
		if mapa.en_mapa(centro) and Datos.DANO_ESTRUCTURA.get(u.tipo, 0) > 0:
			objetivos.append(centro)
	return _mas_cercano_a(u, destinos, objetivos)


## Ir al edificio propio libre más cercano para curarse.
func _mejor_retirada(u: Unidad, destinos: Array[Vector2i]) -> Vector2i:
	var refugios: Array[Vector2i] = []
	for c in mapa.edificios_de(equipo):
		var ocupante := mapa.unidad_en(c)
		if ocupante == null or ocupante == u:
			refugios.append(c)
	return _mas_cercano_a(u, destinos, refugios) if not refugios.is_empty() else _mejor_acercamiento(u, destinos)


func _mas_cercano_a(u: Unidad, destinos: Array[Vector2i], objetivos: Array[Vector2i]) -> Vector2i:
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


# ---------------------------------------------------------------- compras

## Compra lo que le gana al tipo de enemigo más común; si le faltan soldados para capturar,
## compra infantería. En difícil construye una torreta si el jugador se acerca a su cuartel.
func _comprar_unidades() -> void:
	var reglas: Reglas = main.reglas
	var mias := mapa.unidades_de(equipo).size()
	var del_jugador := mapa.unidades_de(_equipo_rival()).size()
	var margen := 3 if dificultad == "dificil" else 1  # para que sea justo
	if mias >= config()["max_unidades"] or mias > del_jugador + margen - 1:
		return

	if dificultad == "dificil" and _cuartel_amenazado():
		var celdas := reglas.celdas_torreta(equipo)
		if not celdas.is_empty() and reglas.comprar("torreta", equipo, _celda_hacia_amenaza(celdas)):
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
	var infanteria_propia := 0
	for u in mapa.unidades_de(equipo):
		if u.tipo == "infanteria":
			infanteria_propia += 1
	var preferidos: Array = []
	if infanteria_propia < 2:
		preferidos.append("infanteria")
	for t in Datos.pierde_contra(mas_comun):
		if not Datos.UNIDADES[t].get("construccion", false):
			preferidos.append(t)
	preferidos.append_array(["tanque", "infanteria"])
	for t in preferidos:
		if reglas.comprar(t, equipo):
			return


func _cuartel_amenazado() -> bool:
	var cuartel := mapa.buscar_edificio("cuartel", equipo)
	for e in mapa.unidades_de(_equipo_rival()):
		if mapa.distancia(e.celda, cuartel) <= 6:
			return true
	return false


func _celda_hacia_amenaza(celdas: Array[Vector2i]) -> Vector2i:
	var mejor := celdas[0]
	var mejor_d := 9999
	for c in celdas:
		for e in mapa.unidades_de(_equipo_rival()):
			var d := mapa.distancia(c, e.celda)
			if d < mejor_d:
				mejor_d = d
				mejor = c
	return mejor


# ---------------------------------------------------------------- habilidades (difícil)

func _usar_habilidades() -> void:
	var reglas: Reglas = main.reglas
	# Bombardeo si hay un grupo de 2 o más unidades del jugador juntas.
	var mejor_centro := Vector2i(-1, -1)
	var mejor_cuenta := 1
	for e in mapa.unidades_de(_equipo_rival()):
		var cuenta := 0
		for otro in mapa.unidades_de(_equipo_rival()):
			if absi(otro.celda.x - e.celda.x) <= 1 and absi(otro.celda.y - e.celda.y) <= 1:
				cuenta += 1
		if cuenta > mejor_cuenta:
			mejor_cuenta = cuenta
			mejor_centro = e.celda
	if mejor_centro.x >= 0 and reglas.creditos[equipo] >= reglas.precio_habilidad("bombardeo", equipo) + 1000:
		if main.has_method("animar_bombardeo"):
			await main.animar_bombardeo(mejor_centro, equipo)
		reglas.usar_bombardeo(equipo, mejor_centro)
	# Bomba nuclear si tiene muchísimo dinero y 3 o más unidades del jugador juntas (sin propias cerca).
	if reglas.creditos[equipo] >= reglas.precio_habilidad("nuclear", equipo) + 2000:
		var mejor_nuke := Vector2i(-1, -1)
		var mejor_valor := 2
		for e in mapa.unidades_de(_equipo_rival()):
			var enemigos := 0
			var propias := 0
			for c in reglas.area_nuclear(e.celda):
				var u := mapa.unidad_en(c)
				if u != null:
					if u.equipo == equipo:
						propias += 1
					else:
						enemigos += 1
			if propias == 0 and enemigos > mejor_valor:
				mejor_valor = enemigos
				mejor_nuke = e.celda
		if mejor_nuke.x >= 0:
			if main.has_method("animar_nuclear"):
				await main.animar_nuclear(mejor_nuke)
			reglas.usar_nuclear(equipo, mejor_nuke)
	# Reparación a su unidad más valiosa si está muy herida.
	for u in mapa.unidades_de(equipo):
		if u.vida <= 4 and u.datos()["precio"] >= 2500 and reglas.creditos[equipo] >= reglas.precio_habilidad("reparacion", equipo) + 1000:
			if main.has_method("animar_reparacion") and mapa.se_ve(u.celda):
				await main.animar_reparacion(u)
			reglas.usar_reparacion(equipo, u)
			break


func _enemigos_de(u: Unidad) -> Array[Unidad]:
	return mapa.unidades_de(_equipo_rival() if u.equipo == equipo else equipo)


func _equipo_rival() -> String:
	return "azul" if equipo == "rojo" else "rojo"
