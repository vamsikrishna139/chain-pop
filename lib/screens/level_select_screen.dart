import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import '../game/levels/generation/difficulty_mode.dart';
import '../models/difficulty.dart';
import '../services/game_audio.dart';
import '../services/game_sfx.dart';
import '../services/storage_service.dart';
import '../theme/app_colors.dart';
import 'game_screen.dart';

const int _pageSize = 20;
const int _mediumPages = 5; // 100 levels

/// How many level cards should be visible for a given unlock progress.
int visibleLevelCardCount(int highestUnlocked) {
  return highestUnlocked >= 19 ? highestUnlocked + 1 : 20;
}

// ── Navigation group model ──────────────────────────────────────────────────

class NavGroup {
  final String label;
  final int firstPage;
  final int pageCount;

  const NavGroup(this.label, this.firstPage, this.pageCount);

  int get lastPage => firstPage + pageCount - 1;
  bool containsPage(int page) => page >= firstPage && page <= lastPage;

  /// A group is drillable when it spans more than 100 levels (> 5 pages).
  /// Tapping it opens a sub-view of 100-level sub-groups.
  bool get isDrillable => pageCount > _mediumPages;
}

String _rangeLabel(int startPage, int pages, int visible) {
  final s = startPage * _pageSize + 1;
  final e = min((startPage + pages) * _pageSize, visible);
  return '$s–$e';
}

/// Builds the top-level pill list. Groups telescope so the strip stays ≤ ~10.
///
/// Tiers (in pages): 5 = 100 lvls, 25 = 500 lvls, 50 = 1000 lvls.
/// Groups with > 5 pages are [NavGroup.isDrillable] and expand on tap into
/// 100-level sub-groups via [buildSubGroups].
List<NavGroup> buildNavGroups(int highestUnlocked) {
  final visible = visibleLevelCardCount(highestUnlocked);
  final totalPages = (visible / _pageSize).ceil().clamp(1, 99999);

  if (totalPages <= 7) {
    return List.generate(
      totalPages,
      (i) => NavGroup(_rangeLabel(i, 1, visible), i, 1),
    );
  }

  const recentCount = 5;
  final oldPageCount = totalPages - recentCount;

  // Jump from 5 straight to 25 so groups of 500 kick in right after 100s
  // overflow. This avoids intermediate 200-level groups that don't align
  // with the 3-tier drill-down (20 → 100 → 500).
  const niceSizes = [5, 25, 50, 100];
  final groupSize = niceSizes.firstWhere(
    (s) => (oldPageCount / s).ceil() <= 5,
    orElse: () => (oldPageCount / 5).ceil(),
  );

  final groups = <NavGroup>[];

  for (int p = 0; p < oldPageCount; p += groupSize) {
    final pages = min(groupSize, oldPageCount - p);
    groups.add(NavGroup(_rangeLabel(p, pages, visible), p, pages));
  }

  for (int p = oldPageCount; p < totalPages; p++) {
    groups.add(NavGroup(_rangeLabel(p, 1, visible), p, 1));
  }

  return groups;
}

/// Builds 100-level sub-groups inside a drillable [parent] group.
List<NavGroup> buildSubGroups(NavGroup parent, int highestUnlocked) {
  final visible = visibleLevelCardCount(highestUnlocked);
  final groups = <NavGroup>[];

  for (int p = parent.firstPage; p <= parent.lastPage; p += _mediumPages) {
    final pages = min(_mediumPages, parent.lastPage - p + 1);
    groups.add(NavGroup(_rangeLabel(p, pages, visible), p, pages));
  }

  return groups;
}

// ── Level Select Screen ─────────────────────────────────────────────────────

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
  late final GameAudioController _audio;

  @override
  void initState() {
    super.initState();
    _audio = GameAudioController(voiceCount: 2);
    _tabController = TabController(
      length: _modes.length,
      vsync: this,
      initialIndex: _modes.indexOf(widget.initialDifficulty),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    unawaited(_audio.dispose());
    super.dispose();
  }

  void _openLevel(int levelId, DifficultyMode mode) async {
    if (StorageService.gameSettings.soundEnabled) {
      unawaited(_audio.play(GameSfx.uiTap));
    }
    await StorageService.setSelectedDifficulty(mode);
    if (!mounted) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => GameScreen(level: levelId, difficulty: mode),
          ),
        )
        .then((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: _modes
                    .map((mode) => _ChapteredLevelView(
                          mode: mode,
                          audio: _audio,
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
            onPressed: () {
              if (StorageService.gameSettings.soundEnabled) {
                unawaited(_audio.play(GameSfx.uiTap, playbackRate: 0.9));
              }
              Navigator.of(context).pop();
            },
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
          onTap: (_) {
            if (StorageService.gameSettings.soundEnabled) {
              unawaited(_audio.play(GameSfx.uiTap, playbackRate: 1.1));
            }
            setState(() {});
          },
        ),
      ),
    );
  }
}

// ── Chaptered level view with drill-down ─────────────────────────────────────

class _ChapteredLevelView extends StatefulWidget {
  final DifficultyMode mode;
  final GameAudioController audio;
  final void Function(int levelId) onTap;

  const _ChapteredLevelView({
    required this.mode,
    required this.audio,
    required this.onTap,
  });

  @override
  State<_ChapteredLevelView> createState() => _ChapteredLevelViewState();
}

class _ChapteredLevelViewState extends State<_ChapteredLevelView> {
  late PageController _pageCtrl;
  late ScrollController _pillScrollCtrl;
  late int _currentPage;
  NavGroup? _drillGroup;

  @override
  void initState() {
    super.initState();
    final highest = StorageService.highestUnlocked(widget.mode);
    _currentPage = ((highest - 1) / _pageSize).floor();
    _pageCtrl = PageController(initialPage: _currentPage);
    _pillScrollCtrl = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollPillIntoView());
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _pillScrollCtrl.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    if (page != _currentPage && StorageService.gameSettings.soundEnabled) {
      unawaited(widget.audio.play(GameSfx.uiTap, playbackRate: 1.2));
    }
    _pageCtrl.animateToPage(
      page,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _onPillTap(NavGroup group) {
    if (StorageService.gameSettings.soundEnabled) {
      unawaited(widget.audio.play(GameSfx.uiTap, playbackRate: 1.05));
    }
    if (group.isDrillable) {
      setState(() => _drillGroup = group);
      _goToPage(group.firstPage);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollPillIntoView());
    } else {
      _goToPage(group.firstPage);
    }
  }

  void _closeDrill() {
    if (StorageService.gameSettings.soundEnabled) {
      unawaited(widget.audio.play(GameSfx.uiTap, playbackRate: 0.95));
    }
    setState(() => _drillGroup = null);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollPillIntoView());
  }

  List<NavGroup> _activePills(int highest) {
    if (_drillGroup != null) {
      return buildSubGroups(_drillGroup!, highest);
    }
    return buildNavGroups(highest);
  }

  void _scrollPillIntoView() {
    if (!_pillScrollCtrl.hasClients) return;
    final highest = StorageService.highestUnlocked(widget.mode);
    final pills = _activePills(highest);
    final activeIdx = pills.indexWhere((g) => g.containsPage(_currentPage));
    if (activeIdx < 0) return;

    const estimatedPillWidth = 80.0;
    final offset = _drillGroup != null ? 44.0 : 0.0;
    final target = offset +
        (activeIdx * estimatedPillWidth) -
        (_pillScrollCtrl.position.viewportDimension / 2) +
        (estimatedPillWidth / 2);
    _pillScrollCtrl.animateTo(
      target.clamp(0.0, _pillScrollCtrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _onPageChanged(int page) {
    setState(() {
      _currentPage = page;
      if (_drillGroup != null && !_drillGroup!.containsPage(page)) {
        _drillGroup = null;
      }
    });
    _scrollPillIntoView();
  }

  @override
  Widget build(BuildContext context) {
    final highest = StorageService.highestUnlocked(widget.mode);
    final visible = visibleLevelCardCount(highest);
    final totalPages = (visible / _pageSize).ceil().clamp(1, 99999);
    final accent = widget.mode.color;
    final nextLevelPage =
        ((highest) / _pageSize).floor().clamp(0, totalPages - 1);

    if (_drillGroup != null && !_drillGroup!.containsPage(_currentPage)) {
      _drillGroup = null;
    }

    final pills = _activePills(highest);
    final activeIdx = pills.indexWhere((g) => g.containsPage(_currentPage));
    final activeGroup = activeIdx >= 0 ? pills[activeIdx] : null;

    return Column(
      children: [
        // ── Pill strip ─────────────────────────────────────────────
        SizedBox(
          height: 44,
          child: Row(
            children: [
              if (_drillGroup != null)
                GestureDetector(
                  onTap: _closeDrill,
                  child: Container(
                    margin: const EdgeInsets.only(left: 12),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: accent.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back_ios_rounded,
                            color: accent, size: 12),
                        const SizedBox(width: 4),
                        Text(
                          _drillGroup!.label,
                          style: TextStyle(
                            color: accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  controller: _pillScrollCtrl,
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  itemCount: pills.length,
                  itemBuilder: (_, i) {
                    final group = pills[i];
                    final isCurrent = group.containsPage(_currentPage);

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: GestureDetector(
                        onTap: () => _onPillTap(group),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? accent.withOpacity(0.20)
                                : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isCurrent
                                  ? accent.withOpacity(0.6)
                                  : Colors.white12,
                              width: isCurrent ? 1.5 : 1,
                            ),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  group.label,
                                  style: TextStyle(
                                    color:
                                        isCurrent ? accent : Colors.white38,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                if (group.isDrillable) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    size: 14,
                                    color: isCurrent
                                        ? accent
                                        : Colors.white24,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 2),

        // ── Sub-page indicator ─────────────────────────────────────
        if (activeGroup != null && activeGroup.pageCount > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              '${_currentPage - activeGroup.firstPage + 1} / ${activeGroup.pageCount}',
              style: TextStyle(
                color: accent.withOpacity(0.5),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          )
        else
          const SizedBox(height: 4),

        // ── Page view ──────────────────────────────────────────────
        Expanded(
          child: Stack(
            children: [
              PageView.builder(
                controller: _pageCtrl,
                itemCount: totalPages,
                onPageChanged: _onPageChanged,
                itemBuilder: (_, pageIndex) {
                  return _ChapterGrid(
                    pageIndex: pageIndex,
                    mode: widget.mode,
                    highestUnlocked: highest,
                    onTap: widget.onTap,
                  );
                },
              ),

              if (_currentPage != nextLevelPage)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: Material(
                    color: accent,
                    borderRadius: BorderRadius.circular(16),
                    elevation: 6,
                    shadowColor: accent.withOpacity(0.4),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _goToPage(nextLevelPage),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.flag_rounded,
                                color: Colors.black87, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              'Lvl ${highest + 1}',
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Single page grid (20 levels) ────────────────────────────────────────────

class _ChapterGrid extends StatelessWidget {
  final int pageIndex;
  final DifficultyMode mode;
  final int highestUnlocked;
  final void Function(int levelId) onTap;

  const _ChapterGrid({
    required this.pageIndex,
    required this.mode,
    required this.highestUnlocked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final startLevel = pageIndex * _pageSize + 1;
    final visible = visibleLevelCardCount(highestUnlocked);

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.9,
      ),
      itemCount: _pageSize,
      itemBuilder: (_, index) {
        final levelId = startLevel + index;

        if (levelId > visible) {
          return const SizedBox.shrink();
        }

        final isUnlocked = levelId <= highestUnlocked;
        final isNext = levelId == highestUnlocked + 1;
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

// ── Level card ───────────────────────────────────────────────────────────────

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

    return Semantics(
      button: true,
      enabled: !locked,
      label: locked
          ? 'Level $levelId, locked'
          : isNext
              ? 'Level $levelId, next challenge'
              : 'Level $levelId, $stars stars',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          splashColor: accent.withOpacity(0.2),
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
                  ? [
                      BoxShadow(
                          color: accent.withOpacity(0.25), blurRadius: 12)
                    ]
                  : [],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (locked)
                  const Icon(Icons.lock_rounded,
                      color: Colors.white24, size: 20)
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
                if (completed)
                  _MiniStars(stars: stars, color: AppColors.starGold)
                else if (isNext)
                  Icon(Icons.play_circle_outline_rounded,
                      color: accent, size: 16)
                else
                  const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Mini stars ───────────────────────────────────────────────────────────────

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
