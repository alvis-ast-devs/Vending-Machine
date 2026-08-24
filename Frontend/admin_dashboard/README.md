# Vending Admin Dashboard

Dashboard React + Vite untuk mengelola produk Smart Vending Machine.

## Menjalankan

```powershell
Copy-Item .env.example .env
npm install
npm run dev
```

Buka `http://localhost:5173` dari komputer. Untuk memeriksa dari HP, hubungkan
HP dan komputer ke Wi-Fi yang sama, cari alamat IPv4 komputer melalui
`ipconfig`, lalu buka `http://ALAMAT-IP-KOMPUTER:5173` dari browser HP.

Biarkan `VITE_API_BASE_URL` kosong agar dashboard memakai proxy lokal menuju
FastAPI di komputer. Pastikan backend berjalan pada port `8000`. Jika Windows
Firewall meminta izin saat `npm run dev` dijalankan, izinkan akses pada jaringan
privat.

## Fitur

- Navigasi tiga tab: Ringkasan, Produk, dan Konten Layar.
- Melihat produk aktif dan nonaktif.
- Mencari produk berdasarkan nama atau nomor slot.
- Mengubah nama, harga, dan stok.
- Mengunggah, mengganti, melihat preview, atau menghapus foto setiap produk.
- Soft delete melalui status nonaktif.
- Mengaktifkan kembali produk.
- Restock penuh otomatis ke nilai `FULL_STOCK` backend.
- Ringkasan produk aktif, total stok, dan slot kosong.
- Mengunggah beberapa foto/video iklan dan menghapusnya.
- Mengunggah satu video tutorial; unggahan baru menggantikan video sebelumnya.
- Mengunggah satu foto/video homescreen; jika dihapus, aplikasi kembali memakai
  Home bawaan.
- Preview iklan/tutorial/homescreen menggunakan rasio layar 9:16 dan crop
  otomatis.
- Tampilan responsif untuk HP: ringkasan ringkas, navigasi sentuh, kartu produk,
  form edit, upload, serta preview media yang menyesuaikan lebar layar.

## Build

```powershell
npm run lint
npm run build
```
