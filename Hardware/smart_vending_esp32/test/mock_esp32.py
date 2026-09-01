#!/usr/bin/env python3
"""Mock ESP32 for Smart Vending Machine - Serial Communication Simulator"""
import sys, time, threading, argparse
from datetime import datetime

class MockESP32:
    def __init__(self, verbose=False):
        self.verbose = verbose
        self.busy_slots = set()
        self.slot_status = {}
        for i in range(1, 46): self.slot_status[f"{i:02d}"] = "PRESENT"
        for i in range(51, 56): self.slot_status[str(i)] = "PRESENT"

    def log(self, msg):
        if self.verbose:
            ts = datetime.now().strftime("%H:%M:%S")
            print(f"[{ts}] {msg}", flush=True)

    def send_event(self, event):
        print(event, flush=True)
        self.log(f"TX: {event}")

    def process_command(self, command):
        cmd = command.strip().upper()
        if not cmd: return
        self.log(f"RX: {cmd}")
        if cmd.startswith("DROP_SLOT_"):
            sc = cmd[10:]
            if not self._valid(sc): self.send_event(f"ERROR_INVALID_SLOT_{sc}"); return
            self._drop(sc)
        elif cmd.startswith("RESET_SLOT_"):
            sc = cmd[11:]
            if not self._valid(sc): self.send_event(f"ERROR_INVALID_SLOT_{sc}"); return
            self._reset(sc)
        elif cmd in ("DETECT","TEST_DETECT"): self.send_event("EVENT_USER_DETECTED")
        elif cmd in ("ACCEPT","TEST_ACCEPT"): self.send_event("EVENT_ACCEPT")
        elif cmd in ("CANCEL","DECLINED","TEST_CANCEL","TEST_DECLINED"): self.send_event("EVENT_CANCEL")
        elif cmd.startswith("KEY_") and len(cmd)==5 and cmd[4].isdigit(): self.send_event(f"EVENT_KEY_{cmd[4]}")
        elif cmd.startswith("TEST_KEY_") and len(cmd)==10 and cmd[9].isdigit(): self.send_event(f"EVENT_KEY_{cmd[9]}")
        elif len(cmd)==1 and cmd.isdigit(): self.send_event(f"EVENT_KEY_{cmd}")
        elif cmd in ("DEBUG_INPUT","STATUS"): self._status()
        elif cmd == "ALL_OFF": self.busy_slots.clear(); self.send_event("ALL_RELAY_OFF")
        elif cmd.startswith("SIM_SLOT_"): self._sim_slot(cmd)
        elif cmd == "HELP": self._help()
        else: self.send_event("ERROR_UNKNOWN_COMMAND")

    def _valid(self, sc):
        if len(sc)!=2 or not sc.isdigit(): return False
        n=int(sc); return (1<=n<=45) or (51<=n<=55)

    def _drop(self, sc):
        if sc in self.busy_slots: self.send_event(f"ERROR_SLOT_BUSY_{sc}"); return
        self.busy_slots.add(sc); self.send_event(f"BUSY_{sc}")
        def run():
            try:
                time.sleep(0.2)
                self.log(f"MOTOR: Slot {sc} sensor LOW")
                time.sleep(0.6)
                self.log(f"MOTOR: Slot {sc} sensor HIGH (drop OK)")
                self.send_event(f"SUCCESS_{sc}")
                self.slot_status[sc] = "EMPTY"
            except Exception as e:
                self.send_event(f"ERROR_MOTOR_{sc}_{e}")
            finally:
                self.busy_slots.discard(sc)
        threading.Thread(target=run, daemon=True).start()

    def _reset(self, sc):
        self.send_event(f"BUSY_{sc}")
        def run(): time.sleep(0.3); self.send_event(f"RESET_OK_{sc}")
        threading.Thread(target=run, daemon=True).start()

    def _sim_slot(self, cmd):
        parts = cmd.split("_")
        if len(parts)!=4: return
        sc, state = parts[2], parts[3]
        if not self._valid(sc): return
        self.slot_status[sc] = state
        self.send_event(f"EVENT_SLOT_{sc}_{state}")

    def _status(self):
        p = sum(1 for v in self.slot_status.values() if v=="PRESENT")
        e = sum(1 for v in self.slot_status.values() if v=="EMPTY")
        b = len(self.busy_slots)
        self.send_event(f"STATUS: {p} PRESENT, {e} EMPTY, {b} BUSY")
        self.send_event(f"STATUS: Busy: {",".join(sorted(self.busy_slots)) or "none"}")

    def _help(self):
        for l in [
            "=== Mock ESP32 Commands ===",
            "DROP_SLOT_XX   - Drop product",
            "RESET_SLOT_XX  - Reset motor",
            "DETECT         - User detected",
            "KEY_X          - Digit input",
            "ACCEPT         - Confirm",
            "CANCEL         - Cancel",
            "SIM_SLOT_XX_PRESENT/EMPTY",
            "STATUS         - Show status",
            "HELP           - This help",
        ]: self.send_event(l)

def main():
    p = argparse.ArgumentParser(description="Mock ESP32")
    p.add_argument("--virtual", action="store_true")
    p.add_argument("--port", type=str)
    p.add_argument("--tcp", type=int)
    p.add_argument("--baudrate", type=int, default=115200)
    p.add_argument("-v","--verbose", action="store_true")
    args = p.parse_args()
    mock = MockESP32(verbose=args.verbose)
    mock.send_event("READY")
    mock.send_event("SHIFT_REG: 7x74HC595 OUT + 7x74HC165 IN initialized")
    if args.port:
        import serial
        ser = serial.Serial(args.port, args.baudrate, timeout=1)
        print(f"Connected to {args.port}")
        while True:
            if ser.in_waiting:
                line = ser.readline().decode("utf-8",errors="ignore").strip()
                if line: mock.process_command(line)
            time.sleep(0.01)
    elif args.tcp:
        import socket
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("0.0.0.0", args.tcp))
        srv.listen(1)
        print(f"TCP listening on port {args.tcp}")
        while True:
            c, a = srv.accept()
            print(f"Client: {a}")
            c.sendall(b"READY\n")
            buf = ""
            while True:
                try:
                    d = c.recv(1024)
                    if not d: break
                    buf += d.decode("utf-8",errors="ignore")
                    while "\n" in buf:
                        line, buf = buf.split("\n",1)
                        if line.strip(): mock.process_command(line.strip())
                except: break
            c.close()
    else:
        print("=== Mock ESP32 (Virtual Mode) ===")
        print("Type commands (HELP for help)")
        try:
            while True:
                try:
                    cmd = input("> ")
                    mock.process_command(cmd)
                except EOFError: break
        except KeyboardInterrupt: print("\nBye")

if __name__ == "__main__": main()
