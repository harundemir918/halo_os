import 'backend.dart';
import 'models.dart';

/// Fixtures that reuse the copy from the designs (design/screens/) so golden
/// tests line up: Friday 23 October, 09:41, Design review in Room 3, Elif.
class MockBackend implements HaloBackend {
  MockBackend({DateTime? now}) : now = now ?? DateTime(2026, 10, 23, 9, 41);

  @override
  final DateTime now;

  @override
  DeviceStatus get status =>
      const DeviceStatus(battery: 0.82, network: '5G · WI-FI');

  @override
  CalendarEvent? get nextEvent => CalendarEvent(
    start: DateTime(now.year, now.month, now.day, 10),
    title: 'Design review',
    location: 'Room 3',
  );

  @override
  List<HaloNotification> get notifications => [
    HaloNotification(
      id: 'elif-1',
      app: 'messages',
      sender: 'Elif',
      body: 'Are we still on for 7?',
      receivedAt: now.subtract(const Duration(minutes: 2)),
      unread: true,
    ),
    HaloNotification(
      id: 'parcel-1',
      app: 'parcel',
      sender: 'Parcel',
      body: 'Arriving 14:00 to 16:00',
      receivedAt: now.subtract(const Duration(hours: 1)),
      unread: false,
    ),
  ];
}
