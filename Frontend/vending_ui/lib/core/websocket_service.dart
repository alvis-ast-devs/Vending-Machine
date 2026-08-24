import 'dart:async';
import 'dart:convert';

import 'package:vending_ui/core/app_config.dart';
import 'package:web_socket_channel/status.dart' as socket_status;
import 'package:web_socket_channel/web_socket_channel.dart';

class MachineEvent {
  final String type;
  final Map<String, dynamic> data;

  const MachineEvent({required this.type, required this.data});

  factory MachineEvent.fromMessage(Object? message) {
    if (message is! String) {
      throw const FormatException('Pesan WebSocket harus berupa teks');
    }
    final decoded = jsonDecode(message);
    if (decoded is! Map || decoded['type'] is! String) {
      throw const FormatException('Format event WebSocket tidak valid');
    }
    final rawData = decoded['data'];
    return MachineEvent(
      type: decoded['type'] as String,
      data: rawData is Map ? Map<String, dynamic>.from(rawData) : const {},
    );
  }
}

abstract interface class MachineEventSource {
  void start({
    required void Function(MachineEvent event) onEvent,
    required void Function(MachineSocketStatus status) onStatusChanged,
  });

  void dispose();
}

class WebSocketService implements MachineEventSource {
  final Uri uri;
  final Duration reconnectDelay;

  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  void Function(MachineEvent event)? _onEvent;
  void Function(MachineSocketStatus status)? _onStatusChanged;
  MachineSocketStatus? _lastStatus;
  bool _disposed = false;
  int _connectionGeneration = 0;

  WebSocketService({
    Uri? uri,
    this.reconnectDelay = AppConfig.socketReconnectDelay,
  }) : uri = uri ?? AppConfig.machineWebSocketUri;

  @override
  void start({
    required void Function(MachineEvent event) onEvent,
    required void Function(MachineSocketStatus status) onStatusChanged,
  }) {
    _onEvent = onEvent;
    _onStatusChanged = onStatusChanged;
    _connect();
  }

  Future<void> _connect() async {
    if (_disposed) {
      return;
    }

    _setStatus(MachineSocketStatus.connecting);
    final generation = ++_connectionGeneration;
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;

    try {
      await channel.ready.timeout(AppConfig.requestTimeout);
      if (_disposed || generation != _connectionGeneration) {
        await channel.sink.close(socket_status.normalClosure);
        return;
      }

      _subscription = channel.stream.listen(
        _handleMessage,
        onError: (_, _) => _handleDisconnect(generation),
        onDone: () => _handleDisconnect(generation),
        cancelOnError: true,
      );
      _setStatus(MachineSocketStatus.connected);
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(
        AppConfig.socketPingInterval,
        (_) => channel.sink.add('PING'),
      );
    } on Object {
      await channel.sink.close();
      _handleDisconnect(generation);
    }
  }

  void _handleMessage(Object? message) {
    try {
      _onEvent?.call(MachineEvent.fromMessage(message));
    } on FormatException {
      // Pesan rusak diabaikan agar koneksi utama tetap hidup.
    }
  }

  void _handleDisconnect(int generation) {
    if (_disposed || generation != _connectionGeneration) {
      return;
    }

    _connectionGeneration++;
    _pingTimer?.cancel();
    _subscription = null;
    _channel = null;
    _setStatus(MachineSocketStatus.disconnected);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(reconnectDelay, _connect);
  }

  void _setStatus(MachineSocketStatus status) {
    if (_lastStatus == status) {
      return;
    }
    _lastStatus = status;
    _onStatusChanged?.call(status);
  }

  @override
  void dispose() {
    _disposed = true;
    _connectionGeneration++;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_channel?.sink.close(socket_status.normalClosure));
    _subscription = null;
    _channel = null;
  }
}
