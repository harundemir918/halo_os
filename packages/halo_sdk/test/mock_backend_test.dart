import 'package:halo_sdk/halo_sdk.dart';
import 'package:test/test.dart';

void main() {
  final backend = MockBackend();

  test('fixtures match the designs', () {
    expect(backend.now, DateTime(2026, 10, 23, 9, 41));
    expect(backend.now.weekday, DateTime.friday);
    expect(backend.status.batteryPercent, 82);
    expect(backend.status.network, '5G · WI-FI');
  });

  test('next event is the Design review in Room 3, 19 minutes away', () {
    final e = backend.nextEvent!;
    expect(e.title, 'Design review');
    expect(e.location, 'Room 3');
    expect(e.minutesUntil(backend.now), 19);
  });

  test('minutesUntil never goes negative', () {
    final e = backend.nextEvent!;
    expect(e.minutesUntil(DateTime(2026, 10, 23, 11)), 0);
  });

  test('notifications are Elif (unread) then Parcel (read)', () {
    final n = backend.notifications;
    expect(n.map((x) => x.sender), ['Elif', 'Parcel']);
    expect(n.map((x) => x.unread), [true, false]);
    expect(n.map((x) => x.age(backend.now)), ['2M', '1H']);
  });

  test('age rolls over to hours and days, minimum 1M', () {
    final base = DateTime(2026, 10, 23, 12);
    HaloNotification at(Duration ago) => HaloNotification(
      id: 'x',
      app: 'a',
      sender: 's',
      body: 'b',
      receivedAt: base.subtract(ago),
      unread: false,
    );
    expect(at(const Duration(seconds: 5)).age(base), '1M');
    expect(at(const Duration(minutes: 59)).age(base), '59M');
    expect(at(const Duration(hours: 5)).age(base), '5H');
    expect(at(const Duration(days: 3)).age(base), '3D');
  });
}
