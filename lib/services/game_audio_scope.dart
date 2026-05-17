import 'package:flutter/widgets.dart';

import 'game_audio.dart';

/// Shared lightweight UI audio for menus / level grid (no gameplay ambient loop).
///
/// **Lifetime:** [ChainPopApp] owns the scoped controller and disposes it with the app.
/// [GameScreen] always builds a **separate** [GameAudioController] for gameplay SFX and
/// ambient bed; it disposes only that instance when leaving the game route. Menu audio is
/// not disposed during menu→game navigation, so there is no double-[dispose] on one pool.
///
/// (Planning docs may refer to this widget as “GameAudioScope”.)
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
