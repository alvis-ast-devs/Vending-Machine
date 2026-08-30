# Smart Vending Machine

Aplikasi Flutter Desktop mandiri untuk mesin vending machine pintar.
Semua data disimpan secara lokal (JSON file), tanpa backend server.

## Arsitektur

```
Flutter Desktop (satu aplikasi)
├── Tampilan vending machine
├── Data produk lokal (products.json)
├── Stok lokal
├── Media lokal (folder assets/)
├── Komunikasi ESP32 (flutter_libserialport)
└── Voice recognition via Python (Process.run)
```

## Struktur Folder

Saat build/run, aplikasi menggunakan struktur folder di sebelah executable:

```
build/.../Release/
├── vending_machine.exe
├── products.json                    ← edit manual untuk produk
├── assets/
│   ├── product_images/
│   │   ├── 01.png                   ← foto produk slot 01
│   │   ├── 02.jpg                   ← foto produk slot 02
│   │   └── ...
│   ├── ads/
│   │   ├── iklan_01.mp4             ← iklan (bisa banyak)
│   │   ├── iklan_02.png
│   │   └── ...
│   ├── tutorial/
│   │   └── tutorial.mp4             ← satu video tutorial
│   └── homescreen/
│       └── homescreen.png           ← satu foto/video homescreen
```

### Format `products.json`

```json
[
  {
    "slot_code": "01",
    "name": "Snack 01",
    "price": 8000,
    "stock": 10,
    "is_active": true
  }
]
```

## Menjalankan

### 1. Install Dependencies

```bash
cd Frontend/vending_ui
flutter pub get
```

### 2. Install Python Dependencies (untuk voice recognition)

```bash
pip install SpeechRecognition PyAudio
```

### 3. Jalankan

```bash
# Tanpa hardware (mode simulasi)
flutter run -d windows

# Dengan hardware ESP32
flutter run -d windows --dart-define=HARDWARE_ENABLED=true --dart-define=SERIAL_PORT=COM3
```

### 4. Build

```bash
flutter build windows --release
```

## Keyboard Shortcuts

| Tombol | Fungsi |
|--------|--------|
| `F` | Pengguna terdeteksi |
| `0`–`9` | Masukkan kode slot |
| `Enter` | Accept |
| `Shift` kiri/kanan | Cancel |
| `G` | Declined |
| `H` | Payment success (simulasi) |

## Media

- **Foto produk:** Letakkan file gambar di `assets/product_images/` dengan nama `{slot_code}.{ext}` (misal `01.png`, `15.jpg`)
- **Iklan:** Letakkan file di `assets/ads/` (foto atau video, diputar bergantian)
- **Tutorial:** Letakkan satu file video di `assets/tutorial/` (ganti = rename file baru)
- **Homescreen:** Letakkan satu file di `assets/homescreen/` (foto atau video)

Format yang didukung:
- Gambar: PNG, JPG, WebP, GIF, BMP
- Video: MP4, WebM, MOV, MKV

## ESP32

Firmware ESP32 ada di `Hardware/smart_vending_esp32/`. Upload via Arduino IDE.
Port USB harus sesuai dengan `SERIAL_PORT` saat menjalankan aplikasi.

## Hardware Test Commands

Jika hardware aktif, ESP32 menerima perintah:
- `DROP_SLOT_XX` → drop produk
- `TEST_DETECT` → simulasi user detected
- `TEST_ACCEPT` / `TEST_CANCEL` / `TEST_DECLINED` → keypad events
- `TEST_KEY_X` → digit keypad

## @ Copyright Aruvisu
