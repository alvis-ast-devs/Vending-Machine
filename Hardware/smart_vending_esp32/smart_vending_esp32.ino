// =============================================================================
// Smart Vending Machine — ESP32 Firmware
// =============================================================================
// 50 Output: 74HC595 × 7 → Relay × 50 → Motor pengdrop produk
// 50 Input:  74HC165 × 7 → Sensor per-slot (deteksi produk)
// Serial:    Komunikasi dengan Flutter Frontend via UART 115200
//
// Mapping Slot → Bit:
//   Slot 01-45 → bit 0-44
//   Slot 51-55 → bit 45-49
//
// Perintah Serial dari Frontend:
//   DROP_SLOT_XX  → jalankan motor slot XX (dengan limit switch detection)
//   RESET_SLOT_XX → putar motor sebentar untuk melepaskan dari limit switch
//   DETECT        → simulasi user terdeteksi
//   KEY_X / X     → input digit keypad (0-9)
//   ACCEPT        → konfirmasi
//   CANCEL        → batal
//
// Event Serial ke Frontend:
//   READY, BUSY_XX, SUCCESS_XX, WARNING_NO_LIMIT_XX, ERROR_*
//   EVENT_USER_DETECTED, EVENT_KEY_X, EVENT_ACCEPT, EVENT_CANCEL
//   EVENT_SLOT_XX_EMPTY, EVENT_SLOT_XX_PRESENT (dari shift input)
//   RESET_OK_XX (hasil RESET_SLOT_XX)
// =============================================================================

#include "shift_output.h"
#include "shift_input.h"

// ─── Konfigurasi ─────────────────────────────────────────────────────────────
const uint32_t SERIAL_BAUD_RATE = 115200;
const unsigned long MOTOR_RUN_TIME_MS = 1500;
const size_t MAX_COMMAND_LENGTH = 40;

// Interval baca shift register input (ms).
const unsigned long INPUT_READ_INTERVAL_MS = 100;
// Timeout untuk menunggu sensor LOW setelah motor mulai berputar (ms).
// Motor di posisi 180° (switch tertekan/HIGH) saat idle, perlu waktu
// untuk menjauh dari switch sebelum bisa mendeteksi drop berikutnya.
const unsigned long SENSOR_LOW_TIMEOUT_MS = 800;

// ─── State ───────────────────────────────────────────────────────────────────
String commandBuffer;
unsigned long lastInputRead = 0;

// =============================================================================
//  RELAY / MOTOR CONTROL (menggunakan shift register output)
// =============================================================================

/// Aktifkan relay untuk satu slot dengan limit switch detection.
/// Menggunakan dua-fase deteksi:
///   Fase 1: Tunggu sensor LOW (motor menjauh dari switch, max SENSOR_LOW_TIMEOUT_MS)
///   Fase 2: Tunggu sensor HIGH lagi (motor sampai 180 derajat, drop berhasil)
/// Jika timeout di fase 2, motor tetap berhenti (safety fallback).
void runMotorForSlot(const String &slotCode) {
  Serial.print(F("BUSY_"));
  Serial.println(slotCode);

  // Mulai motor
  shiftOutput.setSlotActive(slotCode, true);
  shiftOutput.flush();

  const unsigned long startTime = millis();
  bool dropConfirmed = false;

  // -- FASE 1: Tunggu sensor LOW (motor menjauh dari switch) --
  // Sensor awalnya HIGH (posisi 180 derajat sebelumnya). Tunggu LOW.
  while (millis() - startTime < SENSOR_LOW_TIMEOUT_MS) {
    shiftInput.readAll();
    const int8_t bit = shiftInput.slotToBit(slotCode);
    if (bit >= 0 && !shiftInput.readBit((uint8_t)bit)) {
      break;  // Sensor LOW -> motor sudah mulai berputar
    }
    delay(5);
  }

  // -- FASE 2: Tunggu sensor HIGH lagi (motor sampai 180 derajat) --
  // Motor sudah berputar, sekarang tunggu switch tertekan lagi.
  while (millis() - startTime < MOTOR_RUN_TIME_MS) {
    shiftInput.readAll();
    const int8_t bit = shiftInput.slotToBit(slotCode);
    if (bit >= 0 && shiftInput.readBit((uint8_t)bit)) {
      dropConfirmed = true;  // Sensor HIGH -> 180 derajat tercapai
      break;
    }
    delay(5);
  }

  // Matikan motor
  shiftOutput.setSlotActive(slotCode, false);
  shiftOutput.flush();

  if (dropConfirmed) {
    Serial.print(F("SUCCESS_"));
  } else {
    Serial.print(F("WARNING_NO_LIMIT_"));
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

/// Emit event ketika sensor slot mendeteksi perubahan.
void emitSlotSensorEvent(uint8_t bitIndex, bool present) {
  // Konversi bit index ke kode slot untuk kompatibilitas frontend.
  String slotCode;
  if (bitIndex < 45) {
    slotCode = String(bitIndex + 1);
    if (slotCode.length() == 1) slotCode = "0" + slotCode;
  } else if (bitIndex >= 45 && bitIndex < 50) {
    slotCode = String((bitIndex - 45) + 51);
  } else {
    return;  // bit 50-55 tidak digunakan
  }

  Serial.print(F("EVENT_SLOT_"));
  Serial.print(slotCode);
  Serial.println(present ? F("_PRESENT") : F("_EMPTY"));
}

// =============================================================================
//  SHIFT REGISTER INPUT — polling & edge detection
// =============================================================================

void pollShiftInput() {
  shiftInput.readAll();

  if (!shiftInput.hasChanged()) return;

  // Deteksi rising/falling edge pada setiap slot dan emit event.
  for (uint8_t i = 0; i < SR_IN_TOTAL_BITS; i++) {
    if (shiftInput.rose(i)) {
      emitSlotSensorEvent(i, true);
    } else if (shiftInput.fell(i)) {
      emitSlotSensorEvent(i, false);
    }
  }
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

  // DEBUG: cetak status shift register input
  if (command == "DEBUG_INPUT" || command == "STATUS") {
    shiftInput.printStatus();
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

  // RESET_SLOT_XX: putar motor sebentar untuk melepaskan dari limit switch
  const String resetPrefix = "RESET_SLOT_";
  if (command.startsWith(resetPrefix)) {
    const String slotCode = command.substring(resetPrefix.length());
    if (!isValidSlotCode(slotCode)) {
      Serial.print(F("ERROR_INVALID_SLOT_"));
      Serial.println(slotCode);
      return;
    }
    // Putar motor sebentar untuk menjauh dari switch
    shiftOutput.setSlotActive(slotCode, true);
    shiftOutput.flush();
    delay(300);
    shiftOutput.setSlotActive(slotCode, false);
    shiftOutput.flush();
    Serial.print(F("RESET_OK_"));
    Serial.println(slotCode);
    return;
  }

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

  // Inisialisasi shift register input (sensor).
  shiftInput.begin();

  commandBuffer.reserve(MAX_COMMAND_LENGTH);

  Serial.println(F("READY"));
  Serial.println(F("SHIFT_REG: 7×74HC595 OUT + 7×74HC165 IN initialized"));
  Serial.println(F("TEST_COMMANDS: DETECT, 0-9, ACCEPT, CANCEL, DECLINED, DEBUG_INPUT, ALL_OFF"));
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

  // ── 2. Polling shift register input (sensor) ──
  const unsigned long now = millis();
  if (now - lastInputRead >= INPUT_READ_INTERVAL_MS) {
    lastInputRead = now;
    pollShiftInput();
  }
}
