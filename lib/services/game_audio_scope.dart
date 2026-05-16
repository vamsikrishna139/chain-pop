import 'package:flutter/widgets.dart';

import '../services/game_audio.dart';

/// Shared lightweight UI audio for menus / level grid (no gameplay ambient loop).
///
/// [GameScreen] still constructs its own [GameAudioController] for ambient SFX.
class ChainPopAudioScope extends InheritedWidget {
  const ChainPopAudioScope({
    super.key,
    required this.uiAudio,
    required super.child,
  });

  final GameAudioController uiAudio;

  static GameAudioController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ChainPopAudioScope>();
    assert(scope != null, 'ChainPopAudioScope not found');
    return scope!.uiAudio;
  }

  static GameAudioController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChainPopAudioScope>()?.uiAudio;

  @override
  bool updateShouldNotify(covariant ChainPopAudioScope oldWidget) =>
      oldWidget.uiAudio != uiAudio;
}
