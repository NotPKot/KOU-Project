# World Layout

El proyecto separa la escena de arranque, el jugador, los sistemas reusables y las escenografias.

## Carpetas

- `scenes/Main.tscn`: raiz del juego. Debe contener solo sistemas globales, jugador y la zona activa.
- `scenes/Player.tscn`: personaje jugable y camara.
- `scenes/worlds/practice/`: mapas de practica, prototipos y pruebas mecanicas.
- `scenes/worlds/regions/`: futura carpeta para zonas finales o semiabiertas.
- `scenes/orbs/`: orbes reusables de desbloqueo o eleccion.
- `scenes/ui/`: interfaces reusables.

## Regla para mapas

Una zona debe ser una escena propia. `Main.tscn` instancia la zona activa, pero no debe absorber detalles del mapa. Esto permite cambiar de practica a zona final sin reescribir jugador, UI u orbes.

## Regla para mundo abierto/semiabierto

Cuando el mundo crezca, cada region debe poder existir como escena separada. Las conexiones entre regiones se resolveran con portales, triggers o streaming por distancia, dependiendo del costo real del proyecto.
