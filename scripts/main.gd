extends Node2D
## Escena principal: recibe los toques en pantalla y controla la selección, el movimiento,
## los menús de acciones y de tienda, la cámara y la niebla.

## Se emite cuando una unidad termina de moverse.
signal unidad_movida(unidad: Unidad)

enum Estado { LIBRE, SELECCIONADA, MOVIENDO, MENU, OBJETIVO, APUNTAR }

const POS_MENU := Vector2(8, 40)   # dónde aparece el menú (el juego se dibuja a 480x270)
const FUENTE_MENU := 10
const ALTO_BARRA := 30.0           # franja del HUD arriba
const UMBRAL_ARRASTRE := 6.0       # píxeles que hay que mover el dedo para que sea arrastre y no toque
const TIEMPO_PRESION_LARGA := 0.45 # segundos manteniendo el dedo para ver detalles

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
var numero_turno := 1
var seleccionada: Unidad = null
var alcance := {}

# --- reglas (Persona 1) ---
var reglas: Reglas
var juego_terminado := false
var unidad_menu: Unidad = null
var objetivos_actuales: Array[Unidad] = []
## Enemigos que la unidad seleccionada puede atacar este turno: celda del enemigo -> casilla desde donde atacar.
var ataques_posibles := {}
## Enemigo del que se está mostrando la vista previa (mantener presionado).
var objetivo_previsto := Vector2i(-1, -1)
## true mientras una unidad se mueve para atacar (así no se abre el menú de acciones).
var atacando_directo := false
## Mientras se resuelve un ataque se anotan los golpes, para mostrarlos en la cinemática.
var _grabando := false
var _eventos: Array = []
var menu: PanelContainer
var caja_menu: VBoxContainer
## Al apuntar una habilidad o una torreta: casillas válidas y qué hacer al tocar una.
var _celdas_apuntar: Array[Vector2i] = []
var _al_apuntar: Callable
# --- cámara ---
var camara := Camera2D.new()
var _presionado := false
var _arrastrando := false
var _inicio_toque := Vector2.ZERO
var _tiempo_presion := 0.0
var _presion_larga_hecha := false


func _ready() -> void:
	Sonido.iniciar()
	add_child(camara)
	camara.make_current()
	reglas = Reglas.new()
	add_child(reglas)
	reglas.partida_terminada.connect(_on_partida_terminada)
	reglas.creditos_cambiados.connect(func(_e, _c): _actualizar_hud())
	reglas.unidad_atacada.connect(_mostrar_dano)
	reglas.unidad_danada.connect(_mostrar_dano_bombardeo)
	reglas.unidad_curada.connect(_mostrar_curacion)
	reglas.ciudad_capturada.connect(_celebrar_captura)
	hud.tienda_pedida.connect(_on_tienda)
	hud.truco_dinero.connect(_alternar_dinero_infinito)
	unidad_movida.connect(_on_unidad_movida)
	_construir_interfaz()
	hud.terminar_turno_pedido.connect(terminar_turno)
	hud.nuevo_mapa_pedido.connect(nuevo_mapa)
	if modo_prueba:
		_cargar_mapa_de_prueba()
	else:
		nuevo_mapa()


func _process(delta: float) -> void:
	# Mantener presionado (sin arrastrar) = ver detalles, sin actuar.
	if _presionado and not _arrastrando and not _presion_larga_hecha:
		_tiempo_presion += delta
		if _tiempo_presion >= TIEMPO_PRESION_LARGA:
			_presion_larga_hecha = true
			_toque_largo(_inicio_toque)
	_revisar_fin_de_turno(delta)
	if mapa.niebla_activa:
		mapa.actualizar_vision("azul", reglas.radar_activo.has("azul"))


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
	numero_turno = 1
	juego_terminado = false
	_cerrar_menu()
	hud.cerrar_todo()
	hud.bloquear_botones(false)
	ia.dificultad = Config.dificultad
	reglas.multiplicador_ingreso = {"azul": 1.0, "rojo": Datos.DIFICULTADES[Config.dificultad]["ingreso"]}
	reglas.iniciar(mapa)
	reglas.al_empezar_turno(equipo_actual)  # el azul cobra al empezar
	mapa.niebla_activa = Config.niebla and not modo_prueba
	mapa.actualizar_vision("azul")
	mapa.position = Vector2.ZERO
	var cuartel := mapa.buscar_edificio("cuartel", "azul")
	camara.position = _limitar_camara(mapa.celda_a_pos(cuartel) if mapa.en_mapa(cuartel) else Vector2.ZERO)
	camara.reset_smoothing()
	_actualizar_hud()
	if not modo_prueba:
		hud.mostrar_cartel("TU TURNO", Color(0.2, 0.45, 0.9))


# ---------------------------------------------------------------- cámara

## Mantiene la cámara dentro del mapa (si el mapa es más pequeño que la pantalla, lo centra).
func _limitar_camara(pos: Vector2) -> Vector2:
	var vista := get_viewport_rect().size
	var tamano := Vector2(mapa.ancho, mapa.alto) * Datos.TAM_CASILLA
	var margen := 8.0
	var resultado := pos
	var min_x := vista.x / 2.0 - margen
	var max_x := tamano.x + margen - vista.x / 2.0
	resultado.x = tamano.x / 2.0 if max_x < min_x else clampf(pos.x, min_x, max_x)
	var min_y := vista.y / 2.0 - ALTO_BARRA - margen
	var max_y := tamano.y + margen - vista.y / 2.0
	resultado.y = (tamano.y - ALTO_BARRA) / 2.0 if max_y < min_y else clampf(pos.y, min_y, max_y)
	return resultado


## Mueve la cámara para que se vea una unidad (la usa la IA para que sigas sus jugadas).
func enfocar(u: Unidad) -> void:
	if is_instance_valid(u) and mapa.se_ve(u.celda):
		await enfocar_celda(u.celda)


func enfocar_celda(celda: Vector2i) -> void:
	var en_pantalla := get_canvas_transform() * mapa.celda_a_pos(celda)
	var vista := get_viewport_rect().size
	if Rect2(48, ALTO_BARRA + 30, vista.x - 96, vista.y - ALTO_BARRA - 60).has_point(en_pantalla):
		return
	var tw := create_tween()
	tw.tween_property(camara, "position", _limitar_camara(mapa.celda_a_pos(celda)), 0.3)
	await tw.finished


func _en_pantalla(celda: Vector2i) -> Vector2:
	return get_canvas_transform() * mapa.celda_a_pos(celda)


# ---------------------------------------------------------------- entrada táctil

## En Android los toques llegan como clic de mouse (Godot los convierte solo),
## así que esto funciona igual en el PC y en el celular.
## Arrastrar el dedo mueve la cámara; un toque corto selecciona.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_presionado = true
			_arrastrando = false
			_presion_larga_hecha = false
			_tiempo_presion = 0.0
			_inicio_toque = event.position
		else:
			if _presionado and not _arrastrando and not _presion_larga_hecha:
				_toque_en_pantalla(event.position)
			_presionado = false
	elif event is InputEventMouseMotion and _presionado:
		if not _arrastrando and event.position.distance_to(_inicio_toque) > UMBRAL_ARRASTRE:
			_arrastrando = true
		if _arrastrando:
			camara.position = _limitar_camara(camara.position - event.relative)


func _toque_en_pantalla(pos: Vector2) -> void:
	# Pasar la posición del toque (en pantalla) a coordenadas del mapa.
	var celda := mapa.pos_a_celda(mapa.to_local(get_canvas_transform().affine_inverse() * pos))
	if mapa.en_mapa(celda):
		tocar_celda(celda)
	elif estado == Estado.SELECCIONADA:
		deseleccionar()


## Mantener presionado: vista previa del daño sobre un enemigo atacable, o la ficha de una unidad.
func _toque_largo(pos: Vector2) -> void:
	if turno_ia or juego_terminado:
		return
	var celda := mapa.pos_a_celda(mapa.to_local(get_canvas_transform().affine_inverse() * pos))
	if not mapa.en_mapa(celda):
		return
	if estado == Estado.SELECCIONADA and ataques_posibles.has(celda):
		_mostrar_prevision(seleccionada, mapa.unidad_en(celda), ataques_posibles[celda])
	elif estado == Estado.OBJETIVO and _unidad_visible(celda) in objetivos_actuales:
		_mostrar_prevision(unidad_menu, mapa.unidad_en(celda), unidad_menu.celda)
	else:
		var u := _unidad_visible(celda)
		if u != null:
			hud.mostrar_info(_texto_info(u, true), _en_pantalla(celda).x < get_viewport_rect().size.x / 2.0)
	Sonido.reproducir("seleccion", -8.0)


## Unidad que el jugador puede ver en esa casilla (con niebla, las enemigas escondidas no cuentan).
func _unidad_visible(celda: Vector2i) -> Unidad:
	var u := mapa.unidad_en(celda)
	if u != null and u.equipo != equipo_actual and not mapa.se_ve(celda):
		return null
	return u


func tocar_celda(celda: Vector2i) -> void:
	if turno_ia or juego_terminado:
		return
	match estado:
		Estado.MOVIENDO, Estado.MENU:
			return
		Estado.APUNTAR:
			var accion := _al_apuntar
			var valida := celda in _celdas_apuntar
			_cerrar_menu()
			if valida:
				accion.call(celda)
		Estado.OBJETIVO:
			# Después de moverse: tocar un enemigo marcado lo ataca; tocar la propia unidad = esperar.
			var o := _unidad_visible(celda)
			if o != null and o in objetivos_actuales:
				var atacante := unidad_menu
				_cerrar_menu()
				estado = Estado.MOVIENDO
				await ejecutar_ataque(atacante, o)
				estado = Estado.LIBRE
			elif unidad_menu != null and celda == unidad_menu.celda:
				_accion_esperar()
		Estado.LIBRE:
			var u := _unidad_visible(celda)
			if u != null:
				seleccionar(u)
			elif celda == reglas.celda_base(equipo_actual):
				_abrir_compra()
		Estado.SELECCIONADA:
			if _puede_mover(seleccionada) and ataques_posibles.has(celda):
				# Tocar un enemigo marcado en rojo: la unidad va y lo ataca (el daño ya se ve encima).
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
				var otra := _unidad_visible(celda)
				if otra != null and otra != anterior:
					seleccionar(otra)


# ---------------------------------------------------------------- selección y movimiento

func _puede_mover(u: Unidad) -> bool:
	return u.equipo == equipo_actual and not u.ya_se_movio


## Selecciona una unidad. Si es propia muestra en azul a dónde se puede mover;
## si es enemiga (o ya se movió) muestra su alcance en rojo, solo como información.
func seleccionar(u: Unidad) -> void:
	seleccionada = u
	objetivo_previsto = Vector2i(-1, -1)
	var ignorar := mapa.ocultos_para(u.equipo) if u.equipo == equipo_actual else {}
	alcance = mapa.calcular_alcance(u, ignorar)
	ataques_posibles = _calcular_ataques(u) if _puede_mover(u) else {}
	var color := Resaltado.COLOR_MOVER if _puede_mover(u) else Resaltado.COLOR_MOV_ENEMIGO
	var marcados: Array[Vector2i] = []
	marcados.assign(ataques_posibles.keys())
	resaltado.mostrar(alcance["destinos"], color, u.celda, marcados)
	if u.equipo != equipo_actual:
		resaltado.zona_ataque = _zona_ataque(u, alcance["destinos"])
	for c in ataques_posibles:
		var est := reglas.estimar(u, mapa.unidad_en(c), ataques_posibles[c])
		resaltado.etiquetas[c] = "✖" if est["destruye"] else "-%d" % est["dano"]
	resaltado.queue_redraw()
	hud.mostrar_info(_texto_info(u), _en_pantalla(u.celda).x < get_viewport_rect().size.x / 2.0)
	estado = Estado.SELECCIONADA
	Sonido.reproducir("seleccion", -4.0)


func deseleccionar() -> void:
	seleccionada = null
	alcance = {}
	ataques_posibles = {}
	objetivo_previsto = Vector2i(-1, -1)
	resaltado.limpiar()
	hud.ocultar_info()
	estado = Estado.LIBRE


## Casillas que una unidad puede atacar el próximo turno y que no están en su área de movimiento.
func _zona_ataque(u: Unidad, destinos: Array[Vector2i]) -> Array[Vector2i]:
	var d := u.datos()
	var origenes: Array[Vector2i] = destinos
	if d["rango_min"] > 1 or d["movimiento"] == 0:
		origenes = [u.celda]  # la artillería y la torreta atacan sin moverse
	var en_movimiento := {}
	for c in destinos:
		en_movimiento[c] = true
	var zona := {}
	for o in origenes:
		for dy in range(-d["rango_max"], d["rango_max"] + 1):
			for dx in range(-d["rango_max"], d["rango_max"] + 1):
				var dist := absi(dx) + absi(dy)
				var c := o + Vector2i(dx, dy)
				# Si ataca sin moverse (artillería), se muestra toda su zona aunque se cruce con el movimiento.
				var tapada := en_movimiento.has(c) and origenes.size() > 1
				if dist >= d["rango_min"] and dist <= d["rango_max"] and mapa.en_mapa(c) and not tapada:
					zona[c] = true
	var lista: Array[Vector2i] = []
	lista.assign(zona.keys())
	return lista


## Para cada enemigo visible que la unidad puede atacar este turno, elige desde qué casilla:
## primero quedarse quieta; si no, la que deja mejor resultado (más daño, menos contraataque).
func _calcular_ataques(u: Unidad) -> Dictionary:
	var resultado := {}
	if u.ya_ataco:
		return resultado
	var desde_posibles: Array[Vector2i] = []
	if u.datos()["rango_min"] > 1 or u.datos()["movimiento"] == 0:
		desde_posibles = [u.celda]  # la artillería no ataca después de moverse; la torreta no se mueve
	else:
		for d in alcance["destinos"]:
			if mapa.unidad_en(d) == null or d == u.celda:  # no contar casillas con enemigos escondidos
				desde_posibles.append(d)
	for e in mapa.unidades_de(reglas.otro_equipo(u.equipo)):
		if not mapa.se_ve(e.celda):
			continue
		var mejor := Vector2i(-1, -1)
		var mejor_puntos := -INF
		for d in desde_posibles:
			if not reglas.puede_atacar_desde(u, d, e):
				continue
			var est := reglas.estimar(u, e, d)
			var puntos: float = est["dano"] * 3 - est["contra"] * 2 - mapa.camino_hasta(alcance, d).size() * 0.1
			if d == u.celda:
				puntos += 1.0
			if puntos > mejor_puntos:
				mejor_puntos = puntos
				mejor = d
		if mejor.x >= 0:
			resultado[e.celda] = mejor
	return resultado


## Vista previa del daño en el panel de información (al mantener presionado un enemigo).
func _mostrar_prevision(atacante: Unidad, objetivo: Unidad, desde: Vector2i) -> void:
	objetivo_previsto = objetivo.celda
	var est := reglas.estimar(atacante, objetivo, desde)
	var texto := "%s ♥%d: " % [objetivo.nombre_con_rango(), objetivo.vida]
	texto += "¡lo destruyes! (-%d)" % est["dano"] if est["destruye"] else "-%d, le quedan %d" % [est["dano"], objetivo.vida - est["dano"]]
	var extras := []
	if not est["destruye"]:
		extras.append("te devuelve -%d%s" % [est["contra"], " ¡y te destruye!" if est["muere"] else ""] if est["contra"] > 0 else "sin contraataque")
	extras.append("crítico %d%%" % int(est["critico"] * 100))
	if est["flanqueo"] > 0:
		extras.append("flanqueo +%d%%" % int(est["flanqueo"] * Reglas.BONO_FLANQUEO * 100))
	var defensa: int = 0 if objetivo.es_aerea() else Datos.TERRENOS[mapa.terreno_en(objetivo.celda)]["defensa"]
	if defensa > 0:
		extras.append("su terreno -%d%%" % (defensa * 10))
	texto += "\n" + " · ".join(extras)
	hud.mostrar_info(texto, _en_pantalla(atacante.celda).x < get_viewport_rect().size.x / 2.0)


func _mover_y_atacar(u: Unidad, desde: Vector2i, objetivo: Unidad) -> void:
	atacando_directo = true
	if desde != u.celda:
		await mover(u, desde)
	else:
		deseleccionar()
	atacando_directo = false
	if not is_instance_valid(u) or u.ya_ataco:
		return  # cayó en una emboscada en el camino
	u.ya_se_movio = true
	estado = Estado.MOVIENDO
	await ejecutar_ataque(u, objetivo)
	estado = Estado.LIBRE


## Ficha de una unidad. Corta al tocarla (2 líneas); completa al mantenerla presionada.
func _texto_info(u: Unidad, completo := false) -> String:
	var d := u.datos()
	var rango := str(d["rango_min"]) if d["rango_min"] == d["rango_max"] else "%d-%d" % [d["rango_min"], d["rango_max"]]
	var defensa: int = 0 if u.es_aerea() else Datos.TERRENOS[mapa.terreno_en(u.celda)]["defensa"]
	var texto := "%s  ♥%d/%d\n" % [u.nombre_con_rango(), u.vida, d["vida_max"]]
	texto += "Mov %d · Alcance %s · Defensa %s" % [u.movimiento(), rango, "★".repeat(defensa) if defensa > 0 else "—"]
	if u.equipo == equipo_actual:
		var peligro: int = calcular_peligro(u.equipo).get(u.celda, 0)
		if peligro > 0:
			texto += " · ⚠%d" % peligro
	if completo:
		var fuerza := int(100.0 * u.vida / d["vida_max"] * (1.0 + Reglas.BONO_RANGO * u.rango))
		texto += "\nFuerza %d%% · Crítico %d%%" % [fuerza, int(reglas.prob_critico(u) * 100)]
		texto += "\nFuerte contra: %s\nDébil contra: %s" % [Datos.nombres(Datos.gana_a(u.tipo)), Datos.nombres(Datos.pierde_contra(u.tipo))]
		if u.equipo != equipo_actual:
			texto += "\nNaranja: se mueve · Rojo: ataca"
	return texto


## Mueve la unidad con animación. También la usa la IA.
## Con niebla, si en el camino hay un enemigo escondido, la unidad se detiene (emboscada).
func mover(u: Unidad, destino: Vector2i) -> void:
	estado = Estado.MOVIENDO
	resaltado.limpiar()
	hud.ocultar_info()
	if destino != u.celda:
		reglas.reiniciar_captura(u.celda)  # si se va de una ciudad a medias, pierde el avance
	var alcance_u := alcance if seleccionada == u else mapa.calcular_alcance(u)
	var camino := mapa.camino_hasta(alcance_u, destino)
	var emboscada := false
	for i in camino.size():
		var otra := mapa.unidad_en(camino[i])
		if otra != null and otra.equipo != u.equipo:
			camino = camino.slice(0, i)
			emboscada = true
			break
	# No terminar encima de un aliado (pasa si el camino se cortó).
	while not camino.is_empty() and mapa.unidad_en(camino[-1]) != null:
		camino.pop_back()
	var final_ := camino[-1] if not camino.is_empty() else u.celda
	var puntos: Array[Vector2] = []
	for c in camino:
		puntos.append(mapa.celda_a_pos(c))
	mapa.mover_registro(u, final_)
	await u.recorrer(puntos)
	u.ya_se_movio = true
	if turno_ia:
		u.marcar_usada(true)  # la IA no usa el menú
	seleccionada = null
	alcance = {}
	estado = Estado.LIBRE
	if emboscada:
		_numero_flotante(u.position, "¡Emboscada!", Color(1, 0.75, 0.2))
		Sonido.reproducir("golpe")
		reglas.marcar_lista(u)
		return
	unidad_movida.emit(u)


func _on_unidad_movida(u: Unidad) -> void:
	if juego_terminado:
		return
	if turno_ia or u.equipo != "azul" or atacando_directo:
		return  # la IA no usa el menú; ella decide si ataca o captura
	_abrir_menu_unidad(u)


# ---------------------------------------------------------------- peligro (para el aviso ⚠ de la ficha)

## Casillas que el enemigo de "equipo" puede atacar el próximo turno: celda -> cuántos enemigos.
## Con niebla solo cuenta los enemigos que se ven.
func calcular_peligro(equipo: String) -> Dictionary:
	var zona := {}
	for e in mapa.unidades_de(reglas.otro_equipo(equipo)):
		if not mapa.se_ve(e.celda):
			continue
		var d := e.datos()
		var desde: Array[Vector2i] = [e.celda]
		if d["rango_min"] == 1 and d["movimiento"] > 0:
			desde = mapa.calcular_alcance(e)["destinos"]
		var alcanzadas := {}
		for origen in desde:
			for dy in range(-d["rango_max"], d["rango_max"] + 1):
				for dx in range(-d["rango_max"], d["rango_max"] + 1):
					var dist := absi(dx) + absi(dy)
					var c := origen + Vector2i(dx, dy)
					if dist >= d["rango_min"] and dist <= d["rango_max"] and mapa.en_mapa(c):
						alcanzadas[c] = true
		for c in alcanzadas:
			zona[c] = zona.get(c, 0) + 1
	return zona


## Si ya no te queda nada por hacer, el botón "Terminar turno" brilla.
var _reloj_fin := 0.0


func _revisar_fin_de_turno(delta: float) -> void:
	_reloj_fin -= delta
	if _reloj_fin > 0.0:
		return
	_reloj_fin = 0.25
	var sin_acciones := equipo_actual == "azul" and not turno_ia and not juego_terminado \
		and estado == Estado.LIBRE and reglas.mapa != null
	if sin_acciones:
		for u in mapa.unidades_de("azul"):
			if not u.ya_ataco and (not u.ya_se_movio or not reglas.objetivos_de(u).is_empty()):
				if u.datos()["movimiento"] > 0 or not reglas.objetivos_de(u).is_empty():
					sin_acciones = false
					break
	hud.resaltar_terminar(sin_acciones)


## Truco secreto para la expo: tocar 5 veces seguidas el texto del dinero (arriba a la izquierda).
func _alternar_dinero_infinito() -> void:
	Reglas.dinero_infinito = not Reglas.dinero_infinito
	reglas.aplicar_dinero_infinito()
	_actualizar_hud()
	Sonido.reproducir("compra" if Reglas.dinero_infinito else "clic")
	hud.mostrar_aviso("Modo prueba: dinero infinito " + ("ACTIVADO" if Reglas.dinero_infinito else "desactivado"), 2.0)


# ---------------------------------------------------------------- efectos en el mapa

func _numero_flotante(pos: Vector2, texto: String, color: Color, tamano := 12) -> void:
	var etiqueta := Label.new()
	etiqueta.text = texto
	etiqueta.add_theme_font_size_override("font_size", tamano)
	etiqueta.add_theme_color_override("font_color", color)
	etiqueta.add_theme_color_override("font_outline_color", Color.BLACK)
	etiqueta.add_theme_constant_override("outline_size", 4)
	etiqueta.position = pos + Vector2(-6 - 2 * maxi(0, texto.length() - 3), -18)
	etiqueta.z_index = 10
	mapa.add_child(etiqueta)
	var tween := etiqueta.create_tween()
	tween.tween_property(etiqueta, "position:y", etiqueta.position.y - 10, 0.9)
	tween.parallel().tween_property(etiqueta, "modulate:a", 0.0, 0.9).set_delay(0.4)
	tween.tween_callback(etiqueta.queue_free)


func _mostrar_dano_bombardeo(u: Unidad, dano: int) -> void:
	_numero_flotante(u.position, "-%d" % dano, Color(1, 0.35, 0.3))
	if u.vida > 0:
		u.destello()
	else:
		Efectos.explosion(mapa, u.position, 1.3)


func _mostrar_curacion(u: Unidad, cantidad: int) -> void:
	if mapa.se_ve(u.celda):
		_numero_flotante(u.position, "+%d" % cantidad, Color(0.4, 1, 0.5))
		u.destello(Color(0.5, 1, 0.5))


## Al terminar una captura: sonido, chispas del color del equipo y un letrerito.
func _celebrar_captura(celda: Vector2i, equipo: String) -> void:
	Sonido.reproducir("captura")
	var color := Color(0.4, 0.7, 1.0) if equipo == "azul" else Color(1.0, 0.4, 0.35)
	var pos := mapa.celda_a_pos(celda)
	Efectos.chispas(mapa, pos, 16, 1.2, color)
	_numero_flotante(pos, "¡Capturada!", color, 10)


# ---------------------------------------------------------------- animaciones de habilidades

## Bombardeo: un avión cruza la pantalla y suelta bombas sobre las 3 columnas del área.
func animar_bombardeo(centro: Vector2i, equipo := "azul") -> void:
	await enfocar_celda(centro)
	var objetivo := mapa.celda_a_pos(centro)
	var hacia := 1.0 if equipo == "azul" else -1.0
	var mitad := get_viewport_rect().size.x / 2.0 + 30.0
	var avion := Sprite2D.new()
	avion.texture = Datos.ATLAS
	avion.region_enabled = true
	var t := Datos.TAM_CASILLA
	avion.region_rect = Rect2(10 * t, Datos.FILA_EQUIPO[equipo] * t, t, t)
	avion.flip_h = hacia < 0
	avion.scale = Vector2(2, 2)
	avion.z_index = 25
	var altura := objetivo.y - 34.0
	var inicio_x := camara.position.x - mitad * hacia
	var fin_x := camara.position.x + mitad * hacia
	avion.position = Vector2(inicio_x, altura)
	mapa.add_child(avion)
	# Sombra del avión en el suelo.
	var sombra := ColorRect.new()
	sombra.color = Color(0, 0, 0, 0.3)
	sombra.size = Vector2(18, 4)
	sombra.z_index = 4
	mapa.add_child(sombra)
	var duracion := 1.3
	var tw := create_tween()
	tw.tween_method(func(x: float):
		avion.position.x = x
		sombra.position = Vector2(x - 9, objetivo.y + 6), inicio_x, fin_x, duracion)
	Sonido.reproducir("paso", 4.0)
	# Soltar una tanda de bombas cuando el avión pasa por cada columna.
	for dx in [-1, 0, 1]:
		var col_x: float = objetivo.x + dx * t * hacia
		var momento: float = (col_x - inicio_x) / (fin_x - inicio_x) * duracion
		get_tree().create_timer(maxf(0.0, momento)).timeout.connect(
			_soltar_bombas.bind(centro + Vector2i(int(dx * hacia), 0), altura))
	await tw.finished
	avion.queue_free()
	sombra.queue_free()
	await get_tree().create_timer(0.3).timeout


func _soltar_bombas(columna: Vector2i, altura: float) -> void:
	Sonido.reproducir("disparo", -6.0)
	for dy in [-1, 0, 1]:
		var c := columna + Vector2i(0, dy)
		if not mapa.en_mapa(c):
			continue
		var destino := mapa.celda_a_pos(c)
		var bomba := ColorRect.new()
		bomba.color = Color(0.15, 0.15, 0.15)
		bomba.size = Vector2(3, 5)
		bomba.position = Vector2(destino.x - 1.5, altura)
		bomba.z_index = 24
		mapa.add_child(bomba)
		var tw := bomba.create_tween()
		tw.tween_property(bomba, "position:y", destino.y - 2, 0.28).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback(func():
			Efectos.explosion(mapa, destino, 0.8)
			bomba.queue_free())
	get_tree().create_timer(0.28).timeout.connect(Sonido.reproducir.bind("explosion", -2.0))


## Bomba nuclear: sirena y zona en rojo, cae el misil, destello blanco, onda expansiva y hongo.
func animar_nuclear(centro: Vector2i) -> void:
	await enfocar_celda(centro)
	var pos := mapa.celda_a_pos(centro)
	var t := Datos.TAM_CASILLA
	# 1. Alarma: la zona afectada parpadea en rojo.
	Sonido.reproducir("sirena")
	var zona := Node2D.new()
	zona.z_index = 7
	mapa.add_child(zona)
	for c in reglas.area_nuclear(centro):
		var r := ColorRect.new()
		r.color = Color(1, 0.0, 0.0, 0.55)
		r.size = Vector2(t, t)
		r.position = Vector2(c * t)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		zona.add_child(r)
	var tw := zona.create_tween().set_loops(3)
	tw.tween_property(zona, "modulate:a", 0.2, 0.3)
	tw.tween_property(zona, "modulate:a", 1.0, 0.3)
	await get_tree().create_timer(1.8).timeout
	zona.queue_free()
	# 2. Cae el misil con su estela de fuego.
	var misil := Node2D.new()
	misil.z_index = 26
	var cuerpo := ColorRect.new()
	cuerpo.color = Color(0.85, 0.87, 0.9)
	cuerpo.size = Vector2(5, 16)
	cuerpo.position = Vector2(-2.5, -16)
	misil.add_child(cuerpo)
	var punta := ColorRect.new()
	punta.color = Color(0.9, 0.15, 0.1)
	punta.size = Vector2(5, 4)
	punta.position = Vector2(-2.5, 0)
	misil.add_child(punta)
	var estela := CPUParticles2D.new()
	estela.amount = 30
	estela.lifetime = 0.4
	estela.direction = Vector2.UP
	estela.spread = 15.0
	estela.initial_velocity_min = 20.0
	estela.initial_velocity_max = 40.0
	estela.scale_amount_min = 1.5
	estela.scale_amount_max = 3.0
	estela.color = Color(1, 0.6, 0.2)
	estela.position = Vector2(0, -16)
	misil.add_child(estela)
	misil.position = pos + Vector2(0, -get_viewport_rect().size.y)
	mapa.add_child(misil)
	Sonido.reproducir("canon", -4.0)
	var caida := misil.create_tween()
	caida.tween_property(misil, "position", pos, 0.7).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await caida.finished
	misil.queue_free()
	# 3. ¡Boom! Destello blanco, temblor, ondas, explosiones y hongo de humo.
	Sonido.reproducir("nuclear")
	var capa := CanvasLayer.new()
	capa.layer = 9
	var destello := ColorRect.new()
	destello.color = Color(1, 1, 0.92)
	destello.size = get_viewport_rect().size
	destello.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capa.add_child(destello)
	add_child(capa)
	var tw_d := destello.create_tween()
	tw_d.tween_property(destello, "modulate:a", 0.0, 1.0).set_delay(0.1)
	tw_d.tween_callback(capa.queue_free)
	sacudir_camara(7.0, 16)
	for k in 3:
		Efectos.onda(mapa, pos, 75.0 + k * 15, Color(1, 0.65 - k * 0.15, 0.2), 0.9 + k * 0.2)
	Efectos.explosion(mapa, pos, 4.0)
	Efectos.hongo(mapa, pos)
	var celdas: Array = reglas.area_nuclear(centro).keys()
	celdas.shuffle()
	for i in mini(14, celdas.size()):
		get_tree().create_timer(0.05 * i).timeout.connect(
			Efectos.explosion.bind(mapa, mapa.celda_a_pos(celdas[i]), 1.2))
	await get_tree().create_timer(1.3).timeout


## Reparación: un corazón sube desde la unidad entre brillitos verdes.
func animar_reparacion(u: Unidad) -> void:
	await enfocar(u)
	Sonido.reproducir("captura")
	var corazon := Sprite2D.new()
	corazon.texture = Datos.ATLAS
	corazon.region_enabled = true
	var t := Datos.TAM_CASILLA
	corazon.region_rect = Rect2(15 * t, 10 * t, t, t)
	corazon.position = u.position + Vector2(0, -6)
	corazon.z_index = 22
	mapa.add_child(corazon)
	Efectos.chispas(mapa, u.position + Vector2(0, 4), 18, 1.2, Color(0.4, 1, 0.5), true)
	var tw := corazon.create_tween()
	tw.tween_property(corazon, "position:y", corazon.position.y - 16, 0.7)
	tw.parallel().tween_property(corazon, "modulate:a", 0.0, 0.7).set_delay(0.3)
	tw.tween_callback(corazon.queue_free)
	await get_tree().create_timer(0.5).timeout


## Marcha forzada: todas las unidades dan un saltito y levantan polvo.
func animar_marcha(equipo: String) -> void:
	Sonido.reproducir("turno")
	var i := 0
	for u in mapa.unidades_de(equipo):
		if u.datos()["movimiento"] == 0 or not u.visible:
			continue
		var base_y := u.position.y
		var tw := u.create_tween()
		tw.tween_interval(i * 0.04)
		tw.tween_property(u, "position:y", base_y - 5, 0.1).set_ease(Tween.EASE_OUT)
		tw.tween_property(u, "position:y", base_y, 0.12).set_ease(Tween.EASE_IN)
		tw.tween_callback(Efectos.chispas.bind(mapa, u.position + Vector2(0, 6), 6, 1.0, Color(0.75, 0.7, 0.6)))
		_numero_flotante(u.position, "+2", Color(1, 0.9, 0.4), 9)
		i += 1
	await get_tree().create_timer(0.4 + i * 0.04).timeout


## Radar: ondas verdes que salen del cuartel general.
func animar_radar(equipo: String) -> void:
	var cuartel := mapa.buscar_edificio("cuartel", equipo)
	var origen := mapa.celda_a_pos(cuartel) if mapa.en_mapa(cuartel) else camara.position
	for k in 3:
		Sonido.reproducir("seleccion", -2.0)
		Efectos.onda(mapa, origen, 520.0, Color(0.4, 1, 0.6), 1.2)
		await get_tree().create_timer(0.25).timeout
	await get_tree().create_timer(0.4).timeout


# ---------------------------------------------------------------- combate

## Resuelve un ataque con su animación. La usan el jugador y la IA.
## - Con cinemáticas: se calcula el resultado y se muestra en la pantalla de combate.
## - Sin cinemáticas: la unidad se lanza hacia el enemigo en el mapa.
func ejecutar_ataque(atacante: Unidad, objetivo: Unidad) -> void:
	if not is_instance_valid(atacante) or not is_instance_valid(objetivo):
		return
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
	return {"tipo": u.tipo, "equipo": u.equipo, "vida": u.vida, "terreno": terreno, "adorno": adorno,
		"nombre": u.nombre_con_rango()}


## Animación rápida en el mapa: el atacante se lanza hacia el enemigo y vuelve.
## La artillería y la torreta, en cambio, disparan un proyectil.
func _embestida(atacante: Unidad, objetivo: Unidad) -> void:
	var origen := atacante.position
	if mapa.distancia(atacante.celda, objetivo.celda) > 1:
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
## Tres sonidos distintos: golpe normal, golpe crítico y unidad destruida.
func _mostrar_dano(atacante: Unidad, objetivo: Unidad, dano: int, critico := false) -> void:
	if _grabando:
		_eventos.append({"lado": "izq" if atacante.equipo == "azul" else "der",
			"dano": dano, "vida_final": objetivo.vida, "critico": critico})
	else:
		Sonido.reproducir(sonido_de_golpe(objetivo.vida <= 0, critico))
	if objetivo.vida <= 0:
		Efectos.explosion(mapa, objetivo.position, 1.3)
	if critico:
		_numero_flotante(objetivo.position + Vector2(0, -8), "¡CRÍTICO!", Color(1, 0.9, 0.2), 11)
		Efectos.chispas(mapa, objetivo.position, 18, 1.3, Color(1, 0.95, 0.4))
		if not _grabando:
			sacudir_camara(3.0)
	_numero_flotante(objetivo.position, "-%d" % dano, Color(1, 0.35, 0.3), 14 if critico else 12)
	if objetivo.vida > 0:
		objetivo.destello()
	elif not _grabando:
		sacudir_camara(2.0)


static func sonido_de_golpe(destruida: bool, critico: bool) -> String:
	if destruida:
		return "destruccion"
	return "critico" if critico else "golpe"


## Pequeño temblor de pantalla (golpes críticos, destrucciones, bomba nuclear).
func sacudir_camara(fuerza: float, veces := 5) -> void:
	var tw := create_tween()
	for i in veces:
		tw.tween_property(camara, "offset", Vector2(randf_range(-fuerza, fuerza), randf_range(-fuerza, fuerza)), 0.03)
	tw.tween_property(camara, "offset", Vector2.ZERO, 0.04)


# ---------------------------------------------------------------- menú de acciones

func _construir_interfaz() -> void:
	menu = PanelContainer.new()
	menu.position = POS_MENU
	menu.visible = false
	caja_menu = VBoxContainer.new()
	caja_menu.add_theme_constant_override("separation", 3)
	menu.add_child(caja_menu)
	hud.add_child(menu)
	# Que quede debajo del menú de pausa y de la pantalla de fin (si no, se podría tocar a través de ellos).
	hud.move_child(menu, hud.get_node("%MenuPausa").get_index())


## opciones: lista de [texto, Callable, (deshabilitado)]. Un texto sin Callable es un título.
func _mostrar_menu(opciones: Array, referencia := Vector2i(-1, -1)) -> void:
	for h in caja_menu.get_children():
		caja_menu.remove_child(h)
		h.queue_free()
	for o in opciones:
		if o[1] == null:
			var titulo := Label.new()
			titulo.text = o[0]
			titulo.add_theme_font_size_override("font_size", 9)
			titulo.modulate = Color(0.8, 0.85, 1)
			caja_menu.add_child(titulo)
			continue
		var b := Button.new()
		b.text = o[0]
		b.disabled = o.size() > 2 and o[2]
		b.add_theme_font_size_override("font_size", FUENTE_MENU)
		b.pressed.connect(o[1])
		caja_menu.add_child(b)
	menu.reset_size()
	# Ponerlo en el lado contrario a la unidad, para no taparla.
	if referencia.x < 0:
		referencia = unidad_menu.celda if unidad_menu != null else reglas.celda_base(equipo_actual)
	var a_la_derecha := not mapa.en_mapa(referencia) or _en_pantalla(referencia).x < get_viewport_rect().size.x / 2.0
	menu.position = Vector2(get_viewport_rect().size.x - menu.size.x - POS_MENU.x, POS_MENU.y) if a_la_derecha else POS_MENU
	menu.visible = true


func _cerrar_menu() -> void:
	menu.visible = false
	resaltado.limpiar()
	objetivos_actuales.clear()
	_celdas_apuntar.clear()
	objetivo_previsto = Vector2i(-1, -1)
	unidad_menu = null
	hud.ocultar_info()
	estado = Estado.LIBRE


func _abrir_menu_unidad(u: Unidad) -> void:
	estado = Estado.MENU
	unidad_menu = u
	resaltado.limpiar()
	objetivos_actuales.assign(reglas.objetivos_de(u).filter(func(e): return mapa.se_ve(e.celda)))
	var puede_capturar := reglas.puede_capturar(u)
	if objetivos_actuales.is_empty() and not puede_capturar:
		# No hay nada que elegir: la unidad termina sola, sin preguntar.
		_accion_esperar()
		return
	var opciones := []
	if not objetivos_actuales.is_empty():
		# Los enemigos al alcance quedan marcados con su daño: tocar uno lo ataca.
		var celdas: Array[Vector2i] = []
		for o in objetivos_actuales:
			celdas.append(o.celda)
		resaltado.mostrar([], Resaltado.COLOR_MOVER, u.celda, celdas)
		for o in objetivos_actuales:
			var est := reglas.estimar(u, o, u.celda)
			resaltado.etiquetas[o.celda] = "✖" if est["destruye"] else "-%d" % est["dano"]
		resaltado.queue_redraw()
		opciones.append(["Toca un enemigo para atacar", null])
		estado = Estado.OBJETIVO
	if puede_capturar:
		opciones.append(["Capturar", _accion_capturar])
	opciones.append(["Esperar", _accion_esperar])
	_mostrar_menu(opciones)
	if not objetivos_actuales.is_empty():
		estado = Estado.OBJETIVO


func _accion_capturar() -> void:
	var u := unidad_menu
	_cerrar_menu()
	reglas.capturar(u)


func _accion_esperar() -> void:
	var u := unidad_menu
	_cerrar_menu()
	reglas.marcar_lista(u)


# ---------------------------------------------------------------- tienda: unidades y habilidades

func _on_tienda() -> void:
	if estado == Estado.SELECCIONADA:
		deseleccionar()
	if estado == Estado.LIBRE and not turno_ia and not juego_terminado:
		_abrir_compra()


func _abrir_compra() -> void:
	estado = Estado.MENU
	_mostrar_menu([
		["$%d   Población %d/%d" % [reglas.creditos[equipo_actual], reglas.poblacion(equipo_actual), reglas.limite_poblacion(equipo_actual)], null],
		["Unidades", _menu_unidades],
		["Habilidades", _menu_habilidades],
		["Cerrar", _cerrar_menu],
	])


func _menu_unidades() -> void:
	var opciones: Array = [["Unidades  ($%d)" % reglas.creditos[equipo_actual], null]]
	for tipo in Datos.UNIDADES:
		var d: Dictionary = Datos.UNIDADES[tipo]
		var motivo := reglas.motivo_no_compra(tipo, equipo_actual)
		var texto := "%s  $%d" % [d["nombre"], d["precio"]] + ("  (%s)" % motivo if motivo != "" else "")
		opciones.append([texto, _comprar.bind(tipo), motivo != ""])
	opciones.append(["Volver", _abrir_compra])
	_mostrar_menu(opciones)


func _menu_habilidades() -> void:
	var opciones: Array = [["Habilidades  ($%d)" % reglas.creditos[equipo_actual], null]]
	for nombre in Datos.HABILIDADES:
		var h: Dictionary = Datos.HABILIDADES[nombre]
		if h.get("solo_niebla", false) and not mapa.niebla_activa:
			continue
		var precio := reglas.precio_habilidad(nombre, equipo_actual)
		var texto := "%s $%d: %s" % [h["nombre"], precio, h["texto"]]
		opciones.append([texto, _usar_habilidad.bind(nombre), not reglas.puede_pagar_habilidad(nombre, equipo_actual)])
	opciones.append(["Volver", _abrir_compra])
	_mostrar_menu(opciones)


func _comprar(tipo: String) -> void:
	if Datos.UNIDADES[tipo].get("construccion", false):
		_apuntar(reglas.celdas_torreta(equipo_actual), "Toca dónde construir la torreta", _construir_torreta)
		return
	if reglas.comprar(tipo, equipo_actual):
		Sonido.reproducir("compra")
	_cerrar_menu()


func _construir_torreta(celda: Vector2i) -> void:
	if reglas.comprar("torreta", equipo_actual, celda):
		Sonido.reproducir("compra")


func _usar_habilidad(nombre: String) -> void:
	match nombre:
		"reparacion":
			var heridas: Array[Vector2i] = []
			for u in mapa.unidades_de(equipo_actual):
				if u.vida < u.datos()["vida_max"]:
					heridas.append(u.celda)
			_apuntar(heridas, "Toca la unidad a reparar", _reparar)
		"bombardeo":
			var todas: Array[Vector2i] = []
			for y in mapa.alto:
				for x in mapa.ancho:
					if mapa.se_ve(Vector2i(x, y)):
						todas.append(Vector2i(x, y))
			_apuntar(todas, "Toca el centro del bombardeo (3x3)", _bombardear, true)
		"marcha":
			_cerrar_menu()
			if reglas.usar_marcha(equipo_actual):
				estado = Estado.MOVIENDO
				await animar_marcha(equipo_actual)
				estado = Estado.LIBRE
		"nuclear":
			var visibles: Array[Vector2i] = []
			for y in mapa.alto:
				for x in mapa.ancho:
					if mapa.se_ve(Vector2i(x, y)):
						visibles.append(Vector2i(x, y))
			_apuntar(visibles, "Toca el centro de la explosión", _lanzar_nuclear, true)
		"radar":
			_cerrar_menu()
			if reglas.usar_radar(equipo_actual):
				estado = Estado.MOVIENDO
				await animar_radar(equipo_actual)
				estado = Estado.LIBRE


## Primero la animación y después el efecto, para que el daño aparezca cuando caen las bombas.
func _bombardear(centro: Vector2i) -> void:
	if not reglas.puede_pagar_habilidad("bombardeo", equipo_actual):
		return
	estado = Estado.MOVIENDO
	await animar_bombardeo(centro, equipo_actual)
	reglas.usar_bombardeo(equipo_actual, centro)
	estado = Estado.LIBRE


func _lanzar_nuclear(centro: Vector2i) -> void:
	if not reglas.puede_pagar_habilidad("nuclear", equipo_actual):
		return
	estado = Estado.MOVIENDO
	await animar_nuclear(centro)
	reglas.usar_nuclear(equipo_actual, centro)
	estado = Estado.LIBRE


func _reparar(celda: Vector2i) -> void:
	var u := mapa.unidad_en(celda)
	if u == null or not reglas.puede_pagar_habilidad("reparacion", equipo_actual):
		return
	estado = Estado.MOVIENDO
	await animar_reparacion(u)
	reglas.usar_reparacion(equipo_actual, u)
	estado = Estado.LIBRE


## Modo "apuntar": se resaltan las casillas válidas y el siguiente toque decide.
func _apuntar(celdas: Array[Vector2i], instruccion: String, accion: Callable, sin_resaltar := false) -> void:
	if celdas.is_empty():
		_cerrar_menu()
		return
	_mostrar_menu([[instruccion, null], ["Cancelar", _cerrar_menu]])
	_celdas_apuntar = celdas
	_al_apuntar = accion
	if not sin_resaltar:
		resaltado.mostrar(celdas, Color(1, 0.85, 0.3, 0.45), Vector2i(-1, -1))
	estado = Estado.APUNTAR


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
	if equipo_actual == "azul":
		numero_turno += 1
	for u in mapa.unidades_de(equipo_actual):
		u.reiniciar_turno()
	reglas.al_empezar_turno(equipo_actual)
	reglas.revisar_victoria()
	_actualizar_hud()
	if juego_terminado:
		return
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


## Muestra la pantalla de victoria o derrota con las estadísticas. ganador: "azul" o "rojo".
func terminar_partida(ganador: String) -> void:
	juego_terminado = true
	_cerrar_menu()
	deseleccionar()
	hud.mostrar_fin(ganador, _texto_estadisticas())


func _texto_estadisticas() -> String:
	if reglas.estadisticas.is_empty():
		return ""
	var a: Dictionary = reglas.estadisticas["azul"]
	var r: Dictionary = reglas.estadisticas["rojo"]
	var filas := [
		["", "Tú", "Rojo"],
		["Unidades destruidas", a["destruidas"], r["destruidas"]],
		["Unidades perdidas", a["perdidas"], r["perdidas"]],
		["Ciudades capturadas", a["capturadas"], r["capturadas"]],
		["Unidades compradas", a["compradas"], r["compradas"]],
		["Habilidades usadas", a["habilidades"], r["habilidades"]],
		["Dinero gastado", "$%d" % a["gastado"], "$%d" % r["gastado"]],
	]
	var texto := "Turnos: %d   ·   Dificultad: %s\n" % [numero_turno, Datos.DIFICULTADES[Config.dificultad]["nombre"]]
	for f in filas:
		texto += "%-20s %6s %6s\n" % [f[0], str(f[1]), str(f[2])]
	return texto.strip_edges(false, true)


func _actualizar_hud() -> void:
	var quien := "Tú" if equipo_actual == "azul" else "Rojo"
	var texto := "Turno %d · %s\n$%d · Pob %d/%d   (Rojo $%d)" % [numero_turno, quien,
		reglas.creditos.get("azul", 0), reglas.poblacion("azul") if reglas.mapa else 0,
		reglas.limite_poblacion("azul") if reglas.mapa else 0, reglas.creditos.get("rojo", 0)]
	hud.mostrar_estado(texto)


## Botón "atrás" de Android: abre o cierra el menú de pausa.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and not turno_ia:
		if hud.hay_menu_abierto():
			hud.cerrar_pausa()
		else:
			hud.abrir_pausa()
