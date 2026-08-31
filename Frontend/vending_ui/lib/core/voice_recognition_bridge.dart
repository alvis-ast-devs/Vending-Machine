import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Result from the Python voice recognition script.
class VoiceRecognitionResult {
  final String? transcript;
  final int amount;

  const VoiceRecognitionResult({this.transcript, this.amount = 0});

  factory VoiceRecognitionResult.fromJson(Map<String, dynamic> json) {
    return VoiceRecognitionResult(
      transcript: json['transcript'] as String?,
      amount: (json['amount'] as num?)?.toInt() ?? 0,
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

  /// Stream of results from the voice recognition script.
  Stream<VoiceRecognitionResult> get results => _resultController.stream;

  bool get isListening => _listening;

  /// Start the Python voice recognition script.
  ///
  /// [pythonPath] is the path to the Python executable.
  /// [scriptPath] is the path to `voice_recognition.py`.
  Future<void> startListening({
    String pythonPath = 'python',
    String? scriptPath,
  }) async {
    if (_listening) return;

    final resolvedScript = scriptPath ?? _defaultScriptPath();
    final scriptFile = File(resolvedScript);
    if (!await scriptFile.exists()) {
      debugPrint(
        '[VoiceBridge] Script tidak ditemukan: $resolvedScript',
      );
      return;
    }

    try {
      _process = await Process.start(
        pythonPath,
        [resolvedScript],
        mode: ProcessStartMode.normal,
      );

      _listening = true;

      // Listen to stdout for JSON results.
      _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (line.trim().isEmpty) return;
          try {
            final json = jsonDecode(line.trim()) as Map<String, dynamic>;
            final result = VoiceRecognitionResult.fromJson(json);
            if (!_disposed) {
              _resultController.add(result);
            }
          } catch (e) {
            debugPrint('[VoiceBridge] Parse error: $line');
          }
        },
        onError: (error) {
          debugPrint('[VoiceBridge] stdout error: $error');
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
        debugPrint('[VoiceBridge stderr] $line');
      });

      // Watch for process exit.
      _process!.exitCode.then((code) {
        _listening = false;
        debugPrint('[VoiceBridge] Process exited with code $code');
      });
    } catch (e) {
      debugPrint('[VoiceBridge] Failed to start: $e');
      _listening = false;
    }
  }

  /// Stop the voice recognition by sending STOP to stdin.
  void stopListening() {
    if (!_listening || _process == null) return;
    try {
      _process!.stdin.writeln('STOP');
    } catch (_) {
      // Process may have already exited.
    }
    _listening = false;
  }

  void dispose() {
    _disposed = true;
    stopListening();
    _process?.kill(ProcessSignal.sigterm);
    _process = null;
    _resultController.close();
  }

  String _defaultScriptPath() {
    // Look for the script relative to the executable directory.
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return '$exeDir${Platform.pathSeparator}scripts${Platform.pathSeparator}voice_recognition.py';
  }
}
