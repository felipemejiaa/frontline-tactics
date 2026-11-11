class_name GeneradorMapa
extends RefCounted
## Crea mapas aleatorios. Solo genera la mitad izquierda (la del jugador azul)
## y la copia en espejo para el rojo, así ningún bando tiene ventaja.
## Revisa que siempre haya camino entre las bases, los cuarteles y todas las ciudades;
## si no lo hay, vuelve a intentar.

const ANCHO := 26   # debe ser par para que el espejo quede exacto
const ALTO := 15
const MITAD := ANCHO / 2

## Unidades con las que arranca cada bando (se ubican cerca de su base).
const EJERCITO_INICIAL := ["infanteria", "tanque", "artilleria"]

var rng := RandomNumberGenerator.new()
var g: Array = []  # g[y][x] = letra (ver leyenda en game_map.gd)


## Devuelve {"lineas": Array[String], "unidades": [{tipo, equipo, celda}, ...]}
func generar(semilla: int) -> Dictionary:
	rng.seed = semilla
	for intento in 200:
		var resultado := _intentar()
		if not resultado.is_empty():
			return resultado
	# Casi imposible llegar aquí; por si acaso se usa el mapa fijo.
	push_warning("No se pudo generar un mapa, se usa el mapa fijo")
	return {}


func _intentar() -> Dictionary:
	_llenar(".")

	# Agua: un río en el centro con vados, o unos lagos.
	if rng.randf() < 0.55:
		_rio()
	else:
		for i in rng.randi_range(1, 2):
			_manchon("~", rng.randi_range(3, 6), 5, MITAD - 2)

	for i in rng.randi_range(3, 5):
		_manchon("m", rng.randi_range(2, 4), 2, MITAD - 1)
	for i in rng.randi_range(5, 8):
		_manchon("b", rng.randi_range(2, 5), 2, MITAD - 1)

	# Cuartel general y base del azul.
	var hq := Vector2i(1, rng.randi_range(3, ALTO - 4))
	var base := Vector2i(rng.randi_range(3, 4), clampi(hq.y + (2 if rng.randf() < 0.5 else -2), 1, ALTO - 2))
	_despejar(hq)
	_despejar(base)
	_poner(hq, "H")
	_poner(base, "F")

	# Ciudades neutrales (dan créditos al capturarlas).
	var edificios: Array[Vector2i] = [hq, base]
	var faltan := rng.randi_range(4, 6)
	for i in 300:
		if faltan == 0:
			break
		var c := Vector2i(rng.randi_range(2, MITAD - 1), rng.randi_range(0, ALTO - 1))
		if _letra(c) != "." or not _lejos_de(c, edificios, 3):
			continue
		_poner(c, "c")
		edificios.append(c)
		faltan -= 1

	# Unidades iniciales del azul: las casillas libres de llanura más cercanas a la base.
	var celdas_azul := _casillas_libres_cerca(base, EJERCITO_INICIAL.size())
	if celdas_azul.size() < EJERCITO_INICIAL.size():
		return {}

	_espejar()

	if not _todo_conectado(base, celdas_azul):
		return {}

	var unidades := []
	for i in EJERCITO_INICIAL.size():
		var celda: Vector2i = celdas_azul[i]
		unidades.append({"tipo": EJERCITO_INICIAL[i], "equipo": "azul", "celda": celda})
		unidades.append({"tipo": EJERCITO_INICIAL[i], "equipo": "rojo", "celda": _espejo(celda)})

	var lineas: Array[String] = []
	for fila in g:
		lineas.append("".join(fila))
	return {"lineas": lineas, "unidades": unidades}


# ---------------------------------------------------------------- piezas del mapa

func _llenar(letra: String) -> void:
	g = []
	for y in ALTO:
		var fila := []
		fila.resize(ANCHO)
		fila.fill(letra)
		g.append(fila)


func _letra(c: Vector2i) -> String:
	return g[c.y][c.x]


func _poner(c: Vector2i, letra: String) -> void:
	g[c.y][c.x] = letra


func _en_mitad(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < MITAD and c.y >= 0 and c.y < ALTO


## Río vertical en la última columna de la mitad (al espejar queda de 2 de ancho),
## con 2 o 3 vados para cruzar.
func _rio() -> void:
	var x := MITAD - 1
	for y in ALTO:
		_poner(Vector2i(x, y), "~")
	var vados := rng.randi_range(2, 3)
	for i in vados:
		var y := rng.randi_range(1, ALTO - 2)
		_poner(Vector2i(x, y), ".")


## Mancha de terreno: un "caminante" aleatorio que pinta casillas de llanura.
func _manchon(letra: String, tamano: int, x_min: int, x_max: int) -> void:
	var c := Vector2i(rng.randi_range(x_min, x_max), rng.randi_range(0, ALTO - 1))
	for i in tamano * 2:
		if _en_mitad(c) and _letra(c) == ".":
			_poner(c, letra)
			tamano -= 1
			if tamano == 0:
				return
		var paso: Vector2i = GameMap.DIRECCIONES[rng.randi_range(0, 3)]
		var siguiente := c + paso
		if _en_mitad(siguiente) and siguiente.x >= x_min and siguiente.x <= x_max:
			c = siguiente


## Deja en llanura la casilla y sus vecinas (para que los edificios no queden encerrados).
func _despejar(centro: Vector2i) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := centro + Vector2i(dx, dy)
			if _en_mitad(c):
				_poner(c, ".")


func _lejos_de(c: Vector2i, otros: Array[Vector2i], minimo: int) -> bool:
	for o in otros:
		if absi(o.x - c.x) + absi(o.y - c.y) < minimo:
			return false
	return true


func _espejo(c: Vector2i) -> Vector2i:
	return Vector2i(ANCHO - 1 - c.x, c.y)


func _espejar() -> void:
	var cambio := {"H": "h", "F": "f"}
	for y in ALTO:
		for x in MITAD:
			var letra: String = g[y][x]
			g[y][ANCHO - 1 - x] = cambio.get(letra, letra)


func _casillas_libres_cerca(origen: Vector2i, cuantas: int) -> Array[Vector2i]:
	var candidatas: Array[Vector2i] = []
	for y in ALTO:
		for x in MITAD - 1:  # no pegadas al centro
			var c := Vector2i(x, y)
			if _letra(c) == ".":
				candidatas.append(c)
	candidatas.sort_custom(func(a, b):
		return absi(a.x - origen.x) + absi(a.y - origen.y) < absi(b.x - origen.x) + absi(b.y - origen.y))
	return candidatas.slice(0, cuantas)


# ---------------------------------------------------------------- validación

## Revisa que un tanque (la unidad más limitada) pueda llegar desde la base azul
## a todos los edificios y a todas las casillas de arranque.
func _todo_conectado(base_azul: Vector2i, arranque: Array[Vector2i]) -> bool:
	var costos: Dictionary = Datos.UNIDADES["tanque"]["costo_terreno"]
	var visitadas := {base_azul: true}
	var cola: Array[Vector2i] = [base_azul]
	while not cola.is_empty():
		var actual: Vector2i = cola.pop_front()
		for dir in GameMap.DIRECCIONES:
			var v: Vector2i = actual + dir
			if v.x < 0 or v.y < 0 or v.x >= ANCHO or v.y >= ALTO or visitadas.has(v):
				continue
			if costos[GameMap.letra_a_terreno(g[v.y][v.x])] < 0:
				continue
			visitadas[v] = true
			cola.append(v)
	for y in ALTO:
		for x in ANCHO:
			var c := Vector2i(x, y)
			if GameMap.letra_a_dueno(g[y][x]) != "" and not visitadas.has(c):
				return false
	for c in arranque:
		if not visitadas.has(c) or not visitadas.has(_espejo(c)):
			return false
	return true
