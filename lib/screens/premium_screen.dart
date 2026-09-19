import 'dart:async';
import 'package:flutter/material.dart';
import '../helpers/mode_entry_helper.dart';
import '../services/auth_service.dart';
import '../services/billing_service.dart';
import '../services/player_repository.dart';
import '../services/player_service.dart';
import '../services/usage_limit_service.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  Timer? _ticker;
  int _unlocksUsedToday = 0;
  bool _loadingUsage = true;
  bool _subscribing = false;
  bool _watchingAd = false;

  /// Purchases complete asynchronously (BillingService's purchase-update
  /// listener runs globally, not scoped to this screen), so this just
  /// re-renders every couple of seconds to pick up the moment
  /// PlayerService.isPremium actually flips true after a successful
  /// subscribe -- same lightweight "poll a static service" approach the
  /// temp-Premium countdown ticker below already uses.
  Timer? _premiumWatchTimer;

  @override
  void initState() {
    super.initState();
    _loadUsage();
    _maybeStartTicker();
    _premiumWatchTimer = Timer.periodic(const Duration(seconds: 2), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      // Stops once there's nothing left to watch for. This used to rebuild
      // the whole screen every 2 seconds for as long as it stayed open,
      // including long after Premium was already active.
      if (PlayerService.isPremium) {
        t.cancel();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _premiumWatchTimer?.cancel();
    super.dispose();
  }

  /// Real Premium purchases require Google sign-in first (decision locked
  /// in 2026-08-20) -- if the player isn't linked yet, this links them
  /// first, then starts the purchase. Mirrors the sign-in flow used on the
  /// Profile screen.
  Future<void> _handleSubscribe() async {
    if (_subscribing) return;
    setState(() => _subscribing = true);

    try {
      if (!AuthService.isLinkedWithGoogle) {
        final linkResult = await AuthService.linkWithGoogle();
        if (!mounted) return;

        if (!linkResult.ok) {
          if (linkResult.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(linkResult.errorMessage!),
                duration: const Duration(seconds: 6),
              ),
            );
          }
          // Cancelled sign-in: just stop here, no error to show.
          return;
        }

        // Same restore-then-maybe-auto-fill sequence as the Profile
        // screen's sign-in flow -- see the comments there. Without this,
        // subscribing right after a reinstall/second-device Google link
        // would silently start pushing a blank-slate profile to the
        // cloud, overwriting whatever history that account already had.
        if (linkResult.switchedAccount) {
          // discardLocalProgress: true -- identical situation to
          // ProfileScreen.handleLinkGoogle: this is the first moment a
          // switch to a pre-existing account is confirmed, so guest
          // progress on this device is dropped in favour of that
          // account's real history rather than merged into it. This call
          // site was missed when the Profile one was fixed, which left
          // the Subscribe flow still taking the old per-field-max merge
          // path -- the exact path that can leave the practice list
          // larger than the wrong-answer count backing it, and eventually
          // show an over-100% accuracy. See PlayerService.restoreFromCloud.
          final outcome = await PlayerRepository.restorePlayerFromCloud(
            discardLocalProgress: true,
          );
          if (!mounted) return;

          if (outcome == RestoreOutcome.failed) {
            // Same reasoning as the Profile screen: we know this is a
            // pre-existing account, but couldn't read its cloud data back
            // down just now. Stop before subscribing (and before the
            // sync below) rather than risk pushing a blank profile over
            // real saved progress.
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  "Signed in, but couldn't restore your saved progress -- "
                  "check your connection and try again before subscribing.",
                ),
                duration: Duration(seconds: 6),
              ),
            );
            return;
          }
        }

        await PlayerRepository.applyPostLinkSetupIfNeeded();
        unawaited(PlayerRepository.syncCurrentPlayer());
      } else if (await PlayerRepository.hasPendingRestore()) {
        // Already linked, but an earlier restore attempt failed and
        // hasn't succeeded since (see PlayerRepository.syncCurrentPlayer's
        // guard) -- retry it now rather than let a purchase go through on
        // top of a local profile we know might be missing real cloud
        // history. Without this, tapping Subscribe again after the
        // failure above would skip the whole `if (!isLinkedWithGoogle)`
        // block (we're linked now) and the restore would never actually
        // be retried, even though the earlier message told the player to
        // "try again."
        final outcome = await PlayerRepository.restorePlayerFromCloud();
        if (!mounted) return;

        if (outcome == RestoreOutcome.failed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Still couldn't restore your saved progress -- check your "
                "connection and try again before subscribing.",
              ),
              duration: Duration(seconds: 6),
            ),
          );
          return;
        }

        // This retry is only reachable after an earlier attempt (in this
        // method, on the Profile screen, or a background retry on a
        // previous app start) failed before this account's cloud state
        // was ever confirmed caught up -- now that it is, run the
        // autofill/bonus/sync steps so a player who subscribes right
        // after a delayed restore doesn't quietly miss their name
        // autofill or one-time sign-in bonus. Safe even if they somehow
        // already ran (see PlayerRepository.applyPostLinkSetupIfNeeded).
        await PlayerRepository.applyPostLinkSetupIfNeeded();
        unawaited(PlayerRepository.syncCurrentPlayer());
      }

      if (!mounted) return;

      final started = await BillingService.buyMonthlySubscription();
      if (!mounted) return;

      if (!started) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Couldn't start the purchase right now. Make sure you have a "
              "Play Store connection and try again in a moment.",
            ),
          ),
        );
      }
      // If started == true, the purchase sheet is now showing -- the
      // result arrives asynchronously and _premiumWatchTimer above will
      // pick it up once it lands.
    } finally {
      if (mounted) setState(() => _subscribing = false);
    }
  }

  Future<void> _loadUsage() async {
    final used = await UsageLimitService.getTempPremiumUnlocksToday();
    if (!mounted) return;
    setState(() {
      _unlocksUsedToday = used;
      _loadingUsage = false;
    });
  }

  void _maybeStartTicker() {
    _ticker?.cancel();
    if (PlayerService.hasTemporaryPremiumActive) {
      // Cancels via the timer passed to the callback rather than the
      // field, so a stale callback can't cancel a newer timer that has
      // replaced it, and a timer started after dispose() still stops.
      _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        if (!PlayerService.hasTemporaryPremiumActive) {
          t.cancel();
        }
        setState(() {});
      });
    }
  }

  Future<void> _watchAdForTempPremium() async {
    // Local guard so the button visibly disables while the ad loads and
    // plays -- ModeEntryHelper refuses a concurrent second attempt on its
    // own, but without this the button still looked live for several
    // seconds with nothing appearing to happen. _handleSubscribe just
    // above already works this way via _subscribing.
    if (_watchingAd) return;
    setState(() => _watchingAd = true);

    try {
      await _watchAdForTempPremiumInner();
    } finally {
      if (mounted) setState(() => _watchingAd = false);
    }
  }

  Future<void> _watchAdForTempPremiumInner() async {
    final bool success = await ModeEntryHelper.tryWatchAdForTemporaryPremium(
      context,
    );

    if (!mounted) return;

    if (success) {
      final used = await UsageLimitService.getTempPremiumUnlocksToday();
      if (!mounted) return;
      setState(() {
        _unlocksUsedToday = used;
      });
      _maybeStartTicker();
    }
  }

  Widget buildFeatureTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF181C24),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildSubscribeCard() {
    final product = BillingService.cachedProduct;
    final priceText = product?.price; // e.g. "₹149.00" -- real Play price.
    final storeReady = BillingService.storeAvailable;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5B2EFF), Color(0xFF9D4DFF), Color(0xFFFF4DA6)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.workspace_premium_rounded,
                color: Colors.white,
                size: 28,
              ),
              SizedBox(width: 10),
              Text(
                "MindSprint Premium",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            priceText != null
                ? "$priceText / month -- cancel anytime from the Play Store."
                : "Monthly subscription -- cancel anytime from the Play Store.",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            "Requires signing in with Google, so your subscription is tied to your account and follows you across devices.",
            style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.35),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  (_subscribing || !storeReady) ? null : _handleSubscribe,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.35),
                foregroundColor: const Color(0xFF5B2EFF),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon:
                  _subscribing
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                      : const Icon(Icons.workspace_premium_rounded),
              label: Text(
                _subscribing
                    ? "Opening checkout..."
                    : (priceText != null
                        ? "Subscribe -- $priceText/mo"
                        : "Subscribe to Premium"),
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (!storeReady) ...[
            const SizedBox(height: 10),
            const Text(
              "Play Store isn't reachable right now, so purchases aren't available on this device/build yet.",
              style: TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }

  /// Shown while a temporary (ad-earned) Premium window is running --
  /// a live countdown instead of the watch-ad button.
  Widget buildTempPremiumActiveCard() {
    final remaining =
        PlayerService.temporaryPremiumRemaining ?? Duration.zero;
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    final timeText =
        "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFC084FC).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFC084FC)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFC084FC).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.timer_rounded,
              color: Color(0xFFC084FC),
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Temporary Premium Active",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "$timeText remaining -- unlimited stamina and every category unlocked.",
                  style: const TextStyle(color: Colors.white70, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Shown when the player has neither real Premium nor an active
  /// temporary window -- lets them earn one by watching an ad.
  Widget buildWatchAdCard() {
    final int remaining =
        UsageLimitService.freeTempPremiumUnlocksPerDay - _unlocksUsedToday;
    final bool exhausted = remaining <= 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF181C24),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF3D2F5C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFC084FC).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.ondemand_video_rounded,
                  color: Color(0xFFC084FC),
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Try Premium Free",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      "Watch a short ad to unlock unlimited stamina and every category for 15 minutes.",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  (exhausted || _loadingUsage || _watchingAd)
                      ? null
                      : _watchAdForTempPremium,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC084FC),
                disabledBackgroundColor: const Color(0xFF2A2438),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.play_circle_fill_rounded),
              label: Text(
                _watchingAd
                    ? "Loading ad…"
                    : exhausted
                    ? "Come back tomorrow"
                    : "Watch Ad for 15 Minutes of Premium",
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (!_loadingUsage) ...[
            const SizedBox(height: 10),
            Text(
              exhausted
                  ? "You've used all ${UsageLimitService.freeTempPremiumUnlocksPerDay} free unlocks for today."
                  : "$remaining of ${UsageLimitService.freeTempPremiumUnlocksPerDay} free unlocks left today.",
              style: const TextStyle(color: Colors.white54, fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasRealPremium =
        PlayerService.isPremium && !PlayerService.hasTemporaryPremiumActive;
    final bool hasTempPremium = PlayerService.hasTemporaryPremiumActive;

    return Scaffold(
      appBar: AppBar(title: const Text("Premium")),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!hasRealPremium) buildSubscribeCard(),
              if (!hasRealPremium) const SizedBox(height: 16),

              if (hasTempPremium) buildTempPremiumActiveCard(),
              if (!hasRealPremium && !hasTempPremium) buildWatchAdCard(),

              const SizedBox(height: 22),

              const Text(
                "What you get",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),

              buildFeatureTile(
                icon: Icons.block_rounded,
                title: "Ad-Free Experience",
                subtitle: "No interstitial ads between quizzes.",
                color: Colors.redAccent,
              ),
              buildFeatureTile(
                icon: Icons.bolt_rounded,
                title: "Unlimited Stamina",
                subtitle: "Play anytime without waiting for stamina refill.",
                color: Colors.orange,
              ),
              buildFeatureTile(
                icon: Icons.grid_view_rounded,
                title: "Category Practice",
                subtitle:
                    "Choose focused topics like History, Polity, Science and more.",
                color: Colors.lightBlueAccent,
              ),
              buildFeatureTile(
                icon: Icons.replay_rounded,
                title: "Practice Mode",
                subtitle:
                    "Review and re-practice the questions you've gotten wrong, with smart spaced repetition.",
                color: Colors.tealAccent,
              ),
              buildFeatureTile(
                icon: Icons.school_rounded,
                title: "Better Exam Preparation",
                subtitle: "Train weak areas with more control and consistency.",
                color: Colors.greenAccent,
              ),
              buildFeatureTile(
                icon: Icons.emoji_events_rounded,
                title: "Faster Progress",
                subtitle: "Practice more often and climb leagues faster.",
                color: Colors.amber,
              ),

              const SizedBox(height: 20),

              if (hasRealPremium)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.verified_rounded,
                        color: Colors.green,
                        size: 34,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "Premium Already Active",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        "Unlimited stamina and category access are already unlocked.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, height: 1.35),
                      ),
                      if (PlayerService.hasActiveSubscription) ...[
                        const SizedBox(height: 10),
                        const Text(
                          "Manage or cancel your subscription anytime from the Play Store app -- Menu > Payments & subscriptions > Subscriptions.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    // Reports whether the player has any form of Premium
                    // now (not just when they arrived) -- lets callers like
                    // ModeEntryHelper's "go Premium" prompt immediately
                    // resume the action the player was trying to do if a
                    // subscription (or temp Premium) was activated while
                    // they were on this screen.
                    Navigator.pop(context, PlayerService.isPremium);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Color(0xFF3B4659)),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text(
                    "Back",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
