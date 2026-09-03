import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vending_ui/core/api_service.dart';
import 'package:vending_ui/core/app_config.dart';
import 'package:vending_ui/core/app_theme.dart';
import 'package:vending_ui/core/event_bus.dart';
import 'package:vending_ui/core/local_data_service.dart';
import 'package:vending_ui/core/product_model.dart';
import 'package:vending_ui/core/theme_settings.dart';
import 'package:vending_ui/core/vending_controller.dart';
import 'package:vending_ui/core/voice_recognition_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    VendingColors.apply(VendingPalette.defaults);
    tempDir = Directory.systemTemp.createTempSync('vending_ui_test_');
    LocalDataService.instance.resetForTesting();
    await LocalDataService.instance.init(customBasePath: tempDir.path);
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
      ..physicalSize = const Size(540, 960)
      ..devicePixelRatio = 1;
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {
      // Folder temp mungkin sudah terhapus sebagian; abaikan.
    }
  });

  /// Flush microtask (data lokal kini selesai via microtask, tanpa IO nyata)
  /// lalu render dua frame: frame pertama memproses setState dari event,
  /// frame kedua menampilkan hasil rebuild.
  Future<void> settleIo(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  Future<FakeMachineEventSource> pumpVending(
    WidgetTester tester, {
    bool hardwareEnabled = true,
    Duration homeIdleDuration = const Duration(seconds: 30),
    Duration menuIdleDuration = const Duration(seconds: 30),
  }) async {
    final eventSource = FakeMachineEventSource();
    await tester.pumpWidget(
      MaterialApp(
        theme: VendingTheme.data,
        home: VendingController(
          apiService: ApiService(),
          eventSource: eventSource,
          hardwareEnabled: hardwareEnabled,
          homeIdleDuration: homeIdleDuration,
          menuIdleDuration: menuIdleDuration,
        ),
      ),
    );
    await settleIo(tester);
    return eventSource;
  }

  Future<void> goToMenu(WidgetTester tester) async {
    await tester.tap(find.text('Lanjut Belanja'));
    await tester.pump(const Duration(milliseconds: 400));
    await settleIo(tester);
  }

  Future<void> enterAdmin(
    WidgetTester tester,
    FakeMachineEventSource source,
  ) async {
    for (final digit in AppConfig.adminCode.split('')) {
      source.emit(MachineEvent(type: 'KEYPAD_DIGIT', data: {'digit': digit}));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));
    await settleIo(tester);
  }

  Future<void> unmountApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('alur belanja lengkap kembali ke HomeScreen', (tester) async {
    final source = await pumpVending(tester);
    expect(find.text('Selamat Datang'), findsOneWidget);

    await goToMenu(tester);
    expect(find.text('PILIH PRODUK'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('keypad-code'))).data,
      '__',
    );

    final slotTiles = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('slot-');
    });
    expect(slotTiles, findsNWidgets(50));
    expect(find.byKey(const ValueKey('slot-01')), findsOneWidget);
    expect(find.byKey(const ValueKey('slot-55')), findsOneWidget);
    expect(find.text('01'), findsOneWidget);
    expect(find.text('51'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('slot-01')));
    await tester.pump();
    expect(find.byKey(const ValueKey('cart-quantity-01')), findsOneWidget);
    expect(find.text('×1'), findsOneWidget);
    expect(find.text('Rp 10.000'), findsWidgets);

    source.emit(const MachineEvent(type: 'KEYPAD_ACCEPT', data: {}));
    await tester.pump(const Duration(milliseconds: 400));
    await settleIo(tester);
    expect(find.text('PEMBAYARAN'), findsOneWidget);
    expect(find.text('01:00'), findsOneWidget);
    expect(find.textContaining('Sisa:'), findsOneWidget);

    // Pembayaran sukses (tanpa menunggu IR) -> status diterima tampil
    // beberapa detik, lalu halaman "Terima Kasih" 5 detik, lalu home.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pump(const Duration(milliseconds: 400));
    await settleIo(tester);
    expect(find.text('PEMBAYARAN'), findsOneWidget);
    expect(
      find.textContaining('Pembayaran berhasil diterima'),
      findsOneWidget,
    );

    await tester.pump(AppConfig.paymentSuccessDuration);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Terima Kasih!'), findsOneWidget);

    final productsAfter = await LocalDataService.instance.loadProducts();
    expect(productsAfter.firstWhere((p) => p.slotCode == '01').stock, 9);

    await tester.pump(AppConfig.finishDuration);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Selamat Datang'), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('katalog tidak overflow pada viewport landscape', (tester) async {
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
      ..physicalSize = const Size(800, 600)
      ..devicePixelRatio = 1;
    await pumpVending(tester);
    await goToMenu(tester);

    expect(find.text('PILIH PRODUK'), findsOneWidget);
    expect(find.byKey(const ValueKey('slot-55')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await unmountApp(tester);
  });

  testWidgets('badge mengikuti jumlah produk yang dipilih', (tester) async {
    final source = await pumpVending(tester);
    await goToMenu(tester);

    await tester.tap(find.byKey(const ValueKey('slot-01')));
    await tester.tap(find.byKey(const ValueKey('slot-01')));
    await tester.pump();
    expect(find.text('×2'), findsOneWidget);

    source.emit(const MachineEvent(type: 'KEYPAD_DIGIT', data: {'digit': '0'}));
    await tester.pump();
    source.emit(const MachineEvent(type: 'KEYPAD_DIGIT', data: {'digit': '1'}));
    await tester.pump();
    source.emit(const MachineEvent(type: 'KEYPAD_CANCEL', data: {}));
    await tester.pump();
    expect(find.text('×1'), findsOneWidget);

    source.emit(const MachineEvent(type: 'KEYPAD_DIGIT', data: {'digit': '0'}));
    await tester.pump();
    source.emit(const MachineEvent(type: 'KEYPAD_DIGIT', data: {'digit': '1'}));
    await tester.pump();
    source.emit(const MachineEvent(type: 'KEYPAD_CANCEL', data: {}));
    await tester.pump();
    expect(find.byKey(const ValueKey('cart-quantity-01')), findsNothing);

    await unmountApp(tester);
  });

  testWidgets(
    'keypad memilih dan membatalkan produk tanpa mematikan sentuhan',
    (tester) async {
      final source = await pumpVending(tester);

      source.emit(
        const MachineEvent(type: 'KEYPAD_DIGIT', data: {'digit': '0'}),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await settleIo(tester);
      expect(find.text('PILIH PRODUK'), findsOneWidget);

      source.emit(
        const MachineEvent(type: 'KEYPAD_DIGIT', data: {'digit': '1'}),
      );
      source.emit(const MachineEvent(type: 'KEYPAD_ACCEPT', data: {}));
      await tester.pump();
      expect(find.byKey(const ValueKey('cart-quantity-01')), findsOneWidget);

      source.emit(
        const MachineEvent(type: 'KEYPAD_DIGIT', data: {'digit': '0'}),
      );
      await tester.pump();
      source.emit(
        const MachineEvent(type: 'KEYPAD_DIGIT', data: {'digit': '1'}),
      );
      await tester.pump();
      source.emit(const MachineEvent(type: 'KEYPAD_CANCEL', data: {}));
      await tester.pump();
      expect(find.byKey(const ValueKey('cart-quantity-01')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('slot-01')));
      await tester.pump();
      expect(find.byKey(const ValueKey('cart-quantity-01')), findsOneWidget);

      source.emit(const MachineEvent(type: 'KEYPAD_ACCEPT', data: {}));
      await tester.pump(const Duration(milliseconds: 400));
      await settleIo(tester);
      expect(find.text('PEMBAYARAN'), findsOneWidget);

      source.emit(const MachineEvent(type: 'KEYPAD_CANCEL', data: {}));
      await tester.pump(const Duration(milliseconds: 400));
      await settleIo(tester);
      expect(find.text('Selamat Datang'), findsOneWidget);

      await unmountApp(tester);
    },
  );

  testWidgets('keyboard mengirim angka, accept, cancel, dan declined', (
    tester,
  ) async {
    await pumpVending(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.pump(const Duration(milliseconds: 400));
    await settleIo(tester);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('keypad-code'))).data,
      '0_',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('keypad-code'))).data,
      '01',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byKey(const ValueKey('cart-quantity-01')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('keypad-code'))).data,
      '__',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('keypad-code'))).data,
      '05',
    );
    expect(tester.takeException(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(find.byKey(const ValueKey('cart-quantity-01')), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byKey(const ValueKey('cart-quantity-01')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pump();
    expect(find.byKey(const ValueKey('cart-quantity-01')), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byKey(const ValueKey('cart-quantity-01')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 400));
    await settleIo(tester);
    expect(find.text('PEMBAYARAN'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pump(const Duration(milliseconds: 400));
    await settleIo(tester);
    expect(find.text('PEMBAYARAN'), findsOneWidget);
    expect(
      find.textContaining('Pembayaran berhasil diterima'),
      findsOneWidget,
    );

    await tester.pump(AppConfig.paymentSuccessDuration);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Terima Kasih!'), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('mode tanpa hardware tetap menampilkan home', (tester) async {
    await pumpVending(tester, hardwareEnabled: false);

    expect(find.text('Selamat Datang'), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('pembayaran memulai gateway nominal suara', (tester) async {
    final source = await pumpVending(tester, hardwareEnabled: false);
    await goToMenu(tester);

    await tester.tap(find.byKey(const ValueKey('slot-01')));
    await tester.pump();
    source.emit(const MachineEvent(type: 'KEYPAD_ACCEPT', data: {}));
    await tester.pump(const Duration(milliseconds: 400));
    await settleIo(tester);

    expect(find.text('PEMBAYARAN'), findsOneWidget);
    // Status mendengarkan muncul hanya jika sesi suara berjalan.
    expect(find.textContaining('Sisa:'), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('Menu idle kembali ke Home', (tester) async {
    await pumpVending(tester, menuIdleDuration: const Duration(seconds: 1));
    await goToMenu(tester);
    expect(find.text('PILIH PRODUK'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1001));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Selamat Datang'), findsOneWidget);

    await unmountApp(tester);
  });

  // ─── Admin Mode ──────────────────────────────────────────────────────────

  testWidgets('kode rahasia admin membuka dashboard admin', (tester) async {
    final source = await pumpVending(tester);
    await goToMenu(tester);

    await enterAdmin(tester, source);

    expect(find.text('ADMIN — ISI STOK'), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-slot-01')), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-slot-05')), findsOneWidget);
    expect(
      find.text('ACCEPT: isi stok penuh  ·  CANCEL: kembali'),
      findsOneWidget,
    );

    await unmountApp(tester);
  });

  testWidgets('ACCEPT mengisi stok slot hingga penuh', (tester) async {
    // Kurangi stok slot 05 terlebih dahulu supaya pengisian bisa diverifikasi.
    for (var i = 0; i < 3; i++) {
      await LocalDataService.instance.reduceStock('05');
    }
    final productsBefore = await LocalDataService.instance.loadProducts();
    expect(productsBefore.firstWhere((p) => p.slotCode == '05').stock, 7);

    final source = await pumpVending(tester);
    await goToMenu(tester);
    await enterAdmin(tester, source);

    source.emit(const MachineEvent(type: 'KEYPAD_DIGIT', data: {'digit': '0'}));
    await tester.pump();
    source.emit(const MachineEvent(type: 'KEYPAD_DIGIT', data: {'digit': '5'}));
    await settleIo(tester);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('admin-keypad-code'))).data,
      '05',
    );

    source.emit(const MachineEvent(type: 'KEYPAD_ACCEPT', data: {}));
    await tester.pump();
    await settleIo(tester);

    expect(find.text('Slot 05 diisi penuh (10) ✓'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('admin-slot-05')),
        matching: find.text('10/10'),
      ),
      findsOneWidget,
    );

    final productsAfter = await LocalDataService.instance.loadProducts();
    expect(productsAfter.firstWhere((p) => p.slotCode == '05').stock, 10);

    await unmountApp(tester);
  });

  testWidgets('CANCEL menutup dashboard admin kembali ke menu', (tester) async {
    final source = await pumpVending(tester);
    await goToMenu(tester);
    await enterAdmin(tester, source);
    expect(find.text('ADMIN — ISI STOK'), findsOneWidget);

    // CANCEL dengan kode pending -> hanya menghapus input, tetap di admin.
    source.emit(const MachineEvent(type: 'KEYPAD_DIGIT', data: {'digit': '0'}));
    await tester.pump();
    source.emit(const MachineEvent(type: 'KEYPAD_DIGIT', data: {'digit': '5'}));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('admin-keypad-code'))).data,
      '05',
    );
    source.emit(const MachineEvent(type: 'KEYPAD_CANCEL', data: {}));
    await settleIo(tester);
    expect(find.text('ADMIN — ISI STOK'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('admin-keypad-code'))).data,
      '__',
    );

    // CANCEL sekali lagi -> kembali ke menu biasa.
    source.emit(const MachineEvent(type: 'KEYPAD_CANCEL', data: {}));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('PILIH PRODUK'), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('kode rahasia salah tidak membuka dashboard admin', (
    tester,
  ) async {
    final source = await pumpVending(tester);
    await goToMenu(tester);

    for (final digit in ['1', '2', '3', '4']) {
      source.emit(MachineEvent(type: 'KEYPAD_DIGIT', data: {'digit': digit}));
      await tester.pump();
    }
    expect(find.text('PILIH PRODUK'), findsOneWidget);
    expect(find.text('ADMIN — ISI STOK'), findsNothing);

    // Alur pelanggan tetap normal: 01 + ACCEPT masuk keranjang.
    source.emit(const MachineEvent(type: 'KEYPAD_DIGIT', data: {'digit': '0'}));
    await tester.pump();
    source.emit(const MachineEvent(type: 'KEYPAD_DIGIT', data: {'digit': '1'}));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('keypad-code'))).data,
      '01',
    );
    source.emit(const MachineEvent(type: 'KEYPAD_ACCEPT', data: {}));
    await tester.pump();
    expect(find.byKey(const ValueKey('cart-quantity-01')), findsOneWidget);

    await unmountApp(tester);
  });

  test('Product membaca foto backend dan mendukung gambar default', () {
    final withImage = Product.fromJson({
      'id': 1,
      'name': 'Snack 01',
      'price': 8000,
      'slot_code': '01',
      'stock': 10,
      'is_active': true,
      'image_url': '/media/snack-01.png',
    }, backendUrl: 'http://127.0.0.1:8000');
    final withoutImage = Product.fromJson({
      'id': 2,
      'name': 'Snack 02',
      'price': 10000,
      'slot_code': '02',
      'stock': 10,
      'is_active': true,
      'image_url': null,
    }, backendUrl: 'http://127.0.0.1:8000');

    expect(withImage.imageUrl, 'http://127.0.0.1:8000/media/snack-01.png');
    expect(withoutImage.imageUrl, isNull);
  });

  testWidgets('hasil suara Python memperbarui halaman pembayaran', (
    tester,
  ) async {
    final api = ApiService();
    await tester.pumpWidget(
      MaterialApp(
        theme: VendingTheme.data,
        home: VendingController(
          apiService: api,
          eventSource: eventBus,
          hardwareEnabled: false,
        ),
      ),
    );
    await settleIo(tester);

    await goToMenu(tester);

    // Pilih produk 01 (Rp 10.000) lalu buka pembayaran.
    await tester.tap(find.byKey(const ValueKey('slot-01')));
    await tester.pump();
    eventBus.publish(const MachineEvent(type: 'KEYPAD_ACCEPT', data: {}));
    await tester.pump(const Duration(milliseconds: 400));
    await settleIo(tester);
    expect(find.text('PEMBAYARAN'), findsOneWidget);

    // Sebelum ada nominal: sisa = total.
    expect(find.textContaining('Sisa: Rp 10.000'), findsOneWidget);

    // Python mengenali "lima ribu".
    api.voiceBridge.emitResultForTesting(
      const VoiceRecognitionResult(transcript: 'lima ribu', amount: 5000),
    );
    await tester.pump();
    expect(find.textContaining('Bayar: Rp 5.000'), findsOneWidget);
    expect(find.textContaining('Sisa: Rp 5.000'), findsOneWidget);

    // Python mengenali "lima ribu" lagi -> lunas -> status diterima tampil
    // beberapa detik, lalu "Terima Kasih" 5 detik, lalu kembali home.
    api.voiceBridge.emitResultForTesting(
      const VoiceRecognitionResult(transcript: 'lima ribu', amount: 5000),
    );
    await tester.pump();
    await settleIo(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('PEMBAYARAN'), findsOneWidget);
    expect(
      find.textContaining('Pembayaran berhasil diterima'),
      findsOneWidget,
    );

    await tester.pump(AppConfig.paymentSuccessDuration);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Terima Kasih!'), findsOneWidget);

    final productsAfter = await LocalDataService.instance.loadProducts();
    expect(productsAfter.firstWhere((p) => p.slotCode == '01').stock, 9);

    await tester.pump(AppConfig.finishDuration);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Selamat Datang'), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('hasil suara tanpa nominal tidak mengubah pembayaran', (
    tester,
  ) async {
    final api = ApiService();
    await tester.pumpWidget(
      MaterialApp(
        theme: VendingTheme.data,
        home: VendingController(
          apiService: api,
          eventSource: eventBus,
          hardwareEnabled: false,
        ),
      ),
    );
    await settleIo(tester);

    await goToMenu(tester);
    await tester.tap(find.byKey(const ValueKey('slot-01')));
    await tester.pump();
    eventBus.publish(const MachineEvent(type: 'KEYPAD_ACCEPT', data: {}));
    await tester.pump(const Duration(milliseconds: 400));
    await settleIo(tester);
    expect(find.text('PEMBAYARAN'), findsOneWidget);

    api.voiceBridge.emitResultForTesting(
      const VoiceRecognitionResult(transcript: null, amount: 0),
    );
    await tester.pump();
    // Tetap di halaman pembayaran dan nominal tidak berubah.
    expect(find.text('PEMBAYARAN'), findsOneWidget);
    expect(find.textContaining('Bayar: Rp 0'), findsOneWidget);
    expect(find.textContaining('Sisa: Rp 10.000'), findsOneWidget);

    await unmountApp(tester);
  });
}

class FakeMachineEventSource implements MachineEventSource {
  void Function(MachineEvent event)? _onEvent;
  void Function(MachineSocketStatus status)? _onStatusChanged;

  @override
  void start({
    required void Function(MachineEvent event) onEvent,
    required void Function(MachineSocketStatus status) onStatusChanged,
  }) {
    _onEvent = onEvent;
    _onStatusChanged = onStatusChanged;
    _onStatusChanged?.call(MachineSocketStatus.connected);
  }

  void emit(MachineEvent event) => _onEvent?.call(event);

  @override
  void dispose() {
    _onEvent = null;
    _onStatusChanged = null;
  }
}