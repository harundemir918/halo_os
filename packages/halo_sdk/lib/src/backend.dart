import 'models.dart';

/// What the shell can ask the system. Phase 4 adds a real implementation over
/// halo-bus; until then [MockBackend] serves fixtures. The getters are
/// snapshots for now; reactive streams arrive with the real backend.
abstract interface class HaloBackend {
  /// Current local time.
  DateTime get now;

  DeviceStatus get status;

  /// The next calendar event today, if any.
  CalendarEvent? get nextEvent;

  /// Notifications, newest first.
  List<HaloNotification> get notifications;
}
