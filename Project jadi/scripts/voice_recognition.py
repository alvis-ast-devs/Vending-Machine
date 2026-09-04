"""
Voice recognition script for Smart Vending Machine.

Listens to the microphone, recognizes Indonesian speech,
and outputs JSON lines with the recognized amount.

Protocol:
  - Reads from stdin: "STOP" to exit
  - Writes to stdout: JSON lines like {"transcript": "lima belas ribu", "amount": 15000}

Usage:
  python voice_recognition.py
"""

from __future__ import annotations

import json
import re
import sys
import threading

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


# ─── Microphone listening ───────────────────────────────────────────────────


def write_output(data: dict) -> None:
    """Write a JSON line to stdout and flush."""
    print(json.dumps(data, ensure_ascii=False), flush=True)


def listen_loop() -> None:
    """Main loop: listen to microphone, parse amounts, output JSON lines."""
    try:
        import speech_recognition as speech
    except ImportError:
        write_output({"error": "SpeechRecognition belum terpasang"})
        sys.exit(1)

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

        while True:
            try:
                audio = recognizer.listen(source, timeout=1, phrase_time_limit=None)
            except speech.WaitTimeoutError:
                continue

            try:
                transcript = recognizer.recognize_google(
                    audio, language="id-ID"
                )
            except speech.UnknownValueError:
                write_output({"transcript": None, "amount": 0})
                continue
            except speech.RequestError:
                write_output({"error": "Layanan pengenalan suara tidak tersedia"})
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

    stdin_thread = threading.Thread(
        target=watch_stdin,
        args=(stop_event,),
        daemon=True,
    )
    stdin_thread.start()

    try:
        listen_loop()
    except KeyboardInterrupt:
        pass
    finally:
        stop_event.set()
