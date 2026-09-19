import 'package:flutter/material.dart';
import '../models/league.dart';
import '../services/auth_service.dart';
import '../services/leaderboard_repository.dart';
import '../services/league_service.dart';
import '../services/player_service.dart';
import '../widgets/league_badge.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  late String selectedLeague;

  final List<String> leagues = LeagueService.leagueNames;

  bool loading = true;
  List<Map<String, dynamic>> allEntries = [];

  // Bumped on every loadEntries() call and captured as `requestId` below --
  // if a second refresh (e.g. rapid double-tapping the Refresh button)
  // starts before the first one's network call resolves, whichever
  // response lands out of order can no longer overwrite a newer one; a
  // request only applies its result if it's still the most recent one
  // issued by the time it resolves.
  int _loadRequestId = 0;

  @override
  void initState() {
    super.initState();
    selectedLeague = PlayerService.getLeague();
    loadEntries();
  }

  Future<void> loadEntries() async {
    final requestId = ++_loadRequestId;
    final entries = await LeaderboardRepository.fetchTopEntries();
    if (!mounted) return;
    if (requestId != _loadRequestId) return;
    setState(() {
      allEntries = entries;
      loading = false;
      _recomputeVisiblePlayers();
    });
  }

  Color getLeagueColor(String league) {
    return LeagueService.colorForLeague(league);
  }

  /// Reads an entry's XP defensively. This collection is shared and
  /// client-writable (any signed-in player can write their own
  /// `leaderboards/global/entries/{uid}` doc), so a value that isn't a real
  /// number -- garbage written by a tampered client, or just a missing
  /// field on an old/hand-edited doc -- must never crash this screen for
  /// every other player who opens it.
  int _xpOf(Map<String, dynamic> e) => (e["xp"] as num?)?.toInt() ?? 0;

  /// An entry's opt-in photo URL, if it has one and chose to share it (see
  /// SettingsService.showPhotoOnLeaderboard / LeaderboardRepository) --
  /// null for guests, linked accounts with no photo, or anyone who's kept
  /// this off (the common case, since it defaults off).
  String? _photoUrlOf(Map<String, dynamic> e) {
    final url = e["photoUrl"] as String?;
    return (url != null && url.isNotEmpty) ? url : null;
  }

  /// The avatar shown in a leaderboard row's circle: the player's shared
  /// photo when they have one, otherwise the same league medal as always.
  /// `errorBuilder` covers a broken/expired/revoked photo URL by falling
  /// straight back to the medal rather than showing a broken-image icon.
  Widget _buildAvatar(League league, String? photoUrl) {
    if (photoUrl == null) return LeagueBadge(league: league, size: 46);

    return ClipOval(
      child: Image.network(
        photoUrl,
        width: 46,
        height: 46,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            LeagueBadge(league: league, size: 46),
      ),
    );
  }

  /// Players in the currently selected league, sorted by XP with a fresh
  /// #rank assigned within that league -- mirrors the old mock-data
  /// behaviour, just built from real synced entries instead.
  ///
  /// Deliberately returns new maps rather than writing a "rank" key back
  /// into the entries in [allEntries]. This used to run straight from
  /// build() and mutate the shared entry maps in place -- a side effect
  /// during build, re-running the filter and sort over up to 200 entries
  /// on every single rebuild (including every one-second ticker frame
  /// elsewhere in the app), and leaving a stale rank baked into entries
  /// that belong to a different league tab.
  List<Map<String, dynamic>> playersForSelectedLeague() {
    final filtered =
        allEntries.where((e) => e["league"] == selectedLeague).toList();
    filtered.sort((a, b) => _xpOf(b).compareTo(_xpOf(a)));
    return [
      for (int i = 0; i < filtered.length; i++)
        {...filtered[i], "rank": i + 1},
    ];
  }

  /// Cached result of [playersForSelectedLeague] -- recomputed only when
  /// the entries or the selected league actually change, not on every
  /// rebuild. See that method for why.
  List<Map<String, dynamic>> _visiblePlayers = const [];

  void _recomputeVisiblePlayers() {
    _visiblePlayers = playersForSelectedLeague();
  }

  @override
  Widget build(BuildContext context) {
    final players = _visiblePlayers;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Leaderboard"),
        actions: [
          IconButton(
            tooltip: "Refresh",
            onPressed: () {
              setState(() => loading = true);
              loadEntries();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: leagues.length,
              itemBuilder: (context, index) {
                final league = leagues[index];
                final selected = league == selectedLeague;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedLeague = league;
                      _recomputeVisiblePlayers();
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color:
                          selected
                              ? getLeagueColor(league).withValues(alpha: 0.18)
                              : const Color(0xFF181C24),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color:
                            selected ? getLeagueColor(league) : Colors.white10,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      league,
                      style: TextStyle(
                        color:
                            selected ? getLeagueColor(league) : Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF181C24),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              "Showing $selectedLeague League",
              style: TextStyle(
                color: getLeagueColor(selectedLeague),
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child:
                loading
                    ? const Center(child: CircularProgressIndicator())
                    : players.isEmpty
                    ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          "No players in $selectedLeague yet -- keep playing and be the first!",
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white54),
                        ),
                      ),
                    )
                    : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: players.length,
                      itemBuilder: (context, index) {
                        final player = players[index];
                        final isYou = player["uid"] == AuthService.uid;
                        // Uses the entry's stored "league" field (same field
                        // the list is filtered by, and the same one shown as
                        // text a few lines below) rather than deriving a
                        // league fresh from the entry's current XP. A
                        // leaderboard doc's XP can be newer than its "league"
                        // field if the two were last written at slightly
                        // different times -- deriving fresh from XP here
                        // could then show an avatar badge for a different
                        // league than the tab the player is listed under and
                        // the league name printed next to their name.
                        final league = LeagueService.leagueForName(
                          (player["league"] as String?) ?? selectedLeague,
                        );

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color:
                                isYou
                                    ? const Color(0xFF1B2333)
                                    : const Color(0xFF181C24),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color:
                                  isYou
                                      ? getLeagueColor(selectedLeague)
                                      : Colors.white10,
                            ),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 50,
                                height: 50,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    _buildAvatar(
                                      league,
                                      _photoUrlOf(player),
                                    ),
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0F1117),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: Colors.white24,
                                          ),
                                        ),
                                        child: Text(
                                          "#${player["rank"]}",
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (player["username"] as String?) ??
                                          "Player",
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                        color:
                                            isYou
                                                ? getLeagueColor(
                                                  selectedLeague,
                                                )
                                                : Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      (player["league"] as String?) ?? "",
                                      style: TextStyle(
                                        color: getLeagueColor(
                                          (player["league"] as String?) ??
                                              "Bronze",
                                        ),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                "${player["xp"]} XP",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
