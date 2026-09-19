import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Fetches the question bank from Firebase Storage at runtime, instead of
/// [QuestionService] only ever reading the copy bundled into the app at
/// build time. This is what lets questions be added/fixed/edited without a
/// new app build or Play Console release: Sanjay keeps editing
/// `assets/data/questions.json` locally exactly as before, with his
/// existing audit/cleanup tooling, then publishes a change by uploading the
/// finished file to Firebase Console -> Storage -> the `content` folder
/// (drag & drop, overwriting `questions.json` there). Every player picks it
/// up on their next app open -- no rebuild, no store review.
///
/// Every app start tries a fresh, short-timeout fetch (same
/// best-effort/never-throws pattern as ServerTimeService and
/// PlayerRepository elsewhere in this app) and caches whatever it gets
/// locally, so:
/// - Online: always the latest published content.
/// - Offline, but a previous fetch succeeded on this device before now:
///   that cached copy, not whatever's bundled in the app.
/// - Offline AND this device has never fetched successfully (e.g. the very
///   first launch, no network yet): this returns null, and
///   [QuestionService] falls back to the bundled asset itself -- this
///   repository doesn't know anything about that fallback, it only ever
///   deals with "remote" vs. "this device's last-known-good remote copy."
///
/// Also true, deliberately, before Sanjay has ever uploaded anything to
/// Storage at all: the fetch below just 404s, is caught, falls through to
/// an empty cache, returns null, and the app runs exactly as it did before
/// this feature existed. Nothing about shipping this is blocked on the
/// Storage file existing yet.
class QuestionRepository {
  static const String _storagePath = 'content/questions.json';
  static const String _cacheFileName = 'questions_cache.json';
  static const Duration _fetchTimeout = Duration(seconds: 8);

  // 5 MB -- comfortably above the ~1 MB current question bank, generous
  // headroom for future growth, still small enough to guard against
  // downloading something absurd if this path is ever misconfigured to
  // point at the wrong object.
  static const int _maxDownloadBytes = 5 * 1024 * 1024;

  /// Returns the freshest available remote question bank JSON as a string,
  /// or null if nothing usable is available at all -- callers should fall
  /// back to the bundled asset in that case. Never throws.
  static Future<String?> loadJsonString() async {
    try {
      final ref = FirebaseStorage.instance.ref(_storagePath);
      final data = await ref
          .getData(_maxDownloadBytes)
          .timeout(_fetchTimeout);
      if (data != null) {
        final jsonString = utf8.decode(data);
        // Not awaited -- caching is a nice-to-have for next time this
        // device is offline, not something worth delaying this call for.
        unawaited(_writeCache(jsonString));
        return jsonString;
      }
      // getData returns null (rather than throwing) when the stored
      // object exceeds _maxDownloadBytes. Without this log line that's
      // indistinguishable from "nothing uploaded yet" or "offline" --
      // every device would just quietly keep serving stale/bundled
      // content forever the day the real question bank grows past the
      // cap, with nothing anywhere to notice it happened.
      debugPrint(
        'QuestionRepository: content/questions.json exceeds the '
        '${_maxDownloadBytes ~/ (1024 * 1024)}MB download cap -- falling '
        'back to cache/bundled asset. Raise _maxDownloadBytes if the '
        'question bank has genuinely grown this large.',
      );
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') {
        // A real problem (permission-denied, a Storage rules
        // misconfiguration, etc.) rather than the expected, harmless
        // "nothing uploaded to Storage yet" case -- worth its own log
        // line so it doesn't read identically to that during testing.
        debugPrint('QuestionRepository: fetch failed (${e.code}): $e');
      }
    } catch (_) {
      // Ignored on purpose -- offline, a timeout, etc. Fall through to
      // the local cache below.
    }

    return _readCache();
  }

  static Future<File> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_cacheFileName');
  }

  static Future<void> _writeCache(String jsonString) async {
    try {
      final file = await _cacheFile();
      await file.writeAsString(jsonString);
    } catch (_) {
      // Ignored on purpose -- worst case, the next offline launch just
      // falls back to the bundled asset instead of a cached remote copy.
    }
  }

  static Future<String?> _readCache() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }
}
