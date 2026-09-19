import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/player_repository.dart';
import '../services/player_service.dart';
import '../services/username_repository.dart';

enum _CheckState { idle, checking, available, taken, formatError, notSignedIn }

/// Dialog for a player to choose (or change) their real, unique Player ID.
/// Shows live "is this available" feedback as they type, then does the
/// actual atomic claim (via [UsernameRepository]) on Save.
///
/// Cooldown gating (first rename free, then a wait between further ones --
/// see [PlayerService.canRenameUsernameNow]) is enforced by the caller
/// *before* opening this dialog, not inside it -- by the time someone is
/// looking at this dialog they're always eligible to rename right now.
class RenameUsernameDialog extends StatefulWidget {
  const RenameUsernameDialog({super.key});

  @override
  State<RenameUsernameDialog> createState() => _RenameUsernameDialogState();
}

/// Shows the dialog and returns true if the player successfully renamed,
/// false/null otherwise. Callers should `setState` (or otherwise refresh)
/// after a true result to reflect the new name and cooldown state.
Future<bool?> showRenameUsernameDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const RenameUsernameDialog(),
  );
}

class _RenameUsernameDialogState extends State<RenameUsernameDialog> {
  late final TextEditingController _controller;
  Timer? _debounce;
  _CheckState _checkState = _CheckState.idle;
  String? _formatError;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: PlayerService.username);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  bool get _isUnchanged =>
      UsernameRepository.normalize(_controller.text) ==
      UsernameRepository.normalize(PlayerService.username);

  void _onChanged(String text) {
    _debounce?.cancel();
    setState(() => _saveError = null);

    final trimmed = text.trim();
    final formatError = PlayerService.validateUsernameFormat(trimmed);
    if (formatError != null) {
      setState(() {
        _checkState = _CheckState.formatError;
        _formatError = formatError;
      });
      return;
    }

    if (_isUnchanged) {
      setState(() => _checkState = _CheckState.idle);
      return;
    }

    setState(() => _checkState = _CheckState.checking);

    _debounce = Timer(const Duration(milliseconds: 450), () async {
      final uid = AuthService.uid;
      if (uid == null) {
        if (mounted) setState(() => _checkState = _CheckState.notSignedIn);
        return;
      }
      final available = await UsernameRepository.isAvailable(
        trimmed,
        forUid: uid,
      );
      if (!mounted) return;
      // The debounce timer could resolve after the text has changed again --
      // only apply this result if it's still describing the current text.
      if (UsernameRepository.normalize(_controller.text) !=
          UsernameRepository.normalize(trimmed)) {
        return;
      }
      setState(() {
        _checkState = available ? _CheckState.available : _CheckState.taken;
      });
    });
  }

  bool get _canSave =>
      !_saving && !_isUnchanged && _checkState == _CheckState.available;

  Future<void> _handleSave() async {
    final uid = AuthService.uid;
    final trimmed = _controller.text.trim();
    if (uid == null) {
      setState(() => _saveError = "You need to be signed in to do this.");
      return;
    }

    setState(() {
      _saving = true;
      _saveError = null;
    });

    final result = await UsernameRepository.claimUsername(
      uid: uid,
      newName: trimmed,
      oldName: PlayerService.username,
    );

    if (!mounted) return;

    switch (result.status) {
      case UsernameClaimStatus.success:
        await PlayerService.applyUsernameChange(trimmed);
        unawaited(PlayerRepository.syncCurrentPlayer());
        if (mounted) Navigator.of(context).pop(true);
        return;
      case UsernameClaimStatus.taken:
        setState(() {
          _saving = false;
          _checkState = _CheckState.taken;
        });
        return;
      case UsernameClaimStatus.offline:
        setState(() {
          _saving = false;
          _saveError =
              "Couldn't verify that name right now -- check your connection and try again.";
        });
        return;
    }
  }

  Widget _buildStatusLine() {
    switch (_checkState) {
      case _CheckState.idle:
        return const Text(
          "3-20 characters. Letters, numbers, spaces, and underscores.",
          style: TextStyle(color: Colors.white54, fontSize: 12.5, height: 1.4),
        );
      case _CheckState.checking:
        return const Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(Colors.white54),
              ),
            ),
            SizedBox(width: 8),
            Text(
              "Checking availability...",
              style: TextStyle(color: Colors.white54, fontSize: 12.5),
            ),
          ],
        );
      case _CheckState.available:
        return const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 15),
            SizedBox(width: 6),
            Text(
              "Available",
              style: TextStyle(
                color: Colors.greenAccent,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        );
      case _CheckState.taken:
        return const Row(
          children: [
            Icon(Icons.cancel_rounded, color: Colors.redAccent, size: 15),
            SizedBox(width: 6),
            Text(
              "That name is already taken",
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        );
      case _CheckState.formatError:
        return Text(
          _formatError ?? "Invalid name.",
          style: const TextStyle(color: Colors.redAccent, fontSize: 12.5),
        );
      case _CheckState.notSignedIn:
        return const Text(
          "Sign in with Google to set a Player ID.",
          style: TextStyle(color: Colors.orangeAccent, fontSize: 12.5),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF121821),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0xFF2A3342)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFF9D4DFF), Color(0xFFC084FC)],
                    ),
                  ),
                  child: const Icon(
                    Icons.badge_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    "Your Player ID",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: PlayerService.usernameMaxLength,
              onChanged: _onChanged,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                counterText: "",
                filled: true,
                fillColor: const Color(0xFF1A2230),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF2E3A4F)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF2E3A4F)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFC084FC)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _buildStatusLine(),
            if (_saveError != null) ...[
              const SizedBox(height: 8),
              Text(
                _saveError!,
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 12.5),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              "After this, you'll need to wait ${PlayerService.usernameRenameCooldownDays} days to rename again.",
              style: const TextStyle(color: Colors.white38, fontSize: 11.5),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Color(0xFF3B4659)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text("Cancel"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _canSave ? _handleSave : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC084FC),
                      disabledBackgroundColor: const Color(0xFF2E3A4F),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child:
                        _saving
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                            : const Text(
                              "Save",
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
