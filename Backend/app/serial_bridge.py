from __future__ import annotations

import re
import threading
import time
from collections.abc import Callable
from typing import Any

import serial
from serial import SerialException, SerialTimeoutException

from app.config import settings

SLOT_CODE_PATTERN = re.compile(r"^\d{2}$")
SERIAL_KEY_EVENT_PATTERN = re.compile(r"^EVENT_KEY_([0-9])$")
MOCK_MOTOR_DELAY_SECONDS = 0.25
SERIAL_RECONNECT_DELAY_SECONDS = 1.0
SerialEventCallback = Callable[[dict[str, Any]], None]


class SerialBridgeError(RuntimeError):
    pass


def parse_serial_event(line: str) -> dict[str, Any] | None:
    normalized = line.strip().upper()
    if normalized == "EVENT_USER_DETECTED":
        return {"type": "USER_DETECTED", "data": {}}
    if normalized == "EVENT_ACCEPT":
        return {"type": "KEYPAD_ACCEPT", "data": {}}
    if normalized in {"EVENT_CANCEL", "EVENT_DECLINED"}:
        return {"type": "KEYPAD_CANCEL", "data": {}}

    key_match = SERIAL_KEY_EVENT_PATTERN.fullmatch(normalized)
    if key_match:
        return {
            "type": "KEYPAD_DIGIT",
            "data": {"digit": key_match.group(1)},
        }
    return None


class SerialBridge:
    def __init__(
        self,
        port: str,
        baudrate: int,
        timeout_seconds: float,
        hardware_enabled: bool,
    ) -> None:
        self._port = port
        self._baudrate = baudrate
        self._timeout_seconds = timeout_seconds
        self._hardware_enabled = hardware_enabled
        self._connection: serial.Serial | None = None
        self._connection_lock = threading.RLock()
        self._write_lock = threading.Lock()
        self._response_condition = threading.Condition()
        self._responses: list[str] = []
        self._reader_thread: threading.Thread | None = None
        self._stop_event = threading.Event()
        self._event_callback: SerialEventCallback | None = None

    @property
    def hardware_enabled(self) -> bool:
        return self._hardware_enabled

    def _ensure_connection(self) -> serial.Serial:
        with self._connection_lock:
            if self._connection is not None and self._connection.is_open:
                return self._connection

            if not self._port:
                raise SerialBridgeError("SERIAL_PORT belum dikonfigurasi")

            try:
                self._connection = serial.Serial(
                    port=self._port,
                    baudrate=self._baudrate,
                    timeout=0.25,
                    write_timeout=self._timeout_seconds,
                )
            except SerialException as error:
                raise SerialBridgeError(
                    f"Tidak dapat membuka serial port {self._port}: {error}"
                ) from error

            return self._connection

    def start_event_listener(self, callback: SerialEventCallback) -> None:
        self._event_callback = callback
        if not self._hardware_enabled:
            return
        if self._reader_thread is not None and self._reader_thread.is_alive():
            return

        self._stop_event.clear()
        self._reader_thread = threading.Thread(
            target=self._read_loop,
            name="esp32-serial-events",
            daemon=True,
        )
        self._reader_thread.start()

    def _read_loop(self) -> None:
        while not self._stop_event.is_set():
            try:
                connection = self._ensure_connection()
                line = connection.readline().decode("utf-8", errors="replace").strip()
                if not line:
                    continue
                self._handle_line(line)
            except (SerialBridgeError, SerialException):
                self._close_connection()
                self._stop_event.wait(SERIAL_RECONNECT_DELAY_SECONDS)

    def _handle_line(self, line: str) -> None:
        normalized = line.strip().upper()
        if normalized.startswith("SUCCESS_") or normalized.startswith("ERROR_"):
            with self._response_condition:
                self._responses.append(normalized)
                self._response_condition.notify_all()

        event = parse_serial_event(normalized)
        if event is not None and self._event_callback is not None:
            self._event_callback(event)

    def _write_line(self, command: str) -> None:
        connection = self._ensure_connection()
        try:
            connection.write(f"{command}\n".encode())
            connection.flush()
        except (SerialException, SerialTimeoutException) as error:
            self._close_connection()
            raise SerialBridgeError(f"Komunikasi serial gagal: {error}") from error

    def send_test_input(self, input_name: str) -> str:
        normalized = input_name.strip().upper()
        valid = normalized in {"DETECT", "ACCEPT", "CANCEL", "DECLINED"} or bool(
            re.fullmatch(r"KEY_[0-9]", normalized)
        )
        if not valid:
            raise SerialBridgeError("Input tes serial tidak dikenal")
        if not self._hardware_enabled:
            raise SerialBridgeError("Aktifkan HARDWARE_ENABLED untuk tes melalui ESP32")

        command = f"TEST_{normalized}"
        with self._write_lock:
            self._write_line(command)
        return command

    def drop_slot(self, slot_code: str) -> str:
        if not SLOT_CODE_PATTERN.fullmatch(slot_code):
            raise SerialBridgeError("Kode slot harus terdiri dari dua digit")

        command = f"DROP_SLOT_{slot_code}"
        expected_response = f"SUCCESS_{slot_code}"

        with self._write_lock:
            if not self._hardware_enabled:
                print(f"[MOCK HARDWARE] Mengirim: {command}", flush=True)
                time.sleep(MOCK_MOTOR_DELAY_SECONDS)
                print(f"[MOCK HARDWARE] Menerima: {expected_response}", flush=True)
                return expected_response

            reader_active = (
                self._reader_thread is not None and self._reader_thread.is_alive()
            )
            if not reader_active:
                return self._drop_slot_without_listener(command, expected_response)

            with self._response_condition:
                self._responses.clear()
            self._write_line(command)

            deadline = time.monotonic() + self._timeout_seconds
            with self._response_condition:
                while time.monotonic() < deadline:
                    for response in self._responses:
                        if response == expected_response:
                            return response
                        if response.startswith("ERROR_"):
                            raise SerialBridgeError(
                                f"ESP32 menolak perintah: {response}"
                            )
                    remaining = deadline - time.monotonic()
                    if remaining > 0:
                        self._response_condition.wait(remaining)

            raise SerialBridgeError(
                f"ESP32 tidak mengirim {expected_response}: tidak ada respons"
            )

    def _drop_slot_without_listener(self, command: str, expected_response: str) -> str:
        connection = self._ensure_connection()
        self._write_line(command)
        deadline = time.monotonic() + self._timeout_seconds
        last_response = ""
        try:
            while time.monotonic() < deadline:
                response = (
                    connection.readline().decode("utf-8", errors="replace").strip()
                )
                if not response:
                    continue
                last_response = response
                if response == expected_response:
                    return response
        except (SerialException, SerialTimeoutException) as error:
            self._close_connection()
            raise SerialBridgeError(f"Komunikasi serial gagal: {error}") from error

        detail = last_response or "tidak ada respons"
        raise SerialBridgeError(f"ESP32 tidak mengirim {expected_response}: {detail}")

    def _close_connection(self) -> None:
        with self._connection_lock:
            if self._connection is not None and self._connection.is_open:
                self._connection.close()
            self._connection = None

    def close(self) -> None:
        self._stop_event.set()
        self._close_connection()
        reader = self._reader_thread
        if reader is not None and reader is not threading.current_thread():
            reader.join(timeout=1.0)
        self._reader_thread = None


serial_bridge = SerialBridge(
    port=settings.serial_port,
    baudrate=settings.serial_baudrate,
    timeout_seconds=settings.serial_timeout_seconds,
    hardware_enabled=settings.hardware_enabled,
)
