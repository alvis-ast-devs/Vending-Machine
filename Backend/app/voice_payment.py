from __future__ import annotations

import asyncio
import re
import threading
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from typing import Protocol


class SpeechPaymentError(RuntimeError):
    """Raised when the microphone or speech-recognition provider cannot run."""


@dataclass(frozen=True, slots=True)
class RecognizedAmount:
    transcript: str | None
    amount: int = 0


class CurrencyListener(Protocol):
    def listen_once(self, stop_event: threading.Event) -> RecognizedAmount | None: ...


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
    """Convert Indonesian number words or recognised digits into rupiah."""
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
            current += _parse_recognizer_digits(token)
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


def _parse_recognizer_digits(token: str) -> int:
    """Handle a couple of concatenated-number mistakes seen in Google STT."""
    if len(token) == 6:
        leading = int(token[:3])
        trailing = int(token[-3:])
        if leading % 100 == 0 and trailing in range(100, 1_000, 100):
            return (leading // 100) * 1_000 + trailing
    if len(token) == 7 and token.startswith("1000"):
        return 1_000 + int(token[-3:])
    return int(token)


class GoogleSpeechCurrencyListener:
    """Listen until a real pause, without cutting off a long utterance."""

    def __init__(
        self,
        *,
        language: str,
        phrase_time_limit_seconds: int | None,
        pause_threshold_seconds: float = 2.0,
    ) -> None:
        self._language = language
        self._phrase_time_limit_seconds = phrase_time_limit_seconds
        self._pause_threshold_seconds = pause_threshold_seconds

    def listen_once(self, stop_event: threading.Event) -> RecognizedAmount | None:
        try:
            import speech_recognition as speech
        except ImportError as error:
            raise SpeechPaymentError(
                "Paket SpeechRecognition dan PyAudio belum terpasang di backend."
            ) from error

        recognizer = speech.Recognizer()
        # The library default is ~0.8s, which commonly cuts Indonesian speech
        # between words. Keep listening through short pauses instead.
        recognizer.pause_threshold = self._pause_threshold_seconds
        recognizer.non_speaking_duration = min(
            self._pause_threshold_seconds / 2, 1.0
        )
        try:
            with speech.Microphone() as source:
                recognizer.adjust_for_ambient_noise(source, duration=1)
                while not stop_event.is_set():
                    try:
                        audio = recognizer.listen(
                            source,
                            timeout=1,
                            phrase_time_limit=self._phrase_time_limit_seconds,
                        )
                    except speech.WaitTimeoutError:
                        continue

                    try:
                        transcript = recognizer.recognize_google(
                            audio,
                            language=self._language,
                        )
                    except speech.UnknownValueError:
                        return RecognizedAmount(transcript=None)
                    except speech.RequestError as error:
                        raise SpeechPaymentError(
                            "Layanan pengenalan suara tidak dapat dihubungi."
                        ) from error
                    return RecognizedAmount(
                        transcript=transcript,
                        amount=parse_currency_from_speech(transcript),
                    )
        except (AttributeError, OSError) as error:
            raise SpeechPaymentError(
                "Mikrofon pembayaran tidak dapat dibuka. Periksa perangkat input."
            ) from error
        return None


@dataclass(slots=True)
class VoicePaymentSession:
    transaction_id: str
    slot_codes: list[str]
    total_amount: int
    paid_amount: int = 0
    status: str = "listening"
    stop_event: threading.Event = field(default_factory=threading.Event)
    task: asyncio.Task[None] | None = None

    @property
    def remaining_amount(self) -> int:
        return max(self.total_amount - self.paid_amount, 0)


PaymentEventCallback = Callable[
    [str, VoicePaymentSession, str, str | None], Awaitable[None]
]
PaymentConfirmedCallback = Callable[[VoicePaymentSession], Awaitable[bool]]


class VoicePaymentManager:
    """Owns the single microphone and reports progress through callbacks."""

    def __init__(self, listener: CurrencyListener) -> None:
        self._listener = listener
        self._session: VoicePaymentSession | None = None
        self._lock = asyncio.Lock()

    async def start(
        self,
        *,
        transaction_id: str,
        slot_codes: list[str],
        total_amount: int,
        on_event: PaymentEventCallback,
        on_confirmed: PaymentConfirmedCallback,
    ) -> VoicePaymentSession:
        async with self._lock:
            active = self._session
            if active is not None and active.status in {"listening", "confirming"}:
                if active.transaction_id == transaction_id:
                    return active
                raise SpeechPaymentError("Masih ada pembayaran lain yang menunggu suara.")

            session = VoicePaymentSession(
                transaction_id=transaction_id,
                slot_codes=slot_codes,
                total_amount=total_amount,
            )
            self._session = session
            session.task = asyncio.create_task(
                self._run(session, on_event, on_confirmed),
                name=f"voice-payment-{transaction_id}",
            )
            return session

    async def cancel(self, transaction_id: str) -> bool:
        async with self._lock:
            session = self._session
            if session is None or session.transaction_id != transaction_id:
                return False
            session.stop_event.set()
            session.status = "cancelled"
            return True

    async def _run(
        self,
        session: VoicePaymentSession,
        on_event: PaymentEventCallback,
        on_confirmed: PaymentConfirmedCallback,
    ) -> None:
        await on_event(
            "VOICE_PAYMENT_LISTENING",
            session,
            "",
            None,
        )
        try:
            while not session.stop_event.is_set():
                recognized = await asyncio.to_thread(
                    self._listener.listen_once,
                    session.stop_event,
                )
                if recognized is None or session.stop_event.is_set():
                    return
                if recognized.transcript is None:
                    await on_event(
                        "VOICE_PAYMENT_UNRECOGNIZED",
                        session,
                        "Suara belum dikenali. Silakan ucapkan nominal lagi.",
                        None,
                    )
                    continue
                if recognized.amount <= 0:
                    await on_event(
                        "VOICE_PAYMENT_UNRECOGNIZED",
                        session,
                        "Nominal belum terbaca. Contoh: lima belas ribu rupiah.",
                        recognized.transcript,
                    )
                    continue

                session.paid_amount += recognized.amount
                if session.remaining_amount > 0:
                    await on_event(
                        "VOICE_PAYMENT_UPDATE",
                        session,
                        f"Pembayaran masih kurang Rp{session.remaining_amount:,}.",
                        recognized.transcript,
                    )
                    continue

                session.status = "confirming"
                await on_event(
                    "VOICE_PAYMENT_CONFIRMED",
                    session,
                    "Nominal mencukupi. Memproses pesanan.",
                    recognized.transcript,
                )
                if await on_confirmed(session):
                    session.status = "completed"
                else:
                    session.status = "error"
                return
        except SpeechPaymentError as error:
            session.status = "error"
            await on_event("VOICE_PAYMENT_ERROR", session, str(error), None)
        except Exception:
            session.status = "error"
            await on_event(
                "VOICE_PAYMENT_ERROR",
                session,
                "Terjadi kesalahan saat memproses pembayaran suara.",
                None,
            )
