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

  test('agenda matches the Home design', () {
    final a = backend.agenda;
    expect(a.map((e) => e.title), [
      'Design review',
      'Lunch with Elif',
      'Dinner, corner table',
    ]);
    expect(a.map((e) => e.location), ['Room 3', 'Karaköy', 'Unconfirmed']);
    expect(a.first.walkMinutes, 2);
    expect(a.first.attendees, 4);
  });

  test('next event skips events that already started', () {
    final lunchTime = MockBackend(now: DateTime(2026, 10, 23, 12));
    expect(lunchTime.nextEvent!.title, 'Lunch with Elif');
    final late = MockBackend(now: DateTime(2026, 10, 23, 23));
    expect(late.nextEvent, isNull);
  });

  test('apps are in arc order with Messages in the middle', () {
    final ids = backend.apps.map((a) => a.id).toList();
    expect(ids, [
      'notes',
      'maps',
      'music',
      'messages',
      'camera',
      'web',
      'phone',
    ]);
    expect(ids[ids.length ~/ 2], 'messages');
  });

  test('Elif has an action prompt', () {
    expect(backend.notifications.first.actionPrompt, 'Still on for 7?');
    expect(backend.notifications.last.actionPrompt, isNull);
  });

  group('quick settings', () {
    test('start as the Switchboard design', () {
      final b = MockBackend();
      final q = b.quick;
      expect((q.brightness * 100).round(), 64);
      expect(q.brightnessAuto, isTrue);
      expect((q.volume * 100).round(), 42);
      expect(q.volumeFooter, 'Media · ring');
      expect(q.toggles.map((t) => t.title), [
        'Wi-Fi',
        'Bluetooth',
        'Cellular',
        'Airplane',
        'Focus',
      ]);
      expect(q.toggles.map((t) => t.on), [true, true, true, false, true]);
      expect(q.media!.title, 'Night Drive');
      expect(q.media!.artist, 'Mira Okafor');
      expect(q.media!.progress, 0.42);
      expect(b.status.fullBy, '10:20');
    });

    test('setting brightness by hand turns auto off and notifies', () async {
      final b = MockBackend();
      final changed = b.changes.first;
      b.setBrightness(0.8);
      await changed;
      expect(b.quick.brightness, 0.8);
      expect(b.quick.brightnessAuto, isFalse);
    });

    test('values are clamped', () {
      final b = MockBackend();
      b.setBrightness(2);
      b.setVolume(-1);
      expect(b.quick.brightness, 1);
      expect(b.quick.volume, 0);
    });

    test('airplane switches the radios off but not Focus', () {
      final b = MockBackend();
      b.setToggle('airplane', true);
      final on = {for (final t in b.quick.toggles) t.id: t.on};
      expect(on['airplane'], isTrue);
      expect(on['wifi'], isFalse);
      expect(on['bluetooth'], isFalse);
      expect(on['cellular'], isFalse);
      expect(on['focus'], isTrue);
      expect(b.quick.toggles.firstWhere((t) => t.id == 'wifi').detail, 'Off');
    });

    test('leaving airplane does not turn the radios back on', () {
      final b = MockBackend();
      b.setToggle('airplane', true);
      b.setToggle('airplane', false);
      expect(b.quick.toggles.firstWhere((t) => t.id == 'wifi').on, isFalse);
    });

    test('play and pause', () {
      final b = MockBackend();
      b.setPlaying(false);
      expect(b.quick.media!.playing, isFalse);
    });
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
