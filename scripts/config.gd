class_name Config
extends RefCounted
## Opciones de la partida que se eligen en el menú principal.
## Son "static": se guardan mientras el juego esté abierto, aunque se cambie de escena.

static var dificultad := "normal"   # "facil", "normal" o "dificil" (ver Datos.DIFICULTADES)
static var niebla := false
