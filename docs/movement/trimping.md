# Trimping por proyeccion

El trimping de KOU toma la idea de la resolucion de colisiones de Source: una rampa no anade un salto, sino que redirige la velocidad que entra en ella.

- `REFERENCIA/Quake-III-Arena-master/code/game/bg_pmove.c`
- `REFERENCIA/Quake-III-Arena-master/code/game/bg_slidemove.c`

La pieza importante es `PM_ClipVelocity()`: proyecta la velocidad del jugador contra la normal de una superficie. En terminos simples, parte de la velocidad que iba hacia la pared se redirige a lo largo del plano.

En KOU el efecto se calcula asi:

```gdscript
projected_velocity = incoming_velocity.slide(ramp_normal)
```

1. Solo se consideran rampas dentro de un rango de inclinacion; las paredes no lanzan al jugador.
2. El jugador debe llegar con suficiente velocidad y realmente entrar en la rampa.
3. La componente paralela al plano se conserva. Por eso la altura del lanzamiento depende naturalmente de la velocidad y el angulo de la rampa.
4. Un cooldown corto evita repetir el mismo lanzamiento durante el contacto.

Los parametros estan en `scripts/player/player_controller.gd`, en el bloque `Trimping`.

Valores clave:

- `trimp_min_speed`: velocidad minima para activar el efecto.
- `trimp_min_slope_degrees` y `trimp_max_slope_degrees`: rango de rampas validas.
- `trimp_min_impact_speed`: velocidad minima hacia la normal de la rampa.
- `trimp_min_launch_speed`: componente vertical minima para despegar.
- `trimp_velocity_retention`: fraccion de la velocidad proyectada que se conserva; `1.0` es la proyeccion pura.

Con una rampa de 20 a 45 grados, entrar rapido genera una salida ascendente proporcional. En una pared pronunciada se bloquea el efecto, como corresponde a una colision normal.
