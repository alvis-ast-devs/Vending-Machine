// =============================================================================
// Keypad Matrix 4x4 — ESP32 DevKit / ESP32-D
// =============================================================================
// Scanning manual tanpa library eksternal.
//
// ROWS  = OUTPUT
// COLS  = INPUT_PULLDOWN
//
// Semua column menggunakan GPIO yang mendukung internal pull-down.
// Jadi TIDAK membutuhkan resistor 10k eksternal.
//
// Wiring:
//
//   Row 1 (OUTPUT) -> GPIO 2
//   Row 2 (OUTPUT) -> GPIO 4
//   Row 3 (OUTPUT) -> GPIO 5
//   Row 4 (OUTPUT) -> GPIO 16
//
//   Col 1 (INPUT_PULLDOWN) -> GPIO 17
//   Col 2 (INPUT_PULLDOWN) -> GPIO 18
//   Col 3 (INPUT_PULLDOWN) -> GPIO 32
//   Col 4 (INPUT_PULLDOWN) -> GPIO 33
//
// Layout:
//
//             C1    C2    C3    C4
//   R1       [ 1 ] [ 2 ] [ 3 ] [ A ]
//   R2       [ 4 ] [ 5 ] [ 6 ] [ B ]
//   R3       [ 7 ] [ 8 ] [ 9 ] [ C ]
//   R4       [ * ] [ 0 ] [ # ] [ D ]
//
// Contoh:
//   R4 + C3 = GPIO16 + GPIO32 = '#'
// =============================================================================
// CATATAN: GPIO 25 & 26 TIDAK dipakai sebagai kolom karena merupakan pin
// DATA/CLOCK shift register output (74HC595) untuk relay motor. Kolom keypad
// memakai GPIO 17/18/32/33 yang bebas & mendukung INPUT_PULLDOWN.

#ifndef KEYPAD_H
#define KEYPAD_H

#include <Arduino.h>


// =============================================================================
// PIN DEFINITIONS
// =============================================================================

// -----------------------------------------------------------------------------
// ROWS
// -----------------------------------------------------------------------------
// Row akan di-scan HIGH satu per satu.

static const uint8_t KEYPAD_ROW_PINS[4] = {
  2,    // R1
  4,    // R2
  5,    // R3
  16    // R4
};


// -----------------------------------------------------------------------------
// COLUMNS
// -----------------------------------------------------------------------------
// Semua pin column menggunakan internal pull-down.
//
// C1 = GPIO17
// C2 = GPIO18
// C3 = GPIO32
// C4 = GPIO33
//
// Keempat GPIO ini mendukung INPUT_PULLDOWN dan tidak bentrok dengan pin lain
// (shift output 74HC595 = GPIO 25/26/27, IR receiver = GPIO 14).

static const uint8_t KEYPAD_COL_PINS[4] = {
  17,   // C1
  18,   // C2
  32,   // C3
  33    // C4
};


// =============================================================================
// KEY MAP
// =============================================================================

static const char KEYPAD_MAP[4][4] = {

  // C1    C2    C3    C4
  { '1',  '2',  '3',  'A' },   // R1
  { '4',  '5',  '6',  'B' },   // R2
  { '7',  '8',  '9',  'C' },   // R3
  { '*',  '0',  '#',  'D' }    // R4
};


// =============================================================================
// SCANNING CONFIGURATION
// =============================================================================

static const unsigned long KEYPAD_DEBOUNCE_MS = 50;

// Jika tombol ditahan, event HELD akan dikirim setiap 200 ms.
static const unsigned long KEYPAD_REPEAT_MS = 200;


// =============================================================================
// STATE
// =============================================================================

struct KeypadState {

  char lastKey;

  bool keyDown;

  unsigned long lastChangeTime;

  unsigned long lastRepeatTime;
};


// Initial state
static KeypadState _kpState = {
  '\0',
  false,
  0,
  0
};


// =============================================================================
// INTERNAL: SCAN KEYPAD
// =============================================================================
//
// Fungsi ini melakukan:
//
// 1. Semua ROW dibuat LOW
// 2. R1 dibuat HIGH
// 3. Semua COLUMN dibaca
// 4. R1 kembali LOW
// 5. R2 dibuat HIGH
// 6. Semua COLUMN dibaca
// 7. dst.
//
// Karena COLUMN menggunakan INPUT_PULLDOWN:
//
// Tidak ada tombol:
//     COLUMN = LOW
//
// Ada tombol:
//     ROW HIGH → COLUMN HIGH
//
// =============================================================================

static char _keypadScan() {

  // ---------------------------------------------------------------------------
  // Pastikan semua ROW LOW terlebih dahulu
  // ---------------------------------------------------------------------------

  for (uint8_t r = 0; r < 4; r++) {

    digitalWrite(
      KEYPAD_ROW_PINS[r],
      LOW
    );
  }


  // ---------------------------------------------------------------------------
  // Scan setiap ROW
  // ---------------------------------------------------------------------------

  for (uint8_t r = 0; r < 4; r++) {

    // Aktifkan ROW
    digitalWrite(
      KEYPAD_ROW_PINS[r],
      HIGH
    );


    // Tunggu sebentar agar signal stabil
    delayMicroseconds(10);


    // -------------------------------------------------------------------------
    // Baca semua COLUMN
    // -------------------------------------------------------------------------

    for (uint8_t c = 0; c < 4; c++) {

      if (
        digitalRead(KEYPAD_COL_PINS[c]) == HIGH
      ) {

        // Matikan row sebelum return
        digitalWrite(
          KEYPAD_ROW_PINS[r],
          LOW
        );


        // Return tombol berdasarkan posisi row + column
        return KEYPAD_MAP[r][c];
      }
    }


    // Matikan ROW sebelum pindah ke ROW berikutnya
    digitalWrite(
      KEYPAD_ROW_PINS[r],
      LOW
    );
  }


  // Tidak ada tombol
  return '\0';
}


// =============================================================================
// PUBLIC API
// =============================================================================


// -----------------------------------------------------------------------------
// keypadInit()
// -----------------------------------------------------------------------------
// Panggil sekali di setup().
//
// Contoh:
//
// void setup() {
//   Serial.begin(115200);
//   keypadInit();
// }
//
// -----------------------------------------------------------------------------

static void keypadInit() {

  // ---------------------------------------------------------------------------
  // Initialize ROWS
  // ---------------------------------------------------------------------------

  for (uint8_t r = 0; r < 4; r++) {

    pinMode(
      KEYPAD_ROW_PINS[r],
      OUTPUT
    );

    // Pastikan semua ROW awalnya LOW
    digitalWrite(
      KEYPAD_ROW_PINS[r],
      LOW
    );
  }


  // ---------------------------------------------------------------------------
  // Initialize COLUMNS
  // ---------------------------------------------------------------------------
  //
  // INI BAGIAN PENTING.
  //
  // Sebelumnya:
  //
  //     pinMode(..., INPUT);
  //
  // Sekarang:
  //
  //     pinMode(..., INPUT_PULLDOWN);
  //
  // Jadi ketika tidak ada tombol:
  //
  //     COLUMN = LOW
  //
  // dan tidak akan floating.

  for (uint8_t c = 0; c < 4; c++) {

    pinMode(
      KEYPAD_COL_PINS[c],
      INPUT_PULLDOWN
    );
  }


  // ---------------------------------------------------------------------------
  // Reset keypad state
  // ---------------------------------------------------------------------------

  _kpState.lastKey = '\0';

  _kpState.keyDown = false;

  _kpState.lastChangeTime = 0;

  _kpState.lastRepeatTime = 0;


  // ---------------------------------------------------------------------------
  // Debug information
  // ---------------------------------------------------------------------------

  Serial.println(
    F(
      "KEYPAD: 4x4 matrix initialized"
    )
  );

  Serial.println(
    F(
      "ROWS: R1=GPIO2 R2=GPIO4 R3=GPIO5 R4=GPIO16"
    )
  );

  Serial.println(
    F(
      "COLS: C1=GPIO17 C2=GPIO18 C3=GPIO32 C4=GPIO33"
    )
  );

  Serial.println(
    F(
      "COL INPUT MODE: INPUT_PULLDOWN"
    )
  );
}


// =============================================================================
// KEYPAD EVENT TYPE
// =============================================================================

enum KeypadEvent : uint8_t {

  // Tidak ada perubahan
  KEYPAD_NONE,

  // Tombol baru ditekan
  KEYPAD_PRESSED,

  // Tombol masih ditahan
  KEYPAD_HELD,

  // Tombol dilepas
  KEYPAD_RELEASED
};


// =============================================================================
// keypadPoll()
// =============================================================================
//
// Panggil fungsi ini di loop().
//
// Contoh:
//
// char key;
//
// KeypadEvent event = keypadPoll(key);
//
// if (event == KEYPAD_PRESSED) {
//   Serial.print("Pressed: ");
//   Serial.println(key);
// }
//
// =============================================================================

static KeypadEvent keypadPoll(char &keyOut) {

  const unsigned long now = millis();

  // Scan keypad
  const char key = _keypadScan();


  // Default output
  keyOut = '\0';


  // ===========================================================================
  // ADA TOMBOL
  // ===========================================================================

  if (key != '\0') {

    // -------------------------------------------------------------------------
    // Tombol baru ditekan
    // -------------------------------------------------------------------------

    if (!_kpState.keyDown) {

      // Tunggu debounce
      if (
        now - _kpState.lastChangeTime >=
        KEYPAD_DEBOUNCE_MS
      ) {

        _kpState.keyDown = true;

        _kpState.lastKey = key;

        _kpState.lastChangeTime = now;

        _kpState.lastRepeatTime = now;

        keyOut = key;

        return KEYPAD_PRESSED;
      }
    }


    // -------------------------------------------------------------------------
    // Tombol yang sama masih ditekan
    // -------------------------------------------------------------------------

    else if (
      key == _kpState.lastKey
    ) {

      // Auto-repeat
      if (
        now - _kpState.lastRepeatTime >=
        KEYPAD_REPEAT_MS
      ) {

        _kpState.lastRepeatTime = now;

        keyOut = key;

        return KEYPAD_HELD;
      }
    }


    // -------------------------------------------------------------------------
    // Tombol berbeda ditekan
    // -------------------------------------------------------------------------

    else {

      _kpState.lastKey = key;

      _kpState.lastChangeTime = now;

      _kpState.lastRepeatTime = now;

      _kpState.keyDown = true;

      keyOut = key;

      return KEYPAD_PRESSED;
    }
  }


  // ===========================================================================
  // TIDAK ADA TOMBOL
  // ===========================================================================

  else {

    // Jika sebelumnya ada tombol yang ditekan
    if (_kpState.keyDown) {

      _kpState.keyDown = false;

      keyOut = _kpState.lastKey;

      _kpState.lastChangeTime = now;

      return KEYPAD_RELEASED;
    }
  }


  // Tidak ada event
  return KEYPAD_NONE;
}


// =============================================================================
// HELPER FUNCTIONS
// =============================================================================


// -----------------------------------------------------------------------------
// Return true jika key adalah digit 0-9
// -----------------------------------------------------------------------------

static inline bool keypadIsDigit(char key) {

  return (
    key >= '0' &&
    key <= '9'
  );
}


// -----------------------------------------------------------------------------
// Return true jika key adalah ACCEPT
// A atau #
// -----------------------------------------------------------------------------

static inline bool keypadIsAccept(char key) {

  return (
    key == 'A' ||
    key == '#'
  );
}


// -----------------------------------------------------------------------------
// Return true jika key adalah CANCEL
// D atau *
// -----------------------------------------------------------------------------

static inline bool keypadIsCancel(char key) {

  return (
    key == 'D' ||
    key == '*'
  );
}


// -----------------------------------------------------------------------------
// Return true jika key adalah spare
// B atau C
// -----------------------------------------------------------------------------

static inline bool keypadIsSpare(char key) {

  return (
    key == 'B' ||
    key == 'C'
  );
}


#endif // KEYPAD_H