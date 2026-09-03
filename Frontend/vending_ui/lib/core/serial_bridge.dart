import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:vending_ui/core/app_config.dart';
import 'package:vending_ui/core/event_bus.dart';


class SerialBridge {
  SerialBridge({
    required this.portName,
    required this.baudRate,
  });

  final String portName;
  final int baudRate;

  SerialPort? _port;

  bool _listening = false;
  bool _disposed = false;

  // ─── Public API ───────────────────────────────────────────────────────────

  /// Start listening for lines from the serial/TCP port and forward parsed
  void startListening() {
    if (!_listening) {
      _listening = true;
      _startReadLoop();
    }
  }

  /// Send a drop command and wait for acknowledgement.
  Future<String> dropSlot(String slotCode) async {
    final command = 'DROP_SLOT_$slotCode';

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
      if (normalized == 'WARNING_NO_DROP_$slotCode') return normalized;
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

  }

  // ─── Connection Management ────────────────────────────────────────────────

  void _ensureConnection() {
    _ensureSerialConnection();
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

  // ─── Write Operations ─────────────────────────────────────────────────────

  void _writeLine(String command) {
    final data = '$command\n';

    if (_port != null && _port!.isOpen) {
      final bytes = data.codeUnits;
      _port!.write(Uint8List.fromList(bytes));
    }
  }

  // ─── Read Operations ──────────────────────────────────────────────────────

  String? _readLine() {
    return _readSerialLine();
  }

  String? _readSerialLine() {
    if (_port == null || !_port!.isOpen) return null;
    try {
      final available = _port!.bytesAvailable;
      if (available <= 0) return null;
      final data = _port!.read(available, timeout: 100);
      if (data.isEmpty) return null;
      debugPrint('[SerialBridge] Received: ${String.fromCharCodes(data)}');
      return String.fromCharCodes(data);
    } catch (_) {
      return null;
    }
  }

  // ─── Serial Port Read Loop ────────────────────────────────────────────────

  void _startReadLoop() {
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_disposed) {
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
        normalized.length == 11) {
      final digit = normalized.substring(10);
      // if (RegExp(r'^\d$').hasMatch(digit)) {
      debugPrint('[SerialBridge] Handling digit: ${digit}');
      eventBus.publish(
        MachineEvent(type: 'KEYPAD_DIGIT', data: {'digit': digit}),
      );
      // }
    } else if (normalized.startsWith('WARNING_NO_DROP_')) {
      final slotCode = normalized.substring(16);
      eventBus.publish(MachineEvent(
        type: 'DROP_WARNING',
        data: {'slot': slotCode, 'reason': 'no_ir_detected'},
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
