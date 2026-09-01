#!/usr/bin/env python3
"""
Mock ESP32 — Vending Machine Simulator
=======================================
Simulates microcontroller serial communication to test the Flutter app
without real hardware.

Usage:
  python mock_esp32.py --tcp 8888    # TCP mode (for Flutter app connection)
  python mock_esp32.py               # Virtual mode (stdin only, no app needed)

Commands (type these in the terminal):
  Person_TRUE    → Simulate person detected (IR sensor)
  CANCEL         → Simulate shift/cancel button press
  ACCEPT         → Simulate enter/accept button press
  1-9, 0         → Simulate keypad digit input
  Slot_X_HIGH    → Simulate sensor HIGH (dynamo completed rotation, item dropped)
  Slot_X_LOW     → Simulate sensor LOW (dynamo spinning)
  STATUS         → Show pending drops and busy slots
  HELP           → Show full help
"""
import sys
import time
import threading
import argparse
from datetime import datetime


class MockESP32:
    def __init__(self, verbose=False):
        self.verbose = verbose
        self.pending_drops = set()   # slot codes waiting for Slot_X_HIGH
        self.busy_slots = set()
        self.tcp_clients = []
        self.lock = threading.Lock()

    def log(self, msg):
        if self.verbose:
            ts = datetime.now().strftime("%H:%M:%S")
            print(f"[{ts}] {msg}", flush=True)

    # ─── Send to Flutter ──────────────────────────────────────────────────────

    def send_event(self, event):
        """Send an event line to the Flutter app (stdout or TCP)."""
        print(f"← {event}", flush=True)
        self.log(f"TX: {event}")
        with self.lock:
            dead = []
            for c in self.tcp_clients:
                try:
                    c.sendall((event + "\n").encode())
                except Exception:
                    dead.append(c)
            for c in dead:
                self.tcp_clients.remove(c)

    # ─── Command Router ───────────────────────────────────────────────────────

    def process_command(self, command):
        cmd = command.strip()
        if not cmd:
            return
        self.log(f"RX: {cmd}")
        upper = cmd.upper()

        # ── User-input commands (what the human tester types) ──

        # Person detected (IR sensor)
        if upper == "PERSON_TRUE":
            self.send_event("EVENT_USER_DETECTED")
            return

        # Cancel / Shift button
        if upper == "CANCEL":
            self.send_event("EVENT_CANCEL")
            return

        # Accept / Enter button
        if upper == "ACCEPT":
            self.send_event("EVENT_ACCEPT")
            return

        # Keypad digit (single character 0-9)
        if len(cmd) == 1 and cmd.isdigit():
            self.send_event(f"EVENT_KEY_{cmd}")
            return

        # Slot sensor HIGH → item dropped
        if upper.startswith("SLOT_") and upper.endswith("_HIGH"):
            self._handle_slot_high(upper)
            return

        # Slot sensor LOW → motor spinning
        if upper.startswith("SLOT_") and upper.endswith("_LOW"):
            self._handle_slot_low(upper)
            return

        # ── App-originated commands (from DROP_SLOT_XX, etc.) ──

        if upper.startswith("DROP_SLOT_"):
            self._handle_drop(upper)
            return

        if upper.startswith("RESET_SLOT_"):
            self._handle_reset(upper)
            return

        if upper in ("DETECT", "TEST_DETECT"):
            self.send_event("EVENT_USER_DETECTED")
            return

        if upper in ("ACCEPT", "TEST_ACCEPT"):
            self.send_event("EVENT_ACCEPT")
            return

        if upper in ("CANCEL", "DECLINED", "TEST_CANCEL", "TEST_DECLINED"):
            self.send_event("EVENT_CANCEL")
            return

        if upper.startswith("KEY_") and len(upper) == 5 and upper[4].isdigit():
            self.send_event(f"EVENT_KEY_{upper[4]}")
            return

        if upper.startswith("TEST_KEY_") and len(upper) == 10 and upper[9].isdigit():
            self.send_event(f"EVENT_KEY_{upper[9]}")
            return

        # ── Utility commands ──

        if upper in ("STATUS", "PENDING"):
            self._status()
            return

        if upper == "ALL_OFF":
            self.busy_slots.clear()
            self.pending_drops.clear()
            self.send_event("ALL_RELAY_OFF")
            return

        if upper == "HELP":
            self._help()
            return

        print(f"  ⚠ Perintah tidak dikenal: {cmd}", flush=True)

    # ─── Slot Sensor Handling ─────────────────────────────────────────────────

    def _handle_slot_high(self, cmd):
        """Slot_X_HIGH — sensor went HIGH, item dropped."""
        parts = cmd.split("_")
        if len(parts) != 3:
            print("  ⚠ Format: Slot_X_HIGH atau Slot_XX_HIGH", flush=True)
            return

        slot_num = parts[1]
        if not slot_num.isdigit():
            print("  ⚠ Slot harus berupa angka", flush=True)
            return

        # Normalize to 2-digit code: "1" → "01", "51" → "51"
        slot_code = slot_num.zfill(2)

        with self.lock:
            if slot_code in self.pending_drops:
                self.pending_drops.discard(slot_code)
                self.busy_slots.discard(slot_code)
                self.send_event(f"SUCCESS_{slot_code}")
                print(f"  ✓ Drop slot {slot_code} berhasil!", flush=True)
                if self.pending_drops:
                    remaining = ", ".join(sorted(self.pending_drops))
                    print(f"  ⏳ Masih menunggu: {remaining}", flush=True)
                else:
                    print(f"  ✅ Semua drop selesai!", flush=True)
                return

        print(f"  ℹ Slot {slot_code} HIGH (tidak ada drop aktif)", flush=True)

    def _handle_slot_low(self, cmd):
        """Slot_X_LOW — sensor went LOW (motor spinning)."""
        parts = cmd.split("_")
        if len(parts) != 3:
            return
        slot_num = parts[1]
        if not slot_num.isdigit():
            return
        slot_code = slot_num.zfill(2)
        print(f"  ℹ Slot {slot_code} LOW (motor berputar)", flush=True)

    # ─── App Command Handlers ─────────────────────────────────────────────────

    def _handle_drop(self, cmd):
        """DROP_SLOT_XX — app requests product drop."""
        slot_code = cmd[10:]  # Remove "DROP_SLOT_"

        if len(slot_code) != 2 or not slot_code.isdigit():
            self.send_event(f"ERROR_INVALID_SLOT_{slot_code}")
            return

        n = int(slot_code)
        if not ((1 <= n <= 45) or (51 <= n <= 55)):
            self.send_event(f"ERROR_INVALID_SLOT_{slot_code}")
            return

        if slot_code in self.busy_slots:
            self.send_event(f"ERROR_SLOT_BUSY_{slot_code}")
            return

        self.busy_slots.add(slot_code)
        with self.lock:
            self.pending_drops.add(slot_code)

        self.send_event(f"BUSY_{slot_code}")
        display_num = int(slot_code)
        print(f"  → Menunggu: Slot_{display_num}_HIGH", flush=True)

    def _handle_reset(self, cmd):
        """RESET_SLOT_XX — app requests motor reset."""
        slot_code = cmd[11:]  # Remove "RESET_SLOT_"

        if len(slot_code) != 2 or not slot_code.isdigit():
            self.send_event(f"ERROR_INVALID_SLOT_{slot_code}")
            return

        n = int(slot_code)
        if not ((1 <= n <= 45) or (51 <= n <= 55)):
            self.send_event(f"ERROR_INVALID_SLOT_{slot_code}")
            return

        self.send_event(f"BUSY_{slot_code}")

        def run():
            time.sleep(0.3)
            self.send_event(f"RESET_OK_{slot_code}")

        threading.Thread(target=run, daemon=True).start()

    # ─── Status & Help ────────────────────────────────────────────────────────

    def _status(self):
        with self.lock:
            pending = sorted(self.pending_drops)
        busy = sorted(self.busy_slots)
        print(f"  Drop pending : {', '.join(pending) or '—'}", flush=True)
        print(f"  Busy slots   : {', '.join(busy) or '—'}", flush=True)

    def _help(self):
        print(
            """
╔══════════════════════════════════════════════════════════════╗
║              MOCK ESP32 — Vending Machine Simulator         ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║  PERINTAH INPUT (simulasi microcontroller):                  ║
║  ─────────────────────────────────────────────────────────── ║
║  Person_TRUE    → Deteksi orang (sensor IR)                  ║
║  CANCEL         → Tombol shift / batal                       ║
║  ACCEPT         → Tombol enter / konfirmasi                  ║
║  1-9, 0         → Input digit keypad                         ║
║                                                              ║
║  PERINTAH SENSOR (simulasi dynamo & sensor):                 ║
║  ─────────────────────────────────────────────────────────── ║
║  Slot_X_HIGH    → Sensor HIGH (barang jatuh)                 ║
║  Slot_X_LOW     → Sensor LOW  (motor berputar)               ║
║                                                              ║
║  PERINTAH LAINNYA:                                           ║
║  ─────────────────────────────────────────────────────────── ║
║  STATUS         → Drop pending & busy slots                  ║
║  ALL_OFF        → Matikan semua relay                        ║
║  HELP           → Tampilkan bantuan ini                      ║
║                                                              ║
║  ┌──────────────────────────────────────────────────────────┐║
║  │  CONTOH FLOW TEST:                                      │║
║  │                                                          │║
║  │  1. Person_TRUE       → Orang datang, masuk ke menu     │║
║  │  2. 0                 → Digit '0'                        │║
║  │  3. 1                 → Digit '1'                        │║
║  │  4. ACCEPT            → Produk 01 ditambah ke keranjang │║
║  │  5. ACCEPT            → Checkout (bayar)                 │║
║  │  6. (App kirim DROP_SLOT_01 → mock balas BUSY_01)       │║
║  │  7. Slot_1_HIGH       → Barang jatuh → SUCCESS_01       │║
║  │  8. → Halaman "Terima Kasih!" → Kembali ke beranda      │║
║  └──────────────────────────────────────────────────────────┘║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
""",
            flush=True,
        )


# ─── TCP Server ───────────────────────────────────────────────────────────────


def tcp_server(mock, port):
    import socket

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", port))
    srv.listen(1)
    print(f"🔌 TCP listening on port {port}")

    while True:
        c, a = srv.accept()
        print(f"📱 Client connected: {a}")
        with mock.lock:
            mock.tcp_clients.append(c)
        c.sendall(b"READY\n")
        buf = ""
        while True:
            try:
                d = c.recv(1024)
                if not d:
                    break
                buf += d.decode("utf-8", errors="ignore")
                while "\n" in buf:
                    line, buf = buf.split("\n", 1)
                    if line.strip():
                        mock.process_command(line.strip())
            except Exception:
                break
        with mock.lock:
            if c in mock.tcp_clients:
                mock.tcp_clients.remove(c)
        c.close()
        print(f"📱 Client disconnected: {a}")


# ─── Stdin Reader ─────────────────────────────────────────────────────────────


def stdin_reader(mock):
    try:
        while True:
            try:
                cmd = input("🎮 > ")
                mock.process_command(cmd)
            except EOFError:
                break
    except KeyboardInterrupt:
        pass


# ─── Main ─────────────────────────────────────────────────────────────────────


def main():
    parser = argparse.ArgumentParser(
        description="Mock ESP32 — Vending Machine Simulator"
    )
    parser.add_argument("--virtual", action="store_true", help="Virtual mode (stdin only)")
    parser.add_argument("--port", type=str, help="Serial port (not recommended)")
    parser.add_argument("--tcp", type=int, help="TCP port for Flutter connection")
    parser.add_argument("--baudrate", type=int, default=115200)
    parser.add_argument("-v", "--verbose", action="store_true", help="Verbose output")
    args = parser.parse_args()

    mock = MockESP32(verbose=args.verbose)

    print(
        """
╔══════════════════════════════════════════════════════════════╗
║           MOCK ESP32 — Vending Machine Simulator            ║
║          Testing tanpa microcontroller / hardware            ║
╚══════════════════════════════════════════════════════════════╝
""",
        flush=True,
    )
    mock.send_event("READY")
    mock.send_event("SHIFT_REG: 7×74HC595 OUT + 7×74HC165 IN initialized")

    if args.port:
        import serial

        ser = serial.Serial(args.port, args.baudrate, timeout=1)
        print(f"📡 Connected to {args.port}")
        while True:
            if ser.in_waiting:
                line = ser.readline().decode("utf-8", errors="ignore").strip()
                if line:
                    mock.process_command(line)
            time.sleep(0.01)
    elif args.tcp:
        print("🔌 Mode: TCP + stdin")
        print("   Ketik HELP untuk bantuan\n")
        t = threading.Thread(target=tcp_server, args=(mock, args.tcp), daemon=True)
        t.start()
        stdin_reader(mock)
    else:
        print("🎮 Mode: Virtual (stdin only)")
        print("   Ketik HELP untuk bantuan\n")
        stdin_reader(mock)


if __name__ == "__main__":
    main()
