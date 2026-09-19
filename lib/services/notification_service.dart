import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'player_service.dart';
import 'server_time_service.dart';
import 'stamina_service.dart';

/// Local (on-device only, no backend/Cloud Functions -- see the project's
/// launch roadmap for why: Sanjay has deliberately not enabled Firebase's
/// Blaze billing plan, which real server-triggered push would need)
/// reminder notifications for two moments a player might otherwise just
/// forget to come back for:
///
/// - Stamina fully recharged (free players only -- Premium has no stamina
///   cap to wait on).
/// - A day-streak about to lapse (see PlayerService.currentStreak).
///
/// Both `scheduleXIfNeeded` methods are deliberately idempotent and safe to
/// call often with no debouncing needed -- each one fully re-evaluates
/// current state and either (re)schedules its one fixed-ID notification or
/// cancels it, so calling it again with nothing relevant changed just
/// re-arrives at the same answer. HomeScreen.refreshData() is the one call
/// site for both -- it already reloads every other piece of player/stamina
/// state on every app open and every return from a quiz mode, so hooking in
/// there covers "just spent stamina", "just got promoted/streak-extended",
/// "just went Premium", and "just came back after a while" all at once,
/// without needing separate hooks threaded through ModeEntryHelper,
/// StaminaService, or every result screen.
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // Set only once init() has actually succeeded. Every public method below
  // checks this first and silently no-ops if it's false -- a player must
  // never be blocked from playing (or see a crash) just because
  // notification setup failed or hasn't run yet on this launch. See
  // init()'s own try/catch.
  static bool _initialized = false;

  // Fixed, distinct notification IDs -- each `scheduleXIfNeeded` method
  // only ever has at most one notification pending under its own ID, so
  // rescheduling is just "cancel this ID, maybe schedule it again",
  // never a growing pile of stale reminders.
  static const int _staminaFullNotificationId = 1001;
  static const int _streakReminderNotificationId = 1002;

  static const String _channelId = 'mindsprint_reminders';
  static const String _channelName = 'Reminders';

  // init() is called unawaited from splash_screen.dart's startup, and again
  // (retried, per the doc comment below) from both scheduleXIfNeeded
  // methods on every HomeScreen.refreshData() -- so a cold start can easily
  // have two or three calls in flight before _initialized ever flips true.
  // Same "piggyback on the in-flight call" fix as
  // EntitlementRepository.refreshEntitlement()/ServerTimeService.sync():
  // without this, concurrent calls could each independently enter
  // _plugin.initialize()/requestNotificationsPermission() against the same
  // platform channel, and a later-finishing call failing after an earlier
  // one already set _initialized = true would silently flip it back to
  // false, disabling both reminders until some future non-overlapping
  // retry happens to succeed cleanly on its own.
  static Future<void>? _inFlight;

  /// Call once, early in startup (see splash_screen.dart) -- sets up the
  /// plugin, loads the timezone database (needed for zonedSchedule below),
  /// and requests the Android 13+ POST_NOTIFICATIONS runtime permission.
  /// Wrapped in try/catch and flips [_initialized] only on success, same
  /// "never block app startup over a non-critical feature" philosophy
  /// ServerTimeService.sync() and StaminaService's corrupt-timestamp
  /// handling already use elsewhere in this app -- a player on a device
  /// where notification setup fails for some reason should see a perfectly
  /// normal app, just without these two reminders.
  static Future<void> init() {
    if (_initialized) return Future.value();
    return _inFlight ??= _init().whenComplete(() => _inFlight = null);
  }

  static Future<void> _init() async {
    try {
      // Only ever used to build tz.UTC-based instants below (see
      // _scheduleAt) -- this app doesn't need the device's real local zone
      // for anything here, since every reminder time is computed from
      // ServerTimeService's already-UTC-aware "now" and converted with
      // .toUtc() before scheduling. Loading the full IANA database anyway
      // because that's the one documented, always-correct way to get a
      // working tz.UTC.
      tz_data.initializeTimeZones();

      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const initSettings = InitializationSettings(android: androidSettings);
      await _plugin.initialize(initSettings);

      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      // Android 13+ requires this explicit runtime prompt, same shape as
      // any other Android runtime permission -- on 12 and below it's a
      // no-op (the permission doesn't exist pre-13, notifications are
      // allowed by default). A denial here just means these two reminders
      // never show; nothing else in the app depends on it.
      await androidPlugin?.requestNotificationsPermission();

      _initialized = true;
    } catch (e) {
      _initialized = false;
      // Diagnostic only -- debugPrint is throttled/stripped for release
      // builds and never shown to a player. Without this, a systemic,
      // always-failing bug here (e.g. a future plugin/manifest API break)
      // would silently disable both reminders for every install with no
      // signal anywhere to catch it during testing.
      debugPrint('NotificationService.init() failed: $e');
    }
  }

  static Future<void> _cancel(int id) async {
    try {
      await _plugin.cancel(id);
    } catch (_) {
      // Never let a cancel failure propagate -- worst case a stale
      // reminder still fires once, which is a minor annoyance, not a bug
      // worth crashing over.
    }
  }

  static NotificationDetails get _details => const NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Stamina and streak reminders',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
  );

  static Future<void> _scheduleAt({
    required int id,
    required String title,
    required String body,
    required DateTime utcInstant,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(utcInstant, tz.UTC),
        _details,
        // Not time-critical -- see the matching AndroidManifest.xml
        // comment for why this deliberately avoids needing
        // SCHEDULE_EXACT_ALARM (and the separate "Alarms and reminders"
        // special-access screen that permission implies on Android 12+).
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        // Required by this plugin version's zonedSchedule signature.
        // `absoluteTime` is the correct choice here (as opposed to
        // `wallClockTime`) because [utcInstant] is always a real, already-
        // computed absolute point in time -- not a wall-clock time that
        // should shift if the device's timezone changes before it fires.
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      // Scheduling must never throw back into HomeScreen.refreshData() --
      // worst case, this one reminder silently doesn't fire this time, and
      // the next refreshData() call tries again. debugPrint is diagnostic
      // only (throttled/stripped for release, never shown to a player) --
      // without it, a deterministic failure here would silently mean no
      // reminder ever fires for any player, indefinitely, undetected.
      debugPrint('NotificationService._scheduleAt($id) failed: $e');
    }
  }

  /// Re-evaluates whether a "stamina full" reminder should be pending right
  /// now, and (re)schedules or cancels it to match. No-op (and cancels any
  /// stale reminder) for a Premium player, since Premium has no stamina cap
  /// to wait on at all.
  static Future<void> scheduleStaminaFullReminderIfNeeded() async {
    // Retries init() (a cheap no-op once it's already succeeded -- see the
    // guard at its own top) rather than just checking _initialized and
    // bailing. Without this, a transient first-launch init() failure (it
    // races unawaited against AdService/BillingService init on the splash
    // screen) would silently disable both reminders for the rest of the
    // app's process lifetime, with no other code path ever attempting
    // init() again. This is what actually delivers the "every refreshData()
    // after that tries again, so this self-heals" behavior splash_screen.dart
    // already documents at its own NotificationService.init() call site.
    await init();
    if (!_initialized) return;

    if (PlayerService.isPremium) {
      await _cancel(_staminaFullNotificationId);
      return;
    }

    final int needed = StaminaService.maxStamina - StaminaService.currentStamina;
    if (needed <= 0) {
      await _cancel(_staminaFullNotificationId);
      return;
    }

    // Same regen math as StaminaService.refillStamina (1 stamina every 4
    // minutes), projected forward from the same baseline that method
    // itself advances from -- so this lands on the same instant
    // refillStamina would actually finish catching the player up to full,
    // not an approximation.
    final DateTime baseline = StaminaService.lastUpdateTime ?? ServerTimeService.now();
    final DateTime fullAt = baseline.add(Duration(minutes: needed * 4));

    if (!fullAt.isAfter(ServerTimeService.now())) {
      // Already due (or overdue) by wall-clock math -- e.g. the app was
      // closed long enough that stamina is already effectively full and
      // just hasn't been recomputed into the stored value yet. Nothing
      // useful to remind about.
      await _cancel(_staminaFullNotificationId);
      return;
    }

    await _scheduleAt(
      id: _staminaFullNotificationId,
      title: "Stamina's full!",
      body: "Your energy is fully recharged -- jump back in for another round.",
      utcInstant: fullAt.toUtc(),
    );
  }

  /// Re-evaluates whether a "don't lose your streak" reminder should be
  /// pending right now, and (re)schedules or cancels it to match.
  ///
  /// Timed 4 hours before whichever UTC-day deadline the player's streak
  /// actually depends on next (see PlayerService.currentStreak /
  /// hasPlayedToday / isStreakAtRisk for the day-boundary rules this
  /// mirrors): today's deadline if they haven't played yet today and are
  /// at risk, or tomorrow's if they have (today is already secured, so the
  /// next thing that can break the streak is missing tomorrow entirely).
  /// A 4-hour lead time is a nudge, not a last-second alarm -- enough
  /// runway for the player to actually fit a quick round in before the
  /// boundary passes, especially given inexact scheduling can land a bit
  /// early or late anyway.
  static Future<void> scheduleStreakReminderIfNeeded() async {
    // See the matching comment in scheduleStaminaFullReminderIfNeeded --
    // same retry-on-every-call reasoning applies here.
    await init();
    if (!_initialized) return;

    final int streak = PlayerService.displayStreak;
    if (streak <= 0) {
      await _cancel(_streakReminderNotificationId);
      return;
    }

    final DateTime now = ServerTimeService.now().toUtc();
    final DateTime todayUtcDate = DateTime.utc(now.year, now.month, now.day);
    final DateTime deadline =
        PlayerService.hasPlayedToday
            ? todayUtcDate.add(const Duration(days: 2))
            : todayUtcDate.add(const Duration(days: 1));
    final DateTime reminderAt = deadline.subtract(const Duration(hours: 4));

    if (!reminderAt.isAfter(now)) {
      // Less than 4 hours left before the relevant deadline (or it's
      // already passed) -- too late for this particular nudge to be
      // useful; the next scheduleStreakReminderIfNeeded call (next time
      // HomeScreen refreshes) will re-evaluate against whatever's true by
      // then.
      await _cancel(_streakReminderNotificationId);
      return;
    }

    await _scheduleAt(
      id: _streakReminderNotificationId,
      title: "Don't lose your $streak day streak!",
      body: "Play one quick round today to keep it going.",
      utcInstant: reminderAt,
    );
  }
}
