class_name GameMap
extends Node2D
## El mapa de cuadrícula: dibuja el terreno, guarda dónde está cada unidad
## y calcula a qué casillas se puede mover una unidad.

## Leyenda de los mapas en texto:
##   .  llanura      b  bosque       m  montaña      ~  agua
##   H  cuartel azul h  cuartel rojo F  base azul    f  base roja
##   c  ciudad neutral (se puede capturar)
## El juego normal usa mapas aleatorios (ver generador_mapa.gd).
## Este mapa fijo se usa en las pruebas automáticas.
const MAPA_PRUEBA := [
	"..b....~~....m..",
	".....b.~~..b....",
	".F.....~...m..f.",
	"...m.........b..",
	"H...b..mm..b...h",
	"..b....mm..b....",
	"...........m....",
	"....m...~.......",
	"....b..~~.b.....",
	"..m....~~....b..",
]

const DIRECCIONES := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
const EDIFICIOS := ["cuartel", "base", "ciudad"]

var ancho: int = 0
var alto: int = 0
## terrenos[y][x] = nombre del terreno ("llanura", "bosque", ...)
var terrenos: Array = []
## Diccionario celda -> dueño ("azul", "rojo" o "neutral"). Solo para edificios.
var duenos := {}
## Diccionario celda (Vector2i) -> Unidad
var unidades := {}
## Captura a medias: celda -> [fracción 0..1, equipo que captura]
var progreso_captura := {}
## Capa que se dibuja encima de las unidades: banderas de dueño y barras de captura.
var _marcas := Marcas.new()
## Zona de peligro: casillas que el enemigo puede atacar el próximo turno.
var zona_peligro := {}
var _capa_peligro := CapaPeligro.new()
## Niebla (estilo Age of Empires): lo explorado y lo que se ve ahora.
var niebla_activa := false
var explorado := {}
var visible_ahora := {}
var _capa_niebla := CapaNiebla.new()


func _ready() -> void:
	_marcas.mapa = self
	_marcas.z_index = 5
	add_child(_marcas)
	_capa_peligro.mapa = self
	add_child(_capa_peligro)
	_capa_niebla.mapa = self
	_capa_niebla.z_index = 6
	add_child(_capa_niebla)


static func letra_a_terreno(letra: String) -> String:
	match letra:
		"b": return "bosque"
		"m": return "montana"
		"~": return "agua"
		"H", "h": return "cuartel"
		"F", "f": return "base"
		"c": return "ciudad"
		_: return "llanura"


static func letra_a_dueno(letra: String) -> String:
	match letra:
		"H", "F": return "azul"
		"h", "f": return "rojo"
		"c": return "neutral"
		_: return ""


## Carga un mapa escrito como lista de filas de texto (todas del mismo largo).
## Borra las unidades que hubiera.
func cargar_desde_texto(lineas: Array) -> void:
	for u in unidades.values():
		u.queue_free()
	unidades.clear()
	duenos.clear()
	terrenos.clear()
	progreso_captura.clear()
	zona_peligro.clear()
	explorado.clear()
	visible_ahora.clear()
	alto = lineas.size()
	ancho = lineas[0].length()
	for y in alto:
		var fila: Array[String] = []
		for x in ancho:
			var letra: String = lineas[y][x]
			fila.append(letra_a_terreno(letra))
			var dueno := letra_a_dueno(letra)
			if dueno != "":
				duenos[Vector2i(x, y)] = dueno
		terrenos.append(fila)
	queue_redraw()
	_marcas.queue_redraw()
	_capa_peligro.queue_redraw()
	_capa_niebla.queue_redraw()


# ---------------------------------------------------------------- consultas

func en_mapa(celda: Vector2i) -> bool:
	return celda.x >= 0 and celda.y >= 0 and celda.x < ancho and celda.y < alto


func terreno_en(celda: Vector2i) -> String:
	return terrenos[celda.y][celda.x]


## Dueño de un edificio ("azul", "rojo", "neutral") o "" si no es edificio.
func dueno_en(celda: Vector2i) -> String:
	return duenos.get(celda, "")


## Para capturar edificios (persona 1): cambia el dueño y redibuja.
func cambiar_dueno(celda: Vector2i, equipo: String) -> void:
	if duenos.has(celda):
		duenos[celda] = equipo
		queue_redraw()
		_marcas.queue_redraw()


## Barra de captura sobre un edificio (fracción 0 = sin barra).
func mostrar_progreso(celda: Vector2i, fraccion: float, equipo: String) -> void:
	if fraccion <= 0.0:
		progreso_captura.erase(celda)
	else:
		progreso_captura[celda] = [fraccion, equipo]
	_marcas.queue_redraw()


## Edificios (cuarteles, bases y ciudades) que pertenecen a un equipo.
func edificios_de(equipo: String) -> Array[Vector2i]:
	var lista: Array[Vector2i] = []
	for c in duenos:
		if duenos[c] == equipo:
			lista.append(c)
	return lista


## Créditos que gana un equipo al empezar su turno.
func ingreso_de(equipo: String) -> int:
	return edificios_de(equipo).size() * Datos.INGRESO_POR_EDIFICIO


## Busca la celda del cuartel o la base de un equipo. tipo: "cuartel" o "base".
func buscar_edificio(tipo: String, equipo: String) -> Vector2i:
	for c in duenos:
		if duenos[c] == equipo and terreno_en(c) == tipo:
			return c
	return Vector2i(-1, -1)


## Centro de la casilla en coordenadas locales del mapa.
func celda_a_pos(celda: Vector2i) -> Vector2:
	return Vector2(celda * Datos.TAM_CASILLA) + Vector2.ONE * Datos.TAM_CASILLA / 2.0


func pos_a_celda(pos_local: Vector2) -> Vector2i:
	return Vector2i((pos_local / Datos.TAM_CASILLA).floor())


func distancia(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


# ---------------------------------------------------------------- unidades

func unidad_en(celda: Vector2i) -> Unidad:
	return unidades.get(celda, null)


func unidades_de(equipo: String) -> Array[Unidad]:
	var lista: Array[Unidad] = []
	for u in unidades.values():
		if u.equipo == equipo:
			lista.append(u)
	return lista


func crear_unidad(tipo: String, equipo: String, celda: Vector2i) -> Unidad:
	var u := Unidad.new()
	u.tipo = tipo
	u.equipo = equipo
	u.celda = celda
	u.position = celda_a_pos(celda)
	add_child(u)
	unidades[celda] = u
	return u


## Actualiza el registro de posiciones (no anima; la animación la hace Unidad.recorrer).
func mover_registro(u: Unidad, destino: Vector2i) -> void:
	unidades.erase(u.celda)
	u.celda = destino
	unidades[destino] = u


func eliminar_unidad(u: Unidad) -> void:
	unidades.erase(u.celda)
	u.queue_free()


# ---------------------------------------------------------------- movimiento

## Calcula todas las casillas a las que la unidad puede llegar este turno.
## Usa Dijkstra (un BFS que tiene en cuenta que cada terreno cuesta distinto).
## Devuelve {"destinos": Array[Vector2i], "anterior": Dictionary}
## "anterior" sirve para reconstruir el camino con camino_hasta().
## "ignorar": casillas con enemigos escondidos en la niebla, que se tratan como vacías
## (si la unidad intenta pasar por ahí, cae en una emboscada).
func calcular_alcance(u: Unidad, ignorar := {}) -> Dictionary:
	var datos: Dictionary = Datos.UNIDADES[u.tipo]
	var movimiento := u.movimiento()
	var costos := {u.celda: 0}
	var anterior := {u.celda: u.celda}
	var pendientes: Array[Vector2i] = [u.celda]

	while not pendientes.is_empty():
		# Sacar la casilla pendiente más barata (el mapa es pequeño, basta buscar).
		var idx := 0
		for i in range(1, pendientes.size()):
			if costos[pendientes[i]] < costos[pendientes[idx]]:
				idx = i
		var actual: Vector2i = pendientes.pop_at(idx)

		for dir in DIRECCIONES:
			var vecino: Vector2i = actual + dir
			if not en_mapa(vecino):
				continue
			var paso: int = datos["costo_terreno"][terreno_en(vecino)]
			if paso < 0:
				continue  # terreno prohibido para esta unidad
			var otra := unidad_en(vecino)
			if otra != null and otra.equipo != u.equipo and not ignorar.has(vecino):
				continue  # los enemigos bloquean el paso
			var nuevo: int = costos[actual] + paso
			if nuevo > movimiento:
				continue
			if not costos.has(vecino) or nuevo < costos[vecino]:
				costos[vecino] = nuevo
				anterior[vecino] = actual
				if not pendientes.has(vecino):
					pendientes.append(vecino)

	# Se puede pasar por encima de aliados, pero no terminar encima de ellos.
	var destinos: Array[Vector2i] = []
	for celda in anterior:
		var ocupante := unidad_en(celda)
		if ocupante == null or ocupante == u or ignorar.has(celda):
			destinos.append(celda)
	return {"destinos": destinos, "anterior": anterior}


## Camino casilla por casilla desde la unidad hasta destino (sin incluir la casilla inicial).
func camino_hasta(alcance: Dictionary, destino: Vector2i) -> Array[Vector2i]:
	var anterior: Dictionary = alcance["anterior"]
	var camino: Array[Vector2i] = []
	if not anterior.has(destino):
		return camino
	var actual := destino
	while anterior[actual] != actual:
		camino.push_front(actual)
		actual = anterior[actual]
	return camino


# ---------------------------------------------------------------- dibujo

func _draw() -> void:
	if terrenos.is_empty():
		return
	for y in alto:
		for x in ancho:
			var celda := Vector2i(x, y)
			var info: Dictionary = Datos.TERRENOS[terreno_en(celda)]
			_dibujar_tile(celda, info["tile"])
			var dueno := dueno_en(celda)
			if dueno != "" and info.has("adorno_" + dueno):
				_dibujar_tile(celda, info["adorno_" + dueno])
			elif info.has("adorno"):
				_dibujar_tile(celda, info["adorno"])


func _dibujar_tile(celda: Vector2i, tile: Vector2i) -> void:
	var t := Datos.TAM_CASILLA
	draw_texture_rect_region(Datos.ATLAS,
		Rect2(Vector2(celda * t), Vector2(t, t)),
		Rect2(Vector2(tile * t), Vector2(t, t)))


## Dibuja, encima de las unidades, una banderita del color del dueño en cada edificio
## (así se ve de quién es aunque haya una unidad encima) y la barra de captura.
class Marcas extends Node2D:
	const TILE_BANDERA := Vector2i(14, 10)
	const COLORES := {"azul": Color(0.35, 0.65, 1.0), "rojo": Color(1.0, 0.35, 0.3)}
	var mapa: GameMap

	func _draw() -> void:
		var t := Datos.TAM_CASILLA
		for c in mapa.duenos:
			var dueno: String = mapa.duenos[c]
			if COLORES.has(dueno):
				draw_texture_rect_region(Datos.ATLAS, Rect2(Vector2(c * t) + Vector2(-2, -3), Vector2(10, 10)),
					Rect2(Vector2(TILE_BANDERA * t), Vector2(t, t)), COLORES[dueno])
		for c in mapa.progreso_captura:
			var fraccion: float = mapa.progreso_captura[c][0]
			var color: Color = COLORES.get(mapa.progreso_captura[c][1], Color.WHITE)
			var base := Vector2(c * t) + Vector2(1, t - 4)
			draw_rect(Rect2(base, Vector2(t - 2, 3)), Color(0, 0, 0, 0.75))
			draw_rect(Rect2(base + Vector2(0.5, 0.5), Vector2((t - 3) * fraccion, 2)), color)


# ---------------------------------------------------------------- niebla y peligro

func mostrar_peligro(celdas: Dictionary) -> void:
	zona_peligro = celdas
	_capa_peligro.queue_redraw()


## Calcula qué ve un equipo: alrededor de sus unidades (según su visión) y de sus edificios.
## Devuelve true si cambió algo.
func actualizar_vision(equipo: String, revelar_todo := false) -> bool:
	var nuevo := {}
	if revelar_todo or not niebla_activa:
		for y in alto:
			for x in ancho:
				nuevo[Vector2i(x, y)] = true
	else:
		for u in unidades_de(equipo):
			_marcar_radio(nuevo, u.celda, u.datos()["vision"])
		for c in edificios_de(equipo):
			_marcar_radio(nuevo, c, 2 if terreno_en(c) == "cuartel" else 1)
	for c in nuevo:
		explorado[c] = true
	var cambio := nuevo.size() != visible_ahora.size() or nuevo.keys() != visible_ahora.keys()
	visible_ahora = nuevo
	# Esconder las unidades enemigas que no se ven.
	for u in unidades.values():
		u.visible = u.equipo == equipo or visible_ahora.has(u.celda)
	if cambio:
		_capa_niebla.queue_redraw()
	return cambio


func se_ve(celda: Vector2i) -> bool:
	return not niebla_activa or visible_ahora.has(celda)


## Enemigos escondidos en la niebla (para tratarlos como vacíos al calcular movimiento).
func ocultos_para(equipo: String) -> Dictionary:
	var ocultos := {}
	if niebla_activa:
		for u in unidades.values():
			if u.equipo != equipo and not visible_ahora.has(u.celda):
				ocultos[u.celda] = true
	return ocultos


func _marcar_radio(conjunto: Dictionary, centro: Vector2i, radio: int) -> void:
	for dy in range(-radio, radio + 1):
		for dx in range(-radio, radio + 1):
			var c := centro + Vector2i(dx, dy)
			if absi(dx) + absi(dy) <= radio and en_mapa(c):
				conjunto[c] = true


## Rojo suave con borde en las casillas que el enemigo puede atacar.
class CapaPeligro extends Node2D:
	var mapa: GameMap

	func _draw() -> void:
		var t := Datos.TAM_CASILLA
		for c in mapa.zona_peligro:
			var r := Rect2(Vector2(c * t), Vector2(t, t))
			draw_rect(r, Color(1, 0.15, 0.1, 0.22))
			draw_line(r.position, r.position + Vector2(t, t), Color(1, 0.2, 0.1, 0.35), 1.0)


## Negro donde nunca has explorado, gris donde exploraste pero ahora no ves.
class CapaNiebla extends Node2D:
	var mapa: GameMap

	func _draw() -> void:
		if not mapa.niebla_activa:
			return
		var t := Datos.TAM_CASILLA
		for y in mapa.alto:
			for x in mapa.ancho:
				var c := Vector2i(x, y)
				if mapa.visible_ahora.has(c):
					continue
				var color := Color(0.05, 0.05, 0.08, 0.5) if mapa.explorado.has(c) else Color(0.02, 0.02, 0.04, 1.0)
				draw_rect(Rect2(Vector2(c * t), Vector2(t, t)), color)
