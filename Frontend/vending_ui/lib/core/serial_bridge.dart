import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:vending_ui/core/event_bus.dart';

/// Handles direct serial communication with the ESP32 board.
/// When [hardwareEnabled] is false, drop commands are simulated locally.
class SerialBridge {
  SerialBridge({
    required this.portName,
    required this.baudRate,
    required this.hardwareEnabled,
  });

  final String portName;
  final int baudRate;
  final bool hardwareEnabled;

  SerialPort? _port;
  bool _listening = false;
  bool _disposed = false;

  static const _mockDelay = Duration(milliseconds: 250);

  // ─── Public API ───────────────────────────────────────────────────────────

  /// Start listening for lines from the serial port and forward parsed events
  /// to the [eventBus].
  void startListening() {
    if (!hardwareEnabled || _listening) return;
    _listening = true;
    _startReadLoop();
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

    final port = _ensureConnection();
    _writeLine(port, command);

    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      final line = _readLine(port);
      if (line == null) {
        await Future.delayed(const Duration(milliseconds: 50));
        continue;
      }
      final normalized = line.trim().toUpperCase();
      if (normalized == 'SUCCESS_$slotCode') return normalized;
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
    final port = _ensureConnection();
    final command = 'TEST_${inputName.toUpperCase()}';
    _writeLine(port, command);
  }

  void close() {
    _disposed = true;
    _listening = false;
    _port?.close();
    _port?.dispose();
    _port = null;
  }

  // ─── Internal ─────────────────────────────────────────────────────────────

  SerialPort _ensureConnection() {
    if (_port != null && _port!.isOpen) return _port!;

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
      return _port!;
    } catch (e) {
      _port?.dispose();
      _port = null;
      throw SerialBridgeError('Gagal membuka serial port: $e');
    }
  }

  void _writeLine(SerialPort port, String command) {
    final bytes = '$command\n'.codeUnits;
    port.write(Uint8List.fromList(bytes));
  }

  String? _readLine(SerialPort port) {
    try {
      final available = port.bytesAvailable;
      if (available <= 0) return null;
      final buffer = Uint8List(available);
      final read = port.read(buffer, timeout: 100);
      if (read <= 0) return null;
      return String.fromCharCodes(buffer.sublist(0, read));
    } catch (_) {
      return null;
    }
  }

  void _startReadLoop() {
    // Runs in a separate isolate-like loop via timer.
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_disposed || !hardwareEnabled) {
        timer.cancel();
        return;
      }
      try {
        final port = _ensureConnection();
        final line = _readLine(port);
        if (line == null) return;
        _handleLine(line.trim());
      } catch (e) {
        debugPrint('[SerialBridge] Read error: $e');
        // Try to reconnect next tick.
        _port?.dispose();
        _port = null;
      }
    });
  }

  void _handleLine(String line) {
    final normalized = line.toUpperCase();

    // Forward success/error responses (not handled here, used by dropSlot).
    // Forward events to the event bus.
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
    }
  }
}

class SerialBridgeError extends RuntimeError {
  SerialBridgeError(super.message);
}
