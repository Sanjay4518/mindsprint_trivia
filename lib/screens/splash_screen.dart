import 'dart:async';
import 'package:flutter/material.dart';
import '../services/ad_service.dart';
import '../services/auth_service.dart';
import '../services/billing_service.dart';
import '../services/entitlement_repository.dart';
import '../services/notification_service.dart';
import '../services/player_repository.dart';
import '../services/player_service.dart';
import '../services/question_service.dart';
import '../services/server_time_service.dart';
import '../services/settings_service.dart';
import '../services/stamina_service.dart';
import '../services/update_service.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _textFade;
  late final Animation<Offset> _textSlide;
  late final Animation<double> _spinnerFade;

  static const _animDuration = Duration(milliseconds: 1700);

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(vsync: this, duration: _animDuration);

    // Logo: fades in and zooms up from slightly-small to full size with a
    // gentle overshoot ("pop"), finishing in the first ~half of the timeline.
    _logoScale = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack),
      ),
    );
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
      ),
    );

    // App name + tagline: fade and slide up shortly after the logo settles.
    _textFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.42, 0.75, curve: Curves.easeOut),
      ),
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.42, 0.75, curve: Curves.easeOut),
      ),
    );

    // Loading spinner: fades in last, once the branding has settled.
    _spinnerFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.75, 1.0, curve: Curves.easeOut),
      ),
    );

    // Run the entrance animation and the real app initialization at the same
    // time. Whichever takes longer decides when we navigate to Home: on a
    // fast device the full animation always gets to play out in full, and on
    // a slower device we're not sitting on a finished animation waiting for
    // services to load either, since both start together.
    Future.wait([
      _controller.forward(),
      initializeApp(),
    ]).then((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    });
  }

  Future<void> initializeApp() async {
    try {
      // Silently gives every player a real backend account -- no sign-in
      // screen, nothing typed. If this fails (e.g. no internet on first
      // launch), we deliberately don't block the player from playing --
      // local gameplay works exactly as before either way, and this just
      // retries on the next app start.
      await AuthService.ensureSignedIn();
    } catch (_) {
      // Ignored on purpose -- see comment above.
    }
    try {
      // Establishes the device-vs-server clock offset before stamina/Premium
      // get read below, so regen and expiry checks start out trustworthy
      // right from app open. If this fails (offline), stamina/Premium just
      // fall back to the device clock like before -- see ServerTimeService.
      await ServerTimeService.sync();
    } catch (_) {
      // Ignored on purpose -- see comment above.
    }
    try {
      await PlayerService.loadPlayer();
    } catch (_) {
      // Ignored on purpose -- a corrupt local profile shouldn't strand
      // the player on this screen forever. PlayerService's fields keep
      // their declared defaults, so the player just starts this session
      // looking like a fresh guest rather than being unable to open the
      // app at all.
    }
    // If an earlier restore attempt failed (offline, a Firestore hiccup
    // right after sign-in) and hasn't succeeded since, this is the
    // earliest possible moment to quietly retry it -- before the sync
    // below runs, and without the player needing to do anything (like
    // reopening the Profile screen) to trigger the retry themselves. See
    // PlayerRepository.hasPendingRestore/syncCurrentPlayer's guard.
    try {
      if (AuthService.isLinkedWithGoogle &&
          await PlayerRepository.hasPendingRestore()) {
        final outcome = await PlayerRepository.restorePlayerFromCloud();
        if (outcome != RestoreOutcome.failed) {
          // Confirmed caught up -- run the name-autofill/bonus-claim
          // steps that would normally follow a successful restore right
          // after linking, in case the original attempt (back in
          // handleLinkGoogle/_handleSubscribe) failed and skipped them.
          // No snackbar here on purpose: there's no screen open yet to
          // show one on, and the player will just see the correct name
          // and an already-claimed bonus once they get to Home/Profile.
          await PlayerRepository.applyPostLinkSetupIfNeeded();
        }
      }
    } catch (_) {
      // Ignored on purpose -- restorePlayerFromCloud/applyPostLinkSetup-
      // IfNeeded aren't expected to throw, but this stays defensive/
      // consistent with everything else in this method.
    }
    // Pushes current stats to the cloud in the background -- never awaited,
    // so a slow/offline network never delays app startup. Safe even if the
    // retry above didn't succeed -- syncCurrentPlayer() has its own guard
    // against pushing while a restore is still pending.
    unawaited(PlayerRepository.syncCurrentPlayer());
    try {
      await StaminaService.loadStamina();
    } catch (_) {
      // Ignored on purpose -- same reasoning as PlayerService above.
    }
    try {
      await SettingsService.loadSettings();
    } catch (_) {
      // Ignored on purpose -- same reasoning as PlayerService above.
    }
    try {
      // The one most likely to actually throw in practice: a single
      // malformed record in assets/data/questions.json (a missing field,
      // a wrong type) used to reject this whole initializeApp() call and
      // hang the app on this screen forever with no error shown --
      // content edits to that file (see the Phase B cleanup pass)
      // shouldn't be able to brick every install until the next store
      // update. The quiz screens already handle an empty question list
      // without crashing (they just show a loading spinner), so failing
      // this open is safe.
      await QuestionService.loadQuestions();
    } catch (_) {
      // Ignored on purpose -- see comment above.
    }
    // Unawaited, same reasoning as AdService/BillingService just below --
    // this can include an Android 13+ system permission prompt, which
    // should never hold up getting the player into the app. Worst case,
    // the very first HomeScreen.refreshData() call (right after this
    // screen navigates away) runs before init() finishes and its own two
    // scheduleXIfNeeded calls silently no-op for that one call; every
    // refreshData() after that (every mode entry, every screen return)
    // tries again, so this self-heals within moments.
    unawaited(NotificationService.init());
    // Kicks off the Play In-App Update check/background-download as early
    // as possible, same reasoning as the other unawaited calls here --
    // never delay getting the player into the app over it. A flexible
    // download can take a while; HomeScreen.initState() awaits this same
    // call again (piggybacking the in-flight check, see UpdateService) so
    // it can show a "Restart to update" prompt the moment it's ready,
    // whenever that ends up being.
    unawaited(UpdateService.checkAndStartFlexibleUpdate());
    unawaited(AdService.instance.initialize());
    // Billing setup + the first real subscription check both happen in the
    // background -- neither should ever delay getting the player into the
    // app. EntitlementRepository.refreshEntitlement() is a no-op until
    // BillingService finishes initializing, but every Home screen reload
    // after this (which happens constantly) tries again.
    unawaited(
      BillingService.initialize().then(
        (_) => EntitlementRepository.refreshEntitlement(),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D1126), Color(0xFF3D297A)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ScaleTransition(
                  scale: _logoScale,
                  child: FadeTransition(
                    opacity: _logoFade,
                    child: Container(
                      width: 150,
                      height: 150,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFFF7B538,
                            ).withValues(alpha: 0.16),
                            blurRadius: 70,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/images/mindsprint_mark.png',
                        width: 130,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                FadeTransition(
                  opacity: _textFade,
                  child: SlideTransition(
                    position: _textSlide,
                    child: const Column(
                      children: [
                        Text(
                          "MindSprint Trivia",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          "Train faster. Recall sharper.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                FadeTransition(
                  opacity: _spinnerFade,
                  child: const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFFF7B538),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
