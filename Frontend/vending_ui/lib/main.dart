import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:vending_ui/core/api_service.dart';
import 'package:vending_ui/core/app_config.dart';
import 'package:vending_ui/core/app_theme.dart';
import 'package:vending_ui/core/vending_controller.dart';
import 'package:vending_ui/core/websocket_service.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();

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

  runApp(const VendingApp());
}

class VendingApp extends StatefulWidget {
  final ApiService? apiService;
  final MachineEventSource? eventSource;
  final bool hardwareEnabled;
  final Duration homeIdleDuration;
  final Duration menuIdleDuration;

  const VendingApp({
    super.key,
    this.apiService,
    this.eventSource,
    this.hardwareEnabled = AppConfig.hardwareEnabled,
    this.homeIdleDuration = AppConfig.homeIdleDuration,
    this.menuIdleDuration = AppConfig.menuIdleDuration,
  });

  @override
  State<VendingApp> createState() => _VendingAppState();
}

class _VendingAppState extends State<VendingApp> {
  late final ApiService _apiService;

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();
    unawaited(_loadTheme());
  }

  Future<void> _loadTheme() async {
    try {
      final palette = await _apiService.fetchTheme();
      if (!mounted) return;
      setState(() => VendingColors.apply(palette));
    } on ApiException {
      // Palet bawaan tetap dipakai saat backend belum dapat dihubungi.
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Vending Machine',
      debugShowCheckedModeBanner: false,
      theme: VendingTheme.data,
      home: VendingController(
        apiService: _apiService,
        eventSource: widget.eventSource,
        hardwareEnabled: widget.hardwareEnabled,
        homeIdleDuration: widget.homeIdleDuration,
        menuIdleDuration: widget.menuIdleDuration,
        onThemeUpdated: _loadTheme,
      ),
    );
  }
}
