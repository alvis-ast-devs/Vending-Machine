import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vending_ui/core/app_config.dart';
import 'package:vending_ui/core/websocket_service.dart';

void main() {
  test('WebSocketService menerima event JSON dari server lokal', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serverSubscription = server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.add(
        jsonEncode({'type': 'USER_DETECTED', 'data': <String, dynamic>{}}),
      );
    });

    final eventCompleter = Completer<MachineEvent>();
    final connectedCompleter = Completer<void>();
    final service = WebSocketService(
      uri: Uri.parse('ws://127.0.0.1:${server.port}/ws/machine'),
      reconnectDelay: const Duration(milliseconds: 50),
    );

    service.start(
      onEvent: (event) {
        if (!eventCompleter.isCompleted) {
          eventCompleter.complete(event);
        }
      },
      onStatusChanged: (status) {
        if (status == MachineSocketStatus.connected &&
            !connectedCompleter.isCompleted) {
          connectedCompleter.complete();
        }
      },
    );

    await connectedCompleter.future.timeout(const Duration(seconds: 3));
    final event = await eventCompleter.future.timeout(
      const Duration(seconds: 3),
    );
    expect(event.type, 'USER_DETECTED');

    service.dispose();
    await serverSubscription.cancel();
    await server.close(force: true);
  });
}
