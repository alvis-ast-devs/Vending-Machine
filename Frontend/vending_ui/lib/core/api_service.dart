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

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
