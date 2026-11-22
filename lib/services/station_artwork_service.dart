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

  final http.Client _client;
  final Future<Directory> Function() _cacheDir;

  /// [client] and [cacheDir] are for tests.
  StationArtworkService({http.Client? client, Future<Directory> Function()? cacheDir})
      : _client = client ?? http.Client(),
        _cacheDir = cacheDir ?? getTemporaryDirectory;

  /// The logo at [url] (a station's `faviconUrl`) downloaded once into the cache folder and reused after
  /// that, or `null` when it has none or the download fails (not cached, so it
  /// is tried again next time). The file is named after the URL, which carries
  /// a content hash (`<id>-<hash>.png`, see `tool/build_stations.py`): a changed
  /// logo gets a new file instead of a stale one. The temp folder can be
  /// cleared by the OS; that only costs a re-download.
  Future<File?> cachedLogoFile(String? url) async {
    if (url == null) return null;
    try {
      final dir = Directory('${(await _cacheDir()).path}/station_logos');
      final file = File('${dir.path}/${url.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}');
      if (await file.exists()) return file;
      final response = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
      await dir.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes, flush: true);
      return file;
    } catch (_) {
      // Unreachable/broken logo: the caller falls back to the initials.
      return null;
    }
  }

  /// A local file path (not a URI) for the lock-screen/notification artwork:
  /// the cached logo, else a generated initials image (see `_renderInitialsPng`,
  /// cached separately so a logo that downloads later still wins). `null` only
  /// if the initials render fails too (never in practice).
  Future<String?> cachedArtworkFilePath(RadioStation station) async {
    final logo = await cachedLogoFile(station.faviconUrl);
    if (logo != null) return logo.path;
    try {
      final file = File('${(await _cacheDir()).path}/station_initials_${station.id.hashCode}.png');
      if (!await file.exists()) await file.writeAsBytes(await _renderInitialsPng(station), flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// Raw PNG bytes for [station]'s logo (the cached download), else a
  /// generated initials image. Used by the home-screen widget, which needs
  /// bytes to hand to a native `Bitmap`/`UIImage`.
  Future<Uint8List?> logoBytes(RadioStation station) async {
    final logo = await cachedLogoFile(station.faviconUrl);
    if (logo != null) {
      try {
        return await logo.readAsBytes();
      } catch (_) {
        // Fall through to the initials.
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
