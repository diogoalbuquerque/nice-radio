// Generates artwork for surfaces outside the app's own widget tree, where
// `StationAvatar` (the in-app favicon-or-initials box — see
// station_avatar.dart) can't be used directly because there is no Flutter
// widget tree there at all: the lock-screen/notification media artwork
// (iOS's MPNowPlayingInfoCenter, Android's media-session notification
// icon) and the home-screen widget's own station-logo box (Android App
// Widget / iOS WidgetKit). Reported directly, with a screenshot of an
// empty artwork square on a real iPhone's lock screen for a station with
// no favicon.
//
// WHY a real generated PNG instead of, say, a solid-color asset swapped
// in per station: both the lock-screen artwork and the home-screen
// widgets' native image views only understand actual image data (a local
// file or raw bytes) — there's no "draw this Flutter widget as native
// artwork" API. Rendering with `dart:ui`'s `Canvas` directly (the same
// primitive `CustomPainter` is built on) and encoding to PNG is the
// standard way to turn arbitrary drawn content into bytes those APIs can
// use.
//
// WHY this always downloads a real favicon itself rather than just
// handing `audio_service` the remote URL to fetch natively: confirmed by
// reading `audio_service 0.18.19`'s own native source
// (AudioServicePlugin.m/AudioService.java) — on *both* platforms, a plain
// `MediaItem.artUri` is not actually fetched at all unless it is a
// `content://` URI (Android) or arrives via `extras['artCacheFile']` (a
// local file path, both platforms). A plain `https://` URL in `artUri`
// silently renders nothing — this was found by hand, from a real "no
// artwork ever appears" run, not assumed from the package's docs, which
// don't mention this. So every MediaItem this app publishes for actual
// playback needs a real *local* file already downloaded/generated ahead
// of time; see RadioAudioHandler for where `extras['artCacheFile']` (and,
// on iOS specifically, a matching non-null `artUri` — see that class's own
// doc for a second, gnarlier native quirk this needed) is set from
// `cachedArtworkFilePath`'s result.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/radio_station.dart';

class StationArtworkService {
  static const _size = 512.0;

  /// A local filesystem path (not a URI) to [station]'s logo — its real
  /// favicon when one exists and can be downloaded, otherwise a generated
  /// initials image (see `_renderInitialsPng`) — written to the temp
  /// directory on first use and reused after that. Returns `null` only if
  /// both the favicon fetch and the initials render fail (never in
  /// practice, since the initials render has no network dependency).
  Future<String?> cachedArtworkFilePath(RadioStation station) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/station_logo_${station.id.hashCode}.png');
    if (await file.exists()) return file.path;

    final bytes = await logoBytes(station);
    if (bytes == null) return null;
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Raw PNG bytes for [station]'s logo — its real favicon when one
  /// exists and can be downloaded, otherwise a generated initials image.
  /// Used directly by the home-screen widget (which needs bytes to hand
  /// to a native `Bitmap`/`UIImage`, not a file path) and, via
  /// [cachedArtworkFilePath], by the lock-screen/notification artwork. A
  /// short timeout keeps a slow/unreachable favicon host from stalling an
  /// update — same reasoning as `PlayerNotifier`'s own `_connectTimeout`,
  /// just for an image fetch instead of a stream.
  Future<Uint8List?> logoBytes(RadioStation station) async {
    final faviconUrl = station.faviconUrl;
    if (faviconUrl != null) {
      try {
        final uri = Uri.parse(faviconUrl);
        final response = await http.get(uri).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          return response.bodyBytes;
        }
      } catch (_) {
        // Broken/unreachable favicon — same "not an error, just fall back"
        // treatment as StationAvatar's own errorBuilder.
      }
    }
    try {
      return await _renderInitialsPng(station);
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> _renderInitialsPng(RadioStation station) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = const Rect.fromLTWH(0, 0, _size, _size);

    // Same shape/proportions as `_InitialsBox`: a rounded square in the
    // station's avatar color with its initials centered in bold white.
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(_size * 0.22)),
      Paint()..color = station.avatarColor,
    );

    final painter = TextPainter(
      text: TextSpan(
        text: station.initials,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: _size * 0.32),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset((_size - painter.width) / 2, (_size - painter.height) / 2));

    final image = await recorder.endRecording().toImage(_size.toInt(), _size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }
}
