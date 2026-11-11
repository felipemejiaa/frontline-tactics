class_name Datos
extends RefCounted
## Datos compartidos del juego: terrenos y unidades.
## Si necesitan cambiar precios, vida, movimiento, etc., se cambia AQUÍ y nada más.

const TAM_CASILLA := 16
const ATLAS := preload("res://assets/kenney_tiny_battle/tilemap_packed.png")

## Fila del atlas donde están las unidades de cada equipo.
const FILA_EQUIPO := {"azul": 7, "rojo": 8}

## Terrenos. "tile" y "adorno" son (columna, fila) dentro del atlas de Kenney.
## "adorno" se dibuja encima del pasto (árbol, roca, edificio...).
const TERRENOS := {
	"llanura": {"nombre": "Llanura", "defensa": 0, "tile": Vector2i(1, 0)},
	"bosque": {"nombre": "Bosque", "defensa": 2, "tile": Vector2i(1, 0), "adorno": Vector2i(4, 6)},
	"montana": {"nombre": "Montaña", "defensa": 3, "tile": Vector2i(1, 0), "adorno": Vector2i(5, 0)},
	"agua": {"nombre": "Agua", "defensa": 0, "tile": Vector2i(1, 2)},
	"cuartel": {"nombre": "Cuartel general", "defensa": 3, "tile": Vector2i(1, 0),
		"adorno_azul": Vector2i(9, 2), "adorno_rojo": Vector2i(9, 3)},
	"base": {"nombre": "Base", "defensa": 2, "tile": Vector2i(1, 0),
		"adorno_azul": Vector2i(15, 2), "adorno_rojo": Vector2i(15, 3)},
}

## Unidades. "costo_terreno": cuántos puntos de movimiento gasta entrar a cada terreno.
## -1 significa que no puede entrar.
## "columna": columna del dibujo en el atlas (la fila depende del equipo).
const UNIDADES := {
	"infanteria": {
		"nombre": "Infantería",
		"precio": 1000,
		"vida_max": 10,
		"movimiento": 3,
		"rango_min": 1,
		"rango_max": 1,
		"columna": 16,
		"costo_terreno": {"llanura": 1, "bosque": 1, "montana": 2, "agua": -1, "cuartel": 1, "base": 1},
	},
	"tanque": {
		"nombre": "Tanque",
		"precio": 3000,
		"vida_max": 10,
		"movimiento": 5,
		"rango_min": 1,
		"rango_max": 1,
		"columna": 8,
		"costo_terreno": {"llanura": 1, "bosque": 2, "montana": -1, "agua": -1, "cuartel": 1, "base": 1},
	},
	"artilleria": {
		"nombre": "Artillería",
		"precio": 2500,
		"vida_max": 10,
		"movimiento": 4,
		"rango_min": 2,
		"rango_max": 3,
		"columna": 9,
		"costo_terreno": {"llanura": 1, "bosque": 2, "montana": -1, "agua": -1, "cuartel": 1, "base": 1},
	},
}

## Piedra, papel o tijera: cada unidad le gana a la que aparece como valor.
const LE_GANA_A := {
	"infanteria": "artilleria",
	"tanque": "infanteria",
	"artilleria": "tanque",
}
