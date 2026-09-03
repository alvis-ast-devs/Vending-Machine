import 'dart:async';

import 'package:vending_ui/core/app_config.dart';

/// A machine event, identical in shape to the old WebSocket event.
class MachineEvent {
  final String type;
  final Map<String, dynamic> data;

  const MachineEvent({required this.type, required this.data});
}

/// Replaces WebSocketService.  Events are produced locally by the serial
/// bridge, keyboard handler, or the app itself and forwarded over a
/// broadcast stream so existing listeners (VendingController) work unchanged.
abstract interface class MachineEventSource {
  void start({
    required void Function(MachineEvent event) onEvent,
    required void Function(MachineSocketStatus status) onStatusChanged,
  });

  void dispose();
}

class LocalEventBus implements MachineEventSource {
  final StreamController<MachineEvent> _controller =
      StreamController<MachineEvent>.broadcast();

  void Function(MachineEvent event)? _onEvent;
  void Function(MachineSocketStatus status)? _onStatusChanged;
  MachineSocketStatus _lastStatus = MachineSocketStatus.disconnected;
  bool _disposed = false;

  /// Sink used by the serial bridge (or any other producer) to inject events.
  void publish(MachineEvent event) {
    if (_disposed) return;
    _onEvent?.call(event);
  }

  /// Update the connection status shown in the UI.
  void updateStatus(MachineSocketStatus status) {
    if (_disposed || _lastStatus == status) return;
    _lastStatus = status;
    _onStatusChanged?.call(status);
  }

  @override
  void start({
    required void Function(MachineEvent event) onEvent,
    required void Function(MachineSocketStatus status) onStatusChanged,
  }) {
    // start() bisa dipanggil ulang setelah dispose() (mis. di pengujian).
    _disposed = false;
    _lastStatus = MachineSocketStatus.disconnected;
    _onEvent = onEvent;
    _onStatusChanged = onStatusChanged;
    // Consider the hardware channel "connected" immediately in local mode.
    updateStatus(MachineSocketStatus.connected);
  }

  @override
  void dispose() {
    _disposed = true;
    _onEvent = null;
    _onStatusChanged = null;
    _controller.close();
  }
}

/// Singleton instance used throughout the app.
final LocalEventBus eventBus = LocalEventBus();
