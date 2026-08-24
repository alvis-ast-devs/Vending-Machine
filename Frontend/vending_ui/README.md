# Smart Vending Machine UI

Flutter Desktop UI potret 9:16 yang terhubung ke FastAPI melalui REST dan
WebSocket.

## Menjalankan aplikasi

Dengan backend lokal pada port `8000`:

```powershell
flutter run -d windows
```

Secara default UI berjalan tanpa hardware dan langsung membuka halaman
`Selamat Datang`, tanpa menunggu deteksi kamera. Untuk mengaktifkan kembali
alur kamera:

```powershell
flutter run -d windows --dart-define=HARDWARE_ENABLED=true
```

Untuk alamat backend lain:

```powershell
flutter run -d windows `
  --dart-define=BACKEND_HTTP_URL=http://192.168.1.10:8000 `
  --dart-define=BACKEND_WEBSOCKET_URL=ws://192.168.1.10:8000/ws/machine
```

## Alur backend dan media

- Home memeriksa media setelah 30 detik idle dan hanya membuka `AdScreen` jika
  foto/video iklan tersedia.
- `USER_DETECTED` memutar satu video tutorial jika tersedia, kemudian membuka
  Home. Jika tutorial kosong, Home langsung digunakan.
- `MenuScreen` mengambil produk dari `GET /api/products`.
- `MenuScreen` menampilkan foto produk dari backend atau ikon default jika foto
  belum tersedia/gagal dimuat.
- `PaymentScreen` berpindah ke Finish setelah menerima `PAYMENT_SUCCESS`.
- WebSocket akan mencoba tersambung ulang setiap tiga detik ketika koneksi putus.
- Event keypad tidak menggantikan layar sentuh. Keduanya aktif bersamaan.
- `KEYPAD_DIGIT` memasukkan kode slot, `KEYPAD_ACCEPT` memilih produk atau
  membuka pembayaran, dan `KEYPAD_CANCEL` membatalkan pilihan/transaksi.
- Tombol keypad apa pun melewati video tutorial dan kembali ke Home.
- Untuk tes dari keyboard Windows: `F` mengirim `USER_DETECTED`, angka `0`–`9`
  mengisi kode, `Enter` adalah Accept, `Shift` adalah Cancel, dan `G` adalah
  Declined. Tombol `H` menyimulasikan `PAYMENT_SUCCESS` saat layar pembayaran
  aktif. Touchscreen tetap aktif.

Trigger pengujian dapat dikirim ke backend:

```powershell
Invoke-RestMethod -Method Post http://127.0.0.1:8000/api/events/user-detected
Invoke-RestMethod -Method Post `
  -ContentType 'application/json' `
  -Body '{"transaction_id":"TRX-001","slot_codes":["01"]}' `
  http://127.0.0.1:8000/api/events/payment-success
```

## Verifikasi

```powershell
flutter analyze
flutter test
flutter build windows
```
