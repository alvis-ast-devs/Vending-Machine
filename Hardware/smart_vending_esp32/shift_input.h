#ifndef SHIFT_INPUT_H
#define SHIFT_INPUT_H
// =============================================================================
// shift_input.h — 74HC165 Shift Register INPUT Driver
// =============================================================================
// Rangkaian 74HC165 membaca input sensor / tombol keypad dari 50 slot.
// 7 chip × 8 bit = 56 input (50 digunakan untuk slot 01-45, 51-55).
//
// Wiring ESP32 → 74HC165 chain:
//   GPIO 32 → DATA  (Q7 / pin 9)  chip terakhir
//   GPIO 33 → CLOCK (CLK / pin 2)  semua chip (paralel)
//   GPIO 14 → LOAD  (SH/LD / pin 1) semua chip (paralel)
//   SER (pin 10) → Q7' chip sebelumnya (daisy-chain)
//   CE  (pin 15) → LOW (chip enable, selalu aktif)
//
// Cara kerja:
//   1. Pulsa LOAD LOW → parallel load semua input ke internal latch
//   2. Clock sebanyak total bit, baca DATA di setiap falling edge
// =============================================================================

#include <Arduino.h>

// ─── Pin Konfigurasi (bisa di-override via -D sebelum compile) ───────────────
#ifndef SR_IN_DATA_PIN
#define SR_IN_DATA_PIN  32    // Q7 output dari chip terakhir
#endif
#ifndef SR_IN_CLOCK_PIN
#define SR_IN_CLOCK_PIN 33   // CLK — clock untuk shift data keluar
#endif
#ifndef SR_IN_LOAD_PIN
#define SR_IN_LOAD_PIN  14   // SH/LD — LOW = parallel load, HIGH = shift mode
#endif

// ─── Jumlah Chip ─────────────────────────────────────────────────────────────
#define SR_IN_CHAIN_LENGTH  7          // 7 chip × 8 = 56 bit
#define SR_IN_TOTAL_BITS    (SR_IN_CHAIN_LENGTH * 8)

// ─── Debounce ────────────────────────────────────────────────────────────────
#define SR_IN_DEBOUNCE_MS   50         // debounce window (ms)

// ─── Class ───────────────────────────────────────────────────────────────────
class ShiftInput {
public:
  void begin() {
    pinMode(SR_IN_DATA_PIN,  INPUT);
    pinMode(SR_IN_CLOCK_PIN, OUTPUT);
    pinMode(SR_IN_LOAD_PIN,  OUTPUT);

    digitalWrite(SR_IN_CLOCK_PIN, LOW);
    digitalWrite(SR_IN_LOAD_PIN,  HIGH);  // mode shift (default)

    memset(_current,  0, sizeof(_current));
    memset(_previous, 0, sizeof(_previous));
    memset(_lastChange, 0, sizeof(_lastChange));
    _changed = false;
  }

  // ─── Baca Semua Input Sekaligus ──────────────────────────────────────────
  void readAll() {
    // Simpan state sebelumnya untuk deteksi edge.
    memcpy(_previous, _current, sizeof(_current));

    // 1. Parallel load: LOW pada SH/LD.
    digitalWrite(SR_IN_LOAD_PIN, LOW);
    delayMicroseconds(5);
    digitalWrite(SR_IN_LOAD_PIN, HIGH);

    // 2. Shift out bit dari chip terakhir ke pertama (MSB = chip terakhir).
    memset(_current, 0, sizeof(_current));

    for (int8_t chip = SR_IN_CHAIN_LENGTH - 1; chip >= 0; chip--) {
      uint8_t reg = 0;
      for (uint8_t bit = 0; bit < 8; bit++) {
        // Falling edge clock.
        digitalWrite(SR_IN_CLOCK_PIN, HIGH);
        delayMicroseconds(2);
        digitalWrite(SR_IN_CLOCK_PIN, LOW);
        delayMicroseconds(2);

        if (digitalRead(SR_IN_DATA_PIN)) {
          reg |= (1 << (7 - bit));  // MSB-first
        }
      }
      _current[chip] = reg;
    }

    // 3. Deteksi perubahan dengan debounce.
    _changed = false;
    const unsigned long now = millis();
    for (uint16_t i = 0; i < SR_IN_TOTAL_BITS; i++) {
      const bool cur  = readBitRaw(i);
      const bool prev = readBitPrev(i);
      if (cur != prev) {
        if ((now - _lastChange[i]) >= SR_IN_DEBOUNCE_MS) {
          _lastChange[i] = now;
          _changed = true;
        }
      }
    }
  }

  // ─── Baca Satu Bit (menggunakan data terakhir yang di-cache) ──────────────
  bool readBit(uint8_t bitIndex) const {
    if (bitIndex >= SR_IN_TOTAL_BITS) return false;
    return readBitRaw(bitIndex);
  }

  // ─── Cek Apakah Ada Perubahan (debounced) ─────────────────────────────────
  bool hasChanged() const { return _changed; }

  // ─── Cek Rising Edge (newly pressed) ─────────────────────────────────────
  bool rose(uint8_t bitIndex) const {
    if (bitIndex >= SR_IN_TOTAL_BITS) return false;
    return readBitRaw(bitIndex) && !readBitPrev(bitIndex);
  }

  // ─── Cek Falling Edge (newly released) ────────────────────────────────────
  bool fell(uint8_t bitIndex) const {
    if (bitIndex >= SR_IN_TOTAL_BITS) return false;
    return !readBitRaw(bitIndex) && readBitPrev(bitIndex);
  }

  // ─── Slot-to-Bit Mapping (sama dengan ShiftOutput) ───────────────────────
  static int8_t slotToBit(const String &slotCode) {
    if (slotCode.length() != 2) return -1;
    const int n = slotCode.toInt();
    if (n >= 1 && n <= 45)  return (int8_t)(n - 1);
    if (n >= 51 && n <= 55) return (int8_t)((n - 51) + 45);
    return -1;
  }

  bool readSlot(const String &slotCode) const {
    const int8_t bit = slotToBit(slotCode);
    return (bit >= 0) ? readBitRaw((uint8_t)bit) : false;
  }

  bool slotRose(const String &slotCode) const {
    const int8_t bit = slotToBit(slotCode);
    return (bit >= 0) ? rose((uint8_t)bit) : false;
  }

  bool slotFell(const String &slotCode) const {
    const int8_t bit = slotToBit(slotCode);
    return (bit >= 0) ? fell((uint8_t)bit) : false;
  }

  // ─── Debug: cetak status semua input ke Serial ────────────────────────────
  void printStatus() const {
    Serial.print(F("SR_IN: "));
    for (int8_t i = SR_IN_CHAIN_LENGTH - 1; i >= 0; i--) {
      if (_current[i] < 0x10) Serial.print('0');
      Serial.print(_current[i], HEX);
      Serial.print(' ');
    }
    Serial.println();
  }

private:
  bool readBitRaw(uint8_t bitIndex) const {
    const uint8_t byteIdx = bitIndex / 8;
    const uint8_t bitPos  = 7 - (bitIndex % 8);
    return (_current[byteIdx] >> bitPos) & 1;
  }

  bool readBitPrev(uint8_t bitIndex) const {
    const uint8_t byteIdx = bitIndex / 8;
    const uint8_t bitPos  = 7 - (bitIndex % 8);
    return (_previous[byteIdx] >> bitPos) & 1;
  }

  uint8_t _current[SR_IN_CHAIN_LENGTH];
  uint8_t _previous[SR_IN_CHAIN_LENGTH];
  unsigned long _lastChange[SR_IN_TOTAL_BITS];
  bool _changed;
};

// Singleton global
ShiftInput shiftInput;

#endif // SHIFT_INPUT_H
