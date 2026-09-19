// Intentionally emptied 2026-09-02 -- this file was a stale, unused,
// byte-identical duplicate of an old version of LowStaminaPopup (from
// `low_stamina_popup.dart`), left behind from before the temp-Premium
// unlock option was added. Nothing imports this file (verified via grep
// across lib/), and its old contents declared public types
// (`LowStaminaAction`, `LowStaminaPopup`) that collide with the real,
// current versions in `low_stamina_popup.dart` -- the moment anything
// imported both, the build would fail with a baffling ambiguous-import
// error, and the misleading filename ("question_card.dart" containing a
// stamina popup, not a question card) made it a trap for anyone editing
// this app to open by mistake.
//
// Safe to delete this file entirely -- it's kept as an empty stub here
// only because this change was made without direct file-system access to
// actually remove it. Please delete lib/widgets/question_card.dart (and
// lib/widgets/option_button.dart, emptied the same way) next time you're
// in the project folder.
