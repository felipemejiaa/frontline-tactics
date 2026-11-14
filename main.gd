extends Node2D
## Escena principal: recibe los toques en pantalla y controla la selección, el movimiento
## y el menú de acciones (Atacar / Capturar / Esperar / Comprar).

## Se emite cuando una unidad termina de moverse.
signal unidad_movida(unidad: Unidad)

enum Estado { LIBRE, SELECCIONADA, MOVIENDO, MENU, OBJETIVO }

const POS_MENU := Vector2(8, 40)   # dónde aparece el menú (el juego se dibuja a 480x270)
const FUENTE_MENU := 10

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

# --- reglas (Persona 1) ---
var reglas: Reglas
var juego_terminado := false
var unidad_menu: Unidad = null
var objetivos_actuales: Array[Unidad] = []
var menu: PanelContainer
var caja_menu: VBoxContainer
var etiqueta_mensaje: Label


func _ready() -> void:
	reglas = Reglas.new()
	add_child(reglas)
	reglas.partida_terminada.connect(_on_partida_terminada)
	reglas.creditos_cambiados.connect(func(_e, _c): _actualizar_hud())
	ia.ataque_elegido.connect(reglas.atacar)
	unidad_movida.connect(_on_unidad_movida)
	_construir_interfaz()
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
	juego_terminado = false
	etiqueta_mensaje.visible = false
	menu.visible = false
	boton_terminar.disabled = false
	reglas.iniciar(mapa)
	reglas.al_empezar_turno(equipo_actual)  # el azul cobra al empezar
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
	if turno_ia or juego_terminado:
		return
	match estado:
		Estado.MOVIENDO, Estado.MENU:
			return
		Estado.OBJETIVO:
			var o := mapa.unidad_en(celda)
			if o != null and o in objetivos_actuales:
				var atacante := unidad_menu
				_cerrar_menu()
				reglas.atacar(atacante, o)
		Estado.LIBRE:
			var u := mapa.unidad_en(celda)
			if u != null:
				seleccionar(u)
			elif celda == reglas.celda_base(equipo_actual):
				_abrir_compra()
		Estado.SELECCIONADA:
			if _puede_mover(seleccionada) and celda == seleccionada.celda:
				# Tocar otra vez la unidad: se queda quieta y abre el menú de acciones.
				var u := seleccionada
				deseleccionar()
				_abrir_menu_unidad(u)
			elif _puede_mover(seleccionada) and celda in alcance["destinos"]:
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


## Mueve la unidad con animación. También la usa la IA.
func mover(u: Unidad, destino: Vector2i) -> void:
	estado = Estado.MOVIENDO
	resaltado.limpiar()
	if destino != u.celda:
		reglas.reiniciar_captura(u.celda)  # si se va de una ciudad a medias, pierde el avance
	var alcance_u := alcance if seleccionada == u else mapa.calcular_alcance(u)
	var puntos: Array[Vector2] = []
	for c in mapa.camino_hasta(alcance_u, destino):
		puntos.append(mapa.celda_a_pos(c))
	mapa.mover_registro(u, destino)
	await u.recorrer(puntos)
	u.ya_se_movio = true
	if turno_ia:
		u.marcar_usada(true)  # la IA no usa el menú
	seleccionada = null
	alcance = {}
	estado = Estado.LIBRE
	unidad_movida.emit(u)


func _on_unidad_movida(u: Unidad) -> void:
	if juego_terminado:
		return
	if turno_ia or u.equipo != "azul":
		return  # la IA no usa el menú; ella decide si ataca o captura
	_abrir_menu_unidad(u)


# ---------------------------------------------------------------- menú de acciones

func _construir_interfaz() -> void:
	menu = PanelContainer.new()
	menu.position = POS_MENU
	menu.visible = false
	caja_menu = VBoxContainer.new()
	menu.add_child(caja_menu)
	$HUD.add_child(menu)
	etiqueta_mensaje = Label.new()
	etiqueta_mensaje.position = Vector2(170, 110)
	etiqueta_mensaje.add_theme_font_size_override("font_size", 24)
	etiqueta_mensaje.visible = false
	$HUD.add_child(etiqueta_mensaje)


## opciones: lista de [texto, Callable, (deshabilitado)]
func _mostrar_menu(opciones: Array) -> void:
	for h in caja_menu.get_children():
		caja_menu.remove_child(h)
		h.queue_free()
	for o in opciones:
		var b := Button.new()
		b.text = o[0]
		b.disabled = o.size() > 2 and o[2]
		b.add_theme_font_size_override("font_size", FUENTE_MENU)
		b.pressed.connect(o[1])
		caja_menu.add_child(b)
	menu.reset_size()
	menu.visible = true


func _cerrar_menu() -> void:
	menu.visible = false
	resaltado.limpiar()
	objetivos_actuales.clear()
	unidad_menu = null
	estado = Estado.LIBRE


func _abrir_menu_unidad(u: Unidad) -> void:
	estado = Estado.MENU
	unidad_menu = u
	resaltado.limpiar()
	var opciones := []
	if not reglas.objetivos_de(u).is_empty():
		opciones.append(["Atacar", _elegir_ataque])
	if reglas.puede_capturar(u):
		opciones.append(["Capturar", _accion_capturar])
	opciones.append(["Esperar", _accion_esperar])
	_mostrar_menu(opciones)


func _elegir_ataque() -> void:
	objetivos_actuales = reglas.objetivos_de(unidad_menu)
	var celdas: Array[Vector2i] = []
	for o in objetivos_actuales:
		celdas.append(o.celda)
	resaltado.mostrar(celdas, Resaltado.COLOR_ENEMIGO, unidad_menu.celda)
	estado = Estado.OBJETIVO
	_mostrar_menu([["Cancelar", func(): _abrir_menu_unidad(unidad_menu)]])


func _accion_capturar() -> void:
	var u := unidad_menu
	_cerrar_menu()
	reglas.capturar(u)


func _accion_esperar() -> void:
	var u := unidad_menu
	_cerrar_menu()
	reglas.marcar_lista(u)


func _abrir_compra() -> void:
	estado = Estado.MENU
	var opciones := []
	for tipo in Datos.UNIDADES:
		var d: Dictionary = Datos.UNIDADES[tipo]
		var sin_plata: bool = reglas.creditos[equipo_actual] < d["precio"]
		opciones.append(["%s  %d" % [d["nombre"], d["precio"]], _comprar.bind(tipo), sin_plata])
	opciones.append(["Cerrar", _cerrar_menu])
	_mostrar_menu(opciones)


func _comprar(tipo: String) -> void:
	reglas.comprar(tipo, equipo_actual)
	_cerrar_menu()


# ---------------------------------------------------------------- turnos

## Cambia de equipo, reactiva sus unidades, paga el ingreso y,
## si le toca a la máquina, juega la IA y devuelve el turno.
func terminar_turno() -> void:
	if estado == Estado.MOVIENDO or turno_ia or juego_terminado:
		return
	if unidad_menu != null:  # quedó a medias: se da por usada
		reglas.marcar_lista(unidad_menu)
	_cerrar_menu()
	deseleccionar()
	equipo_actual = "rojo" if equipo_actual == "azul" else "azul"
	for u in mapa.unidades_de(equipo_actual):
		u.reiniciar_turno()
	reglas.al_empezar_turno(equipo_actual)
	_actualizar_hud()
	if equipo_actual == ia.equipo:
		turno_ia = true
		boton_terminar.disabled = true
		await ia.jugar_turno()
		turno_ia = false
		boton_terminar.disabled = juego_terminado
		if not juego_terminado:
			terminar_turno()


func _on_partida_terminada(ganador: String) -> void:
	juego_terminado = true
	_cerrar_menu()
	deseleccionar()
	boton_terminar.disabled = true
	etiqueta_mensaje.text = "¡Victoria!" if ganador == "azul" else "Derrota"
	etiqueta_mensaje.visible = true


func _actualizar_hud() -> void:
	var quien := "Azul" if equipo_actual == "azul" else "Rojo"
	var azul: int = reglas.creditos.get("azul", 0)
	var rojo: int = reglas.creditos.get("rojo", 0)
	etiqueta_turno.text = "Turno: %s  |  Azul: %d  Rojo: %d" % [quien, azul, rojo]
