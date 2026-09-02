import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vending_ui/core/api_service.dart';
import 'package:vending_ui/core/app_config.dart';
import 'package:vending_ui/core/app_theme.dart';
import 'package:vending_ui/core/event_bus.dart';
import 'package:vending_ui/core/media_asset.dart';
import 'package:vending_ui/feature/ad_screen.dart';
import 'package:vending_ui/feature/finish_screen.dart';
import 'package:vending_ui/feature/home_screen.dart';
import 'package:vending_ui/feature/menu_screen.dart';
import 'package:vending_ui/feature/payment_screen.dart';
import 'package:vending_ui/feature/tutorial_screen.dart';

class VendingController extends StatefulWidget {
  final ApiService? apiService;
  final MachineEventSource? eventSource;
  final bool hardwareEnabled;
  final Duration homeIdleDuration;
  final Duration menuIdleDuration;
  final Future<void> Function()? onThemeUpdated;

  const VendingController({
    super.key,
    this.apiService,
    this.eventSource,
    this.hardwareEnabled = AppConfig.hardwareEnabled,
    this.homeIdleDuration = AppConfig.homeIdleDuration,
    this.menuIdleDuration = AppConfig.menuIdleDuration,
    this.onThemeUpdated,
  });

  @override
  State<VendingController> createState() => _VendingControllerState();
}

class _VendingControllerState extends State<VendingController> {
  static final Map<LogicalKeyboardKey, String> _keyboardDigits = {
    LogicalKeyboardKey.digit0: '0',
    LogicalKeyboardKey.digit1: '1',
    LogicalKeyboardKey.digit2: '2',
    LogicalKeyboardKey.digit3: '3',
    LogicalKeyboardKey.digit4: '4',
    LogicalKeyboardKey.digit5: '5',
    LogicalKeyboardKey.digit6: '6',
    LogicalKeyboardKey.digit7: '7',
    LogicalKeyboardKey.digit8: '8',
    LogicalKeyboardKey.digit9: '9',
    LogicalKeyboardKey.numpad0: '0',
    LogicalKeyboardKey.numpad1: '1',
    LogicalKeyboardKey.numpad2: '2',
    LogicalKeyboardKey.numpad3: '3',
    LogicalKeyboardKey.numpad4: '4',
    LogicalKeyboardKey.numpad5: '5',
    LogicalKeyboardKey.numpad6: '6',
    LogicalKeyboardKey.numpad7: '7',
    LogicalKeyboardKey.numpad8: '8',
    LogicalKeyboardKey.numpad9: '9',
  };

  late final ApiService _apiService;
  late final MachineEventSource _eventSource;

  VendingRoute _currentRoute = VendingRoute.home;
  MachineSocketStatus _socketStatus = MachineSocketStatus.connecting;
  MediaCatalog _mediaCatalog = MediaCatalog.empty;
  final StreamController<MachineEvent> _keypadEvents = StreamController<MachineEvent>.broadcast();
  Timer? _homeIdleTimer;
  bool _resolvingMedia = false;
  bool _pendingUserDetection = false;
  int _itemCount = 0;
  int _totalPrice = 0;
  List<String> _checkoutSlotCodes = const [];
  String? _checkoutTransactionId;
  bool _processingPayment = false;
  bool _voicePaymentListening = false;
  int _voicePaidAmount = 0;
  int _voiceRemainingAmount = 0;
  String? _voicePaymentMessage;
  String? _paymentError;

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();
    _eventSource = widget.eventSource ?? eventBus;
    _eventSource.start(
      onEvent: _handleMachineEvent,
      onStatusChanged: _handleSocketStatus,
    );
    unawaited(_loadLatestMedia());
    _scheduleHomeIdle();
  }

  @override
  void dispose() {
    _homeIdleTimer?.cancel();
    unawaited(_keypadEvents.close());
    _eventSource.dispose();
    _apiService.close();
    super.dispose();
  }

  void _handleMachineEvent(MachineEvent event) {
    if (!mounted) {
      return;
    }

    if (event.type == 'THEME_UPDATED') {
      final onThemeUpdated = widget.onThemeUpdated;
      if (onThemeUpdated != null) unawaited(onThemeUpdated());
      return;
    }

    if (event.type == 'USER_DETECTED' &&
        (_currentRoute == VendingRoute.ad ||
            _currentRoute == VendingRoute.home)) {
      if (_resolvingMedia) {
        _pendingUserDetection = true;
        _homeIdleTimer?.cancel();
        return;
      }
      unawaited(_showTutorialOrHome());
      return;
    }

    if (_isKeypadEvent(event)) {
      _handleKeypadEvent(event);
      return;
    }

    if (_isCurrentVoicePaymentEvent(event)) {
      _handleVoicePaymentEvent(event);
      return;
    }

    if (event.type == 'PAYMENT_SUCCESS' &&
        _currentRoute == VendingRoute.payment) {
      _processingPayment = false;
      _paymentError = null;
      _goTo(VendingRoute.finish);
    }
  }

  bool _isCurrentVoicePaymentEvent(MachineEvent event) {
    if (!event.type.startsWith('VOICE_PAYMENT_') ||
        _currentRoute != VendingRoute.payment) {
      return false;
    }
    return event.data['transaction_id'] == _checkoutTransactionId;
  }

  void _handleVoicePaymentEvent(MachineEvent event) {
    final paidAmount = event.data['paid_amount'];
    final remainingAmount = event.data['remaining_amount'];
    setState(() {
      if (paidAmount is int) _voicePaidAmount = paidAmount;
      if (remainingAmount is int) _voiceRemainingAmount = remainingAmount;
      _voicePaymentListening =
          event.type == 'VOICE_PAYMENT_LISTENING' ||
          event.type == 'VOICE_PAYMENT_UPDATE' ||
          event.type == 'VOICE_PAYMENT_UNRECOGNIZED';
      _processingPayment = event.type == 'VOICE_PAYMENT_CONFIRMED';
      final message = event.data['message'];
      _voicePaymentMessage = message is String ? message : null;
      _paymentError = event.type == 'VOICE_PAYMENT_ERROR'
          ? _voicePaymentMessage
          : null;
    });
  }

  KeyEventResult _handleKeyboardEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final digit = _keyboardDigits[key];
    if (digit != null) {
      _handleMachineEvent(
        MachineEvent(
          type: 'KEYPAD_DIGIT',
          data: {'digit': digit, 'source': 'keyboard'},
        ),
      );
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.keyF) {
      _handleMachineEvent(
        const MachineEvent(type: 'USER_DETECTED', data: {'source': 'keyboard'}),
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _handleMachineEvent(
        const MachineEvent(type: 'KEYPAD_ACCEPT', data: {'source': 'keyboard'}),
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight) {
      _handleMachineEvent(
        const MachineEvent(
          type: 'KEYPAD_CANCEL',
          data: {'source': 'keyboard', 'action': 'cancel'},
        ),
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyG) {
      _handleMachineEvent(
        const MachineEvent(
          type: 'KEYPAD_CANCEL',
          data: {'source': 'keyboard', 'action': 'declined'},
        ),
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyH) {
      unawaited(_submitMockPaymentSuccess());
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  bool _isKeypadEvent(MachineEvent event) {
    return event.type == 'KEYPAD_DIGIT' ||
        event.type == 'KEYPAD_ACCEPT' ||
        event.type == 'KEYPAD_CANCEL';
  }

  void _handleKeypadEvent(MachineEvent event) {
    switch (_currentRoute) {
      case VendingRoute.tutorial:
        _goTo(VendingRoute.menu);
        break;
      case VendingRoute.ad:
        unawaited(_showTutorialOrHome());
        break;
      case VendingRoute.home:
        if (event.type == 'KEYPAD_DIGIT') {
          _goTo(VendingRoute.menu);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _currentRoute == VendingRoute.menu) {
              _keypadEvents.add(event);
            }
          });
        } else if (event.type == 'KEYPAD_ACCEPT') {
          _goTo(VendingRoute.menu);
        }
        break;
      case VendingRoute.menu:
        _keypadEvents.add(event);
        break;
      case VendingRoute.payment:
        if (event.type == 'KEYPAD_CANCEL') {
          _returnHome();
        }
        break;
      case VendingRoute.finish:
        break;
    }
  }

  void _handleSocketStatus(MachineSocketStatus status) {
    if (!mounted || _socketStatus == status) {
      return;
    }
    setState(() => _socketStatus = status);
  }

  void _goTo(VendingRoute route) {
    _homeIdleTimer?.cancel();
    setState(() => _currentRoute = route);
    if (route == VendingRoute.home) {
      _scheduleHomeIdle();
    }
  }

  void _scheduleHomeIdle() {
    _homeIdleTimer?.cancel();
    _homeIdleTimer = Timer(widget.homeIdleDuration, () {
      unawaited(_showAdsAfterIdle());
    });
  }

  Future<MediaCatalog?> _loadLatestMedia() async {
    try {
      final catalog = await _apiService.fetchMediaCatalog();
      if (mounted) {
        setState(() => _mediaCatalog = catalog);
      }
      return catalog;
    } on ApiException {
      return null;
    }
  }

  Future<void> _showAdsAfterIdle() async {
    if (!mounted || _currentRoute != VendingRoute.home || _resolvingMedia) {
      return;
    }

    _resolvingMedia = true;
    final catalog = await _loadLatestMedia();
    _resolvingMedia = false;
    if (!mounted || _currentRoute != VendingRoute.home) return;

    if (_pendingUserDetection) {
      _pendingUserDetection = false;
      unawaited(_showTutorialOrHome());
      return;
    }

    if (catalog != null && catalog.ads.isNotEmpty) {
      _goTo(VendingRoute.ad);
    } else {
      _scheduleHomeIdle();
    }
  }

  Future<void> _showTutorialOrHome() async {
    if (_resolvingMedia) {
      _pendingUserDetection = true;
      return;
    }
    _pendingUserDetection = false;
    _homeIdleTimer?.cancel();
    _resolvingMedia = true;
    final latestCatalog = await _loadLatestMedia();
    _resolvingMedia = false;
    _pendingUserDetection = false;
    if (!mounted) return;

    final tutorial = (latestCatalog ?? _mediaCatalog).tutorial;
    if (tutorial != null) {
      _goTo(VendingRoute.tutorial);
    } else {
      _goTo(VendingRoute.home);
    }
  }

  void _openPayment(List<String> slotCodes, int itemCount, int totalPrice) {
    setState(() {
      _checkoutSlotCodes = List.unmodifiable(slotCodes);
      _checkoutTransactionId =
          'TRX-${DateTime.now().microsecondsSinceEpoch.toRadixString(36).toUpperCase()}';
      _itemCount = itemCount;
      _totalPrice = totalPrice;
      _processingPayment = false;
      _voicePaymentListening = false;
      _voicePaidAmount = 0;
      _voiceRemainingAmount = totalPrice;
      _voicePaymentMessage = null;
      _paymentError = null;
      _currentRoute = VendingRoute.payment;
    });
    if (AppConfig.voicePaymentEnabled) {
      unawaited(_startVoicePayment());
    }
  }

  Future<void> _startVoicePayment() async {
    if (!mounted ||
        _currentRoute != VendingRoute.payment ||
        _checkoutTransactionId == null ||
        _checkoutSlotCodes.isEmpty) {
      return;
    }
    try {
      final session = await _apiService.startVoicePayment(
        transactionId: _checkoutTransactionId!,
        slotCodes: _checkoutSlotCodes,
        totalAmount: _totalPrice,
      );
      if (mounted && _currentRoute == VendingRoute.payment) {
        setState(() {
          _voicePaymentListening = session.status == 'listening';
          _voicePaidAmount = session.paidAmount;
          _voiceRemainingAmount = session.remainingAmount;
          _voicePaymentMessage = '';
          _paymentError = null;
        });
      }
    } on ApiException catch (error) {
      if (mounted && _currentRoute == VendingRoute.payment) {
        setState(() {
          _voicePaymentListening = false;
          _paymentError = error.message;
        });
      }
    }
  }

  Future<void> _submitMockPaymentSuccess() async {
    if (!mounted ||
        _currentRoute != VendingRoute.payment ||
        _processingPayment ||
        _checkoutSlotCodes.isEmpty) {
      return;
    }

    setState(() {
      _processingPayment = true;
      _paymentError = null;
    });

    try {
      await _apiService.submitPaymentSuccess(
        transactionId: _checkoutTransactionId!,
        slotCodes: _checkoutSlotCodes,
      );
      if (mounted && _currentRoute == VendingRoute.payment) {
        _goTo(VendingRoute.finish);
      }
    } on ApiException catch (error) {
      if (mounted && _currentRoute == VendingRoute.payment) {
        setState(() => _paymentError = error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _processingPayment = false);
      }
    }
  }

  void _returnHome() {
    final transactionId = _checkoutTransactionId;
    if (transactionId != null) {
      unawaited(_apiService.cancelVoicePayment(transactionId));
    }
    setState(() {
      _itemCount = 0;
      _totalPrice = 0;
      _checkoutSlotCodes = const [];
      _checkoutTransactionId = null;
      _processingPayment = false;
      _voicePaymentListening = false;
      _voicePaidAmount = 0;
      _voiceRemainingAmount = 0;
      _voicePaymentMessage = null;
      _paymentError = null;
      _currentRoute = VendingRoute.home;
    });
    _scheduleHomeIdle();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyboardEvent,
      child: Scaffold(
        backgroundColor: VendingColors.background,
        body: AnimatedSwitcher(
          duration: AppConfig.pageTransitionDuration,
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: _buildCurrentScreen(),
        ),
      ),
    );
  }

  Widget _buildCurrentScreen() {
    switch (_currentRoute) {
      case VendingRoute.ad:
        return AdScreen(
          key: const ValueKey(VendingRoute.ad),
          ads: _mediaCatalog.ads,
          socketStatus: _socketStatus,
        );
      case VendingRoute.tutorial:
        final tutorial = _mediaCatalog.tutorial;
        if (tutorial == null) {
          return HomeScreen(
            key: const ValueKey(VendingRoute.home),
            media: _mediaCatalog.homescreen,
            onContinue: () => _goTo(VendingRoute.menu),
          );
        }
        return TutorialScreen(
          key: const ValueKey(VendingRoute.tutorial),
          tutorial: tutorial,
          onFinished: () => _goTo(VendingRoute.menu),
        );
      case VendingRoute.home:
        return HomeScreen(
          key: const ValueKey(VendingRoute.home),
          media: _mediaCatalog.homescreen,
          onContinue: () => _goTo(VendingRoute.menu),
        );
      case VendingRoute.menu:
        return MenuScreen(
          key: const ValueKey(VendingRoute.menu),
          apiService: _apiService,
          keypadEvents: _keypadEvents.stream,
          idleDuration: widget.menuIdleDuration,
          onCheckout: _openPayment,
          onCancel: _returnHome,
        );
      case VendingRoute.payment:
        return PaymentScreen(
          key: const ValueKey(VendingRoute.payment),
          itemCount: _itemCount,
          totalPrice: _totalPrice,
          socketStatus: _socketStatus,
          isProcessing: _processingPayment,
          isListening: _voicePaymentListening,
          paidAmount: _voicePaidAmount,
          remainingAmount: _voiceRemainingAmount,
          voiceMessage: _voicePaymentMessage,
          errorMessage: _paymentError,
          showMockPaymentAction:
              !AppConfig.voicePaymentEnabled && !widget.hardwareEnabled,
          onMockPaymentSuccess: _submitMockPaymentSuccess,
          onExpired: _returnHome,
          onCancel: _returnHome,
        );
      case VendingRoute.finish:
        return FinishScreen(
          key: const ValueKey(VendingRoute.finish),
          onFinished: _returnHome,
        );
    }
  }
}
