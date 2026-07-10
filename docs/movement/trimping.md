# Trimping controlado

El trimping de KOU esta inspirado en el movimiento de Quake III, pero no intenta copiarlo completo. La referencia local esta en:

- `REFERENCIA/Quake-III-Arena-master/code/game/bg_pmove.c`
- `REFERENCIA/Quake-III-Arena-master/code/game/bg_slidemove.c`

La pieza importante es `PM_ClipVelocity()`: proyecta la velocidad del jugador contra la normal de una superficie. En terminos simples, parte de la velocidad que iba hacia la pared se redirige a lo largo del plano.

En KOU usamos una version mas arcade y configurable:

1. Las superficies por encima de `floor_max_angle_degrees` no son caminables.
2. Si la superficie es bastante empinada y el jugador llega con suficiente velocidad, se calcula un impulso vertical.
3. El impulso depende de velocidad, inclinacion e impacto frontal.
4. El impulso tiene cooldown corto para evitar multiples disparos por una sola colision.

Los parametros estan en `scripts/player/player_controller.gd`, en el bloque `Trimping`.

Valores clave:

- `trimp_min_speed`: velocidad minima para activar el efecto.
- `trimp_full_speed`: velocidad donde el factor de velocidad llega al maximo.
- `trimp_min_slope_degrees`: pendiente minima que puede hacer trimping.
- `trimp_full_slope_degrees`: pendiente donde el factor de inclinacion llega al maximo.
- `trimp_max_boost`: fuerza vertical maxima.
- `trimp_impact_threshold`: cuanto debe ir el jugador hacia la superficie.
- `trimp_preserve_horizontal_ratio`: cuanta velocidad horizontal conserva tras el impulso.

Esto permite que una pared de 75 grados se comporte como obstaculo si el jugador va lento, pero como rampa si llega con suficiente velocidad.
