import 'dart:async';
import 'dart:io';

import 'package:vending_ui/core/app_config.dart';
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

    // Start the Python voice recognition script.
    await _voiceBridge.startListening();

    return VoicePaymentSession(
      transactionId: transactionId,
      totalAmount: totalAmount,
      paidAmount: 0,
      remainingAmount: totalAmount,
      status: 'listening',
    );
  }

  /// Cancel an active voice payment session.
  Future<void> cancelVoicePayment(String transactionId) async {
    _voiceBridge.stopListening();
  }

  // ─── Cleanup ──────────────────────────────────────────────────────────────

  void close() {
    _voiceBridge.dispose();
  }
}
