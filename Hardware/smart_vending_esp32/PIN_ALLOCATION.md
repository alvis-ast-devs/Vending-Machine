# Dokumentasi Alokasi Pin ESP32 - Smart Vending Machine

## Ringkasan Komponen

| No | Komponen | Jumlah | Keterangan |
|----|----------|--------|------------|
| 1 | 74HC595 (Shift Register Output) | 7 chip | 56 output -> 50 relay -> 50 motor |
| 2 | IR Receiver (Sensor Infrared) | ~10 unit | Deteksi barang jatuh; semua OUT diparalel ke 1 GPIO |
| 3 | Ultrasonic HC-SR04 (Sensor Jarak) | 2 unit | Deteksi kehadiran orang di depan mesin |
| 4 | Keypad Matrix 4x4 | 1 unit | Input angka oleh user (0-9, A-D) |
| 5 | Serial UART | 1 channel | Komunikasi dengan PC/Frontend |

> **Catatan:** Shift Register Input (74HC165) **TIDAK dipakai lagi**. Penghentian
> dinamo dilakukan oleh **IR receiver array**: motor berputar sampai produk jatuh
> memotong beam salah satu IR receiver, lalu motor langsung dimatikan. Semua OUT
> receiver digabung (paralel) ke satu jalur yang masuk ke 1 GPIO ESP32, sehingga
> jika SATU saja receiver terpicu, motor langsung berhenti (tahan terhadap
> kegagalan satu-dua sensor).

---

## 1. Shift Register Output (74HC595) - 3 Pin

Mengontrol 50 relay untuk menjalankan motor pengdrop produk.

| GPIO | Nama Pin | Arah | Komponen | Keterangan |
|------|----------|------|----------|------------|
| **25** | SR_OUT_DATA | OUTPUT | 74HC595 pin 14 (SER) chip pertama | Data serial masuk |
| **26** | SR_OUT_CLOCK | OUTPUT | 74HC595 pin 11 (SRCLK) semua chip | Clock shift |
| **27** | SR_OUT_LATCH | OUTPUT | 74HC595 pin 12 (RCLK) semua chip | Latch output |

**Wiring 74HC595 Daisy Chain:**
```
ESP32 GPIO 25 --> SER (pin 14) Chip #1
                   Q7' (pin 9) Chip #1 --> SER (pin 14) Chip #2
                                            Q7' (pin 9) Chip #2 --> SER (pin 14) Chip #3
                                                                     ... dst hingga Chip #7

ESP32 GPIO 26 --> SRCLK (pin 11) semua chip (paralel)
ESP32 GPIO 27 --> RCLK  (pin 12) semua chip (paralel)

SRCLR (pin 10) --> HIGH (tidak reset)
OE    (pin 13) --> LOW  (output selalu aktif)
VCC   (pin 16) --> 5V
GND   (pin 8)  --> GND
```

**Mapping Slot -> Bit:**
| Slot | Bit Index | Chip | Bit di Chip |
|------|-----------|------|-------------|
| 01 | 0 | Chip #1 | bit 7 (MSB) |
| 02 | 1 | Chip #1 | bit 6 |
| ... | ... | ... | ... |
| 08 | 7 | Chip #1 | bit 0 (LSB) |
| 09 | 8 | Chip #2 | bit 7 |
| ... | ... | ... | ... |
| 45 | 44 | Chip #6 | bit 2 |
| 51 | 45 | Chip #6 | bit 1 |
| 52 | 46 | Chip #6 | bit 0 |
| 53 | 47 | Chip #7 | bit 7 |
| 54 | 48 | Chip #7 | bit 6 |
| 55 | 49 | Chip #7 | bit 5 |

---

## 2. IR Receiver Array (Drop Detection) - 1 Pin

**Fungsi:** Mendeteksi produk yang benar-benar jatuh dari slot, lalu menghentikan
dinamo yang sedang berputar.

**Arsitektur (OR paralel):**
```
IR Rx #1 OUT ──┐
IR Rx #2 OUT ──┤
IR Rx #3 OUT ──┼──(satu jalur bersama)──► GPIO 14 (ESP32, INPUT_PULLUP)
   ...         │
IR Rx #N OUT ──┘

Semua VCC  --> 3.3V atau 5V (tergantung modul)
Semua GND  --> GND bersama
Transmitter IR (terpisah):
  IR LED VCC --> 5V (power supply langsung)
  IR LED GND --> GND (power supply langsung)
  (TIDAK terhubung ke ESP32)
```

**Penting (kelistrikan paralel):**
- Output modul IR harus **open-collector/open-drain** sehingga bisa di-OR
  langsung ke satu jalur.
- Jika modul memakai output push-pull, pasang **1 dioda OR (mis. 1N4148) dari
  tiap OUT** ke jalur bersama + resistor pull-up (mis. 10k) ke 3.3V, supaya
  modul tidak saling dorong.
- Firmware hanya membaca **1 pin (GPIO 14)**, berapa pun jumlah receiver-nya.
- Karena hanya satu motor yang berjalan dalam satu waktu, setiap produk yang
  jatuh dari slot mana pun akan memicu jalur bersama.

**Cara Kerja:**
```
1. Frontend kirim DROP_SLOT_XX
2. ESP32 nyalakan relay motor slot XX (via 74HC595)
3. Motor berputar mendorong produk
4. Produk jatuh dan memotong beam salah satu IR receiver
5. Jalur bersama berubah ke IR_ACTIVE_LEVEL (beam terblokir)
6. ESP32 langsung matikan motor -> kirim SUCCESS_XX
7. Jika tidak ada IR yang terpicu sampai MOTOR_RUN_TIME_MS (default 2000 ms),
   motor tetap dimatikan -> kirim WARNING_NO_DROP_XX (safety timeout)
```

**Level Logika (kalibrasi `IR_ACTIVE_LEVEL` di firmware):**
| Kondisi beam | Modul tipe A (umum) | Modul tipe B |
|--------------|---------------------|--------------|
| Beam terang (tidak ada barang) | OUT = LOW | OUT = HIGH |
| Beam terblokir (barang jatuh) | OUT = HIGH | OUT = LOW |

Default firmware = `IR_ACTIVE_LEVEL HIGH`. Jika modul Anda tipe B (aktif-LOW),
ubah konstanta tersebut menjadi `LOW`. Untuk memastikannya, kirim perintah serial
`IR_STATUS` lalu blokir beam secara manual — baca level yang tercetak.

| GPIO | Nama Pin | Arah | Komponen | Keterangan |
|------|----------|------|----------|------------|
| **14** | IR_DROP | INPUT_PULLUP | Jalur bersama semua OUT IR receiver | Beam terblokir = produk jatuh |

---

## 3. Sensor Jarak Ultrasonic (HC-SR04) - 4 Pin

**Fungsi:** Mendeteksi kehadiran orang di depan mesin vending.
- Ada orang -> Frontend menampilkan tutorial
- Tidak ada orang -> Frontend kembali ke ad/idle screen

**Komponen:** HC-SR04 (jarak deteksi 2cm - 400cm)

| GPIO | Nama Pin | Arah | Komponen | Keterangan |
|------|----------|------|----------|------------|
| **19** | SONIC1_TRIG | OUTPUT | HC-SR04 #1 (TRIG) | Trigger sensor jarak 1 - kiri mesin |
| **21** | SONIC1_ECHO | INPUT | HC-SR04 #1 (ECHO) | Echo sensor jarak 1 |
| **22** | SONIC2_TRIG | OUTPUT | HC-SR04 #2 (TRIG) | Trigger sensor jarak 2 - kanan mesin |
| **13** | SONIC2_ECHO | INPUT | HC-SR04 #2 (ECHO) | Echo sensor jarak 2 |

**Wiring per HC-SR04:**
```
HC-SR04 TRIG  -->  GPIO ESP32 (OUTPUT)
HC-SR04 ECHO  -->  GPIO ESP32 (INPUT)
HC-SR04 VCC   -->  5V
HC-SR04 GND   -->  GND
```

**Cara Kerja:**
```
1. ESP32 pulsa TRIG HIGH selama 10 micro detik
2. HC-SR04 mengirim ultrasonik (8 pulse 40kHz)
3. HC-SR04 set ECHO HIGH selama waktu tempuh gelombang
4. ESP32 ukur durasi ECHO HIGH
5. Jarak = (durasi x 343 m/s) / 2

Contoh:
  Jarak < 150cm -> ADA ORANG -> emit EVENT_USER_DETECTED
  Jarak > 150cm -> TIDAK ADA -> emit EVENT_USER_LEFT
```

**Posisi di Mesin:**
```
  +---------------------+
  |   [SONIC #1 kiri]   |  <- GPIO 19, 21
  |                     |
  |   VENDING MACHINE   |
  |                     |
  |   [SONIC #2 kanan]  |  <- GPIO 22, 13
  +---------------------+
         ^ ^ ^
      Orang berdiri
```

---

## 4. Keypad Matrix 4x4 - 8 Pin

**Fungsi:** Input angka oleh user untuk memilih slot produk.

**Layout Keypad 4x4:**
```
       Col1  Col2  Col3  Col4
Row1 [  1  ][  2  ][  3  ][  A  ]
Row2 [  4  ][  5  ][  6  ][  B  ]
Row3 [  7  ][  8  ][  9  ][  C  ]
Row4 [  *  ][  0  ][  #  ][  D  ]
```

**Mapping ke Aplikasi Vending:**
| Tombol | Fungsi di Vending |
|--------|-------------------|
| 0-9 | Input digit nomor slot (misal: 1, 5 -> slot 15) |
| A / # | ACCEPT (konfirmasi pembelian) |
| D / * | CANCEL (batal) |
| B, C | Tidak digunakan / spare |

**Kolom memakai GPIO 17/18/32/33** karena GPIO 25/26 adalah pin DATA/CLOCK shift
register output (74HC595) yang dipakai relay motor. Keempat GPIO kolom ini
mendukung `INPUT_PULLDOWN` sehingga tidak butuh resistor 10k eksternal.

| GPIO | Nama Pin | Arah | Komponen | Keterangan |
|------|----------|------|----------|------------|
| **2** | KEYPAD_ROW1 | OUTPUT | Keypad row 1 | Scanning row 1 |
| **4** | KEYPAD_ROW2 | OUTPUT | Keypad row 2 | Scanning row 2 |
| **5** | KEYPAD_ROW3 | OUTPUT | Keypad row 3 | Scanning row 3 |
| **16** | KEYPAD_ROW4 | OUTPUT | Keypad row 4 | Scanning row 4 |
| **17** | KEYPAD_COL1 | INPUT_PULLDOWN | Keypad kolom 1 | Baca kolom 1 |
| **18** | KEYPAD_COL2 | INPUT_PULLDOWN | Keypad kolom 2 | Baca kolom 2 |
| **32** | KEYPAD_COL3 | INPUT_PULLDOWN | Keypad kolom 3 | Baca kolom 3 |
| **33** | KEYPAD_COL4 | INPUT_PULLDOWN | Keypad kolom 4 | Baca kolom 4 |

**Wiring Keypad 4x4 ke ESP32:**
```
Keypad Pin Layout (biasanya kabel warna):
  1 = Row 1    -> GPIO 2   (OUTPUT)
  2 = Row 2    -> GPIO 4   (OUTPUT)
  3 = Row 3    -> GPIO 5   (OUTPUT)
  4 = Row 4    -> GPIO 16  (OUTPUT)
  5 = Col 1    -> GPIO 17  (INPUT_PULLDOWN)
  6 = Col 2    -> GPIO 18  (INPUT_PULLDOWN)
  7 = Col 3    -> GPIO 32  (INPUT_PULLDOWN)
  8 = Col 4    -> GPIO 33  (INPUT_PULLDOWN)
```
*(Urutan pin fisik bisa berbeda tergantung merk keypad — pastikan mapping row/col
sesuai, karena baris & kolom bisa ditukar tanpa mengubah fungsi selama konsisten.)*

---

## Ringkasan Semua GPIO

| GPIO | Fungsi | Arah |
|------|--------|------|
| 2 | Keypad Row 1 | OUTPUT |
| 4 | Keypad Row 2 | OUTPUT |
| 5 | Keypad Row 3 | OUTPUT |
| 13 | Ultrasonic #2 ECHO | INPUT |
| 14 | IR Receiver Array (jalur bersama) | INPUT_PULLUP |
| 16 | Keypad Row 4 | OUTPUT |
| 17 | Keypad Col 1 | INPUT_PULLDOWN |
| 18 | Keypad Col 2 | INPUT_PULLDOWN |
| 19 | Ultrasonic #1 TRIG | OUTPUT |
| 21 | Ultrasonic #1 ECHO | INPUT |
| 22 | Ultrasonic #2 TRIG | OUTPUT |
| 25 | 74HC595 DATA (SER) | OUTPUT |
| 26 | 74HC595 CLOCK (SRCLK) | OUTPUT |
| 27 | 74HC595 LATCH (RCLK) | OUTPUT |
| 32 | Keypad Col 3 | INPUT_PULLDOWN |
| 33 | Keypad Col 4 | INPUT_PULLDOWN |

> GPIO 34-39 & lainnya dikosongkan / cadangan. GPIO 34-39 bersifat input-only
> tanpa pull internal, jadi tidak dipakai untuk keypad.
