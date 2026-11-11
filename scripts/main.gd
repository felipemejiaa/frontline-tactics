extends Node2D
## Escena principal: recibe los toques en pantalla y controla la selección y el movimiento.

## Se emite cuando una unidad termina de moverse.
## Persona 1: conectarse aquí para mostrar el menú Atacar / Esperar.
signal unidad_movida(unidad: Unidad)

enum Estado { LIBRE, SELECCIONADA, MOVIENDO }

@onready var mapa: GameMap = $GameMap
@onready var resaltado: Resaltado = $GameMap/Resaltado
@onready var etiqueta_turno: Label = $HUD/EtiquetaTurno
@onready var boton_terminar: Button = $HUD/BotonTerminar
@onready var ia: IA = $IA
@onready var boton_nuevo_mapa: Button = $HUD/BotonNuevoMapa

## Las pruebas automáticas lo ponen en true para usar siempre el mismo mapa.
var modo_prueba := false
## Semilla del mapa actual (sirve para repetir un mapa que salió bueno).
var semilla := 0

var estado := Estado.LIBRE
var turno_ia := false  # mientras juega la máquina se ignoran los toques
var equipo_actual := "azul"
var seleccionada: Unidad = null
var alcance := {}


func _ready() -> void:
	boton_terminar.pressed.connect(terminar_turno)
	boton_nuevo_mapa.pressed.connect(nuevo_mapa)
	if modo_prueba:
		_cargar_mapa_de_prueba()
	else:
		nuevo_mapa()


## Genera un mapa aleatorio. Con semilla_fija >= 0 repite siempre el mismo mapa.
func nuevo_mapa(semilla_fija: int = -1) -> void:
	if estado == Estado.MOVIENDO or turno_ia:
		return
	deseleccionar()
	semilla = semilla_fija if semilla_fija >= 0 else randi()
	var generado := GeneradorMapa.new().generar(semilla)
	if generado.is_empty():
		_cargar_mapa_de_prueba()
		return
	mapa.cargar_desde_texto(generado["lineas"])
	for u in generado["unidades"]:
		mapa.crear_unidad(u["tipo"], u["equipo"], u["celda"])
	print("Mapa generado con semilla ", semilla)
	_empezar_partida()


func _cargar_mapa_de_prueba() -> void:
	mapa.cargar_desde_texto(GameMap.MAPA_PRUEBA)
	mapa.crear_unidad("infanteria", "azul", Vector2i(2, 4))
	mapa.crear_unidad("tanque", "azul", Vector2i(3, 2))
	mapa.crear_unidad("artilleria", "azul", Vector2i(1, 6))
	mapa.crear_unidad("infanteria", "rojo", Vector2i(13, 4))
	mapa.crear_unidad("tanque", "rojo", Vector2i(12, 2))
	mapa.crear_unidad("artilleria", "rojo", Vector2i(14, 6))
	_empezar_partida()


func _empezar_partida() -> void:
	equipo_actual = "azul"
	# Centrar el mapa en la pantalla (dejando arriba la franja del HUD).
	var tamano := Vector2(mapa.ancho, mapa.alto) * Datos.TAM_CASILLA
	var pantalla := get_viewport_rect().size
	mapa.position = Vector2(floorf((pantalla.x - tamano.x) / 2.0), 30 + floorf((pantalla.y - 30 - tamano.y) / 2.0))
	_actualizar_hud()


# ---------------------------------------------------------------- entrada táctil

## En Android los toques llegan como clic de mouse (Godot los convierte solo),
## así que esto funciona igual en el PC y en el celular.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var celda := mapa.pos_a_celda(mapa.get_local_mouse_position())
		if mapa.en_mapa(celda):
			tocar_celda(celda)
		elif estado == Estado.SELECCIONADA:
			deseleccionar()


func tocar_celda(celda: Vector2i) -> void:
	if turno_ia:
		return
	match estado:
		Estado.MOVIENDO:
			return
		Estado.LIBRE:
			var u := mapa.unidad_en(celda)
			if u != null:
				seleccionar(u)
		Estado.SELECCIONADA:
			if _puede_mover(seleccionada) and celda in alcance["destinos"]:
				mover(seleccionada, celda)
			else:
				var anterior := seleccionada
				deseleccionar()
				var otra := mapa.unidad_en(celda)
				if otra != null and otra != anterior:
					seleccionar(otra)


# ---------------------------------------------------------------- selección y movimiento

func _puede_mover(u: Unidad) -> bool:
	return u.equipo == equipo_actual and not u.ya_se_movio


## Selecciona una unidad. Si es propia muestra en azul a dónde se puede mover;
## si es enemiga (o ya se movió) muestra su alcance en rojo, solo como información.
func seleccionar(u: Unidad) -> void:
	seleccionada = u
	alcance = mapa.calcular_alcance(u)
	var color := Resaltado.COLOR_MOVER if _puede_mover(u) else Resaltado.COLOR_ENEMIGO
	resaltado.mostrar(alcance["destinos"], color, u.celda)
	estado = Estado.SELECCIONADA


func deseleccionar() -> void:
	seleccionada = null
	alcance = {}
	resaltado.limpiar()
	estado = Estado.LIBRE


## Mueve la unidad con animación. También la usará la IA.
func mover(u: Unidad, destino: Vector2i) -> void:
	estado = Estado.MOVIENDO
	resaltado.limpiar()
	var alcance_u := alcance if seleccionada == u else mapa.calcular_alcance(u)
	var puntos: Array[Vector2] = []
	for c in mapa.camino_hasta(alcance_u, destino):
		puntos.append(mapa.celda_a_pos(c))
	mapa.mover_registro(u, destino)
	await u.recorrer(puntos)
	u.ya_se_movio = true
	u.marcar_usada(true)  # TEMPORAL: cuando exista el menú de ataque, marcar al terminar la acción
	seleccionada = null
	alcance = {}
	estado = Estado.LIBRE
	unidad_movida.emit(u)


# ---------------------------------------------------------------- turnos (TEMPORAL)

## TEMPORAL para poder probar: cambia de equipo, reactiva las unidades
## y, si le toca a la máquina, juega la IA y devuelve el turno.
## Persona 1 lo reemplaza con el sistema de turnos real (créditos, victoria, etc.).
func terminar_turno() -> void:
	if estado == Estado.MOVIENDO or turno_ia:
		return
	deseleccionar()
	equipo_actual = "rojo" if equipo_actual == "azul" else "azul"
	for u in mapa.unidades_de(equipo_actual):
		u.reiniciar_turno()
	_actualizar_hud()
	if equipo_actual == ia.equipo:
		turno_ia = true
		boton_terminar.disabled = true
		await ia.jugar_turno()
		turno_ia = false
		boton_terminar.disabled = false
		terminar_turno()


func _actualizar_hud() -> void:
	etiqueta_turno.text = "Turno: " + ("Azul" if equipo_actual == "azul" else "Rojo")
