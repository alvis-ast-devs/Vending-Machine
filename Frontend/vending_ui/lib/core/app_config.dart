import 'package:flutter/material.dart';

enum VendingRoute { ad, tutorial, home, menu, payment, finish }

enum MachineSocketStatus { connecting, connected, disconnected }

class AppConfig {
  const AppConfig._();

  static const bool hardwareEnabled = bool.fromEnvironment(
    'HARDWARE_ENABLED',
    defaultValue: false,
  );

  static const double portraitAspectRatio = 9 / 16;
  static const Size initialWindowSize = Size(540, 960);
  static const Size minimumWindowSize = Size(360, 640);
  static const Size designSize = Size(540, 960);

  static const String backendHttpUrl = String.fromEnvironment(
    'BACKEND_HTTP_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );
  static const String backendWebSocketUrl = String.fromEnvironment(
    'BACKEND_WEBSOCKET_URL',
    defaultValue: 'ws://127.0.0.1:8000/ws/machine',
  );

  static const Duration pageTransitionDuration = Duration(milliseconds: 350);
  static const Duration homeIdleDuration = Duration(seconds: 30);
  static const Duration menuIdleDuration = Duration(seconds: 30);
  static const Duration adImageDuration = Duration(seconds: 8);
  static const Duration paymentDuration = Duration(seconds: 60);
  static const Duration finishDuration = Duration(seconds: 5);
  static const Duration requestTimeout = Duration(seconds: 8);
  static const Duration paymentProcessingTimeout = Duration(minutes: 2);
  static const Duration socketReconnectDelay = Duration(seconds: 3);
  static const Duration socketPingInterval = Duration(seconds: 20);

  static Uri get productsUri => Uri.parse('$backendHttpUrl/api/products');
  static Uri get mediaUri => Uri.parse('$backendHttpUrl/api/media');
  static Uri get themeUri => Uri.parse('$backendHttpUrl/api/theme');
  static Uri get paymentSuccessUri =>
      Uri.parse('$backendHttpUrl/api/events/payment-success');
  static Uri get machineWebSocketUri => Uri.parse(backendWebSocketUrl);
}
