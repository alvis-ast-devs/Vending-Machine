#ifndef SHIFT_OUTPUT_H
#define SHIFT_OUTPUT_H
// =============================================================================
// shift_output.h — 74HC595 Shift Register OUTPUT Driver
// =============================================================================
// Rangkaian 74HC595 mengontrol relay → motor pengdrop produk.
// 7 chip × 8 bit = 56 output (50 digunakan untuk slot 01-45, 51-55).
//
// Wiring ESP32 → 74HC595 chain:
//   GPIO 25 → SER   (pin 14)  chip pertama
//   GPIO 26 → SRCLK (pin 11)  semua chip (paralel)
//   GPIO 27 → RCLK  (pin 12)  semua chip (paralel)
//   SRCLR (pin 10) → HIGH (tidak reset)
//   OE    (pin 13) → LOW  (output selalu aktif)
//   Q7'   (pin 9)  chip ke-N → SER chip ke-N+1 (daisy-chain)
// =============================================================================

#include <Arduino.h>

// ─── Pin Konfigurasi (bisa di-override via -D sebelum compile) ───────────────
#ifndef SR_OUT_DATA_PIN
#define SR_OUT_DATA_PIN  25
#endif
#ifndef SR_OUT_CLOCK_PIN
#define SR_OUT_CLOCK_PIN 26
#endif
#ifndef SR_OUT_LATCH_PIN
#define SR_OUT_LATCH_PIN 27
#endif

// ─── Jumlah Chip ─────────────────────────────────────────────────────────────
#define SR_OUT_CHAIN_LENGTH  7          // 7 chip × 8 = 56 bit
#define SR_OUT_TOTAL_BITS    (SR_OUT_CHAIN_LENGTH * 8)

// ─── Class ───────────────────────────────────────────────────────────────────
class ShiftOutput {
public:
  void begin() {
    pinMode(SR_OUT_DATA_PIN,  OUTPUT);
    pinMode(SR_OUT_CLOCK_PIN, OUTPUT);
    pinMode(SR_OUT_LATCH_PIN, OUTPUT);

    digitalWrite(SR_OUT_DATA_PIN,  LOW);
    digitalWrite(SR_OUT_CLOCK_PIN, LOW);
    digitalWrite(SR_OUT_LATCH_PIN, LOW);

    // Matikan semua relay saat startup.
    memset(_buffer, 0, sizeof(_buffer));
    flush();
  }

  // ─── Slot-to-Bit Mapping ─────────────────────────────────────────────────
  // Slot valid: 01-45 → bit 0-44,  51-55 → bit 45-49
  // Return -1 jika slot tidak valid.
  static int8_t slotToBit(const String &slotCode) {
    if (slotCode.length() != 2) return -1;
    const int n = slotCode.toInt();
    if (n >= 1 && n <= 45)  return (int8_t)(n - 1);
    if (n >= 51 && n <= 55) return (int8_t)((n - 51) + 45);
    return -1;
  }

  // ─── Aktifkan / Matikan Satu Bit ─────────────────────────────────────────
  void setActive(uint8_t bitIndex, bool on) {
    if (bitIndex >= SR_OUT_TOTAL_BITS) return;
    const uint8_t byteIdx = bitIndex / 8;
    const uint8_t bitPos  = 7 - (bitIndex % 8);  // MSB-first
    if (on)
      _buffer[byteIdx] |=  (1 << bitPos);
    else
      _buffer[byteIdx] &= ~(1 << bitPos);
  }

  // ─── Aktifkan / Matikan Berdasarkan Kode Slot ────────────────────────────
  void setSlotActive(const String &slotCode, bool on) {
    const int8_t bit = slotToBit(slotCode);
    if (bit >= 0) setActive((uint8_t)bit, on);
  }

  // ─── Push Buffer ke Hardware ──────────────────────────────────────────────
  void flush() {
    digitalWrite(SR_OUT_LATCH_PIN, LOW);
    for (int8_t i = SR_OUT_CHAIN_LENGTH - 1; i >= 0; i--) {
      shiftOut(SR_OUT_DATA_PIN, SR_OUT_CLOCK_PIN, MSBFIRST, _buffer[i]);
    }
    digitalWrite(SR_OUT_LATCH_PIN, HIGH);
    delayMicroseconds(5);
    digitalWrite(SR_OUT_LATCH_PIN, LOW);
  }

  // ─── Matikan Semua ────────────────────────────────────────────────────────
  void allOff() {
    memset(_buffer, 0, sizeof(_buffer));
    flush();
  }

  // ─── Toggle (untuk testing) ──────────────────────────────────────────────
  void toggle(uint8_t bitIndex) {
    if (bitIndex >= SR_OUT_TOTAL_BITS) return;
    const uint8_t byteIdx = bitIndex / 8;
    const uint8_t bitPos  = 7 - (bitIndex % 8);
    _buffer[byteIdx] ^= (1 << bitPos);
    flush();
  }

  const uint8_t* buffer() const { return _buffer; }

private:
  uint8_t _buffer[SR_OUT_CHAIN_LENGTH];
};

ShiftOutput shiftOutput;

#endif // SHIFT_OUTPUT_H
