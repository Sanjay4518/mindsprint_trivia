import 'package:flutter/material.dart';
import '../services/player_service.dart';
import '../services/stamina_service.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  bool isLoading = false;

  Future<void> activatePremium() async {
    setState(() {
      isLoading = true;
    });

    await PlayerService.setPremium(true);
    await StaminaService.unlockPremiumStamina();

    if (!mounted) return;

    setState(() {
      isLoading = false;
    });

    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            backgroundColor: const Color(0xFF121821),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              "Premium Activated",
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              "You now have unlimited stamina and category-based quiz access.",
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context, true);
                },
                child: const Text("Continue"),
              ),
            ],
          ),
    );
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

  Widget buildPlanCard() {
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
          const Text(
            "Unlock the best version of your quiz journey.",
            style: TextStyle(color: Colors.white, fontSize: 15, height: 1.35),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                "₹99",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "/ month",
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            "Test premium screen for now — billing will be connected later.",
            style: TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool alreadyPremium = PlayerService.isPremium;

    return Scaffold(
      appBar: AppBar(title: const Text("Go Premium")),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildPlanCard(),
              const SizedBox(height: 22),

              const Text(
                "Why upgrade?",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),

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

              if (alreadyPremium)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green),
                  ),
                  child: const Column(
                    children: [
                      Icon(
                        Icons.verified_rounded,
                        color: Colors.green,
                        size: 34,
                      ),
                      SizedBox(height: 10),
                      Text(
                        "Premium Already Active",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        "Unlimited stamina and category access are already unlocked.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, height: 1.35),
                      ),
                    ],
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : activatePremium,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF8A3D),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child:
                        isLoading
                            ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                            : const Text(
                              "Activate Premium (Test)",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                  ),
                ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context, false);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Color(0xFF3B4659)),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text(
                    alreadyPremium ? "Back" : "Maybe Later",
                    style: const TextStyle(
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
