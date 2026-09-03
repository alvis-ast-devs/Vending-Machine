import 'dart:async';
import 'dart:io';

import 'package:vending_ui/core/app_config.dart';
import 'package:vending_ui/core/app_utils.dart';
import 'package:vending_ui/core/event_bus.dart';
import 'package:vending_ui/core/local_data_service.dart';
import 'package:vending_ui/core/media_asset.dart';
import 'package:vending_ui/core/product_model.dart';
import 'package:vending_ui/core/serial_bridge.dart';
import 'package:vending_ui/core/theme_settings.dart';
import 'package:vending_ui/core/voice_recognition_bridge.dart';

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);
  @override
  String toString() => message;
}

class VoicePaymentSession {
  final String transactionId;
  final int totalAmount;
  final int paidAmount;
  final int remainingAmount;
  final String status;

  const VoicePaymentSession({
    required this.transactionId,
    required this.totalAmount,
    required this.paidAmount,
    required this.remainingAmount,
    required this.status,
  });

  factory VoicePaymentSession.fromJson(Map<String, dynamic> json) {
    return VoicePaymentSession(
      transactionId: json['transaction_id'] as String,
      totalAmount: json['total_amount'] as int,
      paidAmount: json['paid_amount'] as int,
      remainingAmount: json['remaining_amount'] as int,
      status: json['status'] as String,
    );
  }
}

/// Local replacement for the old HTTP-based ApiService.
/// All data comes from JSON files and the local assets folder.
class ApiService {
  final LocalDataService _data = LocalDataService.instance;
  SerialBridge? _serialBridge;
  final VoiceRecognitionBridge _voiceBridge = VoiceRecognitionBridge();

  StreamSubscription<VoiceRecognitionResult>? _voiceResultSubscription;
  int _voicePaidAmount = 0;
  int _voiceTotalAmount = 0;

  int _nextAdId = 1000;
  int _nextProductId = 2000;

  void setSerialBridge(SerialBridge bridge) {
    _serialBridge = bridge;
  }

  VoiceRecognitionBridge get voiceBridge => _voiceBridge;

  // ─── Products ─────────────────────────────────────────────────────────────

  Future<List<Product>> fetchProducts() async {
    final products = await _data.loadProducts();
    return products.where((p) => p.isActive).toList()
      ..sort((a, b) => a.slotCode.compareTo(b.slotCode));
  }

  /// Semua produk termasuk yang nonaktif — dipakai layar Admin supaya
  /// admin bisa melihat dan mengisi stok slot apa pun.
  Future<List<Product>> fetchAllProducts() async {
    final products = await _data.loadProducts();
    return products..sort((a, b) => a.slotCode.compareTo(b.slotCode));
  }

  /// Isi stok satu slot hingga penuh (nilai default stok penuh).
  /// Tidak ada perintah ke ESP32: admin mengisi produk secara fisik,
  /// stok hanya dicatat ulang di data lokal.
  Future<Product?> restockSlot(String slotCode) async {
    return _data.restockProduct(
      slotCode,
      quantity: AppConfig.defaultFullStock,
    );
  }

  // ─── Media ────────────────────────────────────────────────────────────────

  Future<MediaCatalog> fetchMediaCatalog() async {
    final ads = _data
        .scanAds()
        .map(
          (f) => MediaAsset.fromFile(
            id: _nextAdId++,
            kind: 'ad',
            file: f.file,
          ),
        )
        .toList();

    final tutorialFile = _data.findTutorial();
    final tutorial = tutorialFile != null
        ? MediaAsset.fromFile(id: _nextAdId++, kind: 'tutorial', file: tutorialFile)
        : null;

    final homescreenFile = _data.findHomescreen();
    final homescreen = homescreenFile != null
        ? MediaAsset.fromFile(
            id: _nextAdId++,
            kind: 'homescreen',
            file: homescreenFile,
          )
        : null;

    return MediaCatalog(ads: ads, tutorial: tutorial, homescreen: homescreen);
  }

  // ─── Theme ────────────────────────────────────────────────────────────────

  Future<VendingPalette> fetchTheme() async {
    // In local mode, always return the default palette.
    return VendingPalette.defaults;
  }

  // ─── Payment ──────────────────────────────────────────────────────────────

  /// Process a payment: reduce stock via serial bridge or mock, log in-memory.
  Future<void> submitPaymentSuccess({
    required String transactionId,
    required List<String> slotCodes,
  }) async {
    for (final slotCode in slotCodes) {
      // Drop the product via serial bridge.
      if (_serialBridge != null) {
        try {
          await _serialBridge!.dropSlot(slotCode);
        } catch (e) {
          throw ApiException('Gagal mengeluarkan produk slot $slotCode: $e');
        }
      }
      // Reduce stock locally.
      await _data.reduceStock(slotCode);
    }
  }

  // ─── Voice Payment ────────────────────────────────────────────────────────

  /// Start a voice payment session.
  Future<VoicePaymentSession> startVoicePayment({
    required String transactionId,
    required List<String> slotCodes,
    required int totalAmount,
  }) async {
    if (!AppConfig.voicePaymentEnabled) {
      throw ApiException('VOICE_PAYMENT_ENABLED belum diaktifkan.');
    }

    // Reset akumulasi nominal untuk sesi baru.
    _voicePaidAmount = 0;
    _voiceTotalAmount = totalAmount;

    // Start the Python voice recognition script.
    await _voiceBridge.startListening();

    // Teruskan setiap nominal yang dikenali Python ke UI via event bus.
    await _voiceResultSubscription?.cancel();
    _voiceResultSubscription = _voiceBridge.results.listen(
      (result) => _handleVoiceRecognitionResult(
        transactionId: transactionId,
        totalAmount: totalAmount,
        result: result,
      ),
    );

    // Beri tahu UI bahwa sesi mulai mendengarkan.
    eventBus.publish(MachineEvent(
      type: 'VOICE_PAYMENT_LISTENING',
      data: {
        'transaction_id': transactionId,
        'paid_amount': 0,
        'remaining_amount': totalAmount,
        'message': null,
      },
    ));

    return VoicePaymentSession(
      transactionId: transactionId,
      totalAmount: totalAmount,
      paidAmount: 0,
      remainingAmount: totalAmount,
      status: 'listening',
    );
  }

  /// Convert satu hasil dari skrip Python menjadi event `VOICE_PAYMENT_*`.
  void _handleVoiceRecognitionResult({
    required String transactionId,
    required int totalAmount,
    required VoiceRecognitionResult result,
  }) {
    // Ping "ready" dari skrip Python — bukan hasil pembayaran.
    if (result.status == 'ready') return;

    // Skrip gagal (mikrofon / library tidak tersedia, dsb).
    if (result.error != null) {
      eventBus.publish(MachineEvent(
        type: 'VOICE_PAYMENT_ERROR',
        data: {
          'transaction_id': transactionId,
          'paid_amount': _voicePaidAmount,
          'remaining_amount': _voiceRemainingAmount,
          'message': result.error,
        },
      ));
      return;
    }

    // Suara tidak dikenali / nominal nol.
    if (result.amount <= 0) {
      eventBus.publish(MachineEvent(
        type: 'VOICE_PAYMENT_UNRECOGNIZED',
        data: {
          'transaction_id': transactionId,
          'paid_amount': _voicePaidAmount,
          'remaining_amount': _voiceRemainingAmount,
          'message': 'Tidak terdengar jelas, silakan coba lagi.',
        },
      ));
      return;
    }

    _voicePaidAmount += result.amount;
    final paid = _voicePaidAmount.clamp(0, totalAmount);
    final remaining = (totalAmount - paid).clamp(0, totalAmount);
    final done = paid >= totalAmount;

    eventBus.publish(MachineEvent(
      type: done ? 'VOICE_PAYMENT_CONFIRMED' : 'VOICE_PAYMENT_UPDATE',
      data: {
        'transaction_id': transactionId,
        'paid_amount': paid,
        'remaining_amount': remaining,
        'message': done
            ? 'Pembayaran lunas, terima kasih!'
            : 'Diterima ${formatRupiah(paid)}, sisa ${formatRupiah(remaining)}',
      },
    ));
  }

  int get _voiceRemainingAmount =>
      (_voiceTotalAmount - _voicePaidAmount).clamp(0, _voiceTotalAmount);

  /// Cancel an active voice payment session.
  Future<void> cancelVoicePayment(String transactionId) async {
    await _voiceResultSubscription?.cancel();
    _voiceResultSubscription = null;
    _voiceBridge.stopListening();
  }

  // ─── Cleanup ──────────────────────────────────────────────────────────────

  void close() {
    unawaited(_voiceResultSubscription?.cancel());
    _voiceResultSubscription = null;
    _voiceBridge.dispose();
  }
}
