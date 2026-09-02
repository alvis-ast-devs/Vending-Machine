import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:vending_ui/core/api_service.dart';
import 'package:vending_ui/core/app_config.dart';
import 'package:vending_ui/core/app_theme.dart';
import 'package:vending_ui/core/event_bus.dart';
import 'package:vending_ui/core/theme_settings.dart';
import 'package:vending_ui/core/local_data_service.dart';
import 'package:vending_ui/core/serial_bridge.dart';
import 'package:vending_ui/core/vending_controller.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();

  // Initialize local data service.
  final dataService = LocalDataService.instance;
  await dataService.init();

  final windowOptions = WindowOptions(
    size: AppConfig.initialWindowSize,
    minimumSize: AppConfig.minimumWindowSize,
    center: true,
    backgroundColor: VendingColors.background,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    title: 'Smart Vending Machine',
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAspectRatio(AppConfig.portraitAspectRatio);
    await windowManager.show();
    await windowManager.focus();
  });

  // Set up serial bridge for ESP32 communication.
  final serialBridge = SerialBridge(
    portName: AppConfig.hardwareEnabled ? AppConfig.serialPort : '',
    baudRate: AppConfig.serialBaudRate,
  );

  // Wire the serial bridge to publish events to the local event bus.
  if (AppConfig.hardwareEnabled) {
    serialBridge.startListening();
  }

  runApp(VendingApp(serialBridge: serialBridge));
}

class VendingApp extends StatefulWidget {
  final SerialBridge serialBridge;

  const VendingApp({super.key, required this.serialBridge});

  @override
  State<VendingApp> createState() => _VendingAppState();
}

class _VendingAppState extends State<VendingApp> {
  late final ApiService _apiService;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _apiService.setSerialBridge(widget.serialBridge);
    unawaited(_loadTheme());
  }

  Future<void> _loadTheme() async {
    if (!mounted) return;
    setState(() => VendingColors.apply(VendingPalette.defaults));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Vending Machine',
      debugShowCheckedModeBanner: false,
      theme: VendingTheme.data,
      home: VendingController(
        apiService: _apiService,
        eventSource: eventBus,
        hardwareEnabled: AppConfig.hardwareEnabled,
        onThemeUpdated: _loadTheme,
      ),
    );
  }
}
