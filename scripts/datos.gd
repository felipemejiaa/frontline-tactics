class_name Datos
extends RefCounted
## Datos compartidos del juego: terrenos, unidades, habilidades y dificultades.
## Si necesitan cambiar precios, vida, movimiento, etc., se cambia AQUÍ y nada más.

const TAM_CASILLA := 16
const ATLAS := preload("res://assets/kenney_tiny_battle/tilemap_packed.png")

## Fila del atlas donde están las unidades de cada equipo.
const FILA_EQUIPO := {"azul": 7, "rojo": 8}
## Fila de los edificios de cada equipo (la torreta usa esta, porque es una construcción).
const FILA_EDIFICIO := {"azul": 2, "rojo": 3}

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
	"ciudad": {"nombre": "Ciudad", "defensa": 2, "tile": Vector2i(1, 0),
		"adorno_neutral": Vector2i(8, 0), "adorno_azul": Vector2i(8, 2), "adorno_rojo": Vector2i(8, 3)},
}

## Créditos que da cada edificio propio (cuartel, base o ciudad) al empezar el turno.
const INGRESO_POR_EDIFICIO := 500
## Población: máximo de unidades = BASE + 1 por cada edificio propio.
const POBLACION_BASE := 5
## Vida que recupera una unidad que empieza el turno en un edificio propio.
const CURACION := 2

const TERRESTRE := {"llanura": 1, "bosque": -1, "montana": -1, "agua": -1, "cuartel": 1, "base": 1, "ciudad": 1}

## Unidades.
## "costo_terreno": cuántos puntos de movimiento gasta entrar a cada terreno (-1 = no puede).
## "columna": columna del dibujo en el atlas (la fila depende del equipo).
## "aerea": vuela (ignora el terreno y no recibe defensa de él).
## "ataca_aire": si puede atacar a unidades aéreas.
## "vision": cuántas casillas ve (para la niebla).
const UNIDADES := {
	"infanteria": {
		"nombre": "Infantería", "precio": 1000, "vida_max": 10, "movimiento": 3,
		"rango_min": 1, "rango_max": 1, "columna": 16, "vision": 2, "ataca_aire": true,
		"costo_terreno": {"llanura": 1, "bosque": 2, "montana": 2, "agua": -1, "cuartel": 1, "base": 1, "ciudad": 1},
	},
	"tanque": {
		"nombre": "Tanque", "precio": 3000, "vida_max": 10, "movimiento": 5,
		"rango_min": 1, "rango_max": 1, "columna": 8, "vision": 2, "ataca_aire": true,
		"costo_terreno": TERRESTRE,
	},
	"artilleria": {
		"nombre": "Artillería", "precio": 2500, "vida_max": 10, "movimiento": 4,
		"rango_min": 2, "rango_max": 3, "columna": 9, "vision": 2, "ataca_aire": false,
		"costo_terreno": TERRESTRE,
	},
	"helicoptero": {
		"nombre": "Helicóptero", "precio": 3500, "vida_max": 10, "movimiento": 6,
		"rango_min": 1, "rango_max": 1, "columna": 11, "vision": 3, "ataca_aire": true, "aerea": true,
		"costo_terreno": {"llanura": 1, "bosque": 1, "montana": 1, "agua": 1, "cuartel": 1, "base": 1, "ciudad": 1},
	},
	"antiaerea": {
		"nombre": "Antiaérea", "precio": 2000, "vida_max": 10, "movimiento": 5,
		"rango_min": 1, "rango_max": 1, "columna": 7, "vision": 2, "ataca_aire": true,
		"costo_terreno": TERRESTRE,
	},
	"torreta": {
		"nombre": "Torreta", "precio": 2500, "vida_max": 10, "movimiento": 0,
		"rango_min": 1, "rango_max": 2, "columna": 12, "vision": 3, "ataca_aire": true, "construccion": true,
		"costo_terreno": TERRESTRE,
	},
}

## La torreta solo se puede construir a esta distancia (o menos) de tu cuartel general.
const DISTANCIA_TORRETA := 2

## Ventajas (como piedra, papel o tijera): cada unidad le pega fuerte a las de su lista.
const VENTAJAS := {
	"infanteria": ["artilleria"],
	"tanque": ["infanteria", "antiaerea"],
	"artilleria": ["tanque", "torreta"],
	"helicoptero": ["tanque", "artilleria"],
	"antiaerea": ["helicoptero"],
	"torreta": ["infanteria", "tanque"],
}


static func le_gana(tipo: String, contra: String) -> bool:
	return contra in VENTAJAS.get(tipo, [])


static func nombres(tipos: Array) -> String:
	var lista := []
	for t in tipos:
		lista.append(UNIDADES[t]["nombre"])
	return ", ".join(lista) if not lista.is_empty() else "—"


## Tipos de unidad que le ganan a este.
static func pierde_contra(tipo: String) -> Array:
	var lista := []
	for t in VENTAJAS:
		if tipo in VENTAJAS[t]:
			lista.append(t)
	return lista


## Habilidades que se compran en la tienda. El precio sube un 50 % cada vez que se usan.
## "objetivo": qué hay que tocar después de comprarla.
const HABILIDADES := {
	"reparacion": {"nombre": "Reparación", "precio": 1500, "objetivo": "unidad_propia",
		"texto": "+5 de vida a una unidad tuya"},
	"bombardeo": {"nombre": "Bombardeo", "precio": 3500, "objetivo": "casilla",
		"texto": "3 de daño en un área de 3x3 (no destruye)"},
	"marcha": {"nombre": "Marcha forzada", "precio": 2000, "objetivo": "",
		"texto": "+2 de movimiento a todas tus unidades este turno"},
	"radar": {"nombre": "Radar", "precio": 1000, "objetivo": "", "solo_niebla": true,
		"texto": "Ves todo el mapa durante este turno"},
}
const DANO_BOMBARDEO := 3
const VIDA_REPARACION := 5

## Dificultades de la máquina.
## "ingreso": multiplicador de lo que gana la máquina por turno.
## "torpeza": probabilidad de que elija un ataque al azar en vez del mejor.
const DIFICULTADES := {
	"facil": {"nombre": "Fácil", "ingreso": 0.6, "torpeza": 0.5, "max_unidades": 6,
		"retirada": false, "habilidades": false},
	"normal": {"nombre": "Normal", "ingreso": 0.85, "torpeza": 0.15, "max_unidades": 9,
		"retirada": false, "habilidades": false},
	"dificil": {"nombre": "Difícil", "ingreso": 1.15, "torpeza": 0.0, "max_unidades": 14,
		"retirada": true, "habilidades": true},
}


## Casilla del atlas con el dibujo de una unidad de un equipo.
static func tile_unidad(tipo: String, equipo: String) -> Vector2i:
	var d: Dictionary = UNIDADES[tipo]
	var fila: int = FILA_EDIFICIO[equipo] if d.get("construccion", false) else FILA_EQUIPO[equipo]
	return Vector2i(d["columna"], fila)
