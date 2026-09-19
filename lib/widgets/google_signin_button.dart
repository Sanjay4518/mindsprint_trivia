import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// A "Sign in with Google" button that follows Google's own branding
/// guidelines (https://developers.google.com/identity/branding-guidelines):
/// the real multi-colour "G" logo, the exact approved call-to-action text,
/// and the official light-theme colours (white fill, #747775 border, dark
/// text) -- so it reads as a real, trustworthy sign-in option rather than a
/// custom-styled button pretending to be one.
class GoogleSignInButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;
  final String label;

  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.loading = false,
    this.label = "Sign in with Google",
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: Material(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onPressed,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFF747775), width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Color(0xFF747775)),
                    ),
                  )
                else
                  SvgPicture.asset(
                    'assets/images/google_logo.svg',
                    width: 18,
                    height: 18,
                  ),
                const SizedBox(width: 10),
                Text(
                  loading ? "Signing in..." : label,
                  style: const TextStyle(
                    color: Color(0xFF1F1F1F),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.15,
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
