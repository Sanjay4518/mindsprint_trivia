import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'player_service.dart';

class AdService {
  AdService._();

  static final AdService instance = AdService._();

  RewardedAd? _rewardedAd;
  bool _isLoadingRewarded = false;

  InterstitialAd? _interstitialAd;
  bool _isLoadingInterstitial = false;

  // Interstitial pacing: shown after every Nth quiz completion, and only
  // once the player has been using the app for a minimum "warm-up" period
  // this session. Both the completion count and session start are
  // in-memory only, so they reset fresh on every app launch.
  DateTime? _sessionStartedAt;
  int _quizCompletionsThisSession = 0;
  static const int _showInterstitialEveryNCompletions = 2;
  static const Duration _interstitialWarmup = Duration(minutes: 12);

  bool get _adsSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  String get rewardedAdUnitId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Real MindSprint Trivia rewarded ad unit (AdMob account set up 2026-07-26).
      return 'ca-app-pub-6370450824074258/2471447753';
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      // Still Google's public test ID -- iOS/App Store isn't part of the v1
      // launch plan, so no real iOS ad unit has been created yet. Swap this
      // in if/when iOS is actually pursued.
      return 'ca-app-pub-3940256099942544/1712485313';
    }
    throw UnsupportedError('Unsupported platform');
  }

  String get interstitialAdUnitId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Real MindSprint Trivia interstitial ad unit (created 2026-07-26).
      return 'ca-app-pub-6370450824074258/8341767241';
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return 'ca-app-pub-3940256099942544/4411468910';
    }
    throw UnsupportedError('Unsupported platform');
  }

  // Sanjay's personal phone, registered as an AdMob test device (2026-07-26).
  // Device ID captured from the "Use RequestConfiguration.Builder()..." line
  // Google's SDK prints to the device log the first time it evaluates an ad
  // request from an unregistered device. With this set, this specific phone
  // always receives Google's safe test ad creative -- never a real ad --
  // even when requesting the real ad unit IDs above. This matters because
  // interacting with your own live ads (even by accident, while testing) is
  // "invalid traffic" under AdMob's policies and can lead to account
  // suspension. Covers both `flutter run`/USB-debugging testing and the
  // sideloaded release APK, since it's tied to the physical device, not the
  // build type. Add more IDs to this list if testing from another device.
  static const List<String> _testDeviceIds = [
    'F1BE297540B89878D0BBDE0699086F1B',
  ];

  Future<void> initialize() async {
    if (!_adsSupported) return;

    _sessionStartedAt = DateTime.now();

    await MobileAds.instance.initialize();
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(testDeviceIds: _testDeviceIds),
    );
    await loadRewardedAd();
    await loadInterstitialAd();
  }

  Future<void> loadRewardedAd() async {
    if (!_adsSupported) return;
    if (_rewardedAd != null || _isLoadingRewarded) return;

    _isLoadingRewarded = true;
    final completer = Completer<void>();

    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          _rewardedAd = ad;
          _isLoadingRewarded = false;
          debugPrint('Rewarded ad loaded.');
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
        onAdFailedToLoad: (LoadAdError error) {
          _rewardedAd = null;
          _isLoadingRewarded = false;
          debugPrint('Rewarded ad failed to load: $error');
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
      ),
    );

    await completer.future;
  }

  Future<bool> showRewardedAd({
    required Future<void> Function() onRewardEarned,
  }) async {
    if (!_adsSupported) return false;

    if (_rewardedAd == null) {
      await loadRewardedAd();
    }

    final RewardedAd? ad = _rewardedAd;
    if (ad == null) {
      return false;
    }

    _rewardedAd = null;

    bool rewardEarned = false;
    // Holds the caller's grant work (add stamina / grant temp Premium /
    // record the daily cap) once onUserEarnedReward starts it.
    //
    // The SDK fires onAdDismissedFullScreenContent independently of that
    // callback, usually immediately after it. Completing on dismissal
    // alone meant this method could return true while the grant was still
    // only half-written -- the caller would then go on to reload the
    // profile and read state the grant hadn't reached yet, which is how a
    // player could watch an ad, have one of their daily unlocks consumed,
    // and still end up without the reward. Waiting on this future makes
    // "this call resolved" actually mean "the reward is fully banked."
    Future<void>? rewardWork;
    final completer = Completer<bool>();

    Future<void> completeOnceRewardBanked() async {
      try {
        await rewardWork;
      } catch (e) {
        // The reward itself failed to persist -- log it and still report
        // the outcome rather than hanging the caller forever.
        debugPrint('Rewarded ad grant failed to save: $e');
      }
      if (!completer.isCompleted) {
        completer.complete(rewardEarned);
      }
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        debugPrint('Rewarded ad opened.');
      },
      onAdDismissedFullScreenContent: (ad) {
        debugPrint('Rewarded ad dismissed.');
        ad.dispose();
        unawaited(completeOnceRewardBanked());
        unawaited(loadRewardedAd());
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('Rewarded ad failed to show: $error');
        ad.dispose();
        if (!completer.isCompleted) {
          completer.complete(false);
        }
        unawaited(loadRewardedAd());
      },
    );

    try {
      await ad.show(
        onUserEarnedReward: (AdWithoutView ad, RewardItem reward) async {
          debugPrint('Reward earned: ${reward.amount} ${reward.type}');
          rewardEarned = true;
          // Kept so the dismissal handler can wait for it to finish
          // before this call resolves -- see completeOnceRewardBanked.
          rewardWork = onRewardEarned();
          await rewardWork;
        },
      );
    } catch (e) {
      debugPrint('Error showing rewarded ad: $e');
      ad.dispose();
      if (!completer.isCompleted) {
        completer.complete(false);
      }
      unawaited(loadRewardedAd());
    }

    return completer.future;
  }

  Future<void> loadInterstitialAd() async {
    if (!_adsSupported) return;
    if (_interstitialAd != null || _isLoadingInterstitial) return;

    _isLoadingInterstitial = true;
    final completer = Completer<void>();

    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          _interstitialAd = ad;
          _isLoadingInterstitial = false;
          debugPrint('Interstitial ad loaded.');
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
        onAdFailedToLoad: (LoadAdError error) {
          _interstitialAd = null;
          _isLoadingInterstitial = false;
          debugPrint('Interstitial ad failed to load: $error');
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
      ),
    );

    await completer.future;
  }

  Future<bool> showInterstitialAd() async {
    if (!_adsSupported) return false;

    if (_interstitialAd == null) {
      await loadInterstitialAd();
    }

    final InterstitialAd? ad = _interstitialAd;
    if (ad == null) {
      return false;
    }

    _interstitialAd = null;

    final completer = Completer<bool>();

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        debugPrint('Interstitial ad opened.');
      },
      onAdDismissedFullScreenContent: (ad) {
        debugPrint('Interstitial ad dismissed.');
        ad.dispose();
        if (!completer.isCompleted) {
          completer.complete(true);
        }
        unawaited(loadInterstitialAd());
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('Interstitial ad failed to show: $error');
        ad.dispose();
        if (!completer.isCompleted) {
          completer.complete(false);
        }
        unawaited(loadInterstitialAd());
      },
    );

    try {
      await ad.show();
    } catch (e) {
      debugPrint('Error showing interstitial ad: $e');
      ad.dispose();
      if (!completer.isCompleted) {
        completer.complete(false);
      }
      unawaited(loadInterstitialAd());
    }

    return completer.future;
  }

  /// Call this right after a quiz ends (Normal Mode or Rapid Fire), before
  /// navigating to the result screen. Shows an interstitial ad only if the
  /// player isn't Premium (real or temporary) and the pacing rules allow
  /// it: every 2nd quiz completion this session, and only once the player
  /// has been using the app for at least [_interstitialWarmup] this
  /// session. Both the completion count and session start reset fresh on
  /// every app launch.
  Future<void> maybeShowInterstitialAfterQuiz() async {
    if (PlayerService.isPremium) return;

    _quizCompletionsThisSession++;

    final sessionStart = _sessionStartedAt;
    final bool pastWarmup =
        sessionStart != null &&
        DateTime.now().difference(sessionStart) >= _interstitialWarmup;
    final bool isEligibleCompletion =
        _quizCompletionsThisSession % _showInterstitialEveryNCompletions == 0;

    if (!pastWarmup || !isEligibleCompletion) return;

    await showInterstitialAd();
  }
}
