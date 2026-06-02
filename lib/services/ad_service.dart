import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  AdService._();

  static final AdService instance = AdService._();

  RewardedAd? _rewardedAd;
  bool _isLoadingRewarded = false;

  bool get _adsSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  String get rewardedAdUnitId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'ca-app-pub-3940256099942544/5224354917';
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return 'ca-app-pub-3940256099942544/1712485313';
    }
    throw UnsupportedError('Unsupported platform');
  }

  Future<void> initialize() async {
    if (!_adsSupported) return;

    await MobileAds.instance.initialize();
    await loadRewardedAd();
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
    final completer = Completer<bool>();

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        debugPrint('Rewarded ad opened.');
      },
      onAdDismissedFullScreenContent: (ad) {
        debugPrint('Rewarded ad dismissed.');
        ad.dispose();
        if (!completer.isCompleted) {
          completer.complete(rewardEarned);
        }
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
          await onRewardEarned();
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
}
