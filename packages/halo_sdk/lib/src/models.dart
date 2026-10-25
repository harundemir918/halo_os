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
    this.walkMinutes,
    this.attendees,
  });

  final DateTime start;
  final String title;

  /// Where it is, or a status shown in the same slot (`Unconfirmed`).
  final String location;

  /// Walking time to the venue, when known.
  final int? walkMinutes;

  /// Number of people, when known.
  final int? attendees;

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
    this.actionPrompt,
  });

  final String id;

  /// Source app id (`messages`, `parcel`).
  final String app;

  /// Mono sender label as shown (`Elif`, `Parcel`).
  final String sender;
  final String body;
  final DateTime receivedAt;
  final bool unread;

  /// Short question Halo offers to answer from Home (`Still on for 7?`).
  final String? actionPrompt;

  /// Compact age as the designs show it: `2M`, `1H`, `3D`.
  String age(DateTime now) {
    final d = now.difference(receivedAt);
    if (d.inMinutes < 60) return '${d.inMinutes < 1 ? 1 : d.inMinutes}M';
    if (d.inHours < 24) return '${d.inHours}H';
    return '${d.inDays}D';
  }
}

/// An installed app, in arc order.
class HaloAppInfo {
  const HaloAppInfo({required this.id, required this.label});

  /// Stable id (`messages`).
  final String id;
  final String label;
}
