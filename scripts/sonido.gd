class_name Sonido
extends Node
## Sonidos y música del juego. Se usa desde cualquier script, por ejemplo:
##     Sonido.reproducir("disparo")
## La primera vez que se usa se crea solo y se queda vivo todo el juego
## (aunque se cambie de escena), así la música no se corta.
## Los sonidos se generaron con herramientas/generar_sonidos.py.

const CARPETA := "res://assets/sonidos/"
const EFECTOS := ["clic", "disparo", "canon", "explosion", "golpe", "paso", "seleccion",
	"compra", "captura", "turno", "victoria", "derrota"]
const CANALES := 8  # cuántos sonidos pueden sonar a la vez

## Se cambia desde el menú de pausa.
static var activado := true:
	set(valor):
		activado = valor
		if is_instance_valid(_yo):
			if valor:
				_yo._musica.play()
			else:
				_yo._musica.stop()

static var _yo: Sonido

var _sonidos := {}
var _canales: Array[AudioStreamPlayer] = []
var _siguiente := 0
var _musica := AudioStreamPlayer.new()


## Crea el reproductor si todavía no existe.
static func iniciar() -> void:
	if is_instance_valid(_yo):
		return
	_yo = Sonido.new()
	var arbol := Engine.get_main_loop() as SceneTree
	arbol.root.add_child.call_deferred(_yo)


static func reproducir(nombre: String, volumen_db := 0.0) -> void:
	iniciar()
	_yo._reproducir(nombre, volumen_db)


func _init() -> void:
	for nombre in EFECTOS:
		_sonidos[nombre] = load(CARPETA + nombre + ".wav")
	for i in CANALES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_canales.append(p)
	_musica.stream = load(CARPETA + "musica.wav")
	_musica.volume_db = -8.0
	_musica.finished.connect(_musica.play)  # repetir la música al terminar
	add_child(_musica)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if activado:
		_musica.play()
	# Todos los botones hacen "clic": los que ya existen y los que se creen después.
	_conectar_botones(get_tree().root)
	get_tree().node_added.connect(_conectar_boton)


func _reproducir(nombre: String, volumen_db: float) -> void:
	if not activado or not is_inside_tree() or not _sonidos.has(nombre):
		return
	var p := _canales[_siguiente]
	_siguiente = (_siguiente + 1) % CANALES
	p.stream = _sonidos[nombre]
	p.volume_db = volumen_db
	p.pitch_scale = randf_range(0.95, 1.05)  # pequeña variación para que no suene repetitivo
	p.play()


func _conectar_botones(nodo: Node) -> void:
	_conectar_boton(nodo)
	for hijo in nodo.get_children():
		_conectar_botones(hijo)


func _conectar_boton(nodo: Node) -> void:
	if nodo is BaseButton and not nodo.pressed.is_connected(_clic):
		nodo.pressed.connect(_clic)


func _clic() -> void:
	_reproducir("clic", 0.0)
