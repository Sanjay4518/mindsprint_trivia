import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';
import 'player_service.dart';
import 'settings_service.dart';

/// Mirrors just enough of the player's stats (username, XP, league) to a
/// shared Firestore collection every signed-in player can read -- this is
/// what makes the Leaderboard screen show real people instead of the old
/// made-up names.
///
/// Deliberately fetches ALL entries sorted by XP once, then filters by
/// league on-device rather than querying Firestore separately per league
/// tab -- at this app's scale that's simpler (no Firestore composite index
/// to set up) and cheaper (one read per screen open, not one per tab).
///
/// [fetchTopEntries] excludes 0-XP entries -- see its own doc comment.
class LeaderboardRepository {
  static final _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _entries =>
      _db.collection('leaderboards').doc('global').collection('entries');

  /// Writes/updates the current player's own leaderboard entry. Called
  /// automatically by `PlayerRepository.syncCurrentPlayer()` -- no need to
  /// call this directly elsewhere. Never throws; a failed sync just means
  /// this player's leaderboard entry is a little stale until next time.
  static Future<void> syncCurrentEntry() async {
    final uid = AuthService.uid;
    if (uid == null) return;

    try {
      // Photo is opt-in (SettingsService.showPhotoOnLeaderboard, off by
      // default) -- see that field's doc comment. When it's off, or the
      // player has no linked Google photo (guests, or a linked account
      // with no avatar), FieldValue.delete() actively removes any photo
      // URL this doc may already have from a previous sync where the
      // setting was on -- merge:true alone would just leave a stale one
      // in place, which would defeat the point of the toggle the moment
      // someone turns it back off.
      final photoUrl =
          SettingsService.showPhotoOnLeaderboard
              ? AuthService.linkedGooglePhotoUrl
              : null;

      await _entries.doc(uid).set({
        'uid': uid,
        'username': PlayerService.username,
        'xp': PlayerService.totalXp,
        'league': PlayerService.getLeague(),
        'photoUrl':
            (photoUrl != null && photoUrl.isNotEmpty)
                ? photoUrl
                : FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Ignored on purpose -- see comment above.
    }
  }

  /// Fetches the top [limit] players globally, sorted by XP descending.
  /// Returns an empty list (never throws) if offline or something goes
  /// wrong -- callers should treat an empty list as "couldn't load right
  /// now", not "nobody's on the leaderboard".
  ///
  /// Excludes anyone still at 0 XP -- every fresh guest account gets a
  /// leaderboard entry written the moment it first opens the app (see
  /// [syncCurrentEntry], called from every app start), often well before
  /// they've actually played a single question. Without this filter the
  /// leaderboard fills up with empty "GuestNNNN -- 0 XP" rows for anyone
  /// who ever opened the app, including a player's own brief pre-sign-in
  /// guest moment showing up right alongside their real signed-in entry.
  /// Correct answers are worth +20 XP and wrong ones 0, so this is a
  /// close-enough proxy for "never actually played" rather than a perfect
  /// one -- the rare player whose very first round is a 100% miss would
  /// also be filtered out until their next point, which is an acceptable
  /// trade for keeping the list free of empty accounts.
  static Future<List<Map<String, dynamic>>> fetchTopEntries({
    int limit = 200,
  }) async {
    try {
      final snapshot =
          await _entries
              .where('xp', isGreaterThan: 0)
              .orderBy('xp', descending: true)
              .limit(limit)
              .get();
      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (_) {
      return [];
    }
  }
}
