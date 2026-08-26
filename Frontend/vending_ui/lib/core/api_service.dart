import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vending_ui/core/app_config.dart';
import 'package:vending_ui/core/media_asset.dart';
import 'package:vending_ui/core/product_model.dart';
import 'package:vending_ui/core/theme_settings.dart';

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

class ApiService {
  final http.Client _client;
  final bool _ownsClient;

  ApiService({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  Future<List<Product>> fetchProducts() async {
    try {
      final response = await _client
          .get(AppConfig.productsUri)
          .timeout(AppConfig.requestTimeout);

      if (response.statusCode != 200) {
        throw ApiException(
          'Server mengembalikan status ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! List) {
        throw const ApiException('Format data produk tidak valid');
      }

      final products =
          decoded
              .map(
                (item) => Product.fromJson(
                  Map<String, dynamic>.from(item as Map),
                  backendUrl: AppConfig.backendHttpUrl.replaceAll(
                    RegExp(r'/$'),
                    '',
                  ),
                ),
              )
              .where((product) => product.isActive)
              .toList()
            ..sort(
              (first, second) => first.slotCode.compareTo(second.slotCode),
            );
      return products;
    } on ApiException {
      rethrow;
    } on FormatException {
      throw const ApiException('Respons server bukan JSON yang valid');
    } catch (_) {
      throw const ApiException('Backend tidak dapat dihubungi');
    }
  }

  Future<MediaCatalog> fetchMediaCatalog() async {
    try {
      final response = await _client
          .get(AppConfig.mediaUri)
          .timeout(AppConfig.requestTimeout);

      if (response.statusCode != 200) {
        throw ApiException(
          'Server media mengembalikan status ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) {
        throw const ApiException('Format data media tidak valid');
      }
      return MediaCatalog.fromJson(
        Map<String, dynamic>.from(decoded),
        backendUrl: AppConfig.backendHttpUrl.replaceAll(RegExp(r'/$'), ''),
      );
    } on ApiException {
      rethrow;
    } on FormatException {
      throw const ApiException('Respons media bukan JSON yang valid');
    } catch (_) {
      throw const ApiException('Media backend tidak dapat dihubungi');
    }
  }

  Future<VendingPalette> fetchTheme() async {
    try {
      final response = await _client
          .get(AppConfig.themeUri)
          .timeout(AppConfig.requestTimeout);

      if (response.statusCode != 200) {
        throw ApiException(
          'Server tema mengembalikan status ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) {
        throw const ApiException('Format palet warna tidak valid');
      }
      return VendingPalette.fromJson(Map<String, dynamic>.from(decoded));
    } on ApiException {
      rethrow;
    } on FormatException {
      throw const ApiException('Respons tema bukan JSON yang valid');
    } catch (_) {
      throw const ApiException('Tema backend tidak dapat dihubungi');
    }
  }

  Future<void> submitPaymentSuccess({
    required String transactionId,
    required List<String> slotCodes,
  }) async {
    try {
      final response = await _client
          .post(
            AppConfig.paymentSuccessUri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'transaction_id': transactionId,
              'slot_codes': slotCodes,
            }),
          )
          .timeout(AppConfig.paymentProcessingTimeout);

      if (response.statusCode != 200) {
        var message = 'Transaksi gagal (${response.statusCode})';
        try {
          final decoded = jsonDecode(utf8.decode(response.bodyBytes));
          if (decoded is Map && decoded['detail'] is String) {
            message = decoded['detail'] as String;
          }
        } on FormatException {
          // Gunakan pesan status HTTP jika respons bukan JSON.
        }
        throw ApiException(message);
      }
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException('Backend tidak dapat memproses transaksi');
    }
  }

  Future<VoicePaymentSession> startVoicePayment({
    required String transactionId,
    required List<String> slotCodes,
    required int totalAmount,
  }) async {
    try {
      final response = await _client
          .post(
            AppConfig.voicePaymentStartUri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'transaction_id': transactionId,
              'slot_codes': slotCodes,
              'total_amount': totalAmount,
            }),
          )
          .timeout(AppConfig.requestTimeout);
      if (response.statusCode != 202) {
        throw ApiException(
          _readError(response, 'Backend gagal memulai mikrofon'),
        );
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) {
        throw const ApiException('Respons pembayaran suara tidak valid');
      }
      return VoicePaymentSession.fromJson(Map<String, dynamic>.from(decoded));
    } on ApiException {
      rethrow;
    } on FormatException {
      throw const ApiException('Respons pembayaran suara tidak valid');
    } catch (_) {
      throw const ApiException(
        'Backend pembayaran suara tidak dapat dihubungi',
      );
    }
  }

  Future<void> cancelVoicePayment(String transactionId) async {
    try {
      await _client
          .post(AppConfig.voicePaymentCancelUri(transactionId))
          .timeout(AppConfig.requestTimeout);
    } catch (_) {
      // Pembatalan bersifat best-effort; UI tetap dapat kembali ke halaman awal.
    }
  }

  String _readError(http.Response response, String fallback) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map && decoded['detail'] is String) {
        return decoded['detail'] as String;
      }
    } on FormatException {
      // Gunakan pesan cadangan bila respons backend bukan JSON.
    }
    return '$fallback (${response.statusCode})';
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
