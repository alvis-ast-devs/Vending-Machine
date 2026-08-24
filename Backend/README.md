# Smart Vending Machine Backend

Backend FastAPI untuk katalog produk, event WebSocket mesin, PostgreSQL, dan
komunikasi serial ESP32.

## Menjalankan PostgreSQL

```powershell
docker compose up -d postgres
```

## Menjalankan API

```powershell
cd Backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env
python seed_products.py
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Dokumentasi interaktif tersedia di `http://localhost:8000/docs`.

Jika PostgreSQL tidak dapat diakses, endpoint database mengembalikan HTTP `503`
dengan pesan ringkas. Periksa `DATABASE_URL` dan status PostgreSQL untuk melihat
akar masalahnya.

## Mode tanpa ESP32

Secara default backend menggunakan simulasi hardware. Pengaturannya berada di
file `.env`:

```dotenv
HARDWARE_ENABLED=false
```

Saat bernilai `false`, endpoint drop tidak membuka serial port. Backend hanya
mencetak `DROP_SLOT_xx` dan `SUCCESS_xx` ke console, lalu tetap mengurangi stok.
Ubah menjadi `true` dan restart Uvicorn saat ingin memakai ESP32 sungguhan.

Mode aktif dapat diperiksa melalui `GET /health` pada field `hardware_mode`.

## Endpoint utama

- `GET /api/products`
- `GET /api/products/{id}`
- `POST /api/products`
- `PUT /api/products/{id}`
- `PUT /api/products/{id}/deactivate`
- `PUT /api/products/{id}/restock`
- `POST /api/products/{id}/image`
- `DELETE /api/products/{id}/image`
- `GET /api/media`
- `POST /api/media/ads`
- `POST /api/media/tutorial`
- `POST /api/media/homescreen`
- `DELETE /api/media/{id}`
- `GET /api/purchases`
- `GET /api/theme`
- `PUT /api/theme`
- `POST /api/events/user-detected`
- `POST /api/events/payment-success`
- `POST /api/events/keypad/{key}`
- `POST /api/hardware/drop/{slot_code}`
- `POST /api/hardware/test-input/{input_name}`
- `WS /ws/machine`

File iklan, tutorial, dan homescreen disimpan pada direktori `MEDIA_UPLOAD_DIR`,
sedangkan metadata media disimpan pada tabel `media_assets`. Foto produk
menggunakan direktori media yang sama dan kolom gambar pada tabel `products`.
Jalankan `python seed_products.py` sekali setelah pembaruan untuk membuat tabel
baru, menambahkan kolom foto produk, dan memperbarui constraint tipe media pada
database yang sudah ada.

Palet layar disimpan sebagai satu baris pada tabel `theme_settings`. Jika tabel
belum ada pada instalasi lama, endpoint tema juga membuatnya secara aman.
`PUT /api/theme` memvalidasi delapan kode warna `#RRGGBB`, menyimpan palet, lalu
menyiarkan event `THEME_UPDATED` agar Flutter memuat ulang tema secara langsung.

Pembayaran sukses wajib membawa `slot_codes`. Backend memvalidasi stok seluruh
pesanan, menjalankan drop untuk setiap item, mengurangi stok, lalu menyimpan
transaksi pada tabel `purchase_logs` dan `purchase_log_items`. Nama serta harga
produk disimpan sebagai snapshot agar riwayat tidak berubah ketika katalog
diedit. Sistem mempertahankan maksimal 30 transaksi terbaru dan otomatis
menghapus transaksi tertua. Pengiriman ulang `transaction_id` yang sama tidak
menjalankan drop atau membuat log duplikat.

Event yang diterima Flutter berbentuk:

```json
{"type":"USER_DETECTED","data":{}}
```

atau:

```json
{
  "type":"PAYMENT_SUCCESS",
  "data":{"transaction_id":"TRX-001","slot_codes":["11"]}
}
```

## Protokol serial

Backend mengirim satu baris:

```text
DROP_SLOT_11
```

ESP32 harus membalas:

```text
SUCCESS_11
```

Endpoint drop manual mengurangi stok setelah balasan sukses diterima. Pada alur
pembayaran, seluruh slot divalidasi terlebih dahulu dan log baru dibuat setelah
semua perintah drop berhasil.

ESP32 juga dapat mengirim event input ke backend:

```text
EVENT_USER_DETECTED
EVENT_KEY_0
EVENT_KEY_1
EVENT_ACCEPT
EVENT_CANCEL
```

Backend meneruskannya ke Flutter sebagai `USER_DETECTED`, `KEYPAD_DIGIT`,
`KEYPAD_ACCEPT`, atau `KEYPAD_CANCEL`. Listener serial hanya aktif jika
`HARDWARE_ENABLED=true`.

Untuk tes penuh tanpa keypad yang sudah dirakit, endpoint
`/api/hardware/test-input/{input_name}` mengirim perintah `TEST_*` ke ESP32.
Nilai yang diterima adalah `DETECT`, `KEY_0` sampai `KEY_9`, `ACCEPT`, `CANCEL`,
dan `DECLINED`. Jika hanya ingin menguji Flutter tanpa hardware, gunakan
`/api/events/keypad/{key}`.

## Test

```powershell
pytest
```
