"""
Voice recognition script for Smart Vending Machine.

Listens to the microphone, recognizes Indonesian speech OFFLINE,
and outputs JSON lines with the recognized amount.

Recognition engine: faster-whisper (CTranslate2) with an Indonesian-capable
multilingual model — works with NO internet connection. The model lives in a
folder next to this script:

    <release folder>\
    ├── vending_ui.exe
    ├── scripts\
    │   └── voice_recognition.py      <- this file
    └── models\
        └── whisper-base\             <- offline model (model.bin inside)

Protocol:
  - Reads from stdin: "STOP" to exit
  - Writes to stdout: JSON lines like {"transcript": "lima belas ribu", "amount": 15000}

Usage:
  python voice_recognition.py
"""

from __future__ import annotations

import json
import os
import re
import sys
import threading
from pathlib import Path

# Name of the offline model folder (Systran/faster-whisper-<size>).
# Switch to "whisper-tiny" for a smaller/faster model, or "whisper-small"
# for better accuracy (download the matching folder into models\).
MODEL_NAME = "whisper-base"

# ─── Currency parsing (ported from Backend/app/voice_payment.py) ─────────────

_NUMBER_WORDS = {
    "nol": 0,
    "satu": 1,
    "dua": 2,
    "tiga": 3,
    "empat": 4,
    "lima": 5,
    "enam": 6,
    "tujuh": 7,
    "delapan": 8,
    "sembilan": 9,
    "sepuluh": 10,
    "sebelas": 11,
}
_SMALL_MULTIPLIERS = {"puluh": 10, "ratus": 100}
_LARGE_MULTIPLIERS = {"ribu": 1_000, "juta": 1_000_000}
_IGNORED_WORDS = {
    "rupiah",
    "rp",
    "sebesar",
    "bayar",
    "pembayaran",
    "uang",
    "nominal",
    "adalah",
    "saya",
    "mau",
    "ini",
    "dan",
}


def parse_currency_from_speech(text: str) -> int:
    """Convert Indonesian number words or recognized digits into rupiah."""
    normalized = text.lower().strip()
    normalized = normalized.replace("seratus", "satu ratus")
    normalized = normalized.replace("seribu", "satu ribu")
    normalized = normalized.replace("sejuta", "satu juta")
    normalized = re.sub(r"(?<=\d)[.,](?=\d)", "", normalized)
    normalized = re.sub(r"[^a-z0-9\s]", " ", normalized)
    tokens = normalized.split()

    total = 0
    current = 0
    seen_number = False

    for token in tokens:
        if token in _IGNORED_WORDS:
            continue
        if token in _NUMBER_WORDS:
            current += _NUMBER_WORDS[token]
            seen_number = True
            continue
        if token.isdigit():
            current += int(token)
            seen_number = True
            continue
        if token == "belas":
            current += 10
            seen_number = True
            continue
        if token in _SMALL_MULTIPLIERS:
            current = max(current, 1) * _SMALL_MULTIPLIERS[token]
            seen_number = True
            continue
        if token in _LARGE_MULTIPLIERS:
            total += max(current, 1) * _LARGE_MULTIPLIERS[token]
            current = 0
            seen_number = True

    return total + current if seen_number else 0


# ─── Offline model location ─────────────────────────────────────────────────


def find_model_dir() -> Path | None:
    """Locate the offline whisper model next to this script or the exe."""
    script_dir = Path(__file__).resolve().parent
    release_root = script_dir.parent  # folder containing the exe / scripts
    candidates = [
        release_root / "models" / MODEL_NAME,  # <release>\models\whisper-base
        script_dir / MODEL_NAME,               # <release>\scripts\whisper-base
    ]
    for candidate in candidates:
        if (candidate / "model.bin").is_file():
            return candidate
    return None


# ─── Microphone listening ───────────────────────────────────────────────────


def write_output(data: dict) -> None:
    """Write a JSON line to stdout and flush."""
    print(json.dumps(data, ensure_ascii=False), flush=True)


def load_offline_model():
    """Load the faster-whisper model once. Never touches the network."""
    os.environ["HF_HUB_OFFLINE"] = "1"  # hard guarantee: no internet access
    os.environ["TRANSFORMERS_OFFLINE"] = "1"

    try:
        from faster_whisper import WhisperModel
    except ImportError:
        write_output({"error": "faster-whisper belum terpasang di runtime python"})
        sys.exit(1)

    model_dir = find_model_dir()
    if model_dir is None:
        write_output({
            "error": (
                f"Model offline '{MODEL_NAME}' tidak ditemukan. "
                f"Letakkan model di folder 'models\\{MODEL_NAME}' "
                "di samping aplikasi."
            )
        })
        sys.exit(1)

    try:
        return WhisperModel(
            str(model_dir), device="cpu", compute_type="int8"
        )
    except Exception as exc:  # noqa: BLE001 - report anything that blocks startup
        write_output({"error": f"Model offline gagal dimuat: {exc}"})
        sys.exit(1)


def transcribe_offline(model, audio) -> str:
    """Transcribe a speech_recognition AudioData chunk to Indonesian text."""
    import numpy as np

    raw = audio.get_raw_data(convert_rate=16_000, convert_width=2)
    samples = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0

    segments, _info = model.transcribe(
        samples,
        language="id",
        beam_size=1,
        condition_on_previous_text=False,
        vad_filter=False,  # silence already trimmed by the mic listener
    )
    return " ".join(segment.text for segment in segments).strip()


def listen_loop(stop_event: threading.Event) -> None:
    """Main loop: listen to microphone, parse amounts, output JSON lines."""
    try:
        import speech_recognition as speech
    except ImportError:
        write_output({"error": "SpeechRecognition belum terpasang"})
        sys.exit(1)

    model = load_offline_model()

    recognizer = speech.Recognizer()
    recognizer.pause_threshold = 2.0
    recognizer.non_speaking_duration = 1.0

    try:
        mic = speech.Microphone()
    except (AttributeError, OSError):
        write_output({"error": "Mikrofon tidak dapat dibuka"})
        sys.exit(1)

    with mic as source:
        recognizer.adjust_for_ambient_noise(source, duration=1)
        write_output({"status": "ready"})

        # IMPORTANT: only start watching stdin AFTER the model and mic are
        # ready. A thread blocked reading stdin while native modules load
        # (numpy / ctranslate2 / pyaudio DLLs) deadlocks the whole process
        # on Windows. The app spawns us with an open stdin pipe, so waiting
        # for STOP too early freezes the script before it can transcribe.
        stdin_thread = threading.Thread(
            target=watch_stdin,
            args=(stop_event,),
            daemon=True,
        )
        stdin_thread.start()

        while not stop_event.is_set():
            try:
                audio = recognizer.listen(source, timeout=60, phrase_time_limit=None)
            except speech.WaitTimeoutError:
                continue

            try:
                transcript = transcribe_offline(model, audio)
            except Exception as exc:  # noqa: BLE001 - never kill the loop
                write_output({"error": f"Gagal memproses audio: {exc}"})
                continue

            if not transcript:
                write_output({"transcript": None, "amount": 0})
                continue

            amount = parse_currency_from_speech(transcript)
            write_output({"transcript": transcript, "amount": amount})


def watch_stdin(stop_event: threading.Event) -> None:
    """Read stdin and stop when 'STOP' is received."""
    for line in sys.stdin:
        if line.strip().upper() == "STOP":
            stop_event.set()
            return


if __name__ == "__main__":
    stop_event = threading.Event()

    try:
        listen_loop(stop_event)
    except KeyboardInterrupt:
        pass
    finally:
        stop_event.set()
