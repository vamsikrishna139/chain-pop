part of 'package:chain_pop/screens/game_screen.dart';

/// Maps Flutter HUD geometry to [ChainPopGame] playfield reserves (logical px).
final class GamePlayfieldInsetController {
  GamePlayfieldInsetController(this._s);

  final GameScreenState _s;

  void scheduleSync() {
    if (_s._game == null) return;
    if (_s._playfieldInsetFrameScheduled) return;
    _s._playfieldInsetFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _s._playfieldInsetFrameScheduled = false;
      if (!_s.mounted) return;
      syncFromHud();
    });
  }

  void syncFromHud() {
    if (_s._game == null) return;
    final mq = MediaQuery.of(_s.context);
    final h = mq.size.height;

    double topReserved = mq.padding.top + 128;
    final headerBox =
        _s._headerHudKey.currentContext?.findRenderObject() as RenderBox?;
    final stackBox =
        _s._bodyStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (headerBox != null && headerBox.hasSize) {
      final headerBottom =
          headerBox.localToGlobal(Offset(0, headerBox.size.height)).dy;
      topReserved = headerBottom + 20;

      if (_s.widget.isTutorial && stackBox != null && stackBox.hasSize) {
        final hintTop = stackBox
            .globalToLocal(
              headerBox.localToGlobal(Offset(0, headerBox.size.height)),
            )
            .dy;
        final next = (hintTop + 8).clamp(72.0, h * 0.4);
        if ((_s._tutorialHintTop - next).abs() > 0.5) {
          _s.patchState(() {
            _s._tutorialHintTop = next;
          });
        }
      }
    }

    double bottomReserved = mq.padding.bottom + 88;
    if (!_s._hasWon) {
      final footerBox =
          _s._footerHudKey.currentContext?.findRenderObject() as RenderBox?;
      if (footerBox != null && footerBox.hasSize) {
        final footerTop = footerBox.localToGlobal(Offset.zero).dy;
        bottomReserved = (h - footerTop) + 16;
      }
    }

    topReserved = topReserved.clamp(96.0, h * 0.55);
    bottomReserved = bottomReserved.clamp(64.0, h * 0.5);

    _s._engine.configurePlayfieldInsets(top: topReserved, bottom: bottomReserved);
  }
}
