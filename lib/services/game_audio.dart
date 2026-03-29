import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import 'game_sfx.dart';

/// Low-latency SFX pool for overlapping taps (match-3 style pop feedback).
class GameAudioController {
  GameAudioController({int voiceCount = 4})
      : _players = List.generate(
          voiceCount,
          (_) => AudioPlayer(),
        ) {
    for (final p in _players) {
      p.setReleaseMode(ReleaseMode.stop);
      p.setPlayerMode(PlayerMode.lowLatency);
    }
    // Release APKs on some Android devices need explicit usage (game/SFX) for routing.
    scheduleMicrotask(() => unawaited(_configureAndroidAudio()));
  }

  Future<void> _configureAndroidAudio() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final ctx = AudioContext(
      android: const AudioContextAndroid(
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.game,
      ),
    );
    await AudioPlayer.global.setAudioContext(ctx);
    for (final p in _players) {
      await p.setAudioContext(ctx);
    }
  }

  /// Kenney.nl assets (CC0): UI Audio, Interface Sounds, Digital Audio — see
  /// `assets/sounds/CREDITS.txt`.
  static const _paths = <GameSfx, String>{
    GameSfx.pop: 'assets/sounds/pop.ogg',
    GameSfx.jam: 'assets/sounds/jam.wav',
    GameSfx.win: 'assets/sounds/win.wav',
    GameSfx.gameOver: 'assets/sounds/game_over.wav',
    GameSfx.hint: 'assets/sounds/hint.wav',
    GameSfx.uiTap: 'assets/sounds/ui_tap.wav',
    GameSfx.restart: 'assets/sounds/restart.wav',
  };

  final List<AudioPlayer> _players;
  int _i = 0;

  Future<void> play(GameSfx sfx, {double playbackRate = 1.0}) async {
    final path = _paths[sfx];
    if (path == null) return;
    final player = _players[_i];
    _i = (_i + 1) % _players.length;
    await player.stop();
    final rate = playbackRate.clamp(0.85, 1.5);
    await player.setPlaybackRate(rate);
    await player.play(AssetSource(path), volume: sfx == GameSfx.pop ? 0.82 : 0.88);
  }

  Future<void> dispose() async {
    for (final p in _players) {
      await p.dispose();
    }
  }
}
