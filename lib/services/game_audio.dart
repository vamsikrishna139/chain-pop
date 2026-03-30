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
        _hudPlayer = AudioPlayer() {
    for (final p in _players) {
      p.setReleaseMode(ReleaseMode.stop);
      p.setPlayerMode(PlayerMode.mediaPlayer);
    }
    _hudPlayer.setReleaseMode(ReleaseMode.stop);
    _hudPlayer.setPlayerMode(PlayerMode.mediaPlayer);
  }

  /// Kenney.nl assets (CC0): UI Audio, Interface Sounds, Digital Audio — see
  /// `assets/sounds/CREDITS.txt`.
  ///
  /// Paths omit the leading `assets/` on purpose: [AudioPlayer] uses
  /// [AudioCache] with default [AudioCache.prefix] `assets/`, so
  /// `sounds/pop.ogg` resolves to bundle key `assets/sounds/pop.ogg`.
  /// Using `assets/sounds/...` here would load `assets/assets/sounds/...`
  /// (missing asset).
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
  int _i = 0;

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

  Future<void> dispose() async {
    await _hudPlayer.dispose();
    for (final p in _players) {
      await p.dispose();
    }
  }
}
