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
@onready var ia: IA = $IA
@onready var hud: HUD = $HUD

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
## Enemigos que la unidad seleccionada puede atacar este turno: celda del enemigo -> casilla desde donde atacar.
var ataques_posibles := {}
## true mientras una unidad se mueve para atacar (así no se abre el menú de acciones).
var atacando_directo := false
## Mientras se resuelve un ataque se anotan los golpes, para mostrarlos en la cinemática.
var _grabando := false
var _eventos: Array = []
var menu: PanelContainer
var caja_menu: VBoxContainer


func _ready() -> void:
	Sonido.iniciar()
	reglas = Reglas.new()
	add_child(reglas)
	reglas.partida_terminada.connect(_on_partida_terminada)
	reglas.creditos_cambiados.connect(func(_e, _c): _actualizar_hud())
	reglas.unidad_atacada.connect(_mostrar_dano)
	reglas.ciudad_capturada.connect(_celebrar_captura)
	hud.tienda_pedida.connect(_on_tienda)
	unidad_movida.connect(_on_unidad_movida)
	_construir_interfaz()
	hud.terminar_turno_pedido.connect(terminar_turno)
	hud.nuevo_mapa_pedido.connect(nuevo_mapa)
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
	_cerrar_menu()
	hud.cerrar_todo()
	hud.bloquear_botones(false)
	reglas.iniciar(mapa)
	reglas.al_empezar_turno(equipo_actual)  # el azul cobra al empezar
	# Centrar el mapa en la pantalla (dejando arriba la franja del HUD).
	var tamano := Vector2(mapa.ancho, mapa.alto) * Datos.TAM_CASILLA
	var pantalla := get_viewport_rect().size
	mapa.position = Vector2(floorf((pantalla.x - tamano.x) / 2.0), 30 + floorf((pantalla.y - 30 - tamano.y) / 2.0))
	_actualizar_hud()
	if not modo_prueba:
		hud.mostrar_cartel("TU TURNO", Color(0.2, 0.45, 0.9))


# ---------------------------------------------------------------- entrada táctil

## En Android los toques llegan como clic de mouse (Godot los convierte solo),
## así que esto funciona igual en el PC y en el celular.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Pasar la posición del toque (en pantalla) a coordenadas del mapa.
		var celda := mapa.pos_a_celda(mapa.to_local(get_canvas_transform().affine_inverse() * event.position))
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
				estado = Estado.MOVIENDO
				await ejecutar_ataque(atacante, o)
				estado = Estado.LIBRE
		Estado.LIBRE:
			var u := mapa.unidad_en(celda)
			if u != null:
				seleccionar(u)
			elif celda == reglas.celda_base(equipo_actual):
				_abrir_compra()
		Estado.SELECCIONADA:
			if _puede_mover(seleccionada) and ataques_posibles.has(celda):
				# Tocar un enemigo marcado en rojo: la unidad va y lo ataca.
				_mover_y_atacar(seleccionada, ataques_posibles[celda], mapa.unidad_en(celda))
			elif _puede_mover(seleccionada) and celda == seleccionada.celda:
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
	ataques_posibles = _calcular_ataques(u) if _puede_mover(u) else {}
	var color := Resaltado.COLOR_MOVER if _puede_mover(u) else Resaltado.COLOR_ENEMIGO
	var marcados: Array[Vector2i] = []
	marcados.assign(ataques_posibles.keys())
	resaltado.mostrar(alcance["destinos"], color, u.celda, marcados)
	hud.mostrar_info(_texto_info(u), u.celda.x < mapa.ancho / 2)
	estado = Estado.SELECCIONADA
	Sonido.reproducir("seleccion", -4.0)


func deseleccionar() -> void:
	seleccionada = null
	alcance = {}
	ataques_posibles = {}
	resaltado.limpiar()
	hud.ocultar_info()
	estado = Estado.LIBRE


## Para cada enemigo que la unidad puede atacar este turno, elige desde qué casilla hacerlo:
## primero quedarse quieta; si no, la casilla con más defensa y más cercana.
func _calcular_ataques(u: Unidad) -> Dictionary:
	var resultado := {}
	if u.ya_ataco:
		return resultado
	var datos := u.datos()
	var desde_posibles: Array[Vector2i] = alcance["destinos"]
	if datos["rango_min"] > 1:
		desde_posibles = [u.celda]  # la artillería no ataca después de moverse
	for e in mapa.unidades_de(reglas.otro_equipo(u.equipo)):
		var mejor := Vector2i(-1, -1)
		var mejor_puntos := -INF
		for d in desde_posibles:
			var dist := mapa.distancia(d, e.celda)
			if dist < datos["rango_min"] or dist > datos["rango_max"]:
				continue
			var puntos: float = Datos.TERRENOS[mapa.terreno_en(d)]["defensa"] * 10 - mapa.camino_hasta(alcance, d).size()
			if d == u.celda:
				puntos += 100
			if puntos > mejor_puntos:
				mejor_puntos = puntos
				mejor = d
		if mejor.x >= 0:
			resultado[e.celda] = mejor
	return resultado


func _mover_y_atacar(u: Unidad, desde: Vector2i, objetivo: Unidad) -> void:
	atacando_directo = true
	if desde != u.celda:
		await mover(u, desde)
	else:
		deseleccionar()
	atacando_directo = false
	u.ya_se_movio = true
	estado = Estado.MOVIENDO
	await ejecutar_ataque(u, objetivo)
	estado = Estado.LIBRE


func _texto_info(u: Unidad) -> String:
	var d := u.datos()
	var rango := str(d["rango_min"]) if d["rango_min"] == d["rango_max"] else "%d-%d" % [d["rango_min"], d["rango_max"]]
	var gana: String = Datos.UNIDADES[Datos.LE_GANA_A[u.tipo]]["nombre"]
	var texto := "%s (%s)\nVida %d/%d   Mov %d   Alcance %s\nLe gana a: %s" % [
		d["nombre"], u.equipo, u.vida, d["vida_max"], d["movimiento"], rango, gana]
	if not ataques_posibles.is_empty():
		texto += "\nToca un enemigo en rojo para atacar"
	return texto


## Al terminar una captura: sonido, chispas del color del equipo y un letrerito.
func _celebrar_captura(celda: Vector2i, equipo: String) -> void:
	Sonido.reproducir("captura")
	var color := Color(0.4, 0.7, 1.0) if equipo == "azul" else Color(1.0, 0.4, 0.35)
	var pos := mapa.celda_a_pos(celda)
	Efectos.chispas(mapa, pos, 16, 1.2, color)
	var etiqueta := Label.new()
	etiqueta.text = "¡Capturada!"
	etiqueta.add_theme_font_size_override("font_size", 10)
	etiqueta.add_theme_color_override("font_color", color)
	etiqueta.add_theme_color_override("font_outline_color", Color.BLACK)
	etiqueta.add_theme_constant_override("outline_size", 4)
	etiqueta.position = pos + Vector2(-26, -22)
	etiqueta.z_index = 10
	mapa.add_child(etiqueta)
	var tw := etiqueta.create_tween()
	tw.tween_property(etiqueta, "position:y", etiqueta.position.y - 8, 1.0)
	tw.parallel().tween_property(etiqueta, "modulate:a", 0.0, 1.0).set_delay(0.5)
	tw.tween_callback(etiqueta.queue_free)


## Resuelve un ataque con su animación. La usan el jugador y la IA.
## - Con cinemáticas: se calcula el resultado y se muestra en la pantalla de combate.
## - Sin cinemáticas: la unidad se lanza hacia el enemigo en el mapa.
func ejecutar_ataque(atacante: Unidad, objetivo: Unidad) -> void:
	if not reglas.puede_atacar(atacante, objetivo) or atacante.ya_ataco:
		return
	var azul := atacante if atacante.equipo == "azul" else objetivo
	var rojo := objetivo if azul == atacante else atacante
	var info_azul := _info_combate(azul)
	var info_rojo := _info_combate(rojo)
	var con_cinematica := Cinematica.activadas and not modo_prueba
	if not con_cinematica:
		await _embestida(atacante, objetivo)
	_eventos.clear()
	_grabando = con_cinematica
	reglas.atacar(atacante, objetivo)
	_grabando = false
	if con_cinematica and not _eventos.is_empty():
		var cine := Cinematica.new()
		add_child(cine)
		await cine.reproducir(info_azul, info_rojo, _eventos.duplicate())


func _info_combate(u: Unidad) -> Dictionary:
	var terreno := mapa.terreno_en(u.celda)
	var datos_t: Dictionary = Datos.TERRENOS[terreno]
	var adorno := Vector2i(-1, -1)
	var dueno := mapa.dueno_en(u.celda)
	if dueno != "" and datos_t.has("adorno_" + dueno):
		adorno = datos_t["adorno_" + dueno]
	elif datos_t.has("adorno"):
		adorno = datos_t["adorno"]
	return {"tipo": u.tipo, "equipo": u.equipo, "vida": u.vida, "terreno": terreno, "adorno": adorno}


## Animación rápida en el mapa: el atacante se lanza hacia el enemigo y vuelve.
## La artillería, en cambio, dispara un proyectil.
func _embestida(atacante: Unidad, objetivo: Unidad) -> void:
	var origen := atacante.position
	if atacante.datos()["rango_min"] > 1:
		Sonido.reproducir("canon")
		var bala := ColorRect.new()
		bala.color = Color(1, 0.9, 0.4)
		bala.size = Vector2(3, 3)
		bala.position = origen
		bala.z_index = 15
		mapa.add_child(bala)
		var tw := bala.create_tween()
		tw.tween_property(bala, "position", objetivo.position, 0.3)
		await tw.finished
		bala.queue_free()
	else:
		Sonido.reproducir("disparo")
		var dir := (objetivo.position - origen).normalized()
		var tw := atacante.create_tween()
		tw.tween_property(atacante, "position", origen + dir * 6, 0.07)
		tw.tween_property(atacante, "position", origen, 0.1)
		await tw.finished
	Efectos.chispas(mapa, objetivo.position, 10)


## Número de daño flotando sobre la unidad golpeada, parpadeo y explosión si muere.
func _mostrar_dano(atacante: Unidad, objetivo: Unidad, dano: int) -> void:
	if _grabando:
		_eventos.append({"lado": "izq" if atacante.equipo == "azul" else "der",
			"dano": dano, "vida_final": objetivo.vida})
	elif objetivo.vida > 0:
		Sonido.reproducir("golpe")
	if objetivo.vida <= 0:
		Efectos.explosion(mapa, objetivo.position)
		if not _grabando:
			Sonido.reproducir("explosion")
	var etiqueta := Label.new()
	etiqueta.text = "-%d" % dano
	etiqueta.add_theme_font_size_override("font_size", 12)
	etiqueta.add_theme_color_override("font_color", Color(1, 0.35, 0.3))
	etiqueta.add_theme_color_override("font_outline_color", Color.BLACK)
	etiqueta.add_theme_constant_override("outline_size", 4)
	etiqueta.position = objetivo.position + Vector2(-6, -18)
	etiqueta.z_index = 10
	mapa.add_child(etiqueta)
	var tween := etiqueta.create_tween()
	tween.tween_property(etiqueta, "position:y", etiqueta.position.y - 10, 0.8)
	tween.parallel().tween_property(etiqueta, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.tween_callback(etiqueta.queue_free)
	if objetivo.vida > 0:
		objetivo.destello()


## Mueve la unidad con animación. También la usa la IA.
func mover(u: Unidad, destino: Vector2i) -> void:
	estado = Estado.MOVIENDO
	resaltado.limpiar()
	hud.ocultar_info()
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
	if turno_ia or u.equipo != "azul" or atacando_directo:
		return  # la IA no usa el menú; ella decide si ataca o captura
	_abrir_menu_unidad(u)


# ---------------------------------------------------------------- menú de acciones

func _construir_interfaz() -> void:
	menu = PanelContainer.new()
	menu.position = POS_MENU
	menu.visible = false
	caja_menu = VBoxContainer.new()
	menu.add_child(caja_menu)
	hud.add_child(menu)
	# Que quede debajo del menú de pausa y de la pantalla de fin (si no, se podría tocar a través de ellos).
	hud.move_child(menu, hud.get_node("%MenuPausa").get_index())


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
	# Ponerlo en el lado contrario a la unidad, para no taparla.
	var referencia: Vector2i = unidad_menu.celda if unidad_menu != null else reglas.celda_base(equipo_actual)
	var a_la_derecha := referencia.x < mapa.ancho / 2
	menu.position = Vector2(get_viewport_rect().size.x - menu.size.x - POS_MENU.x, POS_MENU.y) if a_la_derecha else POS_MENU
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
	if opciones.is_empty():
		# No hay nada que elegir: la unidad termina sola, sin preguntar.
		_accion_esperar()
		return
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
	if mapa.unidad_en(reglas.celda_base(equipo_actual)) != null:
		opciones = [["Base ocupada: mueve esa unidad", func(): pass, true]]
	opciones.append(["Cerrar", _cerrar_menu])
	_mostrar_menu(opciones)


func _on_tienda() -> void:
	if estado == Estado.SELECCIONADA:
		deseleccionar()
	if estado == Estado.LIBRE and not turno_ia and not juego_terminado:
		_abrir_compra()


func _comprar(tipo: String) -> void:
	if reglas.comprar(tipo, equipo_actual):
		Sonido.reproducir("compra")
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
		hud.bloquear_botones(true)
		if not modo_prueba:
			await hud.mostrar_cartel("TURNO DEL ROJO", Color(0.8, 0.2, 0.2))
		await ia.jugar_turno()
		turno_ia = false
		hud.bloquear_botones(false)
		if not juego_terminado:
			terminar_turno()
	elif not modo_prueba:
		await hud.mostrar_cartel("TU TURNO", Color(0.2, 0.45, 0.9))


func _on_partida_terminada(ganador: String) -> void:
	terminar_partida(ganador)


## Muestra la pantalla de victoria o derrota. ganador: "azul" o "rojo".
func terminar_partida(ganador: String) -> void:
	juego_terminado = true
	_cerrar_menu()
	deseleccionar()
	hud.mostrar_fin(ganador)


func _actualizar_hud() -> void:
	hud.mostrar_turno(equipo_actual, reglas.creditos)


## Botón "atrás" de Android: abre o cierra el menú de pausa.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and not turno_ia:
		if hud.hay_menu_abierto():
			hud.cerrar_pausa()
		else:
			hud.abrir_pausa()
