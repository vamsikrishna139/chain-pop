import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

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
import 'game/game_screen_constants.dart';
import 'game/game_time_limit.dart';
import 'game/widgets/game_bottom_toolbar.dart';
import 'game/widgets/game_dialogs.dart';
import 'game/widgets/game_header_hud.dart';
import 'game/widgets/game_pause_overlay.dart';
import 'game/widgets/game_settings_sheet.dart';
import 'game/widgets/win_panel.dart';

/// Full-screen game view for a single level.
///
/// Win overlay is rendered **inside this screen's own Stack** (not as a
/// modal route), which eliminates all Navigator-pop race conditions.
/// Auto-advances to the next level after a countdown ([GameScreenConstants]).
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

  int _totalNodes = 0;
  int _removedNodes = 0;

  int _livesRemaining = GameScreenConstants.maxLives;
  bool _hasWon = false;
  late final Stopwatch _stopwatch;
  int _earnedStars = 0;

  int? _timeLeftSec;
  int? _timeLimitSec;
  Timer? _countdownTimer;

  int _autoAdvanceSec = GameScreenConstants.winAutoAdvanceSeconds;
  Timer? _autoAdvanceDelayTimer;
  Timer? _autoAdvanceTimer;

  Timer? _ghostHintTimer;

  Timer? _easyHudTimer;

  bool _isPaused = false;

  late LevelData _levelData;

  late GameSettings _settings;
  late final GameAudioController _audio;

  final GlobalKey _headerHudKey = GlobalKey();
  final GlobalKey _footerHudKey = GlobalKey();
  bool _playfieldInsetFrameScheduled = false;

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch()..start();
    _settings = StorageService.gameSettings;
    _audio = GameAudioController();

    _levelData = LevelManager.getLevel(widget.level, mode: widget.difficulty);
    _totalNodes = _levelData.nodes.length;

    _timeLimitSec = computeGameTimeLimit(
      widget.difficulty,
      _totalNodes,
      widget.level,
    );
    _timeLeftSec = _timeLimitSec;

    _buildGame();
    _startCountdown();
    _resetGhostHintTimer();
    _startEasyHudTimer();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _autoAdvanceDelayTimer?.cancel();
    _autoAdvanceTimer?.cancel();
    _ghostHintTimer?.cancel();
    _easyHudTimer?.cancel();
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

  void _buildGame() {
    _game = ChainPopGame(
      levelId: widget.level,
      difficulty: widget.difficulty,
      onWin: _handleWin,
      onJam: _handleFoul,
      onNodeRemoved: _handleNodeRemoved,
      preloadedLevel: _levelData,
    );
    _pushFeedbackToGame();
  }

  void _schedulePlayfieldInsetSync() {
    if (_playfieldInsetFrameScheduled) return;
    _playfieldInsetFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playfieldInsetFrameScheduled = false;
      if (!mounted) return;
      _syncPlayfieldInsetsFromHud();
    });
  }

  /// Maps Flutter HUD geometry to [ChainPopGame] top/bottom reserves (logical px).
  void _syncPlayfieldInsetsFromHud() {
    final mq = MediaQuery.of(context);
    final h = mq.size.height;

    double topReserved = mq.padding.top + 128;
    final headerBox =
        _headerHudKey.currentContext?.findRenderObject() as RenderBox?;
    if (headerBox != null && headerBox.hasSize) {
      final headerBottom =
          headerBox.localToGlobal(Offset(0, headerBox.size.height)).dy;
      topReserved = headerBottom + 20;
    }

    double bottomReserved = mq.padding.bottom + 88;
    if (!_hasWon) {
      final footerBox =
          _footerHudKey.currentContext?.findRenderObject() as RenderBox?;
      if (footerBox != null && footerBox.hasSize) {
        final footerTop = footerBox.localToGlobal(Offset.zero).dy;
        bottomReserved = (h - footerTop) + 16;
      }
    }

    topReserved = topReserved.clamp(96.0, h * 0.55);
    bottomReserved = bottomReserved.clamp(64.0, h * 0.5);

    _game.configurePlayfieldInsets(top: topReserved, bottom: bottomReserved);
  }

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
      builder: (_) => GameOverDialog(
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

    final earned = widget.difficulty.starsForJams(
      GameScreenConstants.maxLives - _livesRemaining,
    );
    await StorageService.saveStars(widget.difficulty, widget.level, earned);
    await StorageService.unlockLevel(widget.difficulty, widget.level + 1);

    if (!mounted) return;
    setState(() {
      _hasWon = true;
      _earnedStars = earned;
      _autoAdvanceSec = GameScreenConstants.winAutoAdvanceSeconds;
    });

    _autoAdvanceDelayTimer?.cancel();
    _autoAdvanceTimer?.cancel();
    _autoAdvanceDelayTimer = Timer(
      Duration(milliseconds: GameScreenConstants.winAutoAdvanceDelayMs),
      () {
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
      },
    );
  }

  void _handleTimeUp() {
    _countdownTimer?.cancel();
    _ghostHintTimer?.cancel();
    if (_hasWon || !mounted) return;

    _game.playSfx(GameSfx.gameOver);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => TimeUpDialog(
        difficulty: widget.difficulty,
        onRetry: () {
          Navigator.of(context).pop();
          _resetForRetry();
        },
        onMenu: () => Navigator.of(context).popUntil((r) => r.isFirst),
      ),
    );
  }

  void _handleUndo() {
    if (_isPaused) return;
    if (_game.undo()) {
      _game.playSfx(GameSfx.uiTap);
      _resetGhostHintTimer();
      setState(() {});
    }
  }

  void _resetForRetry() {
    _autoAdvanceDelayTimer?.cancel();
    _autoAdvanceTimer?.cancel();
    _countdownTimer?.cancel();
    _ghostHintTimer?.cancel();
    _easyHudTimer?.cancel();
    setState(() {
      _isPaused = false;
      _livesRemaining = GameScreenConstants.maxLives;
      _hasWon = false;
      _removedNodes = 0;
      _earnedStars = 0;
      _timeLeftSec = _timeLimitSec;
      _autoAdvanceSec = GameScreenConstants.winAutoAdvanceSeconds;
      _stopwatch
        ..reset()
        ..start();
    });
    _game.resumeEngine();
    _game.restart();
    _game.playSfx(GameSfx.restart);
    _startCountdown();
    _resetGhostHintTimer();
    _startEasyHudTimer();
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

  void _startCountdown() {
    if (_timeLimitSec == null) return;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _hasWon || _isPaused) return;
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

  void _startEasyHudTimer() {
    _easyHudTimer?.cancel();
    if (widget.difficulty != DifficultyMode.easy) return;
    _easyHudTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _isPaused || _hasWon) return;
      setState(() {});
    });
  }

  void _togglePause() {
    if (_hasWon || _game.isGameOver) return;
    _game.playSfx(GameSfx.uiTap);
    if (_isPaused) {
      setState(() => _isPaused = false);
      _game.resumeEngine();
      if (!_stopwatch.isRunning) _stopwatch.start();
      _startCountdown();
      _resetGhostHintTimer();
      _startEasyHudTimer();
    } else {
      setState(() => _isPaused = true);
      _game.pauseEngine();
      _stopwatch.stop();
      _countdownTimer?.cancel();
      _ghostHintTimer?.cancel();
      _easyHudTimer?.cancel();
    }
  }

  void _restartFromPause() {
    _game.playSfx(GameSfx.uiTap);
    _resetForRetry();
  }

  void _menuFromPause() {
    _game.playSfx(GameSfx.uiTap);
    setState(() => _isPaused = false);
    _game.resumeEngine();
    _goMenu();
  }

  void _resetGhostHintTimer() {
    if (widget.difficulty != DifficultyMode.easy) return;
    _ghostHintTimer?.cancel();
    _ghostHintTimer = Timer(
      Duration(seconds: GameScreenConstants.ghostHintDelaySeconds),
      () {
        if (!_hasWon && mounted) _game.showHint();
      },
    );
  }

  Future<void> _openSettings() async {
    if (_isPaused) return;
    _game.playSfx(GameSfx.uiTap);
    if (!mounted) return;
    final accent = widget.difficulty.color;
    await showGameSettingsSheet(
      context: context,
      accent: accent,
      settings: _settings,
      onSettingsChanged: (next) async {
        setState(() => _settings = next);
        _pushFeedbackToGame();
        await StorageService.saveGameSettings(_settings);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _schedulePlayfieldInsetSync();
    final accent = widget.difficulty.color;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
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
          Positioned.fill(child: GameWidget(game: _game)),
          GameHeaderHud(
            measureKey: _headerHudKey,
            onBack: _goMenu,
            onOpenSettings: _openSettings,
            livesRemaining: _livesRemaining,
            difficulty: widget.difficulty,
            removedNodes: _removedNodes,
            totalNodes: _totalNodes,
            timeLeftSec: _timeLeftSec,
            timeLimitSec: _timeLimitSec,
            elapsed: _stopwatch.elapsed,
            onTogglePause: _togglePause,
          ),
          if (!_hasWon)
            GameBottomToolbar(
              measureKey: _footerHudKey,
              accent: accent,
              axisGuidesVisible: _game.axisGuidesVisible,
              canUndo: _game.canUndo,
              onHint: () {
                if (_isPaused) return;
                _game.showHint();
                _resetGhostHintTimer();
              },
              onToggleGuides: () {
                if (_isPaused) return;
                _game.toggleAxisGuides();
                setState(() {});
              },
              onResetView: () {
                if (_isPaused) return;
                _game.resetView();
              },
              onUndo: _handleUndo,
              onRestart: _resetForRetry,
            ),
          if (_isPaused && !_hasWon)
            GamePauseOverlay(
              difficulty: widget.difficulty,
              timeLeftSec: _timeLeftSec,
              timeLimitSec: _timeLimitSec,
              elapsed: _stopwatch.elapsed,
              onMenuFromPause: _menuFromPause,
              onTogglePause: _togglePause,
              onRestartFromPause: _restartFromPause,
            ),
          AnimatedSlide(
            offset: _hasWon ? Offset.zero : const Offset(0, 1),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutQuart,
            child: AnimatedOpacity(
              opacity: _hasWon ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: WinPanel(
                  levelId: widget.level,
                  difficulty: widget.difficulty,
                  stars: _earnedStars,
                  foulCount: GameScreenConstants.maxLives - _livesRemaining,
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
