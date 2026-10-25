import 'dart:async';

import 'backend.dart';
import 'models.dart';

/// Fixtures that reuse the copy from the designs (design/screens/) so golden
/// tests line up: Friday 23 October, 09:41, Design review in Room 3, Elif.
class MockBackend implements HaloBackend {
  MockBackend({DateTime? now}) : now = now ?? DateTime(2026, 10, 23, 9, 41);

  @override
  final DateTime now;

  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  DeviceStatus get status =>
      const DeviceStatus(battery: 0.82, network: '5G · WI-FI', fullBy: '10:20');

  QuickSettings _quick = const QuickSettings(
    brightness: 0.64,
    brightnessAuto: true,
    volume: 0.42,
    volumeFooter: 'Media · ring',
    toggles: [
      QuickToggle(id: 'wifi', title: 'Wi-Fi', detail: 'Home-5G', on: true),
      QuickToggle(
        id: 'bluetooth',
        title: 'Bluetooth',
        detail: '2 devices',
        on: true,
      ),
      QuickToggle(id: 'cellular', title: 'Cellular', detail: '5G', on: true),
      QuickToggle(id: 'airplane', title: 'Airplane', detail: 'Off', on: false),
      QuickToggle(
        id: 'focus',
        title: 'Focus',
        detail: 'Work · until 11:00',
        on: true,
      ),
    ],
    media: MediaSession(
      title: 'Night Drive',
      artist: 'Mira Okafor',
      progress: 0.42,
      playing: true,
    ),
  );

  @override
  QuickSettings get quick => _quick;

  void _update(QuickSettings next) {
    _quick = next;
    _changes.add(null);
  }

  @override
  void setToggle(String id, bool on) {
    var toggles = [
      for (final t in _quick.toggles) t.id == id ? t.copyWith(on: on) : t,
    ];
    if (id == 'airplane') {
      // Airplane mode switches the radios off; leaving it does not bring them back.
      toggles = [
        for (final t in toggles)
          switch (t.id) {
            'wifi' ||
            'bluetooth' ||
            'cellular' when on => t.copyWith(on: false, detail: 'Off'),
            'airplane' => t.copyWith(detail: on ? 'On' : 'Off'),
            _ => t,
          },
      ];
    }
    _update(_quick.copyWith(toggles: toggles));
  }

  @override
  void setBrightness(double value) => _update(
    _quick.copyWith(brightness: value.clamp(0.0, 1.0), brightnessAuto: false),
  );

  @override
  void setVolume(double value) =>
      _update(_quick.copyWith(volume: value.clamp(0.0, 1.0)));

  @override
  void setPlaying(bool playing) {
    final m = _quick.media;
    if (m == null) return;
    _update(_quick.copyWith(media: m.copyWith(playing: playing)));
  }

  DateTime _at(int h, int m) => DateTime(now.year, now.month, now.day, h, m);

  @override
  List<CalendarEvent> get agenda => [
    CalendarEvent(
      start: _at(10, 0),
      title: 'Design review',
      location: 'Room 3',
      walkMinutes: 2,
      attendees: 4,
    ),
    CalendarEvent(
      start: _at(13, 30),
      title: 'Lunch with Elif',
      location: 'Karaköy',
    ),
    CalendarEvent(
      start: _at(19, 0),
      title: 'Dinner, corner table',
      location: 'Unconfirmed',
    ),
  ];

  @override
  CalendarEvent? get nextEvent {
    for (final e in agenda) {
      if (!e.start.isBefore(now)) return e;
    }
    return null;
  }

  @override
  List<HaloAppInfo> get apps => const [
    HaloAppInfo(id: 'notes', label: 'Notes'),
    HaloAppInfo(id: 'maps', label: 'Maps'),
    HaloAppInfo(id: 'music', label: 'Music'),
    HaloAppInfo(id: 'messages', label: 'Messages'),
    HaloAppInfo(id: 'camera', label: 'Camera'),
    HaloAppInfo(id: 'web', label: 'Web'),
    HaloAppInfo(id: 'phone', label: 'Phone'),
  ];

  @override
  List<HaloNotification> get notifications => [
    HaloNotification(
      id: 'elif-1',
      app: 'messages',
      sender: 'Elif',
      body: 'Are we still on for 7?',
      receivedAt: now.subtract(const Duration(minutes: 2)),
      unread: true,
      actionPrompt: 'Still on for 7?',
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
