# Dokumentasi Alokasi Pin ESP32 - Smart Vending Machine

## Ringkasan Komponen

| No | Komponen | Jumlah | Keterangan |
|----|----------|--------|------------|
| 1 | 74HC595 (Shift Register Output) | 7 chip | 56 output -> 50 relay -> 50 motor |
| 2 | 74HC165 (Shift Register Input) | 7 chip | 56 input -> 50 sensor slot + 5 IR receiver |
| 3 | IR Receiver (Sensor Infrared) | 5 unit | Deteksi barang jatuh (terhubung ke 74HC165) |
| 4 | Ultrasonic HC-SR04 (Sensor Jarak) | 2 unit | Deteksi kehadiran orang di depan mesin |
| 5 | Keypad Matrix 4x4 | 1 unit | Input angka oleh user (0-9, A-D) |
| 6 | Serial UART | 1 channel | Komunikasi dengan PC/Frontend |

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

## 2. Shift Register Input (74HC165) - 3 Pin

Membaca 50 sensor slot + 5 IR receiver = 55 input dari 56 yang tersedia.

| GPIO | Nama Pin | Arah | Komponen | Keterangan |
|------|----------|------|----------|------------|
| **32** | SR_IN_DATA | INPUT | 74HC165 pin 9 (Q7) chip terakhir | Data serial keluar |
| **33** | SR_IN_CLOCK | OUTPUT | 74HC165 pin 2 (CLK) semua chip | Clock shift |
| **14** | SR_IN_LOAD | OUTPUT | 74HC165 pin 1 (SH/LD) semua chip | Load paralel |

**Wiring 74HC165 Daisy Chain:**
```
ESP32 GPIO 32 <-- Q7  (pin 9)  Chip #7 (terakhir)
                   SER (pin 10) Chip #7 <-- Q7' (pin 9) Chip #6
                                            SER (pin 10) Chip #6 <-- ... dst

ESP32 GPIO 33 --> CLK  (pin 2) semua chip (paralel)
ESP32 GPIO 14 --> SH/LD (pin 1) semua chip (paralel)

CE (pin 15) --> LOW (chip enable, selalu aktif)
VCC (pin 16) --> 5V
GND (pin 8)  --> GND
```

**Mapping Input -> Bit:**
| Bit Index | Fungsi | Keterangan |
|-----------|--------|------------|
| 0 - 49 | Sensor Slot 01-55 | 50 sensor produk |
| 50 | IR Receiver 1 | Zona lampu 1 (slot 01-10) |
| 51 | IR Receiver 2 | Zona lampu 2 (slot 11-20) |
| 52 | IR Receiver 3 | Zona lampu 3 (slot 21-30) |
| 53 | IR Receiver 4 | Zona lampu 4 (slot 31-40) |
| 54 | IR Receiver 5 | Zona lampu 5 (slot 41-55) |
| 55 | Tidak digunakan | Spare |

**Cara Kerja:**
```
1. ESP32 pulsa GPIO 14 (LOAD) LOW selama 5 micro detik
   -> Semua 56 input fisik di-load ke internal latch
2. ESP32 clock sebanyak 56 kali via GPIO 33
   -> Setiap clock, 1 bit bergeser keluar via GPIO 32
3. ESP32 baca GPIO 32 di setiap clock -> dapatkan 56 bit status input
```

---

## 3. Sensor Infrared (IR Receiver) - Via 74HC165

**Fungsi:** Mendeteksi apakah produk benar-benar jatuh dari slot.

**Penting:**
- Hanya RECEIVER yang terhubung ke 74HC165 (bukan ke GPIO langsung)
- TRANSMITTER menggunakan power supply terpisah (langsung ke 5V/GND, tidak lewat ESP32)
- 5 receiver untuk 5 zona di mesin

**Wiring IR Receiver ke 74HC165:**
```
IR Receiver #1 OUT --> 74HC165 input bit 50
IR Receiver #2 OUT --> 74HC165 input bit 51
IR Receiver #3 OUT --> 74HC165 input bit 52
IR Receiver #4 OUT --> 74HC165 input bit 53
IR Receiver #5 OUT --> 74HC165 input bit 54

IR Receiver VCC --> 3.3V atau 5V (tergantung modul)
IR Receiver GND --> GND

IR Transmitter (terpisah):
IR LED VCC --> 5V (power supply langsung)
IR LED GND --> GND (power supply langsung)
(TIDAK terhubung ke ESP32 atau 74HC165)
```

**Cara Kerja:**
```
Normal (tidak ada barang jatuh):
  Transmitter IR menyala -> Receiver mendapat cahaya IR -> Output LOW

Barang jatuh (memotong beam):
  Barang memblokir IR -> Receiver TIDAK dapat cahaya -> Output HIGH
  -> 74HC165 detect bit HIGH -> ESP32 emit EVENT_SLOT_XX_DROP_CONFIRMED
```

**Mapping Zona:**
| IR Receiver | Bit 74HC165 | Area di Mesin |
|-------------|-------------|---------------|
| Sensor 1 | bit 50 | Zona lampu 1 (slot 01-10) |
| Sensor 2 | bit 51 | Zona lampu 2 (slot 11-20) |
| Sensor 3 | bit 52 | Zona lampu 3 (slot 21-30) |
| Sensor 4 | bit 53 | Zona lampu 4 (slot 31-40) |
| Sensor 5 | bit 54 | Zona lampu 5 (slot 41-55) |

---

## 4. Sensor Jarak Ultrasonic (HC-SR04) - 4 Pin

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

## 5. Keypad Matrix 4x4 - 8 Pin

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

| GPIO | Nama Pin | Aarah | Komponen | Keterangan |
|------|----------|------|----------|------------|
| **2** | KEYPAD_ROW1 | OUTPUT | Keypad row 1 | Scanning row 1 |
| **4** | KEYPAD_ROW2 | OUTPUT | Keypad row 2 | Scanning row 2 |
| **5** | KEYPAD_ROW3 | OUTPUT | Keypad row 3 | Scanning row 3 |
| **16** | KEYPAD_ROW4 | OUTPUT | Keypad row 4 | Scanning row 4 |
| **34** | KEYPAD_COL1 | INPUT | Keypad kolom 1 | Baca kolom 1 |
| **35** | KEYPAD_COL2 | INPUT | Keypad kolom 2 | Baca kolom 2 |
| **36** | KEYPAD_COL3 | INPUT | Keypad kolom 3 | Baca kolom 3 |
| **39** | KEYPAD_COL4 | INPUT | Keypad kolom 4 | Baca kolom 4 |

**Wiring Keypad 4x4 ke ESP32:**
```
Keypad Pin Layout (biasanya kabel warna):
  1 = Row 1    -> GPIO 2  (OUTPUT)
  2 = Row 2    -> GPIO 4  (
