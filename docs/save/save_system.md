# Save System

El guardado vive en `SaveManager`, registrado como autoload en `project.godot`.

## Guardado manual

- Boton visible: `scenes/ui/SaveButton.tscn`.
- Tecla rapida: `F5`, accion `manual_save`.

## Autoguardado

- Al terminar combate: llamar `SaveManager.notify_combat_finished()`.
- Al empezar combate: llamar `SaveManager.notify_combat_started()`.
- Exploracion sin combate: guarda cada 15 minutos.
- Seguridad ante cierres bruscos: guarda cada 2 minutos como respaldo.
- Cierre normal de ventana / Alt+F4: intenta guardar antes de salir.

## Cierre forzado

Si el sistema mata el proceso desde el administrador de tareas, Godot puede no recibir ninguna notificacion. No se puede garantizar un guardado en ese instante. La proteccion real es el guardado preventivo periodico y escritura con archivo temporal + backup.

## Contrato para nodos guardables

Un nodo que quiera guardarse debe:

- Estar en el grupo `saveable`.
- Implementar `get_save_data() -> Dictionary`.
- Implementar `apply_save_data(data: Dictionary) -> void`.

El jugador ya implementa este contrato.
