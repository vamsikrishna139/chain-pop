import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../game/levels/generation/difficulty_mode.dart';
import '../game/levels/level_grid_config.dart';
import '../models/difficulty.dart';
import '../theme/app_colors.dart';
import '../services/game_audio_scope.dart';
import '../services/game_sfx.dart';
import '../services/storage/storage_locator.dart';
import 'game_screen.dart';

const int _pageSize = kLevelsPerGridPage;

/// How many level cards should be visible for a given unlock progress.
int visibleLevelCardCount(int highestUnlocked) {
  return highestUnlocked >= 19 ? highestUnlocked + 1 : 20;
}

class NavGroup {
  final String label;
  final int firstLevel;
  final int lastLevel;

  const NavGroup(this.label, this.firstLevel, this.lastLevel);

  int get firstPage => ((firstLevel - 1) / _pageSize).floor();
  int get lastPage => ((lastLevel - 1) / _pageSize).floor();
  int get pageCount => lastPage - firstPage + 1;
  int get levelCount => lastLevel - firstLevel + 1;
  bool containsPage(int page) => page >= firstPage && page <= lastPage;
  bool containsLevel(int level) => level >= firstLevel && level <= lastLevel;

  bool get isDrillable => levelCount > 1;
  bool get isLeaf => levelCount == 1;
}

String _rangeLabel(int startLevel, int endLevel) {
  if (startLevel == endLevel) return '$startLevel';
  return '$startLevel–$endLevel';
}

List<NavGroup> _buildChunkGroups(int start, int end, int chunkSize) {
  final groups = <NavGroup>[];
  for (int s = start; s <= end; s += chunkSize) {
    final e = min(end, s + chunkSize - 1);
    groups.add(NavGroup(_rangeLabel(s, e), s, e));
  }
  return groups;
}

List<NavGroup> buildNavGroups(int highestUnlocked) {
  final visible = visibleLevelCardCount(highestUnlocked);
  if (visible <= 100) {
    return _buildChunkGroups(1, visible, _pageSize);
  }
  final groups = <NavGroup>[];
  final completedHundreds = (highestUnlocked ~/ 100) * 100;
  final summaryEnd = completedHundreds.clamp(100, visible);
  if (summaryEnd >= 100) {
    groups.add(NavGroup(_rangeLabel(1, summaryEnd), 1, summaryEnd));
  }
  if (summaryEnd < visible) {
    groups.addAll(_buildChunkGroups(summaryEnd + 1, visible, 10));
  }
  return groups;
}

List<NavGroup> buildSubGroups(NavGroup parent, int highestUnlocked) {
  final visible = visibleLevelCardCount(highestUnlocked);
  final start = parent.firstLevel.clamp(1, visible);
  final end = parent.lastLevel.clamp(1, visible);
  final span = end - start + 1;

  if (span > 500) return _buildChunkGroups(start, end, 500);
  if (span > 100) return _buildChunkGroups(start, end, 100);
  if (span > 20) return _buildChunkGroups(start, end, 20);
  return _buildChunkGroups(start, end, 1);
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

class _LevelSelectScreenState extends State<LevelSelectScreen> {
  late DifficultyMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialDifficulty;
  }

  void _openLevel(int levelId, DifficultyMode mode) async {
    if (StorageLocator.instance.gameSettings.soundEnabled) {
      unawaited(ChainPopAudioScope.of(context).play(GameSfx.uiTap));
    }
    await StorageLocator.instance.setSelectedDifficulty(mode);
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
    final accent = _mode.color;
    final highest = StorageLocator.instance.highestUnlocked(_mode);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top Navigation Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    onTap: () {
                      if (StorageLocator.instance.gameSettings.soundEnabled) {
                        unawaited(ChainPopAudioScope.of(context).play(GameSfx.uiTap, playbackRate: 0.9));
                      }
                      Navigator.of(context).pop();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.arrow_back_rounded, size: 16, color: Colors.white70),
                          const SizedBox(width: 6),
                          Text(
                            'BACK',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12,
                              color: Colors.white70,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${_mode.label.toUpperCase()} TRACK',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          letterSpacing: 1.5,
                          color: accent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'FRONTIER: LEVEL $highest',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Breadcrumbs / Grid
            Expanded(
              child: _ChapteredLevelView(
                mode: _mode,
                highestUnlocked: highest,
                onTap: (id) => _openLevel(id, _mode),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapteredLevelView extends StatefulWidget {
  final DifficultyMode mode;
  final int highestUnlocked;
  final void Function(int levelId) onTap;

  const _ChapteredLevelView({
    required this.mode,
    required this.highestUnlocked,
    required this.onTap,
  });

  @override
  State<_ChapteredLevelView> createState() => _ChapteredLevelViewState();
}

class _ChapteredLevelViewState extends State<_ChapteredLevelView> {
  late PageController _pageCtrl;
  late ScrollController _pillScrollCtrl;
  late int _currentPage;
  final List<NavGroup> _drillPath = [];
  int? _selectedLeafLevel;

  @override
  void initState() {
    super.initState();
    _currentPage = ((widget.highestUnlocked - 1) / _pageSize).floor();
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
    if (page != _currentPage && StorageLocator.instance.gameSettings.soundEnabled) {
      unawaited(ChainPopAudioScope.of(context).play(GameSfx.uiTap, playbackRate: 1.2));
    }
    _pageCtrl.animateToPage(
      page,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _onPillTap(NavGroup group) {
    if (StorageLocator.instance.gameSettings.soundEnabled) {
      unawaited(ChainPopAudioScope.of(context).play(GameSfx.uiTap, playbackRate: 1.05));
    }
    if (group.isDrillable) {
      setState(() {
        _drillPath.add(group);
        _selectedLeafLevel = null;
      });
      _goToPage(group.firstPage);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollPillIntoView());
    } else {
      setState(() => _selectedLeafLevel = group.firstLevel);
      _goToPage(group.firstPage);
    }
  }

  void _closeDrill() {
    if (StorageLocator.instance.gameSettings.soundEnabled) {
      unawaited(ChainPopAudioScope.of(context).play(GameSfx.uiTap, playbackRate: 0.95));
    }
    if (_drillPath.isEmpty) return;
    setState(() {
      _drillPath.removeLast();
      _selectedLeafLevel = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollPillIntoView());
  }

  List<NavGroup> _activePills(int highest) {
    var groups = buildNavGroups(highest);
    for (final selected in _drillPath) {
      final stillVisible = groups.any((g) => g.firstLevel == selected.firstLevel && g.lastLevel == selected.lastLevel);
      if (!stillVisible) break;
      groups = buildSubGroups(selected, highest);
    }
    return groups;
  }

  bool _isCurrentGroup(NavGroup group) {
    if (group.isLeaf && _selectedLeafLevel != null) {
      return group.firstLevel == _selectedLeafLevel;
    }
    return group.containsPage(_currentPage);
  }

  void _scrollPillIntoView() {
    if (!_pillScrollCtrl.hasClients) return;
    final pills = _activePills(widget.highestUnlocked);
    final activeIdx = pills.indexWhere((g) => g.containsPage(_currentPage));
    if (activeIdx < 0) return;

    const estimatedPillWidth = 80.0;
    final offset = _drillPath.isNotEmpty ? 44.0 : 0.0;
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
      while (_drillPath.isNotEmpty && !_drillPath.last.containsPage(page)) {
        _drillPath.removeLast();
      }
      final pageStart = page * _pageSize + 1;
      final pageEnd = pageStart + _pageSize - 1;
      if (_selectedLeafLevel != null &&
          (_selectedLeafLevel! < pageStart || _selectedLeafLevel! > pageEnd)) {
        _selectedLeafLevel = null;
      }
    });
    _scrollPillIntoView();
  }

  @override
  Widget build(BuildContext context) {
    final highest = widget.highestUnlocked;
    final visible = visibleLevelCardCount(highest);
    final totalPages = (visible / _pageSize).ceil().clamp(1, 99999);
    final nextLevelPage = ((highest) / _pageSize).floor().clamp(0, totalPages - 1);

    final pills = _activePills(highest);
    final accent = widget.mode.color;

    return Column(
      children: [
        // Ribbon
        Container(
          height: 44,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
          ),
          child: Row(
            children: [
              if (_drillPath.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 12, right: 4),
                  child: InkWell(
                    onTap: _closeDrill,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.arrow_back_rounded, size: 14, color: accent),
                          const SizedBox(width: 4),
                          Text(
                            _drillPath.last.label,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  controller: _pillScrollCtrl,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: pills.length,
                  itemBuilder: (_, i) {
                    final group = pills[i];
                    final isCurrent = _isCurrentGroup(group);

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: InkWell(
                        onTap: () => _onPillTap(group),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: isCurrent ? Colors.white : AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isCurrent ? Colors.white : Colors.white.withValues(alpha: 0.1),
                            ),
                            boxShadow: isCurrent ? [BoxShadow(color: Colors.white.withValues(alpha: 0.3), blurRadius: 4)] : [],
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            children: [
                              Text(
                                group.label,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 11,
                                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                  color: isCurrent ? Colors.black : Colors.white70,
                                ),
                              ),
                              if (group.containsLevel(highest)) ...[
                                const SizedBox(width: 4),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ],
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

        // Grid
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
                  child: InkWell(
                    onTap: () => _goToPage(nextLevelPage),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.5), blurRadius: 12)],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.flag_rounded, size: 18, color: Colors.black),
                          const SizedBox(width: 8),
                          Text(
                            'LEVEL $highest',
                            style: GoogleFonts.jetBrainsMono(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.black,
                            ),
                          ),
                        ],
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
    final accent = mode.color;

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.0,
      ),
      itemCount: _pageSize,
      itemBuilder: (_, index) {
        final levelId = startLevel + index;

        if (levelId > visible) {
          return const SizedBox.shrink();
        }

        final isUnlocked = levelId <= highestUnlocked;
        final isNext = levelId == highestUnlocked + 1;
        final isFrontier = isUnlocked && levelId == highestUnlocked;
        final starCount = StorageLocator.instance.stars(mode, levelId);

        return InkWell(
          onTap: (isUnlocked || isNext) ? () => onTap(levelId) : null,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: isFrontier ? const Color(0xFF1A1A26) : (isUnlocked ? AppColors.surface : AppColors.background),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isFrontier ? accent : (isUnlocked ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05)),
                width: isFrontier ? 2 : 1,
              ),
              boxShadow: isFrontier ? [BoxShadow(color: accent.withValues(alpha: 0.5), blurRadius: 18, spreadRadius: -2)] : [],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$levelId',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: isFrontier ? Colors.white : (isUnlocked ? Colors.white70 : Colors.white30),
                  ),
                ),
                if (isFrontier)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow_rounded, size: 14, color: Colors.black),
                  )
                else if (isUnlocked)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      3,
                      (i) => Icon(
                        i < starCount ? Icons.star_rounded : Icons.star_border_rounded,
                        size: 10,
                        color: i < starCount ? AppColors.starGold : Colors.white24,
                      ),
                    ),
                  )
                else if (isNext)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow_rounded, size: 14, color: Colors.white70),
                  )
                else
                  const Icon(Icons.lock_rounded, size: 14, color: Colors.white24),
                Text(
                  isFrontier ? 'ACTIVE' : (isUnlocked ? 'CLEAR' : (isNext ? 'NEXT' : 'LOCKED')),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 8,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
