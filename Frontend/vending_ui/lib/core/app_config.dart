import 'package:flutter/material.dart';

enum VendingRoute { ad, tutorial, home, menu, payment, finish, admin }

enum MachineSocketStatus { connecting, connected, disconnected }

/// Connection mode for ESP32 communication.

class AppConfig {
  const AppConfig._();

  /// Whether real hardware is connected.
  static const bool hardwareEnabled = bool.fromEnvironment(
    'HARDWARE_ENABLED',
    defaultValue: true,
  );

  static const bool voicePaymentEnabled = bool.fromEnvironment(
    'VOICE_PAYMENT_ENABLED',
    defaultValue: true,
  );

  /// Serial port name for ESP32 communication (e.g. COM3 on Windows).
  static const String serialPort = String.fromEnvironment(
    'SERIAL_PORT',
    defaultValue: 'COM7',
  );

  /// Folder dasar data lokal (berisi `assets/` dan `products.json`) saat
  /// development, supaya media bisa dites tanpa build release. Kosong = pakai
  /// folder di sebelah executable. Contoh:
  /// flutter run -d windows --dart-define=ASSETS_BASE_PATH=C:\\repo\\Frontend\\vending_ui
  static const String assetsBasePath = String.fromEnvironment(
    'ASSETS_BASE_PATH',
    defaultValue: '',
  );

  static const int serialBaudRate = 115200;

  /// Kode rahasia untuk membuka Admin Mode dari halaman Menu.
  /// Bisa diganti saat build via --dart-define=ADMIN_CODE=xxxx.
  static const String adminCode = String.fromEnvironment(
    'ADMIN_CODE',
    defaultValue: '9999',
  );

  static const double portraitAspectRatio = 9 / 16;
  static const Size initialWindowSize = Size(540, 960);
  static const Size minimumWindowSize = Size(360, 640);
  static const Size designSize = Size(540, 960);

  static const Duration pageTransitionDuration = Duration(milliseconds: 350);
  static const Duration homeIdleDuration = Duration(seconds: 30);
  static const Duration menuIdleDuration = Duration(seconds: 30);
  static const Duration adImageDuration = Duration(seconds: 8);
  static const Duration paymentDuration = Duration(seconds: 60);

  /// Berapa lama halaman pembayaran menampilkan status "pembayaran diterima"
  /// sebelum berpindah ke halaman "Terima Kasih" (drop produk berjalan
  /// di latar belakang, tanpa menunggu deteksi IR).
  static const Duration paymentSuccessDuration = Duration(seconds: 3);

  static const Duration finishDuration = Duration(seconds: 5);
  static const Duration requestTimeout = Duration(seconds: 8);
  static const Duration paymentProcessingTimeout = Duration(minutes: 2);

  /// Default full stock value for restock operations.
  static const int defaultFullStock = 10;
}
