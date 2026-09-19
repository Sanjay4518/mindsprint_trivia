import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Thin wrapper around Firebase Authentication -- both the invisible
/// Anonymous sign-in every player gets automatically, and the real
/// "Sign in with Google" flow a player can add on top of it later.
///
/// Real Google sign-in *links* to the existing anonymous account rather
/// than replacing it, so nothing a player has already earned is lost --
/// see [linkWithGoogle].
class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  // From Firebase Console -> Authentication -> Sign-in method -> Google ->
  // (click the Google row) -> "Web SDK configuration" -> Web client ID.
  // This is not a secret (it's meant to be embedded in apps) -- it's just
  // how the Google sign-in library knows which Firebase project to talk to.
  static const String _webClientId =
      '1003626375748-2pi3akcrusc8g6sbi2qg97nghi0sdd2m.apps.googleusercontent.com';

  static bool _googleReady = false;

  // ProfileScreen and PremiumScreen can each independently call
  // linkWithGoogle() (e.g. Profile's own link button, or the low-stamina
  // popup's "Go Premium" path opening PremiumScreen while a Profile-
  // initiated link is still resolving) -- each screen only guards its own
  // button against a second local tap, not against a completely separate
  // screen starting a second call. Without this, two concurrent calls
  // could both pass the `if (_googleReady) return;` check before either
  // sets it, and both proceed to call the underlying GoogleSignIn
  // singleton's initialize() at once, which that plugin doesn't support.
  // Same "piggyback on the in-flight call" fix used elsewhere in this app
  // (EntitlementRepository.refreshEntitlement(), ServerTimeService.sync(),
  // NotificationService.init()).
  static Future<void>? _googleReadyInFlight;

  /// The current player's backend user ID, or null if sign-in hasn't
  /// completed yet (should be very brief -- only during the first moment of
  /// app startup, before [ensureSignedIn] finishes).
  static String? get uid => _auth.currentUser?.uid;

  /// True once we have a signed-in Firebase user, anonymous or otherwise.
  static bool get isSignedIn => _auth.currentUser != null;

  /// True once the signed-in account has a real Google identity linked to
  /// it (i.e. it's no longer "just" an anonymous guest account).
  static bool get isLinkedWithGoogle {
    final user = _auth.currentUser;
    if (user == null) return false;
    return user.providerData.any((p) => p.providerId == 'google.com');
  }

  /// The email of the linked Google account, for showing "Signed in as
  /// ..." in the UI. Null until [isLinkedWithGoogle] is true.
  static String? get linkedGoogleEmail {
    final user = _auth.currentUser;
    if (user == null) return null;
    for (final p in user.providerData) {
      if (p.providerId == 'google.com') return p.email;
    }
    return null;
  }

  /// The display name Google reports for the linked account, for using as
  /// the player's real name in place of the random "GuestNNNN" name. Null
  /// until [isLinkedWithGoogle] is true.
  static String? get linkedGoogleDisplayName {
    final user = _auth.currentUser;
    if (user == null) return null;
    for (final p in user.providerData) {
      if (p.providerId == 'google.com') return p.displayName;
    }
    return null;
  }

  /// The profile photo URL Google reports for the linked account, for
  /// showing a real avatar instead of a generic placeholder. Null until
  /// [isLinkedWithGoogle] is true.
  static String? get linkedGooglePhotoUrl {
    final user = _auth.currentUser;
    if (user == null) return null;
    for (final p in user.providerData) {
      if (p.providerId == 'google.com') return p.photoURL;
    }
    return null;
  }

  /// Ensures the player has a Firebase account, signing them in anonymously
  /// if they don't already have one. Safe to call on every app start -- if a
  /// player already has an account (from a previous session on this
  /// install), Firebase Auth remembers it locally on-device and this
  /// returns immediately without creating a new one.
  static Future<void> ensureSignedIn() async {
    if (_auth.currentUser != null) return;
    await _auth.signInAnonymously();
  }

  static Future<void> _ensureGoogleReady() {
    if (_googleReady) return Future.value();
    return _googleReadyInFlight ??= _doEnsureGoogleReady().whenComplete(
      () => _googleReadyInFlight = null,
    );
  }

  static Future<void> _doEnsureGoogleReady() async {
    await _googleSignIn.initialize(serverClientId: _webClientId);
    _googleReady = true;
  }

  /// Links the player's current (anonymous) account to a real Google
  /// account, so their existing local progress carries over under the same
  /// backend ID instead of starting a fresh one.
  ///
  /// If that Google account already has a *different* MindSprint account
  /// linked to it (e.g. they used Google sign-in on another device first),
  /// Firebase won't let us merge the two -- instead we sign into that
  /// existing account, and [GoogleLinkResult.switchedAccount] comes back
  /// true so the UI can explain what happened.
  static Future<GoogleLinkResult> linkWithGoogle() async {
    try {
      await _ensureGoogleReady();

      final googleUser = await _googleSignIn.authenticate();
      final idToken = googleUser.authentication.idToken;
      if (idToken == null) {
        return GoogleLinkResult.failure(
          "Couldn't get a Google sign-in token. Please try again.",
        );
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final current = _auth.currentUser;

      if (current != null && current.isAnonymous) {
        try {
          await current.linkWithCredential(credential);
          return GoogleLinkResult.success();
        } on FirebaseAuthException catch (e) {
          if (e.code == 'credential-already-in-use' ||
              e.code == 'email-already-in-use') {
            await _auth.signInWithCredential(credential);
            return GoogleLinkResult.success(switchedAccount: true);
          }
          rethrow;
        }
      } else {
        // No anonymous session to link from -- e.g. the very first
        // launch's silent anonymous sign-in failed on a flaky network
        // (see ensureSignedIn/splash_screen), or we're already on a
        // non-anonymous account for some other reason. Either way, this
        // Google credential might resolve to a brand-new Firebase account
        // or a pre-existing one, and unlike the branch above we have no
        // "credential-already-in-use" exception to tell us which --
        // `additionalUserInfo.isNewUser` is Firebase's own authoritative
        // answer to that, so use it rather than always assuming "new".
        // Getting this wrong meant a real returning player's cloud
        // history could get silently overwritten by a blank local
        // profile (see PlayerRepository.restorePlayerFromCloud, which
        // only ever runs when switchedAccount is true).
        final userCredential = await _auth.signInWithCredential(credential);
        final isNewUser = userCredential.additionalUserInfo?.isNewUser ?? false;
        return GoogleLinkResult.success(switchedAccount: !isNewUser);
      }
    } on GoogleSignInException catch (e) {
      // A genuine user cancel (backed out of the account picker, dismissed
      // the sheet) isn't an error -- it shows no message at all, per
      // profile_screen.dart/premium_screen.dart's "Cancelled: no snackbar
      // needed" handling. Anything else is a real failure and gets a
      // clean, non-technical message instead of a raw Google Sign-In
      // error code.
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return GoogleLinkResult.cancelled();
      }
      return GoogleLinkResult.failure(
        "Google sign-in didn't go through. Please try again.",
      );
    } on FirebaseAuthException catch (_) {
      return GoogleLinkResult.failure(
        "Couldn't complete Google sign-in. Please try again.",
      );
    } catch (_) {
      return GoogleLinkResult.failure(
        "Something went wrong signing in with Google. Please try again.",
      );
    }
  }
}

/// Outcome of a [AuthService.linkWithGoogle] attempt, in a form the UI can
/// show a sensible message from without needing to know Firebase error
/// codes.
class GoogleLinkResult {
  final bool ok;
  final bool cancelled;
  final bool switchedAccount;
  final String? errorMessage;

  GoogleLinkResult._(this.ok, this.cancelled, this.switchedAccount, this.errorMessage);

  factory GoogleLinkResult.success({bool switchedAccount = false}) =>
      GoogleLinkResult._(true, false, switchedAccount, null);

  factory GoogleLinkResult.cancelled() =>
      GoogleLinkResult._(false, true, false, null);

  factory GoogleLinkResult.failure(String message) =>
      GoogleLinkResult._(false, false, false, message);
}
