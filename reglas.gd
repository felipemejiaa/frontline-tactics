class_name Reglas
extends Node
## Reglas del juego: créditos, compra, combate, captura y victoria.
## Archivo nuevo: scripts/reglas.gd   (Persona 1)
## Los turnos los sigue manejando main.gd; este nodo solo avisa y calcula.

signal creditos_cambiados(equipo: String, cantidad: int)
signal unidad_atacada(atacante: Unidad, objetivo: Unidad, dano: int)
signal ciudad_capturada(celda: Vector2i, equipo: String)
signal partida_terminada(ganador: String)

# ---- Valores que puedes ajustar ----
const EQUIPOS := ["azul", "rojo"]
const CREDITOS_INICIALES := 2000
const DANO_BASE := 0.5          # fracción de la vida máxima del objetivo
const MULT_VENTAJA := 1.5       # piedra-papel-tijera a favor
const MULT_DESVENTAJA := 0.5    # en contra
const DEFENSA_POR_NIVEL := 0.1  # cada nivel de defensa del terreno quita 10 %
const PUNTOS_PARA_CAPTURAR := 20
const TIPOS_EDIFICIO := ["cuartel", "base", "ciudad"]

var mapa: GameMap
var creditos := {}
var terminada := false
var _captura := {}    # celda -> puntos acumulados
var _cuarteles := {}  # equipo -> celda de su cuartel general


func iniciar(mapa_ref: GameMap) -> void:
	mapa = mapa_ref
	terminada = false
	_captura.clear()
	_cuarteles.clear()
	for e in EQUIPOS:
		creditos[e] = CREDITOS_INICIALES
		_cuarteles[e] = mapa.buscar_edificio("cuartel", e)
		creditos_cambiados.emit(e, creditos[e])


func otro_equipo(equipo: String) -> String:
	return "rojo" if equipo == "azul" else "azul"


# ---------------- TURNOS Y CRÉDITOS ----------------
## main.gd lo llama cuando empieza el turno de un equipo.
func al_empezar_turno(equipo: String) -> void:
	_sumar_creditos(equipo, mapa.ingreso_de(equipo))


func celda_base(equipo: String) -> Vector2i:
	return mapa.buscar_edificio("base", equipo)


func comprar(tipo: String, equipo: String) -> bool:
	if terminada:
		return false
	var precio: int = Datos.UNIDADES[tipo]["precio"]
	var base := celda_base(equipo)
	# Si le capturaron la base, buscar_edificio devuelve (-1, -1): ya no puede comprar.
	if not mapa.en_mapa(base) or creditos[equipo] < precio or mapa.unidad_en(base) != null:
		return false
	var nueva := mapa.crear_unidad(tipo, equipo, base)
	_sumar_creditos(equipo, -precio)
	marcar_lista(nueva)  # una unidad recién comprada no actúa ese turno
	return true


func _sumar_creditos(equipo: String, cantidad: int) -> void:
	creditos[equipo] += cantidad
	creditos_cambiados.emit(equipo, creditos[equipo])


# ---------------- COMBATE ----------------
func puede_atacar(atacante: Unidad, objetivo: Unidad) -> bool:
	if atacante.equipo == objetivo.equipo:
		return false
	var d: int = mapa.distancia(atacante.celda, objetivo.celda)
	var datos := atacante.datos()
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
	var vida_max_obj: float = objetivo.datos()["vida_max"]
	var fuerza: float = float(atacante.vida) / float(atacante.datos()["vida_max"])
	var mult := 1.0
	if Datos.LE_GANA_A.get(atacante.tipo, "") == objetivo.tipo:
		mult = MULT_VENTAJA
	elif Datos.LE_GANA_A.get(objetivo.tipo, "") == atacante.tipo:
		mult = MULT_DESVENTAJA
	var defensa: float = Datos.TERRENOS[_terreno_en(objetivo.celda)]["defensa"] * DEFENSA_POR_NIVEL
	var dano: float = vida_max_obj * DANO_BASE * mult * fuerza * (1.0 - defensa)
	return maxi(1, int(round(dano)))


func atacar(atacante: Unidad, objetivo: Unidad) -> void:
	if terminada or atacante.ya_ataco or not puede_atacar(atacante, objetivo):
		return
	var dano := calcular_dano(atacante, objetivo)
	objetivo.vida -= dano
	unidad_atacada.emit(atacante, objetivo, dano)
	print("%s %s hace %d de daño a %s %s" % [atacante.equipo, atacante.tipo, dano, objetivo.equipo, objetivo.tipo])
	if objetivo.vida <= 0:
		_quitar(objetivo)
	elif puede_atacar(objetivo, atacante):  # contraataque
		var contra := calcular_dano(objetivo, atacante)
		atacante.vida -= contra
		unidad_atacada.emit(objetivo, atacante, contra)
		if atacante.vida <= 0:
			_quitar(atacante)
	if is_instance_valid(atacante) and atacante.vida > 0:
		marcar_lista(atacante)
	revisar_victoria()


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
	if _captura[u.celda] >= PUNTOS_PARA_CAPTURAR:
		_captura.erase(u.celda)
		mapa.cambiar_dueno(u.celda, u.equipo)
		ciudad_capturada.emit(u.celda, u.equipo)
	marcar_lista(u)
	revisar_victoria()


## Si la infantería se va de una ciudad a medio capturar, se pierde el avance.
func reiniciar_captura(celda: Vector2i) -> void:
	_captura.erase(celda)


# ---------------- VICTORIA ----------------
## Gana quien deja al rival sin unidades o captura su cuartel general.
func revisar_victoria() -> void:
	if terminada:
		return
	for equipo in EQUIPOS:
		var rival := otro_equipo(equipo)
		var cuartel: Vector2i = _cuarteles.get(rival, Vector2i(-1, -1))
		var cuartel_perdido := mapa.en_mapa(cuartel) and _dueno_en(cuartel) != rival
		if mapa.unidades_de(rival).is_empty() or cuartel_perdido:
			terminada = true
			partida_terminada.emit(equipo)
			return


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
