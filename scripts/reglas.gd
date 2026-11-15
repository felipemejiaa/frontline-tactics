class_name Reglas
extends Node
## Reglas del juego: créditos, compra, combate, captura, curación, habilidades y victoria.
## (Persona 1; ampliado con población, veteranía, flanqueo, habilidades y estadísticas.)
## Los turnos los sigue manejando main.gd; este nodo solo avisa y calcula.

signal creditos_cambiados(equipo: String, cantidad: int)
signal unidad_atacada(atacante: Unidad, objetivo: Unidad, dano: int, critico: bool)
signal unidad_danada(objetivo: Unidad, dano: int)      # daño que no viene de un ataque (bombardeo)
signal unidad_curada(unidad: Unidad, cantidad: int)
signal ciudad_capturada(celda: Vector2i, equipo: String)
signal habilidad_usada(nombre: String, equipo: String)
signal partida_terminada(ganador: String)

# ---- Valores que puedes ajustar ----
const EQUIPOS := ["azul", "rojo"]
const CREDITOS_INICIALES := 2000
const DEFENSA_POR_NIVEL := 0.1  # cada nivel de defensa del terreno quita 10 %
const BONO_FLANQUEO := 0.15     # +15 % por cada aliado pegado al objetivo
const BONO_RANGO := 0.1         # +10 % por cada estrella de veteranía
const PUNTOS_PARA_CAPTURAR := 20
const SUERTE := 1               # el daño real varía entre -1 y +1 del estimado
const PROB_CRITICO := 0.10      # 10 % de probabilidad de golpe crítico...
const CRITICO_POR_RANGO := 0.05 # ...+5 % por cada estrella de veteranía
const MULT_CRITICO := 1.5       # un crítico hace 50 % más de daño
const TIPOS_EDIFICIO := ["cuartel", "base", "ciudad"]

var mapa: GameMap
var creditos := {}
var terminada := false
## Lo que gana cada equipo se multiplica por esto (la dificultad cambia el de la máquina).
var multiplicador_ingreso := {"azul": 1.0, "rojo": 1.0}
## Estadísticas para la pantalla final.
var estadisticas := {}
## Veces que cada equipo usó cada habilidad (el precio sube).
var usos_habilidad := {}
## Equipos con el radar activo este turno.
var radar_activo := {}
## Truco de la expo: el jugador (azul) tiene dinero y población sin límite.
## Es "static" para que siga activo aunque se empiece otra partida.
static var dinero_infinito := false
const DINERO_TRUCO := 999999
var _captura := {}    # celda -> puntos acumulados
var _cuarteles := {}  # equipo -> celda de su cuartel general


func iniciar(mapa_ref: GameMap) -> void:
	mapa = mapa_ref
	terminada = false
	_captura.clear()
	mapa.progreso_captura.clear()
	_cuarteles.clear()
	radar_activo.clear()
	for e in EQUIPOS:
		creditos[e] = CREDITOS_INICIALES
		_cuarteles[e] = mapa.buscar_edificio("cuartel", e)
		estadisticas[e] = {"destruidas": 0, "perdidas": 0, "capturadas": 0, "compradas": 0,
			"gastado": 0, "habilidades": 0}
		usos_habilidad[e] = {}
		creditos_cambiados.emit(e, creditos[e])
	aplicar_dinero_infinito()


func aplicar_dinero_infinito() -> void:
	if dinero_infinito and creditos.has("azul"):
		creditos["azul"] = DINERO_TRUCO
		creditos_cambiados.emit("azul", creditos["azul"])


func otro_equipo(equipo: String) -> String:
	return "rojo" if equipo == "azul" else "azul"


# ---------------- TURNOS Y CRÉDITOS ----------------
## main.gd lo llama cuando empieza el turno de un equipo: cobra y cura.
func al_empezar_turno(equipo: String) -> void:
	radar_activo.erase(equipo)
	_sumar_creditos(equipo, ingreso_de(equipo))
	for u in mapa.unidades_de(equipo):
		var en_edificio_propio := mapa.dueno_en(u.celda) == equipo
		var max_vida: int = u.datos()["vida_max"]
		if en_edificio_propio and u.vida < max_vida:
			var cura := mini(Datos.CURACION, max_vida - u.vida)
			u.vida += cura
			unidad_curada.emit(u, cura)


func ingreso_de(equipo: String) -> int:
	return int(mapa.ingreso_de(equipo) * multiplicador_ingreso.get(equipo, 1.0))


func celda_base(equipo: String) -> Vector2i:
	return mapa.buscar_edificio("base", equipo)


func _sumar_creditos(equipo: String, cantidad: int) -> void:
	creditos[equipo] += cantidad
	if dinero_infinito and equipo == "azul":
		creditos[equipo] = DINERO_TRUCO
	creditos_cambiados.emit(equipo, creditos[equipo])


# ---------------- POBLACIÓN Y COMPRA ----------------
func limite_poblacion(equipo: String) -> int:
	if dinero_infinito and equipo == "azul":
		return 99
	return Datos.POBLACION_BASE + mapa.edificios_de(equipo).size()


func poblacion(equipo: String) -> int:
	return mapa.unidades_de(equipo).size()


## Devuelve "" si se puede comprar, o el motivo por el que no.
func motivo_no_compra(tipo: String, equipo: String) -> String:
	if terminada:
		return "La partida terminó"
	if creditos[equipo] < Datos.UNIDADES[tipo]["precio"]:
		return "Sin créditos"
	if poblacion(equipo) >= limite_poblacion(equipo):
		return "Población llena"
	if Datos.UNIDADES[tipo].get("construccion", false):
		return "" if not celdas_torreta(equipo).is_empty() else "Sin espacio junto al cuartel"
	var base := celda_base(equipo)
	if not mapa.en_mapa(base):
		return "Perdiste tu base"
	if mapa.unidad_en(base) != null:
		return "Base ocupada"
	return ""


## Casillas libres cerca del cuartel general donde se puede construir una torreta.
func celdas_torreta(equipo: String) -> Array[Vector2i]:
	var lista: Array[Vector2i] = []
	var cuartel := mapa.buscar_edificio("cuartel", equipo)
	if not mapa.en_mapa(cuartel):
		return lista
	var r := Datos.DISTANCIA_TORRETA
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := cuartel + Vector2i(dx, dy)
			if c == cuartel or absi(dx) + absi(dy) > r or not mapa.en_mapa(c):
				continue
			if mapa.unidad_en(c) == null and mapa.dueno_en(c) == "" and mapa.terreno_en(c) in ["llanura", "bosque"]:
				lista.append(c)
	return lista


## Compra una unidad. Normalmente aparece en la base; la torreta, en la casilla indicada.
func comprar(tipo: String, equipo: String, celda := Vector2i(-1, -1)) -> bool:
	if motivo_no_compra(tipo, equipo) != "":
		return false
	var destino := celda_base(equipo)
	if Datos.UNIDADES[tipo].get("construccion", false):
		if not celda in celdas_torreta(equipo):
			return false
		destino = celda
	var precio: int = Datos.UNIDADES[tipo]["precio"]
	var nueva := mapa.crear_unidad(tipo, equipo, destino)
	_sumar_creditos(equipo, -precio)
	estadisticas[equipo]["compradas"] += 1
	estadisticas[equipo]["gastado"] += precio
	marcar_lista(nueva)  # una unidad recién comprada no actúa ese turno
	return true


# ---------------- COMBATE ----------------
func puede_atacar(atacante: Unidad, objetivo: Unidad) -> bool:
	return puede_atacar_desde(atacante, atacante.celda, objetivo)


## ¿Podría atacar si estuviera en la casilla "desde"?
func puede_atacar_desde(atacante: Unidad, desde: Vector2i, objetivo: Unidad) -> bool:
	if atacante.equipo == objetivo.equipo:
		return false
	var datos := atacante.datos()
	if Datos.dano_base(atacante.tipo, objetivo.tipo) <= 0:
		return false  # según la tabla de daño, no lo puede atacar (ej. artillería contra helicóptero)
	var d: int = mapa.distancia(desde, objetivo.celda)
	return d >= datos["rango_min"] and d <= datos["rango_max"]


## Enemigos que la unidad puede atacar desde donde está.
func objetivos_de(u: Unidad) -> Array[Unidad]:
	var lista: Array[Unidad] = []
	if u.ya_ataco:
		return lista
	for e in mapa.unidades_de(otro_equipo(u.equipo)):
		if puede_atacar(u, e):
			lista.append(e)
	return lista


func calcular_dano(atacante: Unidad, objetivo: Unidad) -> int:
	return _dano(atacante, atacante.vida, atacante.celda, objetivo, objetivo.celda)


## Fórmula del daño. Se separa la vida y la casilla del atacante para poder
## estimar "qué pasaría si me muevo allá" sin mover nada.
func _dano(atacante: Unidad, vida_atacante: int, celda_atacante: Vector2i,
		objetivo: Unidad, celda_objetivo: Vector2i) -> int:
	var vida_max_obj: float = objetivo.datos()["vida_max"]
	var fuerza: float = float(vida_atacante) / float(atacante.datos()["vida_max"])
	# Daño base de la tabla de Advanced Wars (ver Datos.DANO_BASE).
	var mult := Datos.dano_base(atacante.tipo, objetivo.tipo) / 100.0
	mult *= 1.0 + BONO_RANGO * atacante.rango
	mult *= 1.0 + BONO_FLANQUEO * aliados_flanqueando(atacante.equipo, celda_objetivo, celda_atacante, atacante)
	var defensa := 0.0
	if not objetivo.es_aerea():
		defensa = Datos.TERRENOS[mapa.terreno_en(celda_objetivo)]["defensa"] * DEFENSA_POR_NIVEL
	var dano: float = vida_max_obj * mult * fuerza * (1.0 - defensa)
	return maxi(1, int(round(dano)))


## Cuántos aliados del atacante están pegados al objetivo (sin contar al atacante).
func aliados_flanqueando(equipo: String, celda_objetivo: Vector2i, celda_atacante: Vector2i,
		atacante: Unidad = null) -> int:
	var n := 0
	for d in GameMap.DIRECCIONES:
		var c: Vector2i = celda_objetivo + d
		if c == celda_atacante:
			continue
		var u := mapa.unidad_en(c)
		if u != null and u != atacante and u.equipo == equipo:
			n += 1
	return n


## Vista previa: qué pasaría si "atacante" ataca a "objetivo" desde la casilla "desde".
## Devuelve {dano, contra, destruye, muere, flanqueo}.
func estimar(atacante: Unidad, objetivo: Unidad, desde: Vector2i) -> Dictionary:
	var dano := _dano(atacante, atacante.vida, desde, objetivo, objetivo.celda)
	var vida_restante := objetivo.vida - dano
	var contra := 0
	if vida_restante > 0 and puede_atacar_desde(objetivo, objetivo.celda, _fantasma(atacante, desde)):
		contra = _dano(objetivo, vida_restante, objetivo.celda, atacante, desde)
	return {"dano": dano, "contra": contra, "destruye": vida_restante <= 0, "critico": prob_critico(atacante),
		"destruye_critico": objetivo.vida - int(ceil(dano * MULT_CRITICO)) <= 0,
		"muere": contra >= atacante.vida, "flanqueo": aliados_flanqueando(atacante.equipo, objetivo.celda, desde, atacante)}


## Copia temporal de una unidad en otra casilla (solo para calcular distancias).
func _fantasma(u: Unidad, celda: Vector2i) -> Unidad:
	var f := Unidad.new()
	f.tipo = u.tipo
	f.equipo = u.equipo
	f.celda = celda
	f.queue_free()
	return f


func atacar(atacante: Unidad, objetivo: Unidad) -> void:
	if terminada or atacante.ya_ataco or not puede_atacar(atacante, objetivo):
		return
	var golpe := _tirar_dados(atacante, calcular_dano(atacante, objetivo))
	objetivo.vida -= golpe["dano"]
	unidad_atacada.emit(atacante, objetivo, golpe["dano"], golpe["critico"])
	if objetivo.vida <= 0:
		_destruir(objetivo, atacante)
	elif puede_atacar(objetivo, atacante):  # contraataque
		var contra := _tirar_dados(objetivo, calcular_dano(objetivo, atacante))
		atacante.vida -= contra["dano"]
		unidad_atacada.emit(objetivo, atacante, contra["dano"], contra["critico"])
		if atacante.vida <= 0:
			_destruir(atacante, objetivo)
	if is_instance_valid(atacante) and atacante.vida > 0:
		marcar_lista(atacante)
	revisar_victoria()


## Un poco de azar para que no todos los ataques sean idénticos (nunca menos de 1).
func _con_suerte(dano: int) -> int:
	return maxi(1, dano + randi_range(-SUERTE, SUERTE))


func prob_critico(u: Unidad) -> float:
	return PROB_CRITICO + CRITICO_POR_RANGO * u.rango


## El "factor apuesta": suerte de ±1 y, a veces, un golpe crítico.
## Devuelve {dano, critico}.
func _tirar_dados(atacante: Unidad, dano_estimado: int) -> Dictionary:
	var dano := _con_suerte(dano_estimado)
	var critico := randf() < prob_critico(atacante)
	if critico:
		dano = int(ceil(dano * MULT_CRITICO))
	return {"dano": dano, "critico": critico}


func _destruir(victima: Unidad, verdugo: Unidad) -> void:
	estadisticas[victima.equipo]["perdidas"] += 1
	estadisticas[verdugo.equipo]["destruidas"] += 1
	verdugo.rango += 1  # veteranía
	_quitar(victima)


func _quitar(u: Unidad) -> void:
	reiniciar_captura(u.celda)
	mapa.eliminar_unidad(u)


# ---------------- CAPTURA ----------------
func puede_capturar(u: Unidad) -> bool:
	if u.tipo != "infanteria" or u.ya_ataco:
		return false
	return _terreno_en(u.celda) in TIPOS_EDIFICIO and _dueno_en(u.celda) != u.equipo


func capturar(u: Unidad) -> void:
	if terminada or not puede_capturar(u):
		return
	_captura[u.celda] = _captura.get(u.celda, 0) + u.vida
	mapa.mostrar_progreso(u.celda, float(_captura[u.celda]) / PUNTOS_PARA_CAPTURAR, u.equipo)
	if _captura[u.celda] >= PUNTOS_PARA_CAPTURAR:
		_captura.erase(u.celda)
		mapa.mostrar_progreso(u.celda, 0.0, "")
		mapa.cambiar_dueno(u.celda, u.equipo)
		estadisticas[u.equipo]["capturadas"] += 1
		ciudad_capturada.emit(u.celda, u.equipo)
	marcar_lista(u)
	revisar_victoria()


## Si la infantería se va de una ciudad a medio capturar, se pierde el avance.
func reiniciar_captura(celda: Vector2i) -> void:
	_captura.erase(celda)
	mapa.mostrar_progreso(celda, 0.0, "")


# ---------------- HABILIDADES ----------------
func precio_habilidad(nombre: String, equipo: String) -> int:
	var usos: int = usos_habilidad.get(equipo, {}).get(nombre, 0)
	return int(Datos.HABILIDADES[nombre]["precio"] * (1.0 + 0.5 * usos))


func puede_pagar_habilidad(nombre: String, equipo: String) -> bool:
	return not terminada and creditos[equipo] >= precio_habilidad(nombre, equipo)


func _pagar_habilidad(nombre: String, equipo: String) -> void:
	var precio := precio_habilidad(nombre, equipo)
	_sumar_creditos(equipo, -precio)
	usos_habilidad[equipo][nombre] = usos_habilidad[equipo].get(nombre, 0) + 1
	estadisticas[equipo]["habilidades"] += 1
	estadisticas[equipo]["gastado"] += precio
	habilidad_usada.emit(nombre, equipo)


func usar_reparacion(equipo: String, u: Unidad) -> bool:
	if not puede_pagar_habilidad("reparacion", equipo) or u.equipo != equipo:
		return false
	var max_vida: int = u.datos()["vida_max"]
	if u.vida >= max_vida:
		return false
	_pagar_habilidad("reparacion", equipo)
	var cura := mini(Datos.VIDA_REPARACION, max_vida - u.vida)
	u.vida += cura
	unidad_curada.emit(u, cura)
	return true


## Bombardeo en un área de 3x3 alrededor de "centro". No destruye: deja mínimo 1 de vida.
func usar_bombardeo(equipo: String, centro: Vector2i) -> bool:
	if not puede_pagar_habilidad("bombardeo", equipo) or not mapa.en_mapa(centro):
		return false
	_pagar_habilidad("bombardeo", equipo)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var u := mapa.unidad_en(centro + Vector2i(dx, dy))
			if u != null and u.equipo != equipo:
				var dano := mini(Datos.DANO_BOMBARDEO, u.vida - 1)
				if dano > 0:
					u.vida -= dano
					unidad_danada.emit(u, dano)
	return true


## Casillas afectadas por una bomba nuclear: celda -> daño.
func area_nuclear(centro: Vector2i) -> Dictionary:
	var area := {}
	var r := int(ceil(Datos.RADIO_NUCLEAR))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := centro + Vector2i(dx, dy)
			var dist := Vector2(dx, dy).length()
			if not mapa.en_mapa(c) or dist > Datos.RADIO_NUCLEAR:
				continue
			for escalon in Datos.DANO_NUCLEAR:
				if dist <= escalon[0]:
					area[c] = escalon[1]
					break
	return area


## Bomba nuclear: le pega a TODAS las unidades del área, también a las propias. Sí destruye.
func usar_nuclear(equipo: String, centro: Vector2i) -> bool:
	if not puede_pagar_habilidad("nuclear", equipo) or not mapa.en_mapa(centro):
		return false
	_pagar_habilidad("nuclear", equipo)
	var area := area_nuclear(centro)
	for c in area:
		var u := mapa.unidad_en(c)
		if u == null:
			continue
		var dano := mini(area[c], u.vida)
		u.vida -= dano
		unidad_danada.emit(u, dano)
		if u.vida <= 0:
			estadisticas[u.equipo]["perdidas"] += 1
			if u.equipo != equipo:
				estadisticas[equipo]["destruidas"] += 1
			_quitar(u)
	revisar_victoria()
	return true


func usar_marcha(equipo: String) -> bool:
	if not puede_pagar_habilidad("marcha", equipo):
		return false
	_pagar_habilidad("marcha", equipo)
	for u in mapa.unidades_de(equipo):
		if u.datos()["movimiento"] > 0:
			u.bono_mov += 2
	return true


func usar_radar(equipo: String) -> bool:
	if not puede_pagar_habilidad("radar", equipo):
		return false
	_pagar_habilidad("radar", equipo)
	radar_activo[equipo] = true
	return true


# ---------------- VICTORIA ----------------
## Un equipo pierde si le capturan el cuartel general, o si se queda sin unidades
## y no puede comprar más (sin base o sin dinero suficiente ni con lo del próximo turno).
func revisar_victoria() -> void:
	if terminada:
		return
	for equipo in EQUIPOS:
		var rival := otro_equipo(equipo)
		if esta_derrotado(rival):
			terminada = true
			partida_terminada.emit(equipo)
			return


func esta_derrotado(equipo: String) -> bool:
	var cuartel: Vector2i = _cuarteles.get(equipo, Vector2i(-1, -1))
	if mapa.en_mapa(cuartel) and _dueno_en(cuartel) != equipo:
		return true
	if not mapa.unidades_de(equipo).is_empty():
		return false
	if not mapa.en_mapa(celda_base(equipo)):
		return true
	var mas_barata := 999999
	for t in Datos.UNIDADES:
		if not Datos.UNIDADES[t].get("construccion", false):
			mas_barata = mini(mas_barata, Datos.UNIDADES[t]["precio"])
	return creditos[equipo] + ingreso_de(equipo) < mas_barata


# ---------------- UTILIDADES ----------------
## La unidad ya no puede actuar este turno.
func marcar_lista(u: Unidad) -> void:
	if not is_instance_valid(u):
		return
	u.ya_se_movio = true
	u.ya_ataco = true
	u.marcar_usada(true)


# ---------------- atajos al mapa ----------------
## Nombre del terreno de la casilla ("llanura", "ciudad", "bosque"...).
func _terreno_en(celda: Vector2i) -> String:
	return mapa.terreno_en(celda)

## Dueño del edificio de la casilla ("azul", "rojo" o neutral).
func _dueno_en(celda: Vector2i) -> String:
	return mapa.dueno_en(celda)
