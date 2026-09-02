import 'package:flutter/material.dart';

import '../../game/chain_pop_game.dart';
import '../../game/difficulty_exports.dart';
import '../../models/game_settings.dart';
import '../../services/ads/ad_service.dart';
import '../../services/ads/hint_ad_policy.dart';
import '../../services/ads/undo_ad_policy.dart';
import '../../services/game_audio.dart';
import '../../services/session_campaign_streak.dart';
import '../../services/session_goals.dart';
import '../../services/session_pacing.dart';
import '../../services/storage/chain_pop_progress_store.dart';
import '../../services/storage/chain_pop_storage.dart';
import 'game_screen_timer_coordinator.dart';

/// Surface exposed to extracted [GameScreen] controllers so they no longer
/// need `part of` access to [GameScreenState] private fields.
abstract class GameScreenControllerHost {
  bool get mounted;
  BuildContext get context;

  // Route / mode (mirrors [GameScreen] widget fields).
  int get level;
  DifficultyMode get difficulty;
  bool get isDailyChallenge;
  int? get dailyDayKey;
  bool get isTutorial;
  int get tutorialIndex;

  Map<String, Object> get analyticsParams;

  AdService? get adServiceOverride;
  GameAudioHandle Function()? get audioHandleFactory;
  ChainPopProgressStore? get progressStoreOverride;
  CampaignStreakTracker? get campaignStreakOverride;
  SessionPacingController? get sessionPacingOverride;
  SessionGoalsController? get sessionGoalsOverride;

  GameScreenTimerCoordinator get timers;

  ChainPopGame? get game;
  ChainPopGame get engine;

  int get livesRemaining;
  set livesRemaining(int value);

  bool get hasWon;
  set hasWon(bool value);

  bool get quickWin;
  set quickWin(bool value);

  bool get isPaused;
  set isPaused(bool value);

  bool get isSurge;
  bool get goingNext;
  set goingNext(bool value);

  Stopwatch get stopwatch;

  int get earnedStars;
  set earnedStars(int value);

  int get removedNodes;
  set removedNodes(int value);

  int get movesTaken;
  int get undosUsed;

  int get totalNodes;

  int get autoAdvanceSec;
  set autoAdvanceSec(int value);

  int? get timeLeftSec;
  set timeLeftSec(int? value);

  int? get timeLimitSec;

  Duration get lifetimeGameplaySyncedUpTo;
  set lifetimeGameplaySyncedUpTo(Duration value);

  GameSettings get settings;
  GameAudioHandle get audio;

  ChainPopStorage get gameStorage;
  ChainPopProgressStore get progress;

  AdService get ads;

  UndoAdPolicy get undoAdPolicy;
  HintAdPolicy get hintAdPolicy;

  bool get gateHintsWithAds;
  bool get hardOrDailyFeatures;
  bool get offerRewardedContinue;

  GlobalKey get headerHudKey;
  GlobalKey get footerHudKey;
  GlobalKey get bodyStackKey;

  bool get playfieldInsetFrameScheduled;
  set playfieldInsetFrameScheduled(bool value);

  double get hudBannerTop;
  set hudBannerTop(double value);

  CampaignStreakTracker get streak;
  SessionPacingController get pacing;
  SessionGoalsController get goals;

  /// Schedules a Flutter rebuild.
  void markDirty(VoidCallback fn);

  void showGoalCompleteToast();

  /// Cross-controller hooks — [GameScreenState] delegates to the matching
  /// extracted controller.
  void handleTimeUp();
  void startCountdown();
  void startEasyHudTimer();
  void resetGhostHintTimer();
  void resetForRetry();
  void goMenu();
}
