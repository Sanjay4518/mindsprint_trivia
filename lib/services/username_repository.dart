import 'package:cloud_firestore/cloud_firestore.dart';

/// Outcome of a [UsernameRepository.claimUsername] attempt.
enum UsernameClaimStatus { success, taken, offline }

class UsernameClaimResult {
  final UsernameClaimStatus status;
  const UsernameClaimResult(this.status);
}

/// Backs the real, unique, self-chosen Player ID system: a small
/// `usernames/{normalizedName}` collection acts as a name-reservation index
/// (`{uid, displayName, updatedAt}`), separate from -- and in addition to --
/// each player's own `users/{uid}` document. Uniqueness is case-insensitive
/// (the document key is the lowercased name); [displayName] preserves the
/// player's original capitalization for showing back to them.
///
/// Deliberately does NOT reserve names on Google-sign-in auto-fill or the
/// original random "GuestNNNN" name -- those are cosmetic defaults, not a
/// player's deliberate choice, so forcing global uniqueness on them would
/// either add friction (silently mangling someone's real Google name with a
/// suffix) or bloat this collection with disposable guest names. Uniqueness
/// is enforced only from the moment a player actually chooses to rename
/// themselves via [claimUsername].
///
/// Client-only for v1, same disclosed scope limit as [EntitlementRepository]
/// -- a determined user could bypass the local rename cooldown by editing
/// local storage, but nothing valuable (money, real identity) rides on a
/// display name, so a Cloud Function-enforced version isn't worth building
/// yet. Firestore's security rules are still the real backstop against a
/// name actually being *stolen* from another player, since name ownership
/// (`uid` on each reservation doc) is checked server-side.
class UsernameRepository {
  static final _db = FirebaseFirestore.instance;

  static String normalize(String name) => name.trim().toLowerCase();

  /// Quick, non-transactional check used for live "is this available"
  /// feedback while the player types. Not the final word -- [claimUsername]
  /// below re-checks atomically at save time to close the race window
  /// between two people checking/claiming the same name at once. On any
  /// error (offline, etc.) this deliberately returns true rather than
  /// blocking typing on an uncertain answer -- the real check happens again
  /// at save time regardless.
  static Future<bool> isAvailable(String name, {required String forUid}) async {
    final normalized = normalize(name);
    if (normalized.isEmpty) return false;
    try {
      final doc = await _db.collection('usernames').doc(normalized).get();
      if (!doc.exists) return true;
      return doc.data()?['uid'] == forUid;
    } catch (_) {
      return true;
    }
  }

  /// Atomically claims [newName] for [uid] and releases [oldName]'s
  /// reservation (if it had one) in the same transaction, so a rename can
  /// never leave two reservations pointing at one account, or briefly let
  /// two different accounts both claim the same name. This -- not
  /// [isAvailable] -- is the actual source of truth.
  static Future<UsernameClaimResult> claimUsername({
    required String uid,
    required String newName,
    String? oldName,
  }) async {
    final normalized = normalize(newName);
    final oldNormalized = oldName != null ? normalize(oldName) : null;

    if (normalized.isEmpty) {
      return const UsernameClaimResult(UsernameClaimStatus.taken);
    }
    if (normalized == oldNormalized) {
      return const UsernameClaimResult(UsernameClaimStatus.success);
    }

    final newRef = _db.collection('usernames').doc(normalized);
    final oldRef =
        (oldNormalized != null && oldNormalized.isNotEmpty)
            ? _db.collection('usernames').doc(oldNormalized)
            : null;

    try {
      await _db.runTransaction((tx) async {
        // All reads before any writes -- Firestore transactions require
        // this, so the old-name lookup below (needed for the ownership
        // check) has to happen up front too, not just at delete time.
        final newSnap = await tx.get(newRef);
        if (newSnap.exists && newSnap.data()?['uid'] != uid) {
          throw _UsernameTakenException();
        }

        final oldSnap = oldRef != null ? await tx.get(oldRef) : null;

        tx.set(newRef, {
          'uid': uid,
          'displayName': newName.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Only release the old reservation if it still actually belongs
        // to this account. Previously this deleted unconditionally --
        // if [oldName] was stale (e.g. a second, out-of-sync device
        // passing in a name this account already renamed away from
        // elsewhere, which another player has since legitimately
        // claimed for themselves), that would delete a DIFFERENT
        // player's active reservation and leave their name up for
        // grabs. A no-op if the old reservation doesn't exist at all
        // (e.g. it was still the auto-generated Guest/Google default).
        if (oldRef != null &&
            oldSnap != null &&
            oldSnap.exists &&
            oldSnap.data()?['uid'] == uid) {
          tx.delete(oldRef);
        }
      });
      return const UsernameClaimResult(UsernameClaimStatus.success);
    } on _UsernameTakenException {
      return const UsernameClaimResult(UsernameClaimStatus.taken);
    } catch (_) {
      return const UsernameClaimResult(UsernameClaimStatus.offline);
    }
  }
}

class _UsernameTakenException implements Exception {}
