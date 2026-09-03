import 'package:flutter_test/flutter_test.dart';
import 'package:vending_ui/core/app_config.dart';
import 'package:vending_ui/core/event_bus.dart';

void main() {
  test('LocalEventBus meneruskan event dan status ke listener', () {
    final bus = LocalEventBus();
    final events = <MachineEvent>[];
    final statuses = <MachineSocketStatus>[];

    bus.start(onEvent: events.add, onStatusChanged: statuses.add);

    // Saat start, status langsung "connected" di mode lokal.
    expect(statuses.last, MachineSocketStatus.connected);

    bus.publish(const MachineEvent(type: 'USER_DETECTED', data: {}));
    expect(events.single.type, 'USER_DETECTED');

    // Status yang sama tidak mengirim ulang; yang berbeda diteruskan.
    bus.updateStatus(MachineSocketStatus.connected);
    expect(statuses, hasLength(1));
    bus.updateStatus(MachineSocketStatus.disconnected);
    expect(statuses.last, MachineSocketStatus.disconnected);
    expect(statuses, hasLength(2));

    // Setelah dispose, publish diabaikan.
    bus.dispose();
    bus.publish(const MachineEvent(type: 'KEYPAD_ACCEPT', data: {}));
    expect(events, hasLength(1));

    // start() ulang memungkinkan bus dipakai lagi (mis. di pengujian).
    bus.start(onEvent: events.add, onStatusChanged: statuses.add);
    bus.publish(const MachineEvent(type: 'KEYPAD_DIGIT', data: {'digit': '1'}));
    expect(events, hasLength(2));
    expect(statuses.last, MachineSocketStatus.connected);
  });
}