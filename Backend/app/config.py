from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()


def env_bool(name: str, default: bool = False) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def env_optional_int(name: str, default: int | None = None) -> int | None:
    """Read an integer setting; blank/zero means no limit."""
    value = os.getenv(name)
    if value is None or not value.strip():
        return default
    parsed = int(value)
    return None if parsed <= 0 else parsed


@dataclass(frozen=True, slots=True)
class Settings:
    app_name: str = os.getenv("APP_NAME", "Smart Vending Machine API")
    database_url: str = os.getenv(
        "DATABASE_URL",
        "postgresql+psycopg://vending:vending@localhost:5432/vending_machine",
    )
    cors_origins: str = os.getenv(
        "CORS_ORIGINS",
        (
            "http://localhost:5173,http://127.0.0.1:5173,"
            "http://localhost:4173,http://127.0.0.1:4173"
        ),
    )
    serial_port: str = os.getenv("SERIAL_PORT", "COM3")
    serial_baudrate: int = int(os.getenv("SERIAL_BAUDRATE", "115200"))
    serial_timeout_seconds: float = float(os.getenv("SERIAL_TIMEOUT_SECONDS", "5"))
    hardware_enabled: bool = env_bool("HARDWARE_ENABLED", default=False)
    voice_payment_enabled: bool = env_bool("VOICE_PAYMENT_ENABLED", default=True)
    voice_payment_language: str = os.getenv("VOICE_PAYMENT_LANGUAGE", "id-ID")
    # None means SpeechRecognition listens until the user stops speaking.
    voice_phrase_time_limit_seconds: int | None = env_optional_int(
        "VOICE_PHRASE_TIME_LIMIT_SECONDS", default=None
    )
    voice_pause_threshold_seconds: float = float(
        os.getenv("VOICE_PAUSE_THRESHOLD_SECONDS", "2.0")
    )
    full_stock: int = int(os.getenv("FULL_STOCK", "10"))
    media_upload_dir: str = os.getenv(
        "MEDIA_UPLOAD_DIR",
        str(Path(__file__).resolve().parent.parent / "uploads"),
    )
    max_image_upload_mb: int = int(os.getenv("MAX_IMAGE_UPLOAD_MB", "20"))
    max_video_upload_mb: int = int(os.getenv("MAX_VIDEO_UPLOAD_MB", "500"))

    @property
    def allowed_origins(self) -> list[str]:
        return [
            origin.strip() for origin in self.cors_origins.split(",") if origin.strip()
        ]


settings = Settings()
