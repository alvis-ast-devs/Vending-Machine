import 'package:flutter/material.dart';

enum VendingRoute { ad, tutorial, home, menu, payment, finish }

enum MachineSocketStatus { connecting, connected, disconnected }

/// Connection mode for ESP32 communication.

class AppConfig {
  const AppConfig._();

  /// Whether real hardware is connected.
  static const bool hardwareEnabled = bool.fromEnvironment(
    'HARDWARE_ENABLED',
    defaultValue: true,
  );

  static const bool voicePaymentEnabled = bool.fromEnvironment(
    'VOICE_PAYMENT_ENABLED',
    defaultValue: true,
  );

  /// Serial port name for ESP32 communication (e.g. COM3 on Windows).
  static const String serialPort = String.fromEnvironment(
    'SERIAL_PORT',
    defaultValue: 'COM3',
  );

  static const int serialBaudRate = 115200;


  static const double portraitAspectRatio = 9 / 16;
  static const Size initialWindowSize = Size(540, 960);
  static const Size minimumWindowSize = Size(360, 640);
  static const Size designSize = Size(540, 960);

  static const Duration pageTransitionDuration = Duration(milliseconds: 350);
  static const Duration homeIdleDuration = Duration(seconds: 30);
  static const Duration menuIdleDuration = Duration(seconds: 30);
  static const Duration adImageDuration = Duration(seconds: 8);
  static const Duration paymentDuration = Duration(seconds: 60);
  static const Duration finishDuration = Duration(seconds: 5);
  static const Duration requestTimeout = Duration(seconds: 8);
  static const Duration paymentProcessingTimeout = Duration(minutes: 2);

  /// Default full stock value for restock operations.
  static const int defaultFullStock = 10;
}
