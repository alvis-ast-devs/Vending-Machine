import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vending_ui/core/api_service.dart';
import 'package:vending_ui/core/local_data_service.dart';
import 'package:vending_ui/core/serial_bridge.dart';

/// SerialBridge yang selalu gagal — mensimulasikan ESP32/IR yang tidak
/// merespons (port tidak terbuka, ACK tidak pernah datang, dsb).
class _FailingSerialBridge extends SerialBridge {
  _FailingSerialBridge() : super(portName: '', baudRate: 0);

  @override
  void sendDropCommand(String slotCode) {
    throw SerialBridgeError('gagal kirim perintah');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('vending_api_test_');
    LocalDataService.instance.resetForTesting();
    await LocalDataService.instance.init(customBasePath: tempDir.path);
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {
      // Folder temp mungkin sudah terhapus sebagian; abaikan.
    }
  });

  test('stok berkurang walau perintah drop serial gagal', () async {
    final api = ApiService();
    api.setSerialBridge(_FailingSerialBridge());

    await api.submitPaymentSuccess(
      transactionId: 'TRX-TEST',
      slotCodes: const ['01', '02'],
    );

    final products = await LocalDataService.instance.loadProducts();
    expect(products.firstWhere((p) => p.slotCode == '01').stock, 9);
    expect(products.firstWhere((p) => p.slotCode == '02').stock, 9);
  });
}