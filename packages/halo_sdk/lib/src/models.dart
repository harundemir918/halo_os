/// Battery and connectivity for the status row.
class DeviceStatus {
  const DeviceStatus({required this.battery, required this.network});

  /// 0 to 1.
  final double battery;

  /// Connectivity summary such as `5G · WI-FI`.
  final String network;

  int get batteryPercent => (battery.clamp(0.0, 1.0) * 100).round();
}

/// A calendar entry.
class CalendarEvent {
  const CalendarEvent({
    required this.start,
    required this.title,
    required this.location,
  });

  final DateTime start;
  final String title;
  final String location;

  /// Whole minutes from [now] until the event starts, never negative.
  int minutesUntil(DateTime now) {
    final m = start.difference(now).inMinutes;
    return m < 0 ? 0 : m;
  }
}

/// A notification in the Stream timeline.
class HaloNotification {
  const HaloNotification({
    required this.id,
    required this.app,
    required this.sender,
    required this.body,
    required this.receivedAt,
    required this.unread,
  });

  final String id;

  /// Source app id (`messages`, `parcel`).
  final String app;

  /// Mono sender label as shown (`Elif`, `Parcel`).
  final String sender;
  final String body;
  final DateTime receivedAt;
  final bool unread;

  /// Compact age as the designs show it: `2M`, `1H`, `3D`.
  String age(DateTime now) {
    final d = now.difference(receivedAt);
    if (d.inMinutes < 60) return '${d.inMinutes < 1 ? 1 : d.inMinutes}M';
    if (d.inHours < 24) return '${d.inHours}H';
    return '${d.inDays}D';
  }
}
