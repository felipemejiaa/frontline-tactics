extends Control
## Menú principal: muestra un mapa aleatorio de fondo y los botones Jugar, Cómo jugar y Salir.

@onready var mapa_fondo: GameMap = $MapaFondo
@onready var ayuda: Control = %Ayuda


func _ready() -> void:
	# Conectar cada botón con la función que debe ejecutar al presionarlo.
	%BotonJugar.pressed.connect(_on_jugar)
	%BotonComoJugar.pressed.connect(_on_como_jugar)
	%BotonSalir.pressed.connect(_on_salir)
	%BotonVolver.pressed.connect(_on_volver)
	_poner_mapa_de_fondo()
	Sonido.iniciar()


## Reutiliza el generador del juego para que el fondo sea distinto cada vez.
func _poner_mapa_de_fondo() -> void:
	var generado := GeneradorMapa.new().generar(randi())
	if generado.is_empty():
		return
	mapa_fondo.cargar_desde_texto(generado["lineas"])
	for u in generado["unidades"]:
		mapa_fondo.crear_unidad(u["tipo"], u["equipo"], u["celda"])
	var tamano := Vector2(mapa_fondo.ancho, mapa_fondo.alto) * Datos.TAM_CASILLA
	mapa_fondo.position = ((size - tamano) / 2.0).floor()


func _on_jugar() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_como_jugar() -> void:
	ayuda.show()


func _on_volver() -> void:
	ayuda.hide()


func _on_salir() -> void:
	get_tree().quit()


## Botón "atrás" de Android: cierra la ayuda si está abierta; si no, sale del juego.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if ayuda.visible:
			_on_volver()
		else:
			_on_salir()
