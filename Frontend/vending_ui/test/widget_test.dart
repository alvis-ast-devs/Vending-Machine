import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vending_ui/core/api_service.dart';
import 'package:vending_ui/core/app_config.dart';
import 'package:vending_ui/core/app_theme.dart';
import 'package:vending_ui/core/app_utils.dart';
import 'package:vending_ui/core/product_model.dart';
import 'package:vending_ui/core/theme_settings.dart';
import 'package:vending_ui/core/websocket_service.dart';
import 'package:vending_ui/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    VendingColors.apply(VendingPalette.defaults);
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
      ..physicalSize = const Size(540, 960)
      ..devicePixelRatio = 1;
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });

  testWidgets('alur backend lengkap kembali ke HomeScreen', (tester) async {
    final eventSource = FakeMachineEventSource();
    final apiService = buildMockApiService();

    await tester.pumpWidget(
      VendingApp(
        apiService: apiService,
        eventSource: eventSource,
        hardwareEnabled: true,
      ),
    );
    expect(find.text('Selamat Datang'), findsOneWidget);

    eventSource.emit(const MachineEvent(type: 'USER_DETECTED', data: {}));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Selamat Datang'), findsOneWidget);

    await tester.tap(find.text('Lanjut Belanja'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('PILIH PRODUK'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('keypad-code'))).data,
      '__',
    );
    expect(
      find.text('ACCEPT: tambah/bayar  ·  DECLINED: kurangi'),
      findsOneWidget,
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
    expect(find.text('Rp 8.000'), findsWidgets);

    eventSource.emit(const MachineEvent(type: 'KEYPAD_ACCEPT', data: {}));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('PEMBAYARAN'), findsOneWidget);
    expect(find.text('01:00'), findsOneWidget);
    expect(find.text('Menunggu konfirmasi PAYMENT_SUCCESS'), findsOneWidget);

    eventSource.emit(
      const MachineEvent(
        type: 'PAYMENT_SUCCESS',
        data: {
          'transaction_id': 'TRX-001',
          'slot_codes': ['01'],
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Terima Kasih!'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Selamat Datang'), findsOneWidget);
  });

  testWidgets('katalog tidak overflow pada viewport landscape', (tester) async {
    TestWidgetsFlutterBinding
        .instance
        .platformDispatcher
        .views
        .first
        .physicalSize = const Size(
      800,
      600,
    );
    final eventSource = FakeMachineEventSource();

    await tester.pumpWidget(
      VendingApp(
        apiService: buildMockApiService(),
        eventSource: eventSource,
        hardwareEnabled: true,
      ),
    );
    eventSource.emit(const MachineEvent(type: 'USER_DETECTED', data: {}));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Lanjut Belanja'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('PILIH PRODUK'), findsOneWidget);
    expect(find.byKey(const ValueKey('slot-55')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('badge mengikuti jumlah produk yang dipilih', (tester) async {
    final eventSource = FakeMachineEventSource();

    await tester.pumpWidget(
      VendingApp(
        apiService: buildMockApiService(),
        eventSource: eventSource,
        hardwareEnabled: true,
      ),
    );
    await tester.tap(find.text('Lanjut Belanja'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('slot-01')));
    await tester.tap(find.byKey(const ValueKey('slot-01')));
    await tester.pump();
    expect(find.text('×2'), findsOneWidget);

    eventSource.emit(
      const MachineEvent(type: 'KEYPAD_DIGIT', data: {'digit': '0'}),
    );
    eventSource.emit(
      const MachineEvent(type: 'KEYPAD_DIGIT', data: {'digit': '1'}),
    );
    eventSource.emit(const MachineEvent(type: 'KEYPAD_CANCEL', data: {}));
    await tester.pump();
    expect(find.text('×1'), findsOneWidget);

    eventSource.emit(
      const MachineEvent(type: 'KEYPAD_DIGIT', data: {'digit': '0'}),
    );
    eventSource.emit(
      const MachineEvent(type: 'KEYPAD_DIGIT', data: {'digit': '1'}),
    );
    eventSource.emit(const MachineEvent(type: 'KEYPAD_CANCEL', data: {}));
    await tester.pump();
    expect(find.byKey(const ValueKey('cart-quantity-01')), findsNothing);
  });

  testWidgets(
    'keypad memilih dan membatalkan produk tanpa mematikan sentuhan',
    (tester) async {
      final eventSource = FakeMachineEventSource();

      await tester.pumpWidget(
        VendingApp(
          apiService: buildMockApiService(),
          eventSource: eventSource,
          hardwareEnabled: true,
        ),
      );

      eventSource.emit(
        const MachineEvent(type: 'KEYPAD_DIGIT', data: {'digit': '0'}),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('PILIH PRODUK'), findsOneWidget);

      eventSource.emit(
        const MachineEvent(type: 'KEYPAD_DIGIT', data: {'digit': '1'}),
      );
      eventSource.emit(const MachineEvent(type: 'KEYPAD_ACCEPT', data: {}));
      await tester.pump();
      expect(find.byKey(const ValueKey('cart-quantity-01')), findsOneWidget);

      eventSource.emit(
        const MachineEvent(type: 'KEYPAD_DIGIT', data: {'digit': '0'}),
      );
      eventSource.emit(
        const MachineEvent(type: 'KEYPAD_DIGIT', data: {'digit': '1'}),
      );
      eventSource.emit(const MachineEvent(type: 'KEYPAD_CANCEL', data: {}));
      await tester.pump();
      expect(find.byKey(const ValueKey('cart-quantity-01')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('slot-01')));
      await tester.pump();
      expect(find.byKey(const ValueKey('cart-quantity-01')), findsOneWidget);

      eventSource.emit(const MachineEvent(type: 'KEYPAD_ACCEPT', data: {}));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('PEMBAYARAN'), findsOneWidget);

      eventSource.emit(const MachineEvent(type: 'KEYPAD_CANCEL', data: {}));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Selamat Datang'), findsOneWidget);
    },
  );

  testWidgets('keyboard mengirim angka, accept, cancel, dan declined', (
    tester,
  ) async {
    final paymentRequests = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      VendingApp(
        apiService: buildMockApiService(paymentRequests: paymentRequests),
        eventSource: FakeMachineEventSource(),
        hardwareEnabled: true,
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
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
    expect(find.text('PEMBAYARAN'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Terima Kasih!'), findsOneWidget);
    expect(paymentRequests, hasLength(1));
    expect(paymentRequests.single['slot_codes'], ['01']);
    expect(paymentRequests.single['transaction_id'], startsWith('TRX-'));
  });

  testWidgets('mode tanpa hardware melewati deteksi kamera', (tester) async {
    await tester.pumpWidget(
      VendingApp(
        apiService: buildMockApiService(),
        eventSource: FakeMachineEventSource(),
        hardwareEnabled: false,
      ),
    );

    expect(find.text('MENUNGGU DETEKSI KAMERA'), findsNothing);
    expect(find.text('Selamat Datang'), findsOneWidget);
  });

  testWidgets('mode tanpa hardware menyediakan pembayaran simulasi', (
    tester,
  ) async {
    final paymentRequests = <Map<String, dynamic>>[];
    final eventSource = FakeMachineEventSource();
    await tester.pumpWidget(
      VendingApp(
        apiService: buildMockApiService(paymentRequests: paymentRequests),
        eventSource: eventSource,
        hardwareEnabled: false,
      ),
    );

    await tester.tap(find.text('Lanjut Belanja'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('slot-01')));
    await tester.pump();
    eventSource.emit(const MachineEvent(type: 'KEYPAD_ACCEPT', data: {}));
    await tester.pump(const Duration(milliseconds: 400));

    final simulatePayment = find.text('SIMULASIKAN PEMBAYARAN BERHASIL');
    expect(simulatePayment, findsOneWidget);
    await tester.tap(simulatePayment);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Terima Kasih!'), findsOneWidget);
    expect(paymentRequests.single['slot_codes'], ['01']);
  });

  testWidgets('tanpa iklan layar tetap di Home setelah idle', (tester) async {
    await tester.pumpWidget(
      VendingApp(
        apiService: buildMockApiService(),
        eventSource: FakeMachineEventSource(),
        hardwareEnabled: true,
        homeIdleDuration: const Duration(milliseconds: 10),
      ),
    );

    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();
    expect(find.text('Selamat Datang'), findsOneWidget);
    expect(find.text('DEKATI MESIN UNTUK MULAI'), findsNothing);
  });

  testWidgets('iklan tampil setelah Home idle', (tester) async {
    await tester.pumpWidget(
      VendingApp(
        apiService: buildMockApiService(
          mediaCatalog: {
            'ads': [
              {
                'id': 1,
                'kind': 'ad',
                'media_type': 'image',
                'original_name': 'promo.jpg',
                'mime_type': 'image/jpeg',
                'url': '/media/promo.jpg',
              },
            ],
            'tutorial': null,
          },
        ),
        eventSource: FakeMachineEventSource(),
        hardwareEnabled: true,
        homeIdleDuration: const Duration(milliseconds: 10),
      ),
    );

    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('DEKATI MESIN UNTUK MULAI'), findsOneWidget);
  });

  testWidgets('tutorial selesai langsung membuka Menu', (tester) async {
    final eventSource = FakeMachineEventSource();
    await tester.pumpWidget(
      VendingApp(
        apiService: buildMockApiService(
          mediaCatalog: {
            'ads': [],
            'tutorial': {
              'id': 3,
              'kind': 'tutorial',
              'media_type': 'video',
              'original_name': 'tutorial.mp4',
              'mime_type': 'video/mp4',
              'url': '/media/tutorial.mp4',
            },
            'homescreen': null,
          },
        ),
        eventSource: eventSource,
        hardwareEnabled: true,
      ),
    );

    await tester.pump();
    eventSource.emit(const MachineEvent(type: 'USER_DETECTED', data: {}));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    eventSource.emit(const MachineEvent(type: 'KEYPAD_ACCEPT', data: {}));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('PILIH PRODUK'), findsOneWidget);
    expect(find.text('Selamat Datang'), findsNothing);
  });

  testWidgets('Menu idle kembali ke Home lalu Home berganti menjadi iklan', (
    tester,
  ) async {
    await tester.pumpWidget(
      VendingApp(
        apiService: buildMockApiService(
          mediaCatalog: {
            'ads': [
              {
                'id': 4,
                'kind': 'ad',
                'media_type': 'image',
                'original_name': 'promo-idle.jpg',
                'mime_type': 'image/jpeg',
                'url': '/media/promo-idle.jpg',
              },
            ],
            'tutorial': null,
            'homescreen': null,
          },
        ),
        eventSource: FakeMachineEventSource(),
        hardwareEnabled: true,
        menuIdleDuration: const Duration(seconds: 1),
        homeIdleDuration: const Duration(milliseconds: 500),
      ),
    );

    await tester.tap(find.text('Lanjut Belanja'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('PILIH PRODUK'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1001));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Selamat Datang'), findsOneWidget);
    expect(find.text('DEKATI MESIN UNTUK MULAI'), findsNothing);

    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Selamat Datang'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 51));
    await tester.pump();
    expect(find.text('DEKATI MESIN UNTUK MULAI'), findsOneWidget);
  });

  testWidgets(
    'media homescreen menggantikan Home bawaan dan tetap interaktif',
    (tester) async {
      await tester.pumpWidget(
        VendingApp(
          apiService: buildMockApiService(
            mediaCatalog: {
              'ads': [],
              'tutorial': null,
              'homescreen': {
                'id': 2,
                'kind': 'homescreen',
                'media_type': 'image',
                'original_name': 'home.jpg',
                'mime_type': 'image/jpeg',
                'url': '/media/home.jpg',
              },
            },
          ),
          eventSource: FakeMachineEventSource(),
          hardwareEnabled: true,
        ),
      );

      await tester.pump();
      expect(find.byKey(const ValueKey('homescreen-image-2')), findsOneWidget);
      expect(find.text('Selamat Datang'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('homescreen-touch-target')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('PILIH PRODUK'), findsOneWidget);
    },
  );

  test('MachineEvent membaca payload JSON backend', () {
    final event = MachineEvent.fromMessage(
      '{"type":"PAYMENT_SUCCESS","data":{"slot_codes":["11"]}}',
    );
    expect(event.type, 'PAYMENT_SUCCESS');
    expect(event.data['slot_codes'], ['11']);
  });

  testWidgets('palet backend diterapkan dan dimuat ulang lewat event tema', (
    tester,
  ) async {
    final eventSource = FakeMachineEventSource();
    final theme = <String, dynamic>{
      'background': '#111827',
      'surface': '#1F2937',
      'surface_soft': '#374151',
      'text_primary': '#F9FAFB',
      'text_muted': '#D1D5DB',
      'accent': '#22C55E',
      'warning': '#F59E0B',
      'danger': '#EF4444',
    };

    await tester.pumpWidget(
      VendingApp(
        apiService: buildMockApiService(theme: theme),
        eventSource: eventSource,
      ),
    );
    await tester.pump();
    expect(VendingColors.accent, const Color(0xFF22C55E));

    theme['accent'] = '#A855F7';
    eventSource.emit(const MachineEvent(type: 'THEME_UPDATED', data: {}));
    await tester.pump();
    await tester.pump();
    expect(VendingColors.accent, const Color(0xFFA855F7));
  });

  test('warna permukaan diturunkan dari latar dan mengabaikan nilai lama', () {
    final palette = VendingPalette.fromJson({
      'background': '#101214',
      'surface': '#FFFFFF',
      'surface_soft': '#0000FF',
    });

    expect(palette.surface, const Color(0xFF1A1D21));
    expect(palette.surfaceSoft, const Color(0xFF24282E));
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
}

ApiService buildMockApiService({
  Map<String, dynamic>? mediaCatalog,
  List<Map<String, dynamic>>? paymentRequests,
  Map<String, dynamic>? theme,
}) {
  final products = physicalSlotRows
      .expand((row) => row)
      .toList()
      .asMap()
      .entries
      .map(
        (entry) => {
          'id': entry.key + 1,
          'name': entry.key < 40
              ? 'Snack ${(entry.key + 1).toString().padLeft(2, '0')}'
              : 'Produk Besar ${(entry.key - 39).toString().padLeft(2, '0')}',
          'price': entry.key < 40
              ? 8000 + ((entry.key % 4) * 2000)
              : 20000 + (((entry.key - 40) % 5) * 5000),
          'slot_code': entry.value,
          'stock': 3,
          'is_active': true,
        },
      )
      .toList();

  return ApiService(
    client: MockClient((request) async {
      if (request.url.path == '/api/media') {
        return http.Response(
          jsonEncode(mediaCatalog ?? {'ads': [], 'tutorial': null}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (request.url.path == '/api/theme') {
        return http.Response(
          jsonEncode(theme ?? const <String, dynamic>{}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (request.url.path == '/api/events/payment-success') {
        final payload = Map<String, dynamic>.from(
          jsonDecode(request.body) as Map,
        );
        paymentRequests?.add(payload);
        return http.Response(
          jsonEncode({'type': 'PAYMENT_SUCCESS', 'delivered_to': 0}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      expect(request.url.path, '/api/products');
      return http.Response(
        jsonEncode(products),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
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
