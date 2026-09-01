import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:vending_ui/core/app_config.dart';
import 'package:vending_ui/core/event_bus.dart';

/// Handles serial/TCP communication with the ESP32 board.
/// Supports three modes:
///   - [ConnectionMode.mock]: internal Flutter mock (no hardware)
///   - [ConnectionMode.serial]: direct serial port (COM3, etc)
///   - [ConnectionMode.tcp]: TCP socket (for mock_esp32.py)
class SerialBridge {
  SerialBridge({
    required this.portName,
    required this.baudRate,
    required this.hardwareEnabled,
    this.connectionMode = ConnectionMode.serial,
    this.tcpHost = '127.0.0.1',
    this.tcpPort = 8888,
  });

  final String portName;
  final int baudRate;
  final bool hardwareEnabled;
  final ConnectionMode connectionMode;
  final String tcpHost;
  final int tcpPort;

  // Serial port state
  SerialPort? _port;

  // TCP socket state
  Socket? _tcpSocket;
  String _tcpBuffer = '';

  bool _listening = false;
  bool _disposed = false;

  static const _mockDelay = Duration(milliseconds: 250);

  bool get _isTcp => hardwareEnabled && connectionMode == ConnectionMode.tcp;
  bool get _isSerial =>
      hardwareEnabled && connectionMode == ConnectionMode.serial;

  // ─── Public API ───────────────────────────────────────────────────────────

  /// Start listening for lines from the serial/TCP port and forward parsed
  /// events to the [eventBus].
  void startListening() {
    if (!hardwareEnabled || _listening) return;
    _listening = true;

    if (_isTcp) {
      _startTcpConnection();
    } else {
      _startReadLoop();
    }
  }

  /// Send a drop command and wait for acknowledgement.
  Future<String> dropSlot(String slotCode) async {
    final command = 'DROP_SLOT_$slotCode';

    if (!hardwareEnabled) {
      debugPrint('[MOCK HARDWARE] Mengirim: $command');
      await Future.delayed(_mockDelay);
      final response = 'SUCCESS_$slotCode';
      debugPrint('[MOCK HARDWARE] Menerima: $response');
      return response;
    }

    _ensureConnection();
    _writeLine(command);

    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      final line = _readLine();
      if (line == null) {
        await Future.delayed(const Duration(milliseconds: 50));
        continue;
      }
      final normalized = line.trim().toUpperCase();
      if (normalized == 'SUCCESS_$slotCode') return normalized;
      if (normalized == 'WARNING_NO_LIMIT_$slotCode') return normalized;
      if (normalized.startsWith('ERROR_')) {
        throw SerialBridgeError('ESP32 menolak perintah: $normalized');
      }
    }
    throw SerialBridgeError(
      'ESP32 tidak mengirim SUCCESS_$slotCode: timeout',
    );
  }

  /// Send a test command to the ESP32 (DETECT, ACCEPT, CANCEL, KEY_0…9).
  void sendTestInput(String inputName) {
    if (!hardwareEnabled) {
      debugPrint('[MOCK HARDWARE] Test input: $inputName');
      return;
    }
    _ensureConnection();
    final command = 'TEST_${inputName.toUpperCase()}';
    _writeLine(command);
  }

  void close() {
    _disposed = true;
    _listening = false;

    // Close serial port
    _port?.close();
    _port?.dispose();
    _port = null;

    // Close TCP socket
    _tcpSocket?.destroy();
    _tcpSocket = null;
  }

  // ─── Connection Management ────────────────────────────────────────────────

  void _ensureConnection() {
    if (_isTcp) {
      _ensureTcpConnection();
    } else if (_isSerial) {
      _ensureSerialConnection();
    }
  }

  void _ensureSerialConnection() {
    if (_port != null && _port!.isOpen) return;

    if (portName.isEmpty) {
      throw SerialBridgeError('SERIAL_PORT belum dikonfigurasi');
    }

    try {
      _port = SerialPort(portName);
      final open = _port!.openReadWrite();
      if (!open) {
        throw SerialBridgeError(
          'Tidak dapat membuka serial port $portName',
        );
      }
      final config = SerialPortConfig()
        ..baudRate = baudRate
        ..bits = 8
        ..stopBits = 1
        ..parity = SerialPortParity.none;
      _port!.config = config;
    } catch (e) {
      _port?.dispose();
      _port = null;
      throw SerialBridgeError('Gagal membuka serial port: $e');
    }
  }

  void _ensureTcpConnection() {
    if (_tcpSocket != null) return;

    try {
      // Note: actual TCP connection is established asynchronously
      // in _startTcpConnection(). Here we just check if socket exists.
      throw SerialBridgeError('TCP belum terhubung, menunggu koneksi...');
    } catch (e) {
      throw SerialBridgeError('Gagal koneksi TCP: $e');
    }
  }

  // ─── Write Operations ─────────────────────────────────────────────────────

  void _writeLine(String command) {
    final data = '$command\n';

    if (_isTcp && _tcpSocket != null) {
      _tcpSocket!.write(data);
    } else if (_isSerial && _port != null && _port!.isOpen) {
      final bytes = data.codeUnits;
      _port!.write(Uint8List.fromList(bytes));
    }
  }

  // ─── Read Operations ──────────────────────────────────────────────────────

  String? _readLine() {
    if (_isSerial) {
      return _readSerialLine();
    }
    // TCP lines are handled via _tcpLineController in _startTcpConnection
    return null;
  }

  String? _readSerialLine() {
    if (_port == null || !_port!.isOpen) return null;
    try {
      final available = _port!.bytesAvailable;
      if (available <= 0) return null;
      final data = _port!.read(available, timeout: 100);
      if (data.isEmpty) return null;
      return String.fromCharCodes(data);
    } catch (_) {
      return null;
    }
  }

  // ─── Serial Port Read Loop ────────────────────────────────────────────────

  void _startReadLoop() {
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_disposed || !hardwareEnabled) {
        timer.cancel();
        return;
      }
      try {
        _ensureConnection();
        final line = _readSerialLine();
        if (line == null) return;
        _handleLine(line.trim());
      } catch (e) {
        debugPrint('[SerialBridge] Read error: $e');
        _port?.dispose();
        _port = null;
      }
    });
  }

  // ─── TCP Socket Connection ────────────────────────────────────────────────

  void _startTcpConnection() async {
    debugPrint('[SerialBridge] Menghubungkan ke TCP $tcpHost:$tcpPort...');

    try {
      final socket = await Socket.connect(tcpHost, tcpPort);
      _tcpSocket = socket;
      debugPrint('[SerialBridge] TCP terhubung ke $tcpHost:$tcpPort');

      // Listen for incoming data from mock ESP32
      socket.listen(
        (data) {
          _tcpBuffer += String.fromCharCodes(data);
          // Process complete lines
          while (_tcpBuffer.contains('\n')) {
            final index = _tcpBuffer.indexOf('\n');
            final line = _tcpBuffer.substring(0, index).trim();
            _tcpBuffer = _tcpBuffer.substring(index + 1);
            if (line.isNotEmpty) {
              _handleLine(line);
            }
          }
        },
        onError: (error) {
          debugPrint('[SerialBridge] TCP error: $error');
          _tcpSocket?.destroy();
          _tcpSocket = null;
          // Try to reconnect after delay
          if (!_disposed) {
            Future.delayed(const Duration(seconds: 2), () {
              if (!_disposed) _startTcpConnection();
            });
          }
        },
        onDone: () {
          debugPrint('[SerialBridge] TCP disconnected');
          _tcpSocket = null;
          if (!_disposed) {
            Future.delayed(const Duration(seconds: 2), () {
              if (!_disposed) _startTcpConnection();
            });
          }
        },
      );
    } catch (e) {
      debugPrint('[SerialBridge] TCP connection failed: $e');
      if (!_disposed) {
        Future.delayed(const Duration(seconds: 2), () {
          if (!_disposed) _startTcpConnection();
        });
      }
    }
  }

  // ─── Event Handler ────────────────────────────────

  void _handleLine(String line) {
    final normalized = line.toUpperCase();

    if (normalized == 'EVENT_USER_DETECTED') {
      eventBus.publish(
        const MachineEvent(type: 'USER_DETECTED', data: {}),
      );
    } else if (normalized == 'EVENT_ACCEPT') {
      eventBus.publish(
        const MachineEvent(type: 'KEYPAD_ACCEPT', data: {}),
      );
    } else if (normalized == 'EVENT_CANCEL' ||
        normalized == 'EVENT_DECLINED') {
      eventBus.publish(
        const MachineEvent(type: 'KEYPAD_CANCEL', data: {}),
      );
    } else if (normalized.startsWith('EVENT_KEY_') &&
        normalized.length == 10) {
      final digit = normalized.substring(9);
      if (RegExp(r'^\d$').hasMatch(digit)) {
        eventBus.publish(
          MachineEvent(type: 'KEYPAD_DIGIT', data: {'digit': digit}),
        );
      }
    } else if (normalized.startsWith('WARNING_NO_LIMIT_')) {
      final slotCode = normalized.substring(17);
      eventBus.publish(MachineEvent(
        type: 'DROP_WARNING',
        data: {'slot': slotCode, 'reason': 'limit_switch_not_triggered'},
      ));
    } else if (normalized.startsWith('RESET_OK_')) {
      final slotCode = normalized.substring(9);
      eventBus.publish(MachineEvent(
        type: 'SLOT_RESET',
        data: {'slot': slotCode},
      ));
    } else if (normalized.isNotEmpty) {
      debugPrint('[SerialBridge] Unhandled: $line');
    }
  }
}

class SerialBridgeError implements Exception {
  final String message;
  SerialBridgeError(this.message);

  @override
  String toString() => 'SerialBridgeError: $message';
}
