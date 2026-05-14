import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'game_sfx.dart';

/// SFX pool for overlapping taps. Uses [PlayerMode.mediaPlayer] on all
/// platforms: Android [PlayerMode.lowLatency] (SoundPool) is unreliable with
/// some `.ogg`/devices; [mediaPlayer] matches [AssetSource] playback best.
class GameAudioController {
  GameAudioController({int voiceCount = 4})
      : _players = List.generate(
          voiceCount,
          (_) => AudioPlayer(),
        ),
        _hudPlayer = AudioPlayer(),
        _ambientPlayer = AudioPlayer() {
    for (final p in _players) {
      p.setReleaseMode(ReleaseMode.stop);
      p.setPlayerMode(PlayerMode.mediaPlayer);
    }
    _hudPlayer.setReleaseMode(ReleaseMode.stop);
    _hudPlayer.setPlayerMode(PlayerMode.mediaPlayer);
    _ambientPlayer.setReleaseMode(ReleaseMode.loop);
    _ambientPlayer.setPlayerMode(PlayerMode.mediaPlayer);
  }

  /// Kenney.nl assets (CC0): UI Audio, Interface Sounds, Digital Audio — see
  /// `assets/sounds/CREDITS.txt`.
  ///
  /// Paths omit the leading `assets/` on purpose: [AudioPlayer] uses
  /// [AudioCache] with default [AudioCache.prefix] `assets/`, so
  /// `sounds/pop.ogg` resolves to bundle key `assets/sounds/pop.ogg`.
  /// Using `assets/sounds/...` here would load `assets/assets/sounds/...`
  /// (missing asset).
  /// Soft looping bed (see `assets/sounds/CREDITS.txt`).
  static const _ambientAssetPath = 'sounds/ambient_loop.wav';
  static const double _ambientVolume = 0.22;

  static const _paths = <GameSfx, String>{
    GameSfx.pop: 'sounds/pop.ogg',
    GameSfx.jam: 'sounds/jam.wav',
    GameSfx.win: 'sounds/win.wav',
    GameSfx.gameOver: 'sounds/game_over.wav',
    GameSfx.hint: 'sounds/hint.wav',
    GameSfx.uiTap: 'sounds/ui_tap.wav',
    GameSfx.restart: 'sounds/restart.wav',
  };

  final List<AudioPlayer> _players;
  final AudioPlayer _hudPlayer;
  final AudioPlayer _ambientPlayer;
  int _i = 0;

  /// Set when [GameScreen] begins a session; stays true until [dispose].
  bool _gameplayAmbientArmed = false;

  /// True after [setAmbientGameplayPaused] paused the bed for the pause overlay.
  bool _ambientPausedForGameplayOverlay = false;

  /// Menu / HUD clips use one player so they are not rotated with [pop]/[jam];
  /// sharing the pool caused intermittent drops (short uiTap vs longer clips).
  static bool _isBoardGameplaySfx(GameSfx sfx) =>
      sfx == GameSfx.pop || sfx == GameSfx.jam;

  Future<void> play(GameSfx sfx, {double playbackRate = 1.0}) async {
    final path = _paths[sfx];
    if (path == null) return;
    final player =
        _isBoardGameplaySfx(sfx) ? _players[_i++ % _players.length] : _hudPlayer;
    final rate = playbackRate.clamp(0.85, 1.5);
    final volume = sfx == GameSfx.pop ? 0.82 : 0.88;
    try {
      await player.stop();
      // audioplayers: on Android, setPlaybackRate must run after play()/resume().
      await player.play(AssetSource(path), volume: volume);
      if ((rate - 1.0).abs() > 0.001) {
        await player.setPlaybackRate(rate);
      }
    } on Object catch (e, st) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: st,
          library: 'chain_pop',
          context: ErrorDescription('while playing $sfx'),
        ),
      );
    }
  }

  /// Starts the gameplay ambient bed when [soundEnabled] is true; otherwise stops
  /// it. Idempotent; arms the controller for [setAmbientEnabled] while [dispose]
  /// has not run.
  Future<void> startAmbientIfEnabled(bool soundEnabled) async {
    _gameplayAmbientArmed = true;
    if (!soundEnabled) {
      await stopAmbient();
      return;
    }
    try {
      await _ambientPlayer.stop();
      await _ambientPlayer.setVolume(_ambientVolume);
      await _ambientPlayer.play(AssetSource(_ambientAssetPath));
    } on Object catch (e, st) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: st,
          library: 'chain_pop',
          context: ErrorDescription('while starting ambient bed'),
        ),
      );
    }
  }

  Future<void> stopAmbient() async {
    _ambientPausedForGameplayOverlay = false;
    try {
      await _ambientPlayer.stop();
    } on Object catch (e, st) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: st,
          library: 'chain_pop',
          context: ErrorDescription('while stopping ambient bed'),
        ),
      );
    }
  }

  /// Applies the sound toggle while a gameplay session may still be active:
  /// stops when `false`; when `true`, restarts the bed only if the session was
  /// armed via [startAmbientIfEnabled] (i.e. still on [GameScreen]).
  Future<void> setAmbientEnabled(bool on) async {
    if (!on) {
      await stopAmbient();
      return;
    }
    if (!_gameplayAmbientArmed) return;
    await startAmbientIfEnabled(true);
  }

  /// Pauses or resumes the ambient bed with the in-game pause overlay.
  Future<void> setAmbientGameplayPaused(
    bool paused,
    bool soundEnabled,
  ) async {
    if (paused) {
      _ambientPausedForGameplayOverlay = true;
      try {
        await _ambientPlayer.pause();
      } on Object catch (e, st) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: e,
            stack: st,
            library: 'chain_pop',
            context: ErrorDescription('while pausing ambient bed'),
          ),
        );
      }
      return;
    }
    if (!_ambientPausedForGameplayOverlay) return;
    _ambientPausedForGameplayOverlay = false;
    if (!soundEnabled) return;
    try {
      await _ambientPlayer.resume();
    } on Object catch (e, st) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: st,
          library: 'chain_pop',
          context: ErrorDescription('while resuming ambient bed'),
        ),
      );
    }
  }

  Future<void> dispose() async {
    _gameplayAmbientArmed = false;
    await stopAmbient();
    await _ambientPlayer.dispose();
    await _hudPlayer.dispose();
    for (final p in _players) {
      await p.dispose();
    }
  }
}
