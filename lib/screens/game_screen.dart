import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import '../game/chain_pop_game.dart';
import '../game/levels/generation/difficulty_mode.dart';
import '../game/levels/level.dart';
import '../game/levels/level_manager.dart';
import '../models/difficulty.dart';
import '../models/game_settings.dart';
import '../services/game_audio.dart';
import '../services/game_sfx.dart';
import '../services/storage_service.dart';
import '../theme/app_colors.dart';

/// Full-screen game view for a single level.
///
/// Win overlay is rendered **inside this screen's own Stack** (not as a
/// modal route), which eliminates all Navigator-pop race conditions.
/// Auto-advances to the next level after a 5-second countdown.
class GameScreen extends StatefulWidget {
  final int level;
  final DifficultyMode difficulty;

  const GameScreen({
    super.key,
    required this.level,
    required this.difficulty,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late ChainPopGame _game;

  // ── Progress tracking ────────────────────────────────────────────────────
  int _totalNodes = 0;
  int _removedNodes = 0;

  // ── Lives tracking ───────────────────────────────────────────────────────
  static const int _maxLives = 3;
  int _livesRemaining = _maxLives;
  bool _hasWon = false;
  late final Stopwatch _stopwatch;
  int _earnedStars = 0;

  // ── Countdown timer (Medium / Hard only) ─────────────────────────────────
  int? _timeLeftSec;
  int? _timeLimitSec;
  Timer? _countdownTimer;

  // ── Auto-advance after win (5 seconds) ───────────────────────────────────
  int _autoAdvanceSec = 5;
  Timer? _autoAdvanceDelayTimer;
  Timer? _autoAdvanceTimer;

  // ── Ghost hint timer (Easy only) ─────────────────────────────────────────
  Timer? _ghostHintTimer;

  // ── Pre-generated level (single generation) ───────────────────────────────
  late LevelData _levelData;

  late GameSettings _settings;
  late final GameAudioController _audio;

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch()..start();
    _settings = StorageService.gameSettings;
    _audio = GameAudioController();

    // Generate ONCE here. Pass to the game via preloadedLevel so the
    // generator is never called twice for the same game load.
    _levelData = LevelManager.getLevel(widget.level, mode: widget.difficulty);
    _totalNodes = _levelData.nodes.length;

    _timeLimitSec = _computeTimeLimit(widget.difficulty, _totalNodes, widget.level);
    _timeLeftSec = _timeLimitSec;

    _buildGame();
    _startCountdown();
    _resetGhostHintTimer();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _autoAdvanceDelayTimer?.cancel();
    _autoAdvanceTimer?.cancel();
    _ghostHintTimer?.cancel();
    unawaited(_audio.dispose());
    super.dispose();
  }

  void _pushFeedbackToGame() {
    _game.soundEnabled = _settings.soundEnabled;
    _game.hapticsEnabled = _settings.hapticsEnabled;
    _game.colorblindPalette = _settings.colorblindFriendly;
    _game.onSfx = (sfx, {double playbackRate = 1.0}) =>
        unawaited(_audio.play(sfx, playbackRate: playbackRate));
  }

  // ── Time limit ────────────────────────────────────────────────────────────
  //
  // T(mode, N, L) = α × N × (1 + β × ln N) × max(γ_min, 1 − δ × L)
  //
  //   α   – base seconds per node (Fitts + Hick + scan + error budget)
  //   β   – Hick's-Law complexity coefficient (log-scaling for larger boards)
  //   δ   – Power-Law-of-Practice learning rate per level
  //   γ_min – floor on the learning discount (caps total speedup)
  //
  // Calibrated for the 65th-percentile casual gamer (avg IQ, age 18-35).

  static int? _computeTimeLimit(
    DifficultyMode mode,
    int nodeCount,
    int levelId,
  ) {
    switch (mode) {
      case DifficultyMode.easy:
        return null;
      case DifficultyMode.medium:
        final n = nodeCount.clamp(1, 999);
        final base = 4.0 * n * (1 + 0.18 * log(n));
        final learning = (1.0 - 0.008 * levelId).clamp(0.75, 1.0);
        return (base * learning).round().clamp(45, 180);
      case DifficultyMode.hard:
        final n = nodeCount.clamp(1, 999);
        final base = 2.8 * n * (1 + 0.12 * log(n));
        final learning = (1.0 - 0.004 * levelId).clamp(0.60, 1.0);
        return (base * learning).round().clamp(25, 150);
    }
  }

  // ── Game construction ─────────────────────────────────────────────────────

  void _buildGame() {
    _game = ChainPopGame(
      levelId: widget.level,
      difficulty: widget.difficulty,
      onWin: _handleWin,
      onJam: _handleFoul,
      onNodeRemoved: _handleNodeRemoved,
      preloadedLevel: _levelData, // ← single generation
    );
    _pushFeedbackToGame();
  }

  // ── Event handlers ────────────────────────────────────────────────────────

  void _handleFoul() {
    if (_hasWon) return;
    setState(() => _livesRemaining--);
    _resetGhostHintTimer();
    if (_livesRemaining <= 0) {
      _handleGameOver();
    }
  }

  void _handleGameOver() {
    _countdownTimer?.cancel();
    _ghostHintTimer?.cancel();
    _game.isGameOver = true;
    _game.playSfx(GameSfx.gameOver);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _GameOverDialog(
        difficulty: widget.difficulty,
        onRetry: () {
          Navigator.of(context).pop();
          _resetForRetry();
        },
        onMenu: () => Navigator.of(context).popUntil((r) => r.isFirst),
      ),
    );
  }

  void _handleNodeRemoved(int removed, int total) {
    if (!mounted) return;
    setState(() {
      _removedNodes = removed;
      _totalNodes = total;
    });
    _resetGhostHintTimer();
  }

  Future<void> _handleWin() async {
    _stopwatch.stop();
    _countdownTimer?.cancel();
    _ghostHintTimer?.cancel();
    _game.playSfx(GameSfx.win);

    final earned = widget.difficulty.starsForJams(_maxLives - _livesRemaining);
    await StorageService.saveStars(widget.difficulty, widget.level, earned);
    await StorageService.unlockLevel(widget.difficulty, widget.level + 1);

    if (!mounted) return;
    setState(() {
      _hasWon = true;
      _earnedStars = earned;
      _autoAdvanceSec = 5;
    });

    // Delay auto-advance countdown by 700 ms so the star animation
    // (3 × 150 ms stagger + 450 ms animation ≈ 900 ms) is visible first.
    _autoAdvanceDelayTimer?.cancel();
    _autoAdvanceTimer?.cancel();
    _autoAdvanceDelayTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted || !_hasWon) return;
      _autoAdvanceTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || !_hasWon) {
          t.cancel();
          return;
        }
        setState(() => _autoAdvanceSec--);
        if (_autoAdvanceSec <= 0) {
          t.cancel();
          _goNextLevel();
        }
      });
    });
  }

  void _handleTimeUp() {
    _countdownTimer?.cancel();
    _ghostHintTimer?.cancel();
    if (_hasWon || !mounted) return;

    _game.playSfx(GameSfx.gameOver);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TimeUpDialog(
        difficulty: widget.difficulty,
        onRetry: () {
          Navigator.of(context).pop();
          _resetForRetry();
        },
        onMenu: () => Navigator.of(context).popUntil((r) => r.isFirst),
      ),
    );
  }

  // ── Navigation (all in one place, no race conditions) ─────────────────────

  void _handleUndo() {
    if (_game.undo()) {
      _game.playSfx(GameSfx.uiTap);
      _resetGhostHintTimer();
      setState(() {});
    }
  }

  void _confirmReset() => _resetForRetry();

  void _resetForRetry() {
    _autoAdvanceDelayTimer?.cancel();
    _autoAdvanceTimer?.cancel();
    _countdownTimer?.cancel();
    _ghostHintTimer?.cancel();
    setState(() {
      _livesRemaining = _maxLives;
      _hasWon = false;
      _removedNodes = 0;
      _earnedStars = 0;
      _timeLeftSec = _timeLimitSec;
      _autoAdvanceSec = 5;
      _stopwatch
        ..reset()
        ..start();
    });
    _game.restart();
    _game.playSfx(GameSfx.restart);
    _startCountdown();
    _resetGhostHintTimer();
  }

  void _goNextLevel() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => GameScreen(
          level: widget.level + 1,
          difficulty: widget.difficulty,
        ),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: anim,
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  void _goMenu() {
    _autoAdvanceDelayTimer?.cancel();
    _autoAdvanceTimer?.cancel();
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  // ── Countdown (Medium / Hard) ─────────────────────────────────────────────

  void _startCountdown() {
    if (_timeLimitSec == null) return;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _hasWon) return;
      setState(() {
        _timeLeftSec =
            ((_timeLeftSec ?? _timeLimitSec!) - 1).clamp(0, _timeLimitSec!);
      });
      if (_timeLeftSec == 0) {
        _countdownTimer?.cancel();
        _handleTimeUp();
      }
    });
  }

  // ── Ghost hints (Easy only) ───────────────────────────────────────────────

  void _resetGhostHintTimer() {
    if (widget.difficulty != DifficultyMode.easy) return;
    _ghostHintTimer?.cancel();
    _ghostHintTimer = Timer(const Duration(seconds: 4), () {
      if (!_hasWon && mounted) _game.showHint();
    });
  }

  Future<void> _openSettings() async {
    _game.playSfx(GameSfx.uiTap);
    if (!mounted) return;
    final accent = widget.difficulty.color;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceDialog,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Settings',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.95),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Sound',
                          style: TextStyle(color: Colors.white70)),
                      value: _settings.soundEnabled,
                      activeThumbColor: accent,
                      onChanged: (v) async {
                        setState(() =>
                            _settings = _settings.copyWith(soundEnabled: v));
                        setModalState(() {});
                        _pushFeedbackToGame();
                        await StorageService.saveGameSettings(_settings);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Haptics',
                          style: TextStyle(color: Colors.white70)),
                      value: _settings.hapticsEnabled,
                      activeThumbColor: accent,
                      onChanged: (v) async {
                        setState(() =>
                            _settings = _settings.copyWith(hapticsEnabled: v));
                        setModalState(() {});
                        _pushFeedbackToGame();
                        await StorageService.saveGameSettings(_settings);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Colorblind palette',
                          style: TextStyle(color: Colors.white70)),
                      subtitle: Text(
                        'Higher-contrast hues (Okabe–Ito style)',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.45),
                          fontSize: 12,
                        ),
                      ),
                      value: _settings.colorblindFriendly,
                      activeThumbColor: accent,
                      onChanged: (v) async {
                        setState(() => _settings =
                            _settings.copyWith(colorblindFriendly: v));
                        setModalState(() {});
                        _pushFeedbackToGame();
                        await StorageService.saveGameSettings(_settings);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final accent = widget.difficulty.color;
    final progress = _totalNodes > 0 ? _removedNodes / _totalNodes : 0.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Ambient tint
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.0,
                  colors: [accent.withOpacity(0.05), Colors.transparent],
                ),
              ),
            ),
          ),

          // Flame canvas
          GameWidget(game: _game),

          // ── Top HUD ───────────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Row 1: Back | Level title | Hearts
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: _goMenu,
                        behavior: HitTestBehavior.opaque,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.chevron_left_rounded,
                              color: Colors.white70, size: 28),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'LEVEL ${widget.level}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _openSettings,
                        tooltip: 'Settings',
                        icon: Icon(
                          Icons.tune_rounded,
                          color: Colors.white.withOpacity(0.72),
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 2),
                      _LivesDisplay(livesRemaining: _livesRemaining),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Row 2: Difficulty | Progress | Timer
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        _DifficultyLabel(difficulty: widget.difficulty),
                        const Spacer(),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$_removedNodes / $_totalNodes nodes',
                              style: TextStyle(
                                color: accent.withOpacity(0.7),
                                fontSize: 11,
                                letterSpacing: 1,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              width: 80,
                              height: 3,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: progress.clamp(0.0, 1.0),
                                  backgroundColor: Colors.white12,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      accent.withOpacity(0.7)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        if (_timeLimitSec != null &&
                            _timeLeftSec != null)
                          _TimerBadge(
                            timeLeftSec: _timeLeftSec!,
                            timeLimitSec: _timeLimitSec!,
                            color: accent,
                          )
                        else
                          const SizedBox(width: 48),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom toolbar ────────────────────────────────────────────────
          if (!_hasWon)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ToolbarButton(
                        icon: Icons.lightbulb_outline_rounded,
                        accent: accent,
                        tooltip: 'Hint',
                        onPressed: () {
                          _game.showHint();
                          _resetGhostHintTimer();
                        },
                      ),
                      const SizedBox(width: 12),
                      _ToolbarButton(
                        icon: Icons.grid_on_rounded,
                        accent: accent,
                        tooltip: _game.axisGuidesVisible
                            ? 'Hide guides'
                            : 'Show guides',
                        selected: _game.axisGuidesVisible,
                        onPressed: () {
                          _game.toggleAxisGuides();
                          setState(() {});
                        },
                      ),
                      const SizedBox(width: 12),
                      _ToolbarButton(
                        icon: Icons.zoom_out_map_rounded,
                        accent: accent,
                        tooltip: 'Reset view',
                        onPressed: _game.resetView,
                      ),
                      const SizedBox(width: 12),
                      _UndoRestartButton(
                        accent: accent,
                        canUndo: _game.canUndo,
                        onUndo: _handleUndo,
                        onRestart: _confirmReset,
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Win overlay (inline, no modal) ────────────────────────────────
          AnimatedSlide(
            offset: _hasWon ? Offset.zero : const Offset(0, 1),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutQuart,
            child: AnimatedOpacity(
              opacity: _hasWon ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _WinPanel(
                  levelId: widget.level,
                  difficulty: widget.difficulty,
                  stars: _earnedStars,
                  foulCount: _maxLives - _livesRemaining,
                  timeTaken: _stopwatch.elapsed,
                  autoAdvanceSec: _autoAdvanceSec,
                  onMenu: _goMenu,
                  onRetry: _resetForRetry,
                  onNext: _goNextLevel,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Win Panel (inline, not a bottom sheet)
// ══════════════════════════════════════════════════════════════════════════════

class _WinPanel extends StatefulWidget {
  final int levelId;
  final DifficultyMode difficulty;
  final int stars;
  final int foulCount;
  final Duration timeTaken;
  final int autoAdvanceSec;
  final VoidCallback onMenu;
  final VoidCallback onRetry;
  final VoidCallback onNext;

  const _WinPanel({
    required this.levelId,
    required this.difficulty,
    required this.stars,
    required this.foulCount,
    required this.timeTaken,
    required this.autoAdvanceSec,
    required this.onMenu,
    required this.onRetry,
    required this.onNext,
  });

  @override
  State<_WinPanel> createState() => _WinPanelState();
}

class _WinPanelState extends State<_WinPanel> with TickerProviderStateMixin {
  late final List<AnimationController> _starCtrl;
  late final List<Animation<double>> _starScale;
  late final List<Timer> _starStartTimers;

  @override
  void initState() {
    super.initState();
    _starCtrl = List.generate(3, (i) {
      final c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 450),
      );
      return c;
    });
    _starStartTimers = List.generate(3, (i) {
      return Timer(Duration(milliseconds: 200 + i * 150), () {
        if (mounted) {
          _starCtrl[i].forward();
        }
      });
    });
    _starScale = _starCtrl
        .map((c) => Tween<double>(begin: 0.0, end: 1.0)
            .animate(CurvedAnimation(parent: c, curve: Curves.elasticOut)))
        .toList();
  }

  @override
  void dispose() {
    for (final timer in _starStartTimers) {
      timer.cancel();
    }
    for (final c in _starCtrl) c.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.difficulty.color;
    final frac = widget.autoAdvanceSec / 5.0;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: accent.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(0.2),
              blurRadius: 40,
              spreadRadius: 4,
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag bar / label
            Text(
              'LEVEL ${widget.levelId} · ${widget.difficulty.label}',
              style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2),
            ),
            const SizedBox(height: 6),
            const Text(
              'Complete!',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 20),

            // Stars
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) {
                final earned = i < widget.stars;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: ScaleTransition(
                    scale: _starScale[i],
                    child: Icon(
                      earned ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 50,
                      color: earned ? AppColors.starGold : Colors.white24,
                      shadows: earned
                          ? [
                              Shadow(
                                  color:
                                      AppColors.starGold.withOpacity(0.7),
                                  blurRadius: 16)
                            ]
                          : [],
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 18),

            // Stats
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Stat(label: 'TIME', value: _fmt(widget.timeTaken)),
                const SizedBox(width: 16),
                _Stat(label: 'FOULS', value: '${widget.foulCount}'),
              ],
            ),
            const SizedBox(height: 20),

            // Auto-advance progress bar + label
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.skip_next_rounded,
                        size: 14, color: Colors.white38),
                    const SizedBox(width: 4),
                    Text(
                      'Next level in ${widget.autoAdvanceSec}s',
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: frac.clamp(0.0, 1.0),
                    backgroundColor: Colors.white12,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(accent.withOpacity(0.6)),
                    minHeight: 3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: _OutBtn(
                      label: 'MENU',
                      icon: Icons.home_rounded,
                      onPressed: widget.onMenu),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _OutBtn(
                      label: 'RETRY',
                      icon: Icons.refresh_rounded,
                      onPressed: widget.onRetry),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: _FillBtn(
                      label: 'NEXT',
                      icon: Icons.arrow_forward_rounded,
                      color: accent,
                      onPressed: widget.onNext),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Small widgets
// ══════════════════════════════════════════════════════════════════════════════

class _Stat extends StatelessWidget {
  final String label, value;
  const _Stat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Text(label,
            style: const TextStyle(
                color: Colors.white38, fontSize: 10, letterSpacing: 1.2)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

class _OutBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  const _OutBtn(
      {required this.label, required this.icon, required this.onPressed});
  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 15, color: Colors.white38),
      label: Text(label,
          style: const TextStyle(
              color: Colors.white38,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Colors.white12)),
      ),
    );
  }
}

class _FillBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  const _FillBtn(
      {required this.label,
      required this.icon,
      required this.color,
      required this.onPressed});
  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 8,
        shadowColor: color.withOpacity(0.5),
      ),
    );
  }
}

class _TimerBadge extends StatelessWidget {
  final int timeLeftSec, timeLimitSec;
  final Color color;
  const _TimerBadge(
      {required this.timeLeftSec,
      required this.timeLimitSec,
      required this.color});
  @override
  Widget build(BuildContext context) {
    final frac = timeLimitSec > 0 ? timeLeftSec / timeLimitSec : 0.0;
    final c = frac < 0.20
        ? AppColors.timerWarning
        : frac < 0.40
            ? AppColors.timerCaution
            : color;
    final m = (timeLeftSec ~/ 60).toString();
    final s = (timeLeftSec % 60).toString().padLeft(2, '0');
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.timer_outlined, size: 14, color: c),
      const SizedBox(width: 4),
      Text('$m:$s',
          style: TextStyle(
              color: c,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1)),
    ]);
  }
}

class _TimeUpDialog extends StatelessWidget {
  final DifficultyMode difficulty;
  final VoidCallback onRetry, onMenu;
  const _TimeUpDialog(
      {required this.difficulty, required this.onRetry, required this.onMenu});
  @override
  Widget build(BuildContext context) {
    final accent = difficulty.color;
    return AlertDialog(
      backgroundColor: AppColors.surfaceDialog,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: accent.withOpacity(0.3)),
      ),
      title: Column(children: [
        Icon(Icons.timer_off_rounded, color: accent, size: 48),
        const SizedBox(height: 12),
        const Text("TIME'S UP!",
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 2)),
      ]),
      content: Text('The clock ran out. Try again?',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withOpacity(0.6))),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
            onPressed: onMenu,
            child: const Text('MENU', style: TextStyle(color: Colors.white38))),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('RETRY',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.black,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }
}

class _DifficultyLabel extends StatelessWidget {
  final DifficultyMode difficulty;
  const _DifficultyLabel({required this.difficulty});
  @override
  Widget build(BuildContext context) {
    return Text(
      difficulty.label.toUpperCase(),
      style: TextStyle(
        color: difficulty.color,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    );
  }
}

/// Dual-purpose button: **tap → undo**, **hold → restart**.
///
/// Shows a brief floating label ("UNDO" / "RESTART") above the button as
/// feedback. The hold gesture uses a circular progress ring (popular game
/// pattern — no blocking dialog). Both actions are designed to later gate
/// behind a rewarded ad.
class _UndoRestartButton extends StatefulWidget {
  final Color accent;
  final bool canUndo;
  final VoidCallback onUndo;
  final VoidCallback onRestart;

  const _UndoRestartButton({
    required this.accent,
    required this.canUndo,
    required this.onUndo,
    required this.onRestart,
  });

  @override
  State<_UndoRestartButton> createState() => _UndoRestartButtonState();
}

class _UndoRestartButtonState extends State<_UndoRestartButton>
    with TickerProviderStateMixin {
  static const _holdDuration = Duration(milliseconds: 700);

  late final AnimationController _holdCtrl;
  late final AnimationController _labelCtrl;
  bool _holding = false;
  String _labelText = '';

  @override
  void initState() {
    super.initState();
    _holdCtrl = AnimationController(vsync: this, duration: _holdDuration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          _holding = false;
          _holdCtrl.reset();
          _showLabel('RESTART');
          widget.onRestart();
        }
      });
    _labelCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void dispose() {
    _holdCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  void _showLabel(String text) {
    setState(() => _labelText = text);
    _labelCtrl.forward(from: 0);
  }

  void _onTap() {
    if (!widget.canUndo) return;
    _showLabel('UNDO');
    widget.onUndo();
  }

  void _onLongPressStart(LongPressStartDetails _) {
    _holding = true;
    _holdCtrl.forward(from: 0);
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    if (_holding) {
      _holding = false;
      _holdCtrl.reverse();
    }
  }

  void _onLongPressCancel() {
    if (_holding) {
      _holding = false;
      _holdCtrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUndo = widget.canUndo;
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Floating label — positioned above the button via negative top
          Positioned(
            top: -22,
            child: AnimatedBuilder(
              animation: _labelCtrl,
              builder: (context, _) {
                final t = _labelCtrl.value;
                final opacity = t < 0.15
                    ? (t / 0.15)
                    : t > 0.7
                        ? ((1.0 - t) / 0.3).clamp(0.0, 1.0)
                        : 1.0;
                final slide = t < 0.15 ? (1.0 - t / 0.15) * 6 : 0.0;
                if (opacity <= 0) return const SizedBox.shrink();
                return Transform.translate(
                  offset: Offset(0, slide),
                  child: Opacity(
                    opacity: opacity,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: widget.accent.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _labelText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // The button itself
          GestureDetector(
            onTap: _onTap,
            onLongPressStart: _onLongPressStart,
            onLongPressEnd: _onLongPressEnd,
            onLongPressCancel: _onLongPressCancel,
            child: AnimatedBuilder(
              animation: _holdCtrl,
              builder: (context, _) {
                final v = _holdCtrl.value;
                return Container(
                  width: 48,
                  height: 48,
                    decoration: BoxDecoration(
                      color: Color.lerp(
                        Colors.white.withValues(alpha: hasUndo ? 0.06 : 0.03),
                        widget.accent.withValues(alpha: 0.18),
                        v,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: v > 0
                          ? [
                              BoxShadow(
                                color: widget.accent
                                    .withValues(alpha: v * 0.4),
                                blurRadius: 12 * v,
                                spreadRadius: 2 * v,
                              ),
                            ]
                          : null,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (v > 0)
                          SizedBox(
                            width: 36,
                            height: 36,
                            child: CircularProgressIndicator(
                              value: v,
                              strokeWidth: 2.5,
                              color: widget.accent,
                              backgroundColor: Colors.white12,
                            ),
                          ),
                        Transform.rotate(
                          angle: v * 2 * 3.14159265,
                          child: Icon(
                            v > 0.1
                                ? Icons.refresh_rounded
                                : Icons.undo_rounded,
                            color: Color.lerp(
                              hasUndo
                                  ? Colors.white70
                                  : Colors.white24,
                              widget.accent,
                              v,
                            ),
                            size: 22,
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

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String tooltip;
  final VoidCallback onPressed;
  final bool selected;

  const _ToolbarButton({
    required this.icon,
    required this.accent,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: selected
                  ? accent.withOpacity(0.18)
                  : Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon,
                color: selected ? accent : Colors.white70, size: 22),
          ),
        ),
      ),
    );
  }
}

class _LivesDisplay extends StatelessWidget {
  final int livesRemaining;
  final int maxLives;
  const _LivesDisplay({required this.livesRemaining, this.maxLives = 3});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(maxLives, (i) {
        final alive = i < livesRemaining;
        return Padding(
          padding: EdgeInsets.only(left: i > 0 ? 4.0 : 0),
          child: AnimatedScale(
            scale: alive ? 1.0 : 0.7,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutBack,
            child: AnimatedOpacity(
              opacity: alive ? 1.0 : 0.3,
              duration: const Duration(milliseconds: 400),
              child: Icon(
                alive ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: alive ? Colors.redAccent : Colors.white38,
                size: 20,
                shadows: alive
                    ? [
                        Shadow(
                          color: Colors.redAccent.withOpacity(0.5),
                          blurRadius: 8,
                        )
                      ]
                    : [],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _GameOverDialog extends StatelessWidget {
  final DifficultyMode difficulty;
  final VoidCallback onRetry, onMenu;
  const _GameOverDialog(
      {required this.difficulty, required this.onRetry, required this.onMenu});
  @override
  Widget build(BuildContext context) {
    final accent = difficulty.color;
    return AlertDialog(
      backgroundColor: AppColors.surfaceDialog,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.redAccent.withOpacity(0.3)),
      ),
      title: Column(children: [
        Icon(Icons.favorite_rounded, color: Colors.redAccent.withOpacity(0.4), size: 48),
        const SizedBox(height: 12),
        const Text('OUT OF LIVES',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 2)),
      ]),
      content: Text('You ran out of lives. Try again?',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withOpacity(0.6))),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
            onPressed: onMenu,
            child: const Text('MENU', style: TextStyle(color: Colors.white38))),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('RETRY',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.black,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }
}
