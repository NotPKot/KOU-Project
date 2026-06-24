# BPM Detection

El BPM no se calcula durante combate. Se analiza offline y se guarda en `data/audio_bpm_cache.json`.

## Generar cache

Desde la raiz del proyecto:

```powershell
python tools/audio/detect_bpm.py "Assets/TEMPORARY SONGS" --output data/audio_bpm_cache.json --project-root .
```

Dependencias:

```powershell
python -m pip install -r tools/audio/requirements.txt
```

## Runtime

- `scripts/audio/bpm_database.gd` lee el JSON.
- `scripts/audio/music_tempo_sync.gd` toma el `stream.resource_path` de un `AudioStreamPlayer`, busca su BPM y llama `set_music_bpm()` en el objetivo.
- `Player` recuerda el BPM actual y se lo pasa al arma de mouse equipada.
- `BrokenStopwatch` convierte BPM a `beat_period = 60 / bpm`.

## Nota

El detector guarda `raw_bpm` y `bpm`. `raw_bpm` es el pulso detectado directo; `bpm` es el pulso de gameplay, que puede duplicar un medio-tempo bajo para que el Cronometro use una subdivision mas jugable.
