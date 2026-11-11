# Frontline Tactics

Juego de estrategia por turnos para Android, inspirado en Advanced Wars. Hecho en **Godot 4.3**.

## Cómo abrirlo

1. Descargar Godot 4.3 (versión estándar, no la .NET): https://godotengine.org/download/archive/4.3-stable/
2. Abrir Godot → **Importar** → escoger el archivo `project.godot` de esta carpeta.
3. Presionar **F5** (o el botón ▶) para jugar. En el PC el clic del mouse funciona como el toque del celular.

## Cómo se juega (por ahora)

- Toca una unidad azul: se resaltan en azul las casillas a donde puede moverse.
- Toca una casilla resaltada: la unidad se mueve y queda gris (ya actuó).
- Toca una unidad roja: se ve en rojo hasta dónde puede llegar.
- **Terminar turno** pasa al otro equipo (temporal, mientras está la IA).

## Estructura

```
scenes/main.tscn        Escena principal (mapa + HUD)
scripts/datos.gd        Datos de terrenos y unidades (precios, vida, movimiento...)
scripts/game_map.gd     Mapa, posiciones de las unidades y cálculo de movimiento
scripts/unidad.gd       Una unidad: tipo, equipo, vida, si ya se movió
scripts/resaltado.gd    Dibuja las casillas resaltadas y el cursor
scripts/main.gd         Toques en pantalla, selección y movimiento
tests/                  Prueba automática del movimiento
assets/kenney_tiny_battle/  Gráficos de Kenney.nl (licencia CC0)
```

- **Cambiar el mapa:** editar `MAPA` en `scripts/game_map.gd` (la leyenda está ahí mismo).
- **Cambiar valores de las unidades:** editar `UNIDADES` en `scripts/datos.gd`.

## Estado y tareas

| Parte | Responsable | Estado |
|---|---|---|
| Mapa de cuadrícula y terrenos | Persona 2 | ✅ Listo |
| Selección y movimiento táctil | Persona 2 | ✅ Listo |
| IA del enemigo | Persona 2 | ⏳ Pendiente |
| Turnos, combate, créditos y victoria | Persona 1 | ⏳ Pendiente |
| Menús, HUD, sonido y exportar APK | Persona 3 | ⏳ Pendiente |

### Para la persona 1 (reglas)
- `main.gd` emite la señal `unidad_movida(unidad)` cuando una unidad termina de moverse: ahí va el menú *Atacar / Esperar*.
- `Datos.LE_GANA_A` ya tiene el piedra, papel o tijera; `rango_min` y `rango_max` de cada unidad dicen desde qué distancia ataca.
- `mapa.distancia(a, b)`, `mapa.unidades_de(equipo)` y `mapa.eliminar_unidad(u)` sirven para el combate.
- `mapa.buscar_edificio("base", "azul")` da la casilla donde aparecen las unidades compradas; para crearlas: `mapa.crear_unidad(tipo, equipo, celda)`.
- `terminar_turno()` en `main.gd` es temporal: reemplazarlo por el sistema de turnos real.

### Para la persona 3 (visual)
- El HUD está en el nodo `HUD` de `main.tscn`. El juego se dibuja a 320×180 y se escala a la pantalla.
- Para exportar: Proyecto → Exportar → Android (hay que instalar las plantillas de exportación y configurar el SDK de Android).

## Prueba automática

```
godot --headless --path . --script res://tests/prueba_movimiento.gd
```

## Créditos

Gráficos: [Tiny Battle](https://kenney.nl/assets/tiny-battle) de Kenney.nl (CC0).
