# KOU Optimization Playbook

Objetivo: mantener sistemas de gameplay simples, medibles y baratos. Para codigo que corre cada frame, preferimos O(1), O(log n) u O(n) con `n` muy pequeno y acotado. O(n log n) queda para trabajo ocasional, carga de datos o herramientas. Evitamos O(n^2) en runtime salvo que `n` sea fijo y diminuto.

## Reglas de base

- Cachear referencias a nodos con `@onready`; evitar `find_child`, `get_node` repetido o busquedas por nombre en `_process` y `_physics_process`.
- Separar sistemas por frecuencia: fisica en `_physics_process`, entrada en `_unhandled_input`, calculos pesados en eventos o timers.
- Medir antes de optimizar agresivamente; un algoritmo claro O(n) suele ser mejor que una solucion compleja prematura.
- Usar arrays compactos para listas pequenas y diccionarios/tablas hash para acceso directo por clave.
- Mantener escenas low-poly, materiales simples y pocas luces con sombras.

## Herramientas algorítmicas

- Big O: estimar como crece el costo cuando crecen enemigos, items, nodos o puntos de pathfinding.
- Busqueda binaria: usar en datos ordenados, por ejemplo curvas, tablas de niveles, tiempos de animacion o checkpoints.
- Recursion: usar con cuidado; preferir iterativo en gameplay para evitar overflow y picos de frame.
- Programacion dinamica: util para precalcular costos o rutas cuando el espacio de estados se repite.
- BFS: caminos sin pesos, expansion por capas, busqueda de celdas cercanas.
- DFS: exploracion de grafos, validacion de conectividad, herramientas de generacion.
- Dijkstra: caminos con pesos; usarlo fuera del frame critico o con presupuesto por tick.
- Arboles binarios: utiles para datos ordenados si no hay estructura mejor disponible.
- Tablas hash: acceso promedio O(1) para ids, estados, inventario, pools y caches.
- Merge Sort: orden estable O(n log n), bueno para datos grandes fuera del gameplay inmediato.
- Quick Sort: rapido en promedio O(n log n), pero cuidar peor caso; preferir sort nativo salvo necesidad real.

## Convencion inicial

Todo sistema nuevo debe indicar su costo esperado si maneja colecciones que puedan crecer. Si algo corre cada frame, debe justificar por que no puede moverse a eventos, cache, timer o precalculo.

## Patron actual: orbes de eleccion

El orbe de eleccion usa deteccion por evento (`body_entered`) y una lista fija de 3 opciones. Su costo de contacto y UI es O(1). Para futuros desbloqueos, como armas de mouse o habilidades de Shift, se debe preferir instanciar una escena de orbe configurada en vez de escribir logica especifica dentro del escenario.

## Patron actual: Cronometro Roto

El Cronometro Roto usa una maquina de estados pequena: ritmo, cargas, menu Rift y secuencia. Las secuencias tienen largo maximo 4 y las cargas maximas son 3, asi que validacion, HUD y casteo son O(1). Las futuras hitboxes, proyectiles o burbujas deben buscar objetivos por areas fisicas acotadas o caches, no por escaneos globales de enemigos.
^^^^^^^^^
esta wea esta vieja, ignorar