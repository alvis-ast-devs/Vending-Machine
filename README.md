# Smart Vending Machine

Sistem terdiri dari Flutter Desktop UI, FastAPI + PostgreSQL, React Admin, dan
firmware ESP32.

## 1. Jalankan database

```powershell
docker compose up -d postgres
```

## 2. Jalankan backend

```powershell
cd Backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env
python seed_products.py
uvicorn app.main:app --reload --port 8000
```

Perintah `seed_products.py` juga membuat tabel log pembelian pada database yang
sudah ada. Dashboard menyimpan dan menampilkan maksimal 30 transaksi terbaru;
transaksi tertua dihapus otomatis setelah batas tersebut terlampaui.

Untuk menjalankan seluruh alur tanpa ESP32/relay, pastikan
`HARDWARE_ENABLED=false` di `Backend/.env`. Backend akan menyimulasikan respons
hardware sehingga proses drop dan pengurangan stok tetap dapat diuji.

Flutter juga melewati layar tunggu kamera secara default. Saat hardware sudah
siap, jalankan Flutter dengan `--dart-define=HARDWARE_ENABLED=true` untuk
mengaktifkan kembali alur `USER_DETECTED`.

## 3. Jalankan admin dashboard

```powershell
cd Frontend\admin_dashboard
Copy-Item .env.example .env
npm install
npm run dev
```

## 4. Jalankan Flutter Desktop

```powershell
cd Frontend\vending_ui
flutter run -d windows
```

## 5. Upload firmware ESP32

Buka `Hardware/smart_vending_esp32.ino` melalui Arduino IDE, pilih board ESP32,
sesuaikan `MOTOR_RELAY_PIN`, lalu upload. Port USB yang sama harus ditulis pada
`SERIAL_PORT` di `Backend/.env`.

## Alur komunikasi

```text
React Admin ──REST──> FastAPI <──REST── Flutter
                              └──WebSocket──> Flutter
FastAPI ──DROP_SLOT_xx──> ESP32 ──SUCCESS_xx──> FastAPI
Flutter <──WebSocket── FastAPI <──EVENT_*── ESP32/keypad
```

## Alur media layar

- Aplikasi mulai dari Home. Setelah 30 detik tidak digunakan, aplikasi memutar
  foto/video iklan yang diunggah dari dashboard admin.
- Saat event `USER_DETECTED` diterima, satu video tutorial diputar lalu aplikasi
  langsung membuka Menu. Jika tutorial belum tersedia, aplikasi tetap berada di
  Home dan pengguna dapat masuk melalui tombol atau sentuhan layar.
- Home dapat memakai satu foto atau video 9:16 dari dashboard admin. Video
  diputar berulang dan seluruh layar dapat disentuh untuk mulai berbelanja.
- Jika media Home dihapus atau belum diunggah, aplikasi memakai layar Home
  bawaan. Iklan/tutorial yang kosong juga dilewati tanpa layar media kosong.
- Menu yang tidak menerima interaksi selama 30 detik dianggap ditinggalkan dan
  kembali ke Home. Setelah Home idle selama 30 detik, iklan mulai diputar.

## Palet warna layar

Tombol **Pengaturan warna** berada di header dashboard admin, di atas navbar.
Halaman tersebut menyediakan preview menu 9:16, input color picker/HEX, reset ke
palet bawaan, pembatalan perubahan, dan tombol simpan. Palet disimpan pada
backend dan dikirim ke Flutter melalui event WebSocket `THEME_UPDATED`, sehingga
layar mesin mengambil warna terbaru tanpa perlu restart manual.

Warna yang dapat diatur adalah latar utama, teks utama, teks sekunder, aksen,
sorotan, dan bahaya. Warna permukaan internal dan pemisah diturunkan otomatis
dari latar utama agar desain Flutter tetap sederhana tanpa kartu produk.

## Kontrol keypad dan tes ESP32

Kontrol sentuh Flutter tetap aktif. Keypad menjadi jalur input tambahan dengan
alur berikut:

- tombol apa pun saat tutorial memutar video akan melewati tutorial dan langsung
  membuka Menu;
- masukkan dua digit kode slot, lalu `ACCEPT` untuk menambahkan produk;
- tekan `ACCEPT` tanpa kode untuk membuka pembayaran jika keranjang berisi;
- masukkan kode slot, lalu `CANCEL`/`DECLINED` untuk mengurangi produk tersebut;
- tekan `CANCEL` tanpa kode untuk membatalkan transaksi;
- `CANCEL` pada layar pembayaran kembali ke Home.

Untuk pengujian langsung melalui keyboard komputer:

| Tombol keyboard | Trigger aplikasi |
| --- | --- |
| `F` | Pengguna terdeteksi/dekati mesin |
| `0`–`9` atau numpad | Masukkan kode slot |
| `Enter` | Accept |
| `Shift` kiri/kanan | Cancel |
| `G` | Declined |
| `H` | Payment success |

Keyboard, touchscreen, dan event mikrokontroler aktif secara bersamaan.

Pada mode `HARDWARE_ENABLED=false`, layar pembayaran menyediakan tombol
`SIMULASIKAN PEMBAYARAN BERHASIL`. Tombol tersebut dan tombol keyboard `H`
mengirim daftar slot keranjang ke backend. Backend menyimulasikan drop, mengurangi
stok, dan mencatat log pembelian. Pada mode hardware aktif, endpoint
`POST /api/events/payment-success` dari sistem pembayaran menjalankan alur yang
sama menggunakan ESP32.

Firmware menerima perintah tes `DETECT`, angka `0` sampai `9`, `ACCEPT`,
`CANCEL`, dan `DECLINED`. Untuk menguji rangkaian lengkap saat backend memegang
port serial, kirim perintah melalui endpoint berikut di halaman `/docs`:

```text
POST /api/hardware/test-input/DETECT
POST /api/hardware/test-input/KEY_0
POST /api/hardware/test-input/KEY_1
POST /api/hardware/test-input/ACCEPT
POST /api/hardware/test-input/DECLINED
```

Untuk menguji Flutter tanpa ESP32, gunakan `POST /api/events/user-detected` dan
`POST /api/events/keypad/{key}`.
