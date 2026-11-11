class_name GameMap
extends Node2D
## El mapa de cuadrícula: dibuja el terreno, guarda dónde está cada unidad
## y calcula a qué casillas se puede mover una unidad.

## Leyenda del mapa:
##   .  llanura      b  bosque       m  montaña      ~  agua
##   H  cuartel azul h  cuartel rojo F  base azul    f  base roja
## Para cambiar el mapa basta con editar estas filas (todas del mismo largo).
const MAPA := [
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

var ancho: int = 0
var alto: int = 0
## Diccionario celda (Vector2i) -> Unidad
var unidades := {}


func _ready() -> void:
	alto = MAPA.size()
	ancho = MAPA[0].length()
	queue_redraw()


# ---------------------------------------------------------------- consultas

func en_mapa(celda: Vector2i) -> bool:
	return celda.x >= 0 and celda.y >= 0 and celda.x < ancho and celda.y < alto


func letra_en(celda: Vector2i) -> String:
	return MAPA[celda.y][celda.x]


func terreno_en(celda: Vector2i) -> String:
	match letra_en(celda):
		"b": return "bosque"
		"m": return "montana"
		"~": return "agua"
		"H", "h": return "cuartel"
		"F", "f": return "base"
		_: return "llanura"


## Dueño de un edificio ("azul", "rojo") o "" si no es edificio.
func dueno_en(celda: Vector2i) -> String:
	var letra := letra_en(celda)
	if letra == "H" or letra == "F":
		return "azul"
	if letra == "h" or letra == "f":
		return "rojo"
	return ""


## Busca la celda del cuartel o la base de un equipo. tipo: "cuartel" o "base".
func buscar_edificio(tipo: String, equipo: String) -> Vector2i:
	for y in alto:
		for x in ancho:
			var c := Vector2i(x, y)
			if terreno_en(c) == tipo and dueno_en(c) == equipo:
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
func calcular_alcance(u: Unidad) -> Dictionary:
	var datos: Dictionary = Datos.UNIDADES[u.tipo]
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
			if otra != null and otra.equipo != u.equipo:
				continue  # los enemigos bloquean el paso
			var nuevo: int = costos[actual] + paso
			if nuevo > datos["movimiento"]:
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
		if ocupante == null or ocupante == u:
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
