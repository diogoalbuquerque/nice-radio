// The app's core data type: one radio station, as returned by the
// Radio Browser API (https://api.radio-browser.info) and trimmed down to
// only the fields Nice Radio actually displays or uses.
//
// WHY not just pass the raw JSON map around: a typed model gives us one
// place (fromJson) where "the API sent something unexpected" is handled,
// instead of every screen doing its own defensive `json['x'] as String?`
// checks and risking a crash if a field is missing (which does happen —
// Radio Browser is a crowdsourced database and not every entry is
// complete).
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

@immutable
class RadioStation {
  /// Radio Browser's `stationuuid`. Stable across requests, so this is
  /// what we use as the identity for favorites — never the station name,
  /// which is not guaranteed unique (there are multiple "Antena 1"s).
  final String id;

  final String name;
  final String streamUrl;
  final String? faviconUrl;

  /// A short, human-friendly genre label, e.g. "Sertanejo". Radio Browser
  /// stores free-text tags (comma-separated, inconsistent casing); we
  /// take the first one and title-case it rather than showing the raw
  /// tag soup, which is what most of the sources actually look like.
  final String genre;

  final String state;
  final int bitrateKbps;

  const RadioStation({
    required this.id,
    required this.name,
    required this.streamUrl,
    required this.faviconUrl,
    required this.genre,
    required this.state,
    required this.bitrateKbps,
  });

  /// Builds a station from one entry of Radio Browser's `/stations/search`
  /// response. Returns `null` when the entry is unusable (no id or no
  /// stream URL) instead of throwing, so one bad entry in a 50-station
  /// response does not take down the whole list — see
  /// [RadioBrowserService] for where the `null`s get filtered out.
  static RadioStation? fromJson(Map<String, dynamic> json) {
    final id = json['stationuuid'] as String?;
    // Validated the same way favicon URLs already are (http/https only) —
    // Radio Browser is a crowdsourced, untrusted-input API, and this is
    // fed straight into just_audio's setUrl() with no other gate. A
    // non-http(s) scheme (a malformed entry, or a mirror returning
    // something unexpected) can't be a real playable radio stream anyway,
    // so treating it the same as a missing URL — drop the whole entry —
    // is strictly safer than passing it through unchecked.
    final streamUrl = _cleanUrl(json['url_resolved'] as String?) ?? _cleanUrl(json['url'] as String?);
    final name = json['name'] as String?;

    if (id == null || id.isEmpty || streamUrl == null || streamUrl.isEmpty) {
      return null;
    }

    return RadioStation(
      id: id,
      name: (name == null || name.trim().isEmpty) ? 'Rádio sem nome' : name.trim(),
      streamUrl: streamUrl,
      faviconUrl: _cleanUrl(json['favicon'] as String?),
      genre: _firstTag(json['tags'] as String?),
      state: (json['state'] as String?)?.trim() ?? '',
      bitrateKbps: (json['bitrate'] as num?)?.toInt() ?? 0,
    );
  }

  /// Round-trips a station through [SharedPreferences] as JSON — used to
  /// remember "the last station played" across app restarts, which the
  /// home-screen quick action needs (see `StorageService.getLastStation`):
  /// a shortcut tapped after the app was fully closed has no in-memory
  /// [PlayerNotifier] state to read from, only whatever was last saved.
  ///
  /// WHY a dedicated pair instead of reusing [fromJson]/matching its
  /// shape: [fromJson] parses Radio Browser's API response shape
  /// (`stationuuid`, `url_resolved`, comma-separated `tags`, ...), which
  /// is a different, larger shape than this app's own trimmed-down
  /// model. Conflating the two would mean a future change to how we
  /// *parse the API* could silently break *cached persistence*, or vice
  /// versa — two unrelated concerns that happen to look similar.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'streamUrl': streamUrl,
        'faviconUrl': faviconUrl,
        'genre': genre,
        'state': state,
        'bitrateKbps': bitrateKbps,
      };

  /// The other half of [toJson]. Returns `null` if [json] is missing a
  /// required field — e.g. because a future app version changes this
  /// shape and reads back data written by an older one — so a corrupt or
  /// stale cache entry is silently ignored rather than crashing startup.
  static RadioStation? fromCache(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final name = json['name'] as String?;
    final streamUrl = json['streamUrl'] as String?;
    if (id == null || name == null || streamUrl == null) return null;

    return RadioStation(
      id: id,
      name: name,
      streamUrl: streamUrl,
      faviconUrl: json['faviconUrl'] as String?,
      genre: json['genre'] as String? ?? 'Rádio',
      state: json['state'] as String? ?? '',
      bitrateKbps: (json['bitrateKbps'] as num?)?.toInt() ?? 0,
    );
  }

  static String? _cleanUrl(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    // Radio Browser occasionally stores non-http(s) or malformed URLs
    // (favicon *and* stream URLs alike) — validating here means both the
    // favicon fallback (Image.network would just fail silently later) and
    // fromJson's own "unusable entry" check (a stream URL this app has no
    // business handing to just_audio's setUrl()) can rely on always
    // having a genuine http(s) URL or nothing at all.
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || !uri.isScheme('https') && !uri.isScheme('http')) {
      return null;
    }
    return uri.toString();
  }

  static String _firstTag(String? tags) {
    if (tags == null || tags.trim().isEmpty) return 'Rádio';
    final first = tags.split(',').first.trim();
    if (first.isEmpty) return 'Rádio';
    return first[0].toUpperCase() + first.substring(1);
  }

  /// Up to two letters shown on the fallback avatar when there is no
  /// (usable) [faviconUrl] — e.g. "Antena 1 SP" -> "AS".
  ///
  /// WHY words are filtered to ones starting with a letter: real station
  /// names from Radio Browser often carry technical suffixes in brackets,
  /// e.g. "Antena 1 São Paulo, SP (ZYD823 94,7 MHz FM) [aac]" — naively
  /// taking the first letter of the *last* word there would grab "[" from
  /// "[aac]", not a real initial. Numbers ("1") are skipped the same way,
  /// for the same reason.
  String get initials {
    final letterWords = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && RegExp(r'^[A-Za-zÀ-ÿ]').hasMatch(w))
        .toList();

    if (letterWords.isEmpty) return '?';
    if (letterWords.length == 1) return letterWords.first.substring(0, 1).toUpperCase();
    return (letterWords.first.substring(0, 1) + letterWords.last.substring(0, 1)).toUpperCase();
  }

  /// A deterministic color from [AppColors.avatarPalette], picked by
  /// hashing [id]. WHY hash the id and not the name: the id never
  /// changes for a given station, so its color stays stable even if the
  /// station is renamed upstream; hashing the name could make a
  /// station's color flicker between app updates.
  Color get avatarColor {
    final palette = AppColors.avatarPalette;
    return palette[id.hashCode.abs() % palette.length];
  }

  static final RegExp _freqNumberFirst = RegExp(
    r'(\d{2,4}(?:[.,]\d{1,2})?)\s*(?:mhz\s*)?\b(fm|am)\b',
    caseSensitive: false,
  );
  static final RegExp _freqBandFirst = RegExp(
    r'\b(fm|am)\s*(\d{2,4}(?:[.,]\d{1,2})?)',
    caseSensitive: false,
  );

  /// Best-effort FM/AM frequency parsed out of [name] — Radio Browser has
  /// no dedicated frequency field, but Brazilian station names almost
  /// always embed one, e.g. "Antena 1 São Paulo, SP (94,7 MHz FM)" or
  /// "Jovem Pan FM 100.9". `null` when nothing frequency-shaped is found,
  /// which [frequencySortKey] and [displayName] both then treat as "no
  /// frequency" rather than guessing one. Deliberately never consulted by
  /// [initials] or [avatarColor] above — both keep reading [name]
  /// directly, so reordering/reformatting the display text below can
  /// never change a station's avatar.
  ({double value, String label, String matched})? get _frequency {
    final numberFirst = _freqNumberFirst.firstMatch(name);
    if (numberFirst != null) {
      final value = double.tryParse(numberFirst.group(1)!.replaceAll(',', '.'));
      if (value != null) {
        return (
          value: value,
          label: '${numberFirst.group(1)} ${numberFirst.group(2)!.toUpperCase()}',
          matched: numberFirst.group(0)!,
        );
      }
    }
    final bandFirst = _freqBandFirst.firstMatch(name);
    if (bandFirst != null) {
      final value = double.tryParse(bandFirst.group(2)!.replaceAll(',', '.'));
      if (value != null) {
        return (
          value: value,
          label: '${bandFirst.group(1)!.toUpperCase()} ${bandFirst.group(2)}',
          matched: bandFirst.group(0)!,
        );
      }
    }
    return null;
  }

  /// Sort key for ordering stations like a real radio dial — see
  /// `sortStationsByFrequency` in `stations_provider.dart`. Stations with
  /// no detectable frequency sort after every station that has one.
  double get frequencySortKey => _frequency?.value ?? double.infinity;

  /// [name] with its frequency moved to the front, e.g. "94,7 FM — Antena
  /// 1 São Paulo" — falls back to the plain [name] when no frequency was
  /// found. This is what the station list and the player show; avoid
  /// feeding this into anything that computes the avatar ([initials],
  /// [avatarColor]) — both intentionally read [name] itself, never this
  /// getter, so a station's avatar never changes because of this.
  String get displayName {
    final freq = _frequency;
    if (freq == null) return name;
    final rest = name
        .replaceFirst(freq.matched, '')
        .replaceAll(RegExp(r'\(\s*\)'), '')
        .replaceAll(RegExp(r'\[\s*\]'), '')
        .replaceAllMapped(RegExp(r'\s+([)\]])'), (m) => m.group(1)!)
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim()
        .replaceAll(RegExp(r'^[\s,\-–]+|[\s,\-–]+$'), '');
    return rest.isEmpty ? freq.label : '${freq.label} — $rest';
  }

  /// One-line label for pickers that show many stations at once (Siri /
  /// Shortcuts): "RJ - 98,1 FM - O Dia", i.e. state abbreviation, then
  /// frequency, then the name. Without a detectable frequency it is
  /// "RJ - O Dia"; without [stateAbbreviation] the prefix is left out.
  String listLabel(String? stateAbbreviation) {
    final prefix = stateAbbreviation == null ? '' : '$stateAbbreviation - ';
    return '$prefix${displayName.replaceFirst(' — ', ' - ')}';
  }
}
