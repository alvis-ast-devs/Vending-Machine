import 'package:flutter/material.dart';

enum VendingRoute { ad, tutorial, home, menu, payment, finish }

enum MachineSocketStatus { connecting, connected, disconnected }

/// Connection mode for ESP32 communication.
enum ConnectionMode {
  /// No hardware - use Flutter's internal mock.
  mock,

  /// Direct serial port (COM3, etc).
  serial,

  /// TCP socket connection (for mock_esp32.py --tcp).
  tcp,
}

class AppConfig {
  const AppConfig._();

  /// Whether real hardware is connected.
  static const bool hardwareEnabled = bool.fromEnvironment(
    'HARDWARE_ENABLED',
    defaultValue: false,
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

  /// Connection mode: mock, serial, or tcp.
  /// When hardwareEnabled is true, this determines the transport.
  static ConnectionMode get connectionMode {
    if (!hardwareEnabled) return ConnectionMode.mock;
    final mode = String.fromEnvironment(
      'CONNECTION_MODE',
      defaultValue: 'serial',
    );
    switch (mode.toLowerCase()) {
      case 'tcp':
        return ConnectionMode.tcp;
      case 'serial':
        return ConnectionMode.serial;
      default:
        return ConnectionMode.serial;
    }
  }

  /// TCP host for mock ESP32 connection (default: localhost).
  static const String tcpHost = String.fromEnvironment(
    'TCP_HOST',
    defaultValue: '127.0.0.1',
  );

  /// TCP port for mock ESP32 connection.
  static const int tcpPort = int.fromEnvironment(
    'TCP_PORT',
    defaultValue: 8888,
  );

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
