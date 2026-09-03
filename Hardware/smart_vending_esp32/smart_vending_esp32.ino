// =============================================================================
// Smart Vending Machine — ESP32 Firmware
// =============================================================================
// 50 Output: 74HC595 × 7 → Relay × 50 → Motor pengdrop produk
// Drop detect: IR receiver array (≈10 unit) → semua OUT diparalel ke 1 pin
// Serial:    Komunikasi dengan Flutter Frontend via UART 115200
//
// Mapping Slot → Bit:
//   Slot 01-45 → bit 0-44
//   Slot 51-55 → bit 45-49
//
// Perintah Serial dari Frontend:
//   DROP_SLOT_XX  → jalankan motor slot XX; motor berhenti saat salah satu
//                    IR receiver mendeteksi produk jatuh (beam terblokir),
//                    atau setelah MOTOR_RUN_TIME_MS (safety timeout)
//   DETECT        → simulasi user terdeteksi
//   KEY_X / X     → input digit keypad (0-9)
//   ACCEPT        → konfirmasi
//   CANCEL        → batal
//
// Event Serial ke Frontend:
//   READY, BUSY_XX, SUCCESS_XX, WARNING_NO_DROP_XX, ERROR_*
//   EVENT_USER_DETECTED, EVENT_KEY_X, EVENT_ACCEPT, EVENT_CANCEL
//   IR_STATUS (debug: baca level IR untuk kalibrasi IR_ACTIVE_LEVEL)
// =============================================================================

#include "shift_output.h"
#include "keypad.h"

// ─── IR Receiver (Drop Detection) ────────────────────────────────────────────
// Semua OUT dari IR receiver array (≈10 unit) diparalel ke satu jalur bersama.
// Jalur ini masuk ke satu GPIO; jika salah satu beam terblokir, motor berhenti.
#define IR_PIN 14
// Level saat beam TERBLOKIR (produk jatuh). Ganti ke LOW bila modul aktif-LOW.
#define IR_ACTIVE_LEVEL LOW
// Lama beam harus stabil terblokir sebelum motor dihentikan (ms).
#define IR_DEBOUNCE_MS 40

// ─── Konfigurasi ─────────────────────────────────────────────────────────────
const uint32_t SERIAL_BAUD_RATE = 115200;
// Safety timeout: motor dipaksa berhenti bila IR tidak mendeteksi produk jatuh.
const unsigned long MOTOR_RUN_TIME_MS = 5000;
const size_t MAX_COMMAND_LENGTH = 40;

// ─── State ───────────────────────────────────────────────────────────────────
String commandBuffer;
unsigned long lastKeypadPoll = 0;
const unsigned long KEYPAD_POLL_INTERVAL_MS = 10;  // debounce-safe polling interval

// =============================================================================
//  IR RECEIVER — drop detection (array receiver diparalel ke 1 pin)
// =============================================================================

/// Return true jika beam IR terblokir stabil selama IR_DEBOUNCE_MS.
/// Semua receiver diparalel ke IR_PIN, jadi jika SATU saja beam-nya
/// terblokir (produk jatuh), fungsi ini mengembalikan true.
bool irBeamBlocked() {
  const unsigned long start = millis();
  while (millis() - start < IR_DEBOUNCE_MS) {
    if (digitalRead(IR_PIN) != IR_ACTIVE_LEVEL) {
      return false;  // sempat tidak aktif → noise/bouncing, abaikan
    }
    delay(1);
  }
  return true;
}

// =============================================================================
//  RELAY / MOTOR CONTROL (menggunakan shift register output)
// =============================================================================

/// Jalankan motor slot sampai IR mendeteksi produk jatuh, atau timeout.
/// Motor menyala → produk jatuh melewati salah satu IR receiver → beam
/// terblokir → motor langsung dimatikan. Jika timeout tanpa deteksi, motor
/// tetap dimatikan dan warning dikirim (safety fallback).
void runMotorForSlot(const String &slotCode) {
  Serial.print(F("BUSY_"));
  Serial.println(slotCode);

  // Mulai motor
  shiftOutput.setSlotActive(slotCode, true);
  shiftOutput.flush();

  const unsigned long startTime = millis();
  bool dropConfirmed = false;

  // Tunggu IR: salah satu beam terblokir = produk jatuh terdeteksi.
  while (millis() - startTime < MOTOR_RUN_TIME_MS) {
    if (irBeamBlocked()) {
      dropConfirmed = true;  // drop terdeteksi → hentikan dinamo sekarang
      break;
    }
    delay(5);
  }

  // Matikan motor (baik sukses maupun timeout)
  shiftOutput.setSlotActive(slotCode, false);
  shiftOutput.flush();

  if (dropConfirmed) {
    Serial.print(F("SUCCESS_"));
  } else {
    Serial.print(F("WARNING_NO_DROP_"));
  }
  Serial.println(slotCode);
}

// =============================================================================
//  EVENT EMITTERS
// =============================================================================

void emitUserDetected() {
  Serial.println(F("EVENT_USER_DETECTED"));
}

void emitKeypadDigit(const char digit) {
  Serial.print(F("EVENT_KEY_"));
  Serial.println(digit);
}

void emitKeypadAccept() {
  Serial.println(F("EVENT_ACCEPT"));
}

void emitKeypadCancel() {
  Serial.println(F("EVENT_CANCEL"));
}

// =============================================================================
//  SERIAL COMMAND PARSER
// =============================================================================

bool processTestInput(const String &command) {
  if (command == "DETECT" || command == "TEST_DETECT") {
    emitUserDetected();
    return true;
  }
  if (command == "ACCEPT" || command == "TEST_ACCEPT") {
    emitKeypadAccept();
    return true;
  }
  if (command == "CANCEL" || command == "DECLINED" ||
      command == "TEST_CANCEL" || command == "TEST_DECLINED") {
    emitKeypadCancel();
    return true;
  }

  // Single digit: 0-9
  if (command.length() == 1 && isDigit(command.charAt(0))) {
    emitKeypadDigit(command.charAt(0));
    return true;
  }

  // KEY_X atau TEST_KEY_X
  const String keyPrefix = "KEY_";
  const String testKeyPrefix = "TEST_KEY_";
  if (command.startsWith(keyPrefix) && command.length() == 5 &&
      isDigit(command.charAt(4))) {
    emitKeypadDigit(command.charAt(4));
    return true;
  }
  if (command.startsWith(testKeyPrefix) && command.length() == 10 &&
      isDigit(command.charAt(9))) {
    emitKeypadDigit(command.charAt(9));
    return true;
  }

  // DEBUG: cetak level IR saat ini (untuk kalibrasi IR_ACTIVE_LEVEL)
  if (command == "IR_STATUS" || command == "STATUS") {
    Serial.print(F("IR_LEVEL="));
    Serial.println(digitalRead(IR_PIN) ? F("HIGH") : F("LOW"));
    return true;
  }

  // DEBUG: matikan semua relay
  if (command == "ALL_OFF") {
    shiftOutput.allOff();
    Serial.println(F("ALL_RELAY_OFF"));
    return true;
  }

  return false;
}

void processCommand(String command) {
  command.trim();
  command.toUpperCase();
  if (command.isEmpty()) return;

  if (processTestInput(command)) return;

  const String commandPrefix = "DROP_SLOT_";
  if (!command.startsWith(commandPrefix)) {
    Serial.println(F("ERROR_UNKNOWN_COMMAND"));
    return;
  }

  const String slotCode = command.substring(commandPrefix.length());
  if (!isValidSlotCode(slotCode)) {
    Serial.print(F("ERROR_INVALID_SLOT_"));
    Serial.println(slotCode);
    return;
  }

  runMotorForSlot(slotCode);
}

// =============================================================================
//  VALIDASI SLOT
// =============================================================================

bool isValidSlotCode(const String &slotCode) {
  if (slotCode.length() != 2) return false;

  for (size_t i = 0; i < slotCode.length(); i++) {
    const char c = slotCode.charAt(i);
    if (c < '0' || c > '9') return false;
  }

  const int n = slotCode.toInt();
  return (n >= 1 && n <= 45) || (n >= 51 && n <= 55);
}

// =============================================================================
//  SETUP & LOOP
// =============================================================================

void setup() {
  Serial.begin(SERIAL_BAUD_RATE);

  // Inisialisasi shift register output (relay).
  shiftOutput.begin();

  // Inisialisasi pin IR receiver (drop detection, semua receiver diparalel).
  pinMode(IR_PIN, INPUT_PULLUP);

  commandBuffer.reserve(MAX_COMMAND_LENGTH);

  // Inisialisasi keypad matrix 4x4.
  keypadInit();

  Serial.println(F("READY"));
  Serial.println(F("SHIFT_OUT: 7×74HC595 → relay ×50 initialized"));
  Serial.println(F("IR_DROP: IR receiver array (≈10 unit, paralel) → 1 pin; motor stop saat beam terblokir"));
  Serial.println(F("KEYPAD: 4x4 matrix ready (physical + serial input)"));
  Serial.println(F("TEST_COMMANDS: DETECT, 0-9, ACCEPT, CANCEL, DECLINED, IR_STATUS, ALL_OFF"));
}

void loop() {
  // ── 1. Baca serial commands dari frontend ──
  while (Serial.available() > 0) {
    const char incoming = static_cast<char>(Serial.read());

    if (incoming == '\r') continue;

    if (incoming == '\n') {
      processCommand(commandBuffer);
      commandBuffer = "";
      continue;
    }

    if (commandBuffer.length() >= MAX_COMMAND_LENGTH) {
      commandBuffer = "";
      Serial.println(F("ERROR_COMMAND_TOO_LONG"));
      continue;
    }

    commandBuffer += incoming;
  }

  const unsigned long now = millis();
  // ── 3. Polling keypad matrix ──
  if (now - lastKeypadPoll >= KEYPAD_POLL_INTERVAL_MS) {
    lastKeypadPoll = now;
    char key;
    KeypadEvent event = keypadPoll(key);

    if (event == KEYPAD_PRESSED || event == KEYPAD_HELD) {
      if (keypadIsDigit(key)) {
        emitKeypadDigit(key);
      } else if (keypadIsAccept(key)) {
        emitKeypadAccept();
      } else if (keypadIsCancel(key)) {
        emitKeypadCancel();
      }
      // spare keys (B, C) diabaikan untuk saat ini
    }
  }

  // Jeda kecil supaya polling keypad berjalan sesuai interval ~10 ms.
  delay(5);
}
