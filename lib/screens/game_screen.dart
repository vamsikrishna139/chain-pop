library;

import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../game/chain_pop_game.dart';
import '../game/daily_challenge.dart';
import '../game/difficulty_exports.dart';
import '../game/levels/level.dart';
import '../game/levels/level_manager.dart';
import '../game/levels/tutorial_levels.dart';
import '../models/game_settings.dart';
import '../services/ads/ad_placements.dart';
import '../services/ads/ad_service.dart';
import '../services/ads/ads_locator.dart';
import '../services/crash_reporting.dart';
import '../services/ads/campaign_between_levels_ads.dart';
import '../services/ads/campaign_interstitial_frustration_gate.dart';
import '../services/ads/hint_ad_policy.dart';
import '../services/ads/undo_ad_policy.dart';
import '../services/game_audio.dart';
import '../services/game_sfx.dart';
import '../services/session_campaign_streak.dart';
import '../services/storage/chain_pop_progress_store.dart';
import '../services/storage/chain_pop_storage.dart';
import '../services/storage/storage_locator.dart';
import '../theme/app_colors.dart';
import 'game/game_screen_constants.dart';
import 'game/game_screen_timer_coordinator.dart';
import 'game/game_time_limit.dart';
import 'game/widgets/game_bottom_toolbar.dart';
import 'game/widgets/game_dialogs.dart';
import 'game/widgets/game_header_hud.dart';
import 'game/widgets/game_pause_overlay.dart';
import 'game/widgets/game_settings_sheet.dart';
import 'game/widgets/win_celebration_overlay.dart';
import 'game/widgets/win_panel.dart';

part 'game/game_playfield_sync.dart';
part 'game/game_timer_controller.dart';
part 'game/game_ad_coordination.dart';
part 'game/game_flow_controller.dart';

/// Full-screen game view for a single level.
///
/// **Lifetime ad engagement:** [ChainPopProgressStore.accumulateLifetimeGameplaySeconds] is fed
/// via delta flushes from [GameFlowController.flushLifetimeGameplayDelta] (pause, app
/// background, win, lifecycle) so OS kills only lose at most a tiny window — not an
/// entire level.
///
/// Win overlay is rendered **inside this screen's own Stack** (not as a
/// modal route), which eliminates all Navigator-pop race conditions.
/// Auto-advances to the next level after a countdown ([GameScreenConstants]),
/// except for [isDailyChallenge] runs (no auto-next; stars go to
/// [ChainPopProgressStore.saveDailyStars]) and the last step of [isTutorial].
class GameScreen extends StatefulWidget {
  final int level;
  final DifficultyMode difficulty;
  final LevelData? fixedLevel;
  final bool isDailyChallenge;
  final int? dailyDayKey;
  final bool isTutorial;
  final int tutorialIndex;

  /// Overrides [AdsLocator] for tests (`NoOpAdService`).
  final AdService? adService;

  /// Widget tests: avoids `audioplayers` platform channels.
  final GameAudioHandle Function()? audioHandleFactory;

  /// Overrides Hive-backed persistence (deterministic widget/integration tests).
  final ChainPopProgressStore? progressStore;

  /// Overrides session streak tracker ([SessionCampaignStreak] default).
  final CampaignStreakTracker? campaignStreak;

  /// Overrides [StorageLocator] reads/writes for settings and ad-coach flags
  /// (widget tests with a fake [ChainPopStorage]).
  final ChainPopStorage? storage;

  /// Replaces [LevelManager.getLevel] for deferred campaign loads (widget tests,
  /// deterministic fixtures). Omit in production builds.
  final LevelData Function(int level, DifficultyMode mode)?
      campaignLevelBuilder;

  /// When true, skip starting countdown / HUD tick / ghost-hint timers. Used by
  /// automated screenshot and widget tests so the test binding can idle.
  final bool suppressGameplayTimers;

  const GameScreen({
    super.key,
    required this.level,
    required this.difficulty,
    this.fixedLevel,
    this.isDailyChallenge = false,
    this.dailyDayKey,
    this.isTutorial = false,
    this.tutorialIndex = 0,
    this.adService,
    this.audioHandleFactory,
    this.progressStore,
    this.campaignStreak,
    this.storage,
    this.campaignLevelBuilder,
    this.suppressGameplayTimers = false,
  }) : assert(
          !isDailyChallenge || (dailyDayKey != null && fixedLevel != null),
        ),
        assert(!isTutorial || fixedLevel != null),
        assert(!isTutorial || !isDailyChallenge),
        assert(!isTutorial || (tutorialIndex >= 0 && tutorialIndex < 5));

  @override
  State<GameScreen> createState() => GameScreenState();
}

class GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  /// Elapsed gameplay already persisted from this route (prevents duplicate adds).
  Duration _lifetimeGameplaySyncedUpTo = Duration.zero;

  ChainPopGame? _game;

  ChainPopGame get _engine => _game!;

  final GameScreenTimerCoordinator _timers = GameScreenTimerCoordinator();

  int _totalNodes = 0;
  int _removedNodes = 0;

  int _livesRemaining = GameScreenConstants.maxLives;
  bool _hasWon = false;
  late final Stopwatch _stopwatch;
  int _earnedStars = 0;

  int? _timeLeftSec;
  int? _timeLimitSec;

  int _autoAdvanceSec = GameScreenConstants.winAutoAdvanceSeconds;

  bool _isPaused = false;

  LevelData? _levelData;

  late GameSettings _settings;
  late final GameAudioHandle _audio;

  late final ChainPopStorage _gameStorage;

  late final GamePlayfieldInsetController _playfieldInsetController =
      GamePlayfieldInsetController(this);
  late final GameFlowController _gameFlow = GameFlowController(this);
  late final GameAdCoordinator _adCoordinator = GameAdCoordinator(this);
  late final GameTimerController _timerController = GameTimerController(this);

  late final ChainPopProgressStore _progress;


  CampaignStreakTracker get _streak =>
      widget.campaignStreak ?? defaultCampaignStreakTracker;

  bool _needsDeferredCampaignGeneration() =>
      widget.fixedLevel == null &&
      !widget.isDailyChallenge &&
      !widget.isTutorial;

  AdService get _ads => widget.adService ?? AdsLocator.instance;

  final UndoAdPolicy _undoAdPolicy = UndoAdPolicy();
  late final HintAdPolicy _hintAdPolicy;

  bool get _gateHintsWithAds => !widget.isTutorial;

  /// Hard campaign + daily (non-tutorial): rewarded continue after lives/time out; hints are rewarded-first (no free hint budget).
  bool get _hardOrDailyFeatures =>
      !widget.isTutorial &&
      (widget.isDailyChallenge || widget.difficulty == DifficultyMode.hard);

  /// Rewarded “continue” after lives or time run out: **hard campaign** and **daily challenge** (not tutorial; easy/medium campaign has no offer).
  bool get _offerRewardedContinue => _hardOrDailyFeatures;

  final GlobalKey _headerHudKey = GlobalKey();
  final GlobalKey _footerHudKey = GlobalKey();
  final GlobalKey _bodyStackKey = GlobalKey();
  bool _playfieldInsetFrameScheduled = false;

  /// Suppresses concurrent [GameFlowController.goNextLevel] (timer + Next tap, or rapid taps).
  bool _goingNext = false;

  /// Stack-local Y for tutorial hint banner (below measured [GameHeaderHud]).
  double _tutorialHintTop = 118;

  /// Controllers declared in `part` files rebuild through this helper because
  /// [setState] is protected outside [State] subclasses.
  void patchState(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    _hintAdPolicy = HintAdPolicy(
      freeBudget: _hardOrDailyFeatures ? 0 : 2,
    );
    WidgetsBinding.instance.addObserver(this);

    _gameStorage = widget.storage ?? StorageLocator.instance;
    _progress = widget.progressStore ??
        HiveChainPopProgressStore(widget.storage);

    _stopwatch = Stopwatch();
    _settings = _gameStorage.gameSettings;
    _audio = widget.audioHandleFactory?.call() ?? GameAudioController();

    if (_needsDeferredCampaignGeneration()) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await Future<void>.delayed(Duration.zero);
        if (!mounted) return;
        try {
          final level = widget.campaignLevelBuilder?.call(
                widget.level,
                widget.difficulty,
              ) ??
              LevelManager.getLevel(widget.level, mode: widget.difficulty);
          if (!mounted) return;
          _installResolvedLevel(level);
        } catch (e, st) {
          recordNonFatal(e, st);
          if (!mounted) return;
          _installResolvedLevel(
            LevelManager.emergencyFallbackLevel(widget.level),
          );
        }
      });
    } else {
      final LevelData initial;
      if (widget.isDailyChallenge) {
        initial = widget.fixedLevel!;
      } else if (widget.isTutorial) {
        initial = widget.fixedLevel!;
      } else {
        initial = widget.fixedLevel ??
            LevelManager.getLevel(widget.level, mode: widget.difficulty);
      }
      _installResolvedLevel(initial);
    }
  }

  void _installResolvedLevel(LevelData level) {
    _levelData = level;
    _totalNodes = level.nodes.length;
    if (widget.isDailyChallenge) {
      _timeLimitSec = computeDailyChallengeTimeLimit(_totalNodes);
    } else if (widget.isTutorial) {
      _timeLimitSec = computeTutorialCountdownSec(widget.tutorialIndex);
    } else {
      _timeLimitSec = computeGameTimeLimit(
        widget.difficulty,
        _totalNodes,
        widget.level,
      );
    }
    _timeLeftSec = _timeLimitSec;

    if (!_stopwatch.isRunning) _stopwatch.start();

    _buildGame();
    if (!widget.suppressGameplayTimers) {
      _timerController.startCountdown();
      _timerController.resetGhostHintTimer();
      _timerController.startEasyHudTimer();
    }
    unawaited(_audio.startAmbientIfEnabled(_settings.soundEnabled));

    _adCoordinator.preloadForLevelStartup();
    _adCoordinator.scheduleRewardedHintsEntryCoachIfNeeded();

    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _goingNext = false;
    _gameFlow.flushLifetimeGameplayDelta(clearTrackedAfter: true);
    _timers.disposeAll();
    unawaited(_audio.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _gameFlow.flushLifetimeGameplayDelta();
      case AppLifecycleState.resumed:
        break;
    }
  }

  void _pushFeedbackToGame() {
    final g = _game;
    if (g == null) return;
    g.soundEnabled = _settings.soundEnabled;
    g.hapticsEnabled = _settings.hapticsEnabled;
    g.colorblindPalette = _settings.colorblindFriendly;
    g.onSfx = (sfx, {double playbackRate = 1.0}) =>
        unawaited(_audio.play(sfx, playbackRate: playbackRate));
  }

  void _buildGame() {
    _game = ChainPopGame(
      levelId: widget.isDailyChallenge
          ? widget.dailyDayKey!
          : (widget.isTutorial ? widget.tutorialIndex : widget.level),
      difficulty: widget.difficulty,
      onWin: () => unawaited(_gameFlow.handleWin()),
      onJam: _handleFoul,
      onNodeRemoved: _handleNodeRemoved,
      preloadedLevel: _levelData!,
    );
    _pushFeedbackToGame();
  }

  void _handleFoul() {
    if (_hasWon) return;
    setState(() => _livesRemaining--);
    _timerController.resetGhostHintTimer();
    if (_livesRemaining <= 0) {
      _adCoordinator.handleGameOver();
    }
  }

  void _handleNodeRemoved(int removed, int total) {
    if (!mounted) return;
    setState(() {
      _removedNodes = removed;
      _totalNodes = total;
    });
    _timerController.resetGhostHintTimer();
  }

  /// Invokes the same path as the win rail **Next** control (for automated tests).
  @visibleForTesting
  Future<void> debugGoNextLevelForTest() => _gameFlow.goNextLevel();

  /// Drives the win overlay without clearing the board (for automated tests).
  @visibleForTesting
  Future<void> debugSimulateWinForTest() => _gameFlow.handleWin();

  void _togglePause() {
    if (_hasWon || _engine.isGameOver) return;
    _engine.playSfx(GameSfx.uiTap);
    if (_isPaused) {
      setState(() => _isPaused = false);
      _engine.resumeEngine();
      if (!_stopwatch.isRunning) _stopwatch.start();
      unawaited(
        _audio.setAmbientGameplayPaused(false, _settings.soundEnabled),
      );
      if (!widget.suppressGameplayTimers) {
        _timerController.startCountdown();
        _timerController.resetGhostHintTimer();
        _timerController.startEasyHudTimer();
      }
    } else {
      _engine.pauseEngine();
      _stopwatch.stop();
      _gameFlow.flushLifetimeGameplayDelta();
      setState(() => _isPaused = true);
      unawaited(
        _audio.setAmbientGameplayPaused(true, _settings.soundEnabled),
      );
      _timers.countdownTimer?.cancel();
      _timers.ghostHintTimer?.cancel();
      _timers.easyHudTimer?.cancel();
    }
  }

  void _restartFromPause() {
    _engine.playSfx(GameSfx.uiTap);
    _gameFlow.resetForRetry();
  }

  void _menuFromPause() {
    _engine.playSfx(GameSfx.uiTap);
    setState(() => _isPaused = false);
    _engine.resumeEngine();
    _gameFlow.goMenu();
  }

  Future<void> _openSettings() async {
    if (_isPaused) return;
    _engine.playSfx(GameSfx.uiTap);
    if (!mounted) return;
    final accent = widget.difficulty.color;
    await showGameSettingsSheet(
      context: context,
      accent: accent,
      settings: _settings,
      onSettingsChanged: (next) async {
        setState(() => _settings = next);
        _pushFeedbackToGame();
        await _audio.setAmbientEnabled(_settings.soundEnabled);
        await _gameStorage.saveGameSettings(_settings);
      },
    );
  }

  String _tutorialHintText() {
    switch (widget.tutorialIndex) {
      case 0:
        return 'Tap the glowing arrow and clear the board before the countdown reaches zero. '
            'Pinch or tap Zoom in for a closer look; Reset zoom snaps back to the full board.';
      case 1:
        return 'Arrows block each other—clear a free exit first and watch the countdown. '
            'Tap the grid button for alignment lines along shared rows and columns.';
      case 2:
        return 'Chain good pops in a safe order. The timer only counts down; pops do not add time.';
      case 3:
        return 'Bigger board: plan clears and watch the countdown—zoom or alignment lines help scan paths.';
      default:
        return 'Final recap: 8 arrows—clear everything before the 45s countdown hits zero. '
            'Pinch out or Reset zoom if you need the full board again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.difficulty.color;
    final ready = _game != null && _levelData != null;
    if (!ready) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Semantics(
            label: 'Generating puzzle layout',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: accent),
                const SizedBox(height: 16),
                Text(
                  'Building level…',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    _playfieldInsetController.scheduleSync();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        key: _bodyStackKey,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.0,
                  colors: [accent.withValues(alpha: 0.05), Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned.fill(child: GameWidget(game: _game!)),
          if (_hasWon)
            Positioned.fill(
              child: IgnorePointer(
                child: WinCelebrationOverlay(accent: accent),
              ),
            ),
          GameHeaderHud(
            measureKey: _headerHudKey,
            onBack: _gameFlow.goMenu,
            onOpenSettings: _openSettings,
            livesRemaining: _livesRemaining,
            difficulty: widget.difficulty,
            headerModeLabel: widget.isDailyChallenge
                ? 'DAILY CHALLENGE'
                : (widget.isTutorial
                    ? 'TUTORIAL ${widget.tutorialIndex + 1}/5'
                    : null),
            removedNodes: _removedNodes,
            totalNodes: _totalNodes,
            timeLeftSec: _timeLeftSec,
            timeLimitSec: _timeLimitSec,
            elapsed: _stopwatch.elapsed,
            onTogglePause: _togglePause,
          ),
          if (widget.isTutorial && !_hasWon)
            Positioned(
              top: _tutorialHintTop,
              left: 12,
              right: 12,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _isPaused ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 220),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.55),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        _tutorialHintText(),
                        textAlign: TextAlign.center,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (!_hasWon)
            GameBottomToolbar(
              measureKey: _footerHudKey,
              accent: accent,
              showHintAdBadge: _hardOrDailyFeatures,
              axisGuidesVisible: _engine.axisGuidesVisible,
              canUndo: _engine.canUndo,
              onHint: () => unawaited(_adCoordinator.handleHint()),
              onToggleGuides: () {
                if (_isPaused) return;
                _engine.toggleAxisGuides();
                setState(() {});
              },
              onZoomIn: widget.isTutorial
                  ? () {
                      if (_isPaused) return;
                      _engine.zoomInStep();
                    }
                  : null,
              onResetView: () {
                if (_isPaused) return;
                _engine.resetView();
              },
              onUndo: () => unawaited(_adCoordinator.handleUndo()),
              onRestart: _gameFlow.resetForRetry,
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
              pauseBanner: widget.isTutorial
                  ? const SizedBox.shrink()
                  : _ads.buildGamePauseBanner(context),
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
                  levelId: widget.isDailyChallenge
                      ? widget.dailyDayKey!
                      : widget.level,
                  difficulty: widget.difficulty,
                  stars: _earnedStars,
                  foulCount: GameScreenConstants.maxLives - _livesRemaining,
                  timeTaken: _stopwatch.elapsed,
                  autoAdvanceSec: _autoAdvanceSec,
                  onMenu: _gameFlow.goMenu,
                  onRetry: _gameFlow.resetForRetry,
                  onNext: () => unawaited(_gameFlow.goNextLevel()),
                  showNextAndAutoAdvance: !widget.isDailyChallenge &&
                      (!widget.isTutorial || widget.tutorialIndex < 4),
                  titleLine: widget.isDailyChallenge
                      ? 'DAILY CHALLENGE · ${DailyChallenge.compactDateLabelFromKey(widget.dailyDayKey!)}'
                      : (widget.isTutorial
                          ? 'TUTORIAL · STEP ${widget.tutorialIndex + 1} / 5'
                          : null),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
