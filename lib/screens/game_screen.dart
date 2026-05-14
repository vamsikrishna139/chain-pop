import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../game/chain_pop_game.dart';
import '../game/daily_challenge.dart';
import '../game/levels/generation/difficulty_mode.dart';
import '../game/levels/level.dart';
import '../game/levels/level_manager.dart';
import '../game/levels/tutorial_levels.dart';
import '../models/difficulty.dart';
import '../models/game_settings.dart';
import '../services/ads/ad_placements.dart';
import '../services/ads/campaign_between_levels_ads.dart';
import '../services/ads/campaign_interstitial_frustration_gate.dart';
import '../services/ads/ads_locator.dart';
import '../services/ads/ad_service.dart';
import '../services/ads/hint_ad_policy.dart';
import '../services/ads/undo_ad_policy.dart';
import '../services/game_audio.dart';
import '../services/game_sfx.dart';
import '../services/session_campaign_streak.dart';
import '../services/storage_service.dart';
import '../theme/app_colors.dart';
import 'game/game_screen_constants.dart';
import 'game/game_time_limit.dart';
import 'game/widgets/game_bottom_toolbar.dart';
import 'game/widgets/game_dialogs.dart';
import 'game/widgets/game_header_hud.dart';
import 'game/widgets/game_pause_overlay.dart';
import 'game/widgets/game_settings_sheet.dart';
import 'game/widgets/win_celebration_overlay.dart';
import 'game/widgets/win_panel.dart';

/// Full-screen game view for a single level.
///
/// **Lifetime ad engagement:** [StorageService.accumulateLifetimeGameplaySeconds] is fed
/// via delta flushes from [_flushLifetimeGameplayDelta] (pause, app background, win,
/// lifecycle) so OS kills only lose at most a tiny window — not an entire level.
///
/// Win overlay is rendered **inside this screen's own Stack** (not as a
/// modal route), which eliminates all Navigator-pop race conditions.
/// Auto-advances to the next level after a countdown ([GameScreenConstants]),
/// except for [isDailyChallenge] runs (no auto-next; stars go to
/// [StorageService.saveDailyStars]) and the last step of [isTutorial].
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
  Timer? _tutorialExitTimer;

  bool _isPaused = false;

  late LevelData _levelData;

  late GameSettings _settings;
  late final GameAudioHandle _audio;

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

  /// Suppresses concurrent [_goNextLevel] (timer + Next tap, or rapid taps).
  bool _goingNext = false;

  /// Stack-local Y for tutorial hint banner (below measured [GameHeaderHud]).
  double _tutorialHintTop = 118;

  @override
  void initState() {
    super.initState();
    _hintAdPolicy = HintAdPolicy(
      freeBudget: _hardOrDailyFeatures ? 0 : 2,
    );
    WidgetsBinding.instance.addObserver(this);

    _stopwatch = Stopwatch()..start();
    _settings = StorageService.gameSettings;
    _audio = widget.audioHandleFactory?.call() ?? GameAudioController();

    if (widget.isDailyChallenge) {
      _levelData = widget.fixedLevel!;
      _totalNodes = _levelData.nodes.length;
      _timeLimitSec = computeDailyChallengeTimeLimit(_totalNodes);
    } else if (widget.isTutorial) {
      _levelData = widget.fixedLevel!;
      _totalNodes = _levelData.nodes.length;
      _timeLimitSec = computeTutorialCountdownSec(widget.tutorialIndex);
    } else {
      _levelData = widget.fixedLevel ??
          LevelManager.getLevel(widget.level, mode: widget.difficulty);
      _totalNodes = _levelData.nodes.length;
      _timeLimitSec = computeGameTimeLimit(
        widget.difficulty,
        _totalNodes,
        widget.level,
      );
    }
    _timeLeftSec = _timeLimitSec;

    _buildGame();
    _startCountdown();
    _resetGhostHintTimer();
    _startEasyHudTimer();
    unawaited(_audio.startAmbientIfEnabled(_settings.soundEnabled));

    if (_offerRewardedContinue) {
      unawaited(_ads.preloadRewarded(AdPlacements.continueAfterLives));
    }
    if (!widget.isTutorial) {
      unawaited(_ads.preloadRewarded(AdPlacements.hint));
    }
    if (!widget.isTutorial) {
      unawaited(_ads.preloadRewarded(AdPlacements.undo));
    }
    if (!widget.isDailyChallenge && !widget.isTutorial) {
      unawaited(_ads.preloadInterstitial());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _goingNext = false;
    _flushLifetimeGameplayDelta(clearTrackedAfter: true);
    _countdownTimer?.cancel();
    _cancelWinAdvanceTimers();
    _ghostHintTimer?.cancel();
    _easyHudTimer?.cancel();
    _tutorialExitTimer?.cancel();
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
        _flushLifetimeGameplayDelta();
      case AppLifecycleState.resumed:
        break;
    }
  }

  void _flushLifetimeGameplayDelta({bool clearTrackedAfter = false}) {
    if (widget.isTutorial) return;
    final elapsed = _stopwatch.elapsed;
    final delta = elapsed - _lifetimeGameplaySyncedUpTo;
    final secs = delta.inSeconds.clamp(0, 8 * 3600);
    if (secs <= 0) {
      if (clearTrackedAfter) _lifetimeGameplaySyncedUpTo = Duration.zero;
      return;
    }
    unawaited(StorageService.accumulateLifetimeGameplaySeconds(secs));
    _lifetimeGameplaySyncedUpTo =
        clearTrackedAfter ? Duration.zero : elapsed;
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
      levelId: widget.isDailyChallenge
          ? widget.dailyDayKey!
          : (widget.isTutorial ? widget.tutorialIndex : widget.level),
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
    final stackBox =
        _bodyStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (headerBox != null && headerBox.hasSize) {
      final headerBottom =
          headerBox.localToGlobal(Offset(0, headerBox.size.height)).dy;
      topReserved = headerBottom + 20;

      if (widget.isTutorial &&
          stackBox != null &&
          stackBox.hasSize) {
        final hintTop = stackBox
            .globalToLocal(
              headerBox.localToGlobal(Offset(0, headerBox.size.height)),
            )
            .dy;
        final next = (hintTop + 8).clamp(72.0, h * 0.4);
        if ((_tutorialHintTop - next).abs() > 0.5) {
          setState(() => _tutorialHintTop = next);
        }
      }
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
    if (!widget.isTutorial && !widget.isDailyChallenge) {
      CampaignInterstitialFrustrationGate.noteFailedRunEnded();
    }

    final offer = _offerRewardedContinue;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => GameOverDialog(
        difficulty: widget.difficulty,
        showRewardedContinue: offer,
        rewardedAdReady:
            offer && _ads.isRewardedReady(AdPlacements.continueAfterLives),
        onWatchAdContinue: !offer
            ? null
            : () async {
                final ok = await _ads.showRewarded(
                  placement: AdPlacements.continueAfterLives,
                );
                if (!dialogContext.mounted || !mounted || !ok) return;
                Navigator.of(dialogContext).pop();
                _resumeAfterRewardedContinueFromLives();
              },
        onRetry: () {
          Navigator.of(context).pop();
          _resetForRetry();
        },
        onMenu: _goMenu,
      ),
    );
  }

  void _resumeAfterRewardedContinueFromLives() {
    setState(() {
      _livesRemaining = 1;
    });
    _game.isGameOver = false;
    _game.resumeEngine();
    _startCountdown();
    unawaited(_ads.preloadRewarded(AdPlacements.continueAfterLives));
  }

  void _handleNodeRemoved(int removed, int total) {
    if (!mounted) return;
    setState(() {
      _removedNodes = removed;
      _totalNodes = total;
    });
    _resetGhostHintTimer();
  }

  /// Invokes the same path as the win rail **Next** control (for automated tests).
  @visibleForTesting
  Future<void> debugGoNextLevelForTest() => _goNextLevel();

  /// Drives the win overlay without clearing the board (for automated tests).
  @visibleForTesting
  Future<void> debugSimulateWinForTest() => _handleWin();

  Future<void> _handleWin() async {
    _flushLifetimeGameplayDelta();
    _stopwatch.stop();
    _countdownTimer?.cancel();
    _ghostHintTimer?.cancel();
    _game.playSfx(GameSfx.win);

    final earned = widget.difficulty.starsForJams(
      GameScreenConstants.maxLives - _livesRemaining,
    );
    if (widget.isTutorial) {
      if (widget.tutorialIndex == 4) {
        await StorageService.setTutorialCompleted(true);
      }
    } else if (widget.isDailyChallenge) {
      await StorageService.saveDailyStars(widget.dailyDayKey!, earned);
    } else {
      SessionCampaignStreak.onWin();
      await StorageService.incrementLifetimeCampaignClears();
      CampaignInterstitialFrustrationGate.noteCampaignWin();
      await StorageService.saveStars(widget.difficulty, widget.level, earned);
      await StorageService.unlockLevel(widget.difficulty, widget.level + 1);
    }

    if (!mounted) return;
    setState(() {
      _hasWon = true;
      _earnedStars = earned;
      _autoAdvanceSec = GameScreenConstants.winAutoAdvanceSeconds;
    });

    if (widget.isDailyChallenge) {
      return;
    }

    if (widget.isTutorial && widget.tutorialIndex == 4) {
      _tutorialExitTimer?.cancel();
      _tutorialExitTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) _goMenu();
      });
      return;
    }

    _autoAdvanceDelayTimer?.cancel();
    _autoAdvanceTimer?.cancel();
    _autoAdvanceDelayTimer = Timer(
      const Duration(milliseconds: GameScreenConstants.winAutoAdvanceDelayMs),
      () {
        if (!mounted || !_hasWon || _goingNext) return;
        _autoAdvanceTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted || !_hasWon || _goingNext) {
            t.cancel();
            return;
          }
          setState(() => _autoAdvanceSec--);
          if (_autoAdvanceSec <= 0) {
            t.cancel();
            unawaited(_goNextLevel());
          }
        });
      },
    );
  }

  void _handleTimeUp() {
    _countdownTimer?.cancel();
    _ghostHintTimer?.cancel();
    if (_hasWon || !mounted) return;

    _game.isGameOver = true;
    _game.playSfx(GameSfx.gameOver);
    if (!widget.isTutorial && !widget.isDailyChallenge) {
      CampaignInterstitialFrustrationGate.noteFailedRunEnded();
    }
    final offer = _offerRewardedContinue;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => TimeUpDialog(
        difficulty: widget.difficulty,
        showRewardedContinue: offer,
        rewardedAdReady:
            offer && _ads.isRewardedReady(AdPlacements.continueAfterLives),
        onWatchAdContinue: !offer
            ? null
            : () async {
                final ok = await _ads.showRewarded(
                  placement: AdPlacements.continueAfterLives,
                );
                if (!dialogContext.mounted || !mounted || !ok) return;
                Navigator.of(dialogContext).pop();
                _resumeAfterRewardedContinueFromTimeUp();
              },
        onRetry: () {
          Navigator.of(context).pop();
          _resetForRetry();
        },
        onMenu: _goMenu,
      ),
    );
  }

  void _resumeAfterRewardedContinueFromTimeUp() {
    _game.isGameOver = false;
    _game.resumeEngine();
    final lim = _timeLimitSec;
    if (lim != null) {
      final bonus = (lim * 0.35).round().clamp(15, lim);
      setState(() {
        _timeLeftSec = bonus;
      });
    }
    _startCountdown();
    unawaited(_ads.preloadRewarded(AdPlacements.continueAfterLives));
  }

  Future<void> _handleUndo() async {
    if (_isPaused) return;
    final needsAd = _undoAdPolicy.needsRewardedForNextUndo();
    if (needsAd) {
      final cooldown = _undoAdPolicy.remainingCooldownIfBlocked();
      if (cooldown != null) {
        final secs = cooldown.inSeconds.clamp(1, 9999);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('Undo via ad unlocks in ${secs}s')),
        );
        _game.playSfx(GameSfx.uiTap);
        return;
      }
      if (!_ads.isRewardedReady(AdPlacements.undo)) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Ad loading… try again in a moment')),
        );
        _game.playSfx(GameSfx.uiTap);
        return;
      }
      final ok = await _ads.showRewarded(placement: AdPlacements.undo);
      if (!mounted || !ok) return;
      if (!_game.undo()) return;
      _undoAdPolicy.recordRewardedUndo();
      _game.playSfx(GameSfx.uiTap);
      _resetGhostHintTimer();
      setState(() {});
      unawaited(_ads.preloadRewarded(AdPlacements.undo));
      return;
    }

    if (_game.undo()) {
      _undoAdPolicy.recordFreeUndo();
      _game.playSfx(GameSfx.uiTap);
      _resetGhostHintTimer();
      setState(() {});
    }
  }

  Future<void> _handleHint() async {
    if (_isPaused) return;
    if (!_game.hasAvailableHint()) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('No hint available right now.')),
      );
      _game.playSfx(GameSfx.uiTap);
      return;
    }

    if (!_gateHintsWithAds) {
      _game.showHint();
      _resetGhostHintTimer();
      return;
    }

    final needsAd = _hintAdPolicy.needsRewardedForNextHint();
    if (needsAd) {
      final cooldown = _hintAdPolicy.remainingCooldownIfBlocked();
      if (cooldown != null) {
        final secs = cooldown.inSeconds.clamp(1, 9999);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('Hint via ad unlocks in ${secs}s')),
        );
        _game.playSfx(GameSfx.uiTap);
        return;
      }
      if (!_ads.isRewardedReady(AdPlacements.hint)) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Ad loading… try again in a moment')),
        );
        _game.playSfx(GameSfx.uiTap);
        return;
      }
      final ok = await _ads.showRewarded(placement: AdPlacements.hint);
      if (!mounted || !ok) return;
      if (!_game.showHint()) return;
      _hintAdPolicy.recordRewardedHint();
      _resetGhostHintTimer();
      setState(() {});
      unawaited(_ads.preloadRewarded(AdPlacements.hint));
      return;
    }

    if (!_game.showHint()) return;
    _hintAdPolicy.recordFreeHint();
    _resetGhostHintTimer();
    setState(() {});
  }

  void _resetForRetry() {
    _flushLifetimeGameplayDelta();
    _lifetimeGameplaySyncedUpTo = Duration.zero;
    _tutorialExitTimer?.cancel();
    _cancelWinAdvanceTimers();
    _goingNext = false;
    _countdownTimer?.cancel();
    _ghostHintTimer?.cancel();
    _easyHudTimer?.cancel();
    _undoAdPolicy.resetForNewAttempt();
    _hintAdPolicy.resetForNewAttempt();
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
    unawaited(
      _audio.setAmbientGameplayPaused(false, _settings.soundEnabled),
    );
    _game.restart();
    _game.playSfx(GameSfx.restart);
    _startCountdown();
    _resetGhostHintTimer();
    _startEasyHudTimer();
  }

  void _cancelWinAdvanceTimers() {
    _autoAdvanceDelayTimer?.cancel();
    _autoAdvanceDelayTimer = null;
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = null;
  }

  Future<void> _goNextLevel() async {
    if (!mounted || widget.isDailyChallenge) return;
    if (_goingNext) return;
    _goingNext = true;
    _cancelWinAdvanceTimers();

    try {
      await CampaignBetweenLevelsAds.maybePresentForCampaignTransition(
        ads: _ads,
        difficulty: widget.difficulty,
        isTutorial: widget.isTutorial,
        isDailyChallenge: widget.isDailyChallenge,
      );

      if (!mounted) return;

      if (widget.isTutorial) {
        final next = widget.tutorialIndex + 1;
        if (next >= tutorialLevels.length) return;
        // Do not await: [Navigator.pushReplacement]'s future completes when this
        // new route is popped, not when the transition finishes (would pin state).
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => GameScreen(
              level: next + 1,
              difficulty: DifficultyMode.easy,
              fixedLevel: tutorialLevels[next],
              isTutorial: true,
              tutorialIndex: next,
              adService: widget.adService,
              audioHandleFactory: widget.audioHandleFactory,
            ),
            transitionsBuilder: (_, anim, __, child) => FadeTransition(
              opacity: anim,
              child: child,
            ),
            transitionDuration: const Duration(milliseconds: 350),
          ),
        );
        return;
      }
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => GameScreen(
            level: widget.level + 1,
            difficulty: widget.difficulty,
            adService: widget.adService,
            audioHandleFactory: widget.audioHandleFactory,
          ),
          transitionsBuilder: (_, anim, __, child) => FadeTransition(
            opacity: anim,
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 350),
        ),
      );
    } finally {
      if (mounted) _goingNext = false;
    }
  }

  void _goMenu() {
    SessionCampaignStreak.reset();
    _tutorialExitTimer?.cancel();
    _cancelWinAdvanceTimers();
    _goingNext = false;
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
    // Elapsed clock only when Easy is **untimed** (no countdown). Timed Easy
    // uses [_countdownTimer] for HUD updates.
    if (_timeLimitSec != null) return;
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
      unawaited(
        _audio.setAmbientGameplayPaused(false, _settings.soundEnabled),
      );
      _startCountdown();
      _resetGhostHintTimer();
      _startEasyHudTimer();
    } else {
      _game.pauseEngine();
      _stopwatch.stop();
      _flushLifetimeGameplayDelta();
      setState(() => _isPaused = true);
      unawaited(
        _audio.setAmbientGameplayPaused(true, _settings.soundEnabled),
      );
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
      const Duration(seconds: GameScreenConstants.ghostHintDelaySeconds),
      () {
        if (_hasWon || !mounted) return;
        if (_gateHintsWithAds && _hintAdPolicy.needsRewardedForNextHint()) {
          return;
        }
        final showed = _game.showHint();
        if (!showed) return;
        if (_gateHintsWithAds) _hintAdPolicy.recordFreeHint();
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
        await _audio.setAmbientEnabled(_settings.soundEnabled);
        await StorageService.saveGameSettings(_settings);
      },
    );
  }

  String _tutorialHintText() {
    switch (widget.tutorialIndex) {
      case 0:
        return 'Tap the glowing arrow. Clear the board before the countdown reaches zero.';
      case 1:
        return 'Arrows block each other. Clear a free exit first—keep an eye on the countdown.';
      case 2:
        return 'Chain good pops in a safe order. The timer only counts down; pops do not add time.';
      case 3:
        return 'Bigger board: plan clears and watch the countdown.';
      default:
        return 'Final recap: 8 arrows. Clear every piece before the 45s countdown hits zero.';
    }
  }

  @override
  Widget build(BuildContext context) {
    _schedulePlayfieldInsetSync();
    final accent = widget.difficulty.color;

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
          Positioned.fill(child: GameWidget(game: _game)),
          if (_hasWon)
            Positioned.fill(
              child: IgnorePointer(
                child: WinCelebrationOverlay(accent: accent),
              ),
            ),
          GameHeaderHud(
            measureKey: _headerHudKey,
            onBack: _goMenu,
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
                        maxLines: 3,
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
              axisGuidesVisible: _game.axisGuidesVisible,
              canUndo: _game.canUndo,
              onHint: () => unawaited(_handleHint()),
              onToggleGuides: () {
                if (_isPaused) return;
                _game.toggleAxisGuides();
                setState(() {});
              },
              onZoomIn: widget.isTutorial
                  ? () {
                      if (_isPaused) return;
                      _game.zoomInStep();
                    }
                  : null,
              onResetView: () {
                if (_isPaused) return;
                _game.resetView();
              },
              onUndo: () => unawaited(_handleUndo()),
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
                  onMenu: _goMenu,
                  onRetry: () =>
                      _resetForRetry(),
                  onNext: () => unawaited(_goNextLevel()),
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
