import 'package:flutter/material.dart';
import '../game/levels/generation/difficulty_mode.dart';
import '../models/difficulty.dart';
import '../services/storage_service.dart';
import 'game_screen.dart';

/// Level Select Screen.
///
/// Shows a scrollable grid of level cards grouped by difficulty.
/// Tabs switch the active difficulty.  Locked levels show a padlock;
/// completed levels show their star rating.
int visibleLevelCardCount(int highestUnlocked) {
  return highestUnlocked >= 19 ? highestUnlocked + 1 : 20;
}

class LevelSelectScreen extends StatefulWidget {
  final DifficultyMode initialDifficulty;

  const LevelSelectScreen({
    super.key,
    required this.initialDifficulty,
  });

  @override
  State<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends State<LevelSelectScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _modes = DifficultyMode.values;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _modes.length,
      vsync: this,
      initialIndex: _modes.indexOf(widget.initialDifficulty),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openLevel(int levelId, DifficultyMode mode) async {
    // Persist the selected difficulty globally.
    await StorageService.setSelectedDifficulty(mode);

    if (!mounted) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => GameScreen(level: levelId, difficulty: mode),
          ),
        )
        .then((_) => setState(() {})); // refresh stars on return
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: _modes
                    .map((mode) => _LevelGrid(
                          mode: mode,
                          onTap: (id) => _openLevel(id, mode),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          IconButton(
            icon:
                const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          const Text(
            'SELECT LEVEL',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: _modes[_tabController.index].color.withOpacity(0.20),
            border: Border.all(
              color: _modes[_tabController.index].color.withOpacity(0.5),
            ),
          ),
          dividerColor: Colors.transparent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1),
          tabs: _modes
              .map((m) => Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(m.icon, size: 14),
                        const SizedBox(width: 6),
                        Text(m.label),
                      ],
                    ),
                  ))
              .toList(),
          onTap: (_) => setState(() {}), // update tab indicator colour
        ),
      ),
    );
  }
}

// ── Level grid ────────────────────────────────────────────────────────────────

class _LevelGrid extends StatelessWidget {
  final DifficultyMode mode;
  final void Function(int levelId) onTap;

  const _LevelGrid({required this.mode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final highest = StorageService.highestUnlocked(mode);
    // Show up to highest+1 (the next challenge) or minimum 20 cards.
    final visibleCount = visibleLevelCardCount(highest);

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.9,
      ),
      itemCount: visibleCount,
      itemBuilder: (_, index) {
        final levelId = index + 1;
        final isUnlocked = levelId <= highest;
        final isNext = levelId == highest + 1;
        final starCount = StorageService.stars(mode, levelId);

        return _LevelCard(
          levelId: levelId,
          mode: mode,
          stars: starCount,
          isUnlocked: isUnlocked,
          isNext: isNext,
          onTap: isUnlocked || isNext ? () => onTap(levelId) : null,
        );
      },
    );
  }
}

class _LevelCard extends StatelessWidget {
  final int levelId;
  final DifficultyMode mode;
  final int stars;
  final bool isUnlocked;
  final bool isNext;
  final VoidCallback? onTap;

  const _LevelCard({
    required this.levelId,
    required this.mode,
    required this.stars,
    required this.isUnlocked,
    required this.isNext,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = mode.color;
    final locked = !isUnlocked && !isNext;
    final completed = isUnlocked && stars > 0;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: locked
              ? Colors.white.withOpacity(0.04)
              : completed
                  ? accent.withOpacity(0.12)
                  : Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isNext
                ? accent.withOpacity(0.7)
                : completed
                    ? accent.withOpacity(0.3)
                    : Colors.white12,
            width: isNext ? 1.5 : 1,
          ),
          boxShadow: isNext
              ? [BoxShadow(color: accent.withOpacity(0.25), blurRadius: 12)]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Level number or lock icon
            if (locked)
              const Icon(Icons.lock_rounded, color: Colors.white24, size: 20)
            else
              Text(
                '$levelId',
                style: TextStyle(
                  color: isNext ? accent : Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),

            const SizedBox(height: 4),

            // Stars (only when completed)
            if (completed)
              _MiniStars(stars: stars, color: const Color(0xFFFFC371))
            else if (isNext)
              Icon(Icons.play_circle_outline_rounded, color: accent, size: 16)
            else
              const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _MiniStars extends StatelessWidget {
  final int stars;
  final Color color;
  const _MiniStars({required this.stars, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
          3,
          (i) => Icon(
                i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 12,
                color: i < stars ? color : Colors.white24,
              )),
    );
  }
}
