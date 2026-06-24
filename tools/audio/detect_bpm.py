from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np

try:
    import soundfile as sf
except ImportError as exc:
    raise SystemExit(
        "Missing dependency: soundfile. Install with `python -m pip install soundfile`."
    ) from exc


AUDIO_EXTENSIONS = {".wav", ".ogg", ".flac", ".aiff", ".aif"}
TARGET_SAMPLE_RATE = 11_025
HOP_LENGTH = 256
MIN_BPM = 70.0
MAX_BPM = 220.0


def main() -> None:
    parser = argparse.ArgumentParser(description="Detect BPM for Godot music assets.")
    parser.add_argument("input", type=Path, help="Audio file or folder to scan.")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("data/audio_bpm_cache.json"),
        help="JSON cache written for Godot runtime use.",
    )
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path.cwd(),
        help="Project root used to write res:// paths.",
    )
    args = parser.parse_args()

    project_root = args.project_root.resolve()
    audio_paths = _collect_audio_paths(args.input.resolve())
    if not audio_paths:
        raise SystemExit(f"No audio files found in {args.input}")

    cache: dict[str, dict[str, float | str]] = {}
    for path in audio_paths:
        result = detect_bpm(path)
        resource_path = _to_resource_path(path, project_root)
        cache[resource_path] = result
        print(f"{resource_path}: {result['bpm']:.2f} BPM confidence={result['confidence']:.2f}")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(cache, indent=2, sort_keys=True), encoding="utf-8")
    print(f"Wrote {args.output}")


def _collect_audio_paths(input_path: Path) -> list[Path]:
    if input_path.is_file() and input_path.suffix.lower() in AUDIO_EXTENSIONS:
        return [input_path]

    return sorted(
        path
        for path in input_path.rglob("*")
        if path.is_file() and path.suffix.lower() in AUDIO_EXTENSIONS
    )


def detect_bpm(path: Path) -> dict[str, float | str]:
    samples, sample_rate = sf.read(path, always_2d=True, dtype="float32")
    mono = samples.mean(axis=1)
    mono = _resample_linear(mono, sample_rate, TARGET_SAMPLE_RATE)
    onset_envelope = _onset_envelope(mono)
    raw_bpm, confidence = _tempo_from_autocorrelation(onset_envelope, TARGET_SAMPLE_RATE / HOP_LENGTH)
    bpm = _to_gameplay_bpm(raw_bpm)

    return {
        "raw_bpm": round(float(raw_bpm), 3),
        "bpm": round(float(bpm), 3),
        "beat_period": round(float(60.0 / bpm), 6),
        "confidence": round(float(confidence), 3),
        "source": "offline_autocorrelation_v1",
    }


def _resample_linear(samples: np.ndarray, source_rate: int, target_rate: int) -> np.ndarray:
    if source_rate == target_rate:
        return samples.astype(np.float32, copy=False)

    duration = len(samples) / float(source_rate)
    target_length = max(1, int(duration * target_rate))
    source_positions = np.linspace(0.0, len(samples) - 1, num=len(samples), dtype=np.float32)
    target_positions = np.linspace(0.0, len(samples) - 1, num=target_length, dtype=np.float32)
    return np.interp(target_positions, source_positions, samples).astype(np.float32)


def _onset_envelope(samples: np.ndarray) -> np.ndarray:
    frame_size = 1024
    if len(samples) < frame_size + HOP_LENGTH:
        return np.zeros(1, dtype=np.float32)

    window = np.hanning(frame_size).astype(np.float32)
    previous_spectrum: np.ndarray | None = None
    flux_values: list[float] = []

    for start in range(0, len(samples) - frame_size, HOP_LENGTH):
        frame = samples[start : start + frame_size] * window
        spectrum = np.abs(np.fft.rfft(frame))
        if previous_spectrum is None:
            flux_values.append(0.0)
        else:
            flux_values.append(float(np.maximum(spectrum - previous_spectrum, 0.0).sum()))
        previous_spectrum = spectrum

    envelope = np.asarray(flux_values, dtype=np.float32)
    envelope -= _moving_average(envelope, 16)
    envelope = np.maximum(envelope, 0.0)
    if envelope.max(initial=0.0) > 0.0:
        envelope /= envelope.max()
    return envelope


def _moving_average(values: np.ndarray, radius: int) -> np.ndarray:
    if values.size == 0:
        return values

    kernel_size = radius * 2 + 1
    kernel = np.ones(kernel_size, dtype=np.float32) / float(kernel_size)
    return np.convolve(values, kernel, mode="same")


def _tempo_from_autocorrelation(envelope: np.ndarray, envelope_rate: float) -> tuple[float, float]:
    if envelope.size < 4 or np.allclose(envelope, 0.0):
        return 120.0, 0.0

    envelope = envelope - envelope.mean()
    autocorrelation = np.correlate(envelope, envelope, mode="full")[envelope.size - 1 :]
    autocorrelation[0] = 0.0

    min_lag = max(1, int(math.floor(envelope_rate * 60.0 / MAX_BPM)))
    max_lag = min(len(autocorrelation) - 1, int(math.ceil(envelope_rate * 60.0 / MIN_BPM)))
    if max_lag <= min_lag:
        return 120.0, 0.0

    lag_scores = autocorrelation[min_lag : max_lag + 1]
    best_relative = int(np.argmax(lag_scores))
    best_lag = min_lag + best_relative
    bpm = 60.0 * envelope_rate / float(best_lag)
    bpm = _normalize_tempo_range(bpm)

    best_score = float(lag_scores[best_relative])
    mean_score = float(np.mean(np.abs(lag_scores))) + 1e-6
    confidence = max(0.0, min(1.0, best_score / (mean_score * 8.0)))
    return bpm, confidence


def _normalize_tempo_range(bpm: float) -> float:
    while bpm < MIN_BPM:
        bpm *= 2.0
    while bpm > MAX_BPM:
        bpm *= 0.5
    return bpm


def _to_gameplay_bpm(bpm: float) -> float:
    if bpm < 110.0 and bpm * 2.0 <= MAX_BPM:
        return bpm * 2.0

    return bpm


def _to_resource_path(path: Path, project_root: Path) -> str:
    try:
        relative = path.resolve().relative_to(project_root)
    except ValueError:
        return str(path.resolve()).replace("\\", "/")
    return "res://" + relative.as_posix()


if __name__ == "__main__":
    main()
