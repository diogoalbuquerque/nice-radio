// A request to control the radio from outside the app's own screen: a
// Siri/Shortcuts action on iOS, or a launcher shortcut / Google Assistant
// App Action on Android. Both platforms translate whatever the OS gave
// them into this one shape, so the app has a single place that decides
// what each request *does* (`VoiceCommandHandler`).

enum VoiceAction { play, pause, next, previous, playStation }

class VoiceCommand {
  final VoiceAction action;

  /// Exact station id (iOS Shortcuts picks from the cached list), for
  /// `playStation`. Wins over [station] when both are present.
  final String? stationId;

  /// Free-text station name or frequency (Android URI), for `playStation`.
  final String? station;

  const VoiceCommand(this.action, {this.stationId, this.station});

  /// The custom URL scheme Android shortcuts and App Actions use:
  /// `niceradio://play`, `niceradio://pause`, `niceradio://next`,
  /// `niceradio://previous`, `niceradio://station?name=Antena 1`.
  /// Google Assistant's generic "open app feature" action arrives as
  /// `niceradio://feature?featureName=pause`.
  static const scheme = 'niceradio';

  /// Accepts the native side's map: either `{'uri': 'niceradio://…'}`
  /// (Android) or `{'action': 'playStation', 'stationId': '…'}`
  /// (iOS). Returns null for anything unrecognized, so a malformed request
  /// is ignored instead of crashing the app.
  static VoiceCommand? fromMap(Map<Object?, Object?> map) {
    final uri = map['uri'];
    if (uri is String) return fromUri(uri);
    return _build(map['action'] as String?, map['stationId'] as String?, map['station'] as String?);
  }

  static VoiceCommand? fromUri(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != scheme) return null;
    var action = uri.host.toLowerCase();
    if (action == 'feature') {
      action = (uri.queryParameters['featureName'] ?? '').toLowerCase();
    }
    return _build(action, null, uri.queryParameters['name']);
  }

  static VoiceCommand? _build(String? action, String? stationId, String? station) {
    switch (action?.toLowerCase()) {
      case 'play':
        return const VoiceCommand(VoiceAction.play);
      case 'pause':
        return const VoiceCommand(VoiceAction.pause);
      case 'next':
        return const VoiceCommand(VoiceAction.next);
      case 'previous':
        return const VoiceCommand(VoiceAction.previous);
      case 'station' || 'playstation':
        final query = station?.trim();
        final id = stationId?.trim();
        if (id != null && id.isNotEmpty) return VoiceCommand(VoiceAction.playStation, stationId: id, station: query);
        return query == null || query.isEmpty ? null : VoiceCommand(VoiceAction.playStation, station: query);
    }
    return null;
  }
}
