class_name HUD
extends CanvasLayer
## Interfaz dentro de la partida: barra de arriba, menú de pausa y pantalla de fin.
## No sabe nada de las reglas del juego: solo muestra cosas y avisa con señales
## cuando el jugador presiona un botón. main.gd escucha esas señales.

signal terminar_turno_pedido
signal nuevo_mapa_pedido

const ESCENA_MENU := "res://scenes/menu_principal.tscn"


func _ready() -> void:
	%BotonTerminar.pressed.connect(func(): terminar_turno_pedido.emit())
	%BotonMenu.pressed.connect(abrir_pausa)
	%BotonContinuar.pressed.connect(cerrar_pausa)
	%BotonNuevoMapa.pressed.connect(_pedir_nuevo_mapa)
	%BotonMenuPrincipal.pressed.connect(ir_al_menu_principal)
	%BotonJugarOtraVez.pressed.connect(_pedir_nuevo_mapa)
	%BotonSalirAlMenu.pressed.connect(ir_al_menu_principal)


## creditos: diccionario {"azul": 3000, "rojo": 2000}
func mostrar_turno(equipo: String, creditos: Dictionary = {}) -> void:
	var texto := "Turno: " + ("Azul" if equipo == "azul" else "Rojo")
	if not creditos.is_empty():
		texto += "   |   Azul: %d   Rojo: %d" % [creditos.get("azul", 0), creditos.get("rojo", 0)]
	%EtiquetaTurno.text = texto


## Mientras juega la máquina no se puede terminar turno ni abrir el menú.
func bloquear_botones(bloquear: bool) -> void:
	%BotonTerminar.disabled = bloquear
	%BotonMenu.disabled = bloquear


func hay_menu_abierto() -> bool:
	return %MenuPausa.visible or %PantallaFin.visible


func abrir_pausa() -> void:
	if not %PantallaFin.visible:
		%MenuPausa.show()


func cerrar_pausa() -> void:
	%MenuPausa.hide()


## Persona 1: llamar esto (a través de main.terminar_partida) cuando alguien gane.
func mostrar_fin(ganador: String) -> void:
	%MenuPausa.hide()
	if ganador == "azul":
		%TituloFin.text = "¡VICTORIA!"
		%MensajeFin.text = "Derrotaste al ejército rojo."
	else:
		%TituloFin.text = "DERROTA"
		%MensajeFin.text = "El ejército rojo te venció."
	%PantallaFin.show()


## Oculta la pausa y la pantalla de fin (al empezar una partida nueva).
func cerrar_todo() -> void:
	%MenuPausa.hide()
	%PantallaFin.hide()


func _pedir_nuevo_mapa() -> void:
	%MenuPausa.hide()
	%PantallaFin.hide()
	nuevo_mapa_pedido.emit()


func ir_al_menu_principal() -> void:
	get_tree().change_scene_to_file(ESCENA_MENU)
