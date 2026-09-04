import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Result from the Python voice recognition script.
class VoiceRecognitionResult {
  final String? transcript;
  final int amount;

  /// Non-payment status ping, e.g. `ready` when the script starts.
  final String? status;

  /// Error message when the script failed (mic, library, network, ...).
  final String? error;

  const VoiceRecognitionResult({
    this.transcript,
    this.amount = 0,
    this.status,
    this.error,
  });

  factory VoiceRecognitionResult.fromJson(Map<String, dynamic> json) {
    return VoiceRecognitionResult(
      transcript: json['transcript'] as String?,
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      status: json['status'] as String?,
      error: json['error'] as String?,
    );
  }
}

/// Manages a running Python voice recognition process.
/// Sends a `STOP` command to stdin to terminate listening.
class VoiceRecognitionBridge {
  Process? _process;
  bool _listening = false;
  bool _disposed = false;

  final StreamController<VoiceRecognitionResult> _resultController =
      StreamController<VoiceRecognitionResult>.broadcast();

  File? _logFile;

  /// Stream of results from the voice recognition script.
  Stream<VoiceRecognitionResult> get results => _resultController.stream;

  /// Log ke konsol (debug) DAN ke `voice_log.txt` di samping exe.
  /// Versi release tidak punya konsol, jadi file log ini satu-satunya
  /// cara melihat error voice recognition saat aplikasi sudah di-build.
  void _log(String message) {
    debugPrint(message);
    try {
      _logFile ??= File(
        '${File(Platform.resolvedExecutable).parent.path}'
        '${Platform.pathSeparator}voice_log.txt',
      );
      _logFile!.writeAsStringSync(
        '${DateTime.now().toIso8601String()} $message\r\n',
        mode: FileMode.append,
      );
    } catch (_) {
      // Logging tidak boleh merusak aplikasi.
    }
  }

  bool get isListening => _listening;

  /// Start the Python voice recognition script.
  ///
  /// [pythonPath] is the path to the Python executable. When omitted, the
  /// bridge prefers the bundled embeddable Python at
  /// `<exe>/runtime/python/python.exe` and falls back to `python` on PATH.
  /// [scriptPath] is the path to `voice_recognition.py`; when omitted it is
  /// resolved to `<exe>/scripts/voice_recognition.py`.
  Future<void> startListening({
    String? pythonPath,
    String? scriptPath,
  }) async {
    if (_listening) return;

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final sep = Platform.pathSeparator;
    final resolvedScript = scriptPath ??
        '$exeDir${sep}scripts${sep}voice_recognition.py';

    final bundledPython = File(
      '$exeDir${sep}runtime${sep}python${sep}python.exe',
    );
    final resolvedPython = pythonPath ??
        (bundledPython.existsSync() ? bundledPython.path : 'python');

    final scriptFile = File(resolvedScript);
    if (!scriptFile.existsSync()) {
      _log('[VoiceBridge] Script tidak ditemukan: $resolvedScript');
      return;
    }

    try {
      _process = await Process.start(
        resolvedPython,
        [resolvedScript],
        mode: ProcessStartMode.normal,
      );

      _listening = true;
      _log('[VoiceBridge] ✅ Voice recognition MULAI');

      // Listen to stdout for JSON results.
      _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (line.trim().isEmpty) return;
          _log('[VoiceBridge] 🎤 Data diterima dari script: $line');
          try {
            final json = jsonDecode(line.trim()) as Map<String, dynamic>;
            final result = VoiceRecognitionResult.fromJson(json);
            _log('[VoiceBridge] 📝 Transcript: ${result.transcript}, Amount: ${result.amount}'
                '${result.error != null ? ', Error: ${result.error}' : ''}');
            if (!_disposed) {
              _resultController.add(result);
            }
          } catch (e) {
            _log('[VoiceBridge] Parse error: $line');
          }
        },
        onError: (error) {
          _log('[VoiceBridge] stdout error: $error');
          _listening = false;
        },
        onDone: () {
          _listening = false;
        },
      );

      // Log stderr for debugging.
      _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _log('[VoiceBridge stderr] $line');
      });

      // Watch for process exit.
      _process!.exitCode.then((code) {
        _listening = false;
        _log('[VoiceBridge] Process exited with code $code');
      });
    } catch (e) {
      _log('[VoiceBridge] Failed to start: $e');
      _listening = false;
    }
  }

  /// Test-only: inject a result as if the Python script had emitted it.
  @visibleForTesting
  void emitResultForTesting(VoiceRecognitionResult result) {
    _resultController.add(result);
  }

  /// Stop the voice recognition by sending STOP to stdin.
  void stopListening() {
    if (!_listening || _process == null) return;
    _log('[VoiceBridge] 🛑 Menghentikan voice recognition...');
    try {
      _process!.stdin.writeln('STOP');
    } catch (_) {
      // Process may have already exited.
    }
    _listening = false;
    _log('[VoiceBridge] ⏹️ Voice recognition BERHENTI');
  }

  void dispose() {
    _log('[VoiceBridge] 🗑️ Disposing voice recognition bridge...');
    _disposed = true;
    stopListening();
    _process?.kill(ProcessSignal.sigterm);
    _process = null;
    _resultController.close();
    _log('[VoiceBridge] ⏹️ Voice recognition BERHENTI (disposed)');
  }
}
