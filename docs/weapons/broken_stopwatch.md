# Cronometro Roto

Arma de mouse basada en ritmo y Cargas de Rift.

## Estado implementado

- Click izquierdo: golpe sincronizado con el compas `click / clack`.
- Cada golpe genera un slash visual reusable con arco, particulas, trail simple y flash.
- Golpes perfectos: aumentan cadena.
- Cada 4 golpes perfectos: +1 Carga de Rift.
- Maximo: 3 cargas.
- Click derecho mantenido: abre menu Rift si hay cargas.
- Mientras el menu esta abierto: `Engine.time_scale` baja a 0.28.
- La rueda Rift es un diamante de 4 direcciones. El cursor virtual empieza al centro; al deslizar hacia una direccion, ese sector se ilumina. Al volver al centro se apaga.
- Soltar click derecho: ejecuta la secuencia marcada con movimientos del mouse.
- Abrir y cerrar sin secuencia: cooldown de 4 segundos.
- Tras un Rift valido: 3 notas de reincorporacion.
- Secuencia invalida: consume 1 carga, rompe cadena y emite falla critica.

## Secuencias

- `^ v`: Impulso Temporal, coste 1.
- `< > ^`: Fragmento Cinetico, coste 1.
- `^ > v <`: Burbuja Temporal, coste 1.
- `> <`: Tajo Universal, coste 1.
- `v ^ v ^`: Sobrecarga Cinetica, coste 3.

## Pendiente

Los efectos ofensivos imprimen placeholders hasta que existan enemigos, vida y hurtboxes. `Impulso Temporal` ya aplica salto, caida lenta y mayor control aereo temporal.

## BPM automatico

El BPM se analiza offline con `tools/audio/detect_bpm.py` y se guarda en `data/audio_bpm_cache.json`. En runtime, `scripts/audio/bpm_database.gd` lee ese cache y `music_tempo_sync.gd` puede aplicar el BPM actual llamando `set_music_bpm()` en el Cronometro. Esto evita hacer analisis pesado durante combate.

## Slash basico

El slash vive en `scenes/effects/combat/SlashEffect.tscn` y su script en `scripts/effects/combat/slash_effect.gd`. El Cronometro lo instancia desde el jugador con 3 variantes visuales para que los golpes no se vean identicos. Los parametros principales estan juntos bajo el comentario `CRONOMETRO SLASH TUNING` en `broken_stopwatch_weapon.gd`.
