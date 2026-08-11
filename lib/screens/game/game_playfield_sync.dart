import 'package:flutter/material.dart';

import 'game_screen_controller_host.dart';

/// Maps Flutter HUD geometry to [ChainPopGame] playfield reserves (logical px).
final class GamePlayfieldInsetController {
  GamePlayfieldInsetController(this._host);

  final GameScreenControllerHost _host;

  void scheduleSync() {
    if (_host.game == null) return;
    if (_host.playfieldInsetFrameScheduled) return;
    _host.playfieldInsetFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _host.playfieldInsetFrameScheduled = false;
      if (!_host.mounted) return;
      syncFromHud();
    });
  }

  void syncFromHud() {
    if (_host.game == null) return;
    final mq = MediaQuery.of(_host.context);
    final h = mq.size.height;

    double topReserved = mq.padding.top + 128;
    final headerBox =
        _host.headerHudKey.currentContext?.findRenderObject() as RenderBox?;
    final stackBox =
        _host.bodyStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (headerBox != null && headerBox.hasSize) {
      final headerBottom =
          headerBox.localToGlobal(Offset(0, headerBox.size.height)).dy;
      topReserved = headerBottom + 20;

      if (_host.isTutorial && stackBox != null && stackBox.hasSize) {
        final hintTop = stackBox
            .globalToLocal(
              headerBox.localToGlobal(Offset(0, headerBox.size.height)),
            )
            .dy;
        final next = (hintTop + 8).clamp(72.0, h * 0.4);
        if ((_host.tutorialHintTop - next).abs() > 0.5) {
          _host.markDirty(() {
            _host.tutorialHintTop = next;
          });
        }
      }
    }

    double bottomReserved = mq.padding.bottom + 88;
    if (!_host.hasWon) {
      final footerBox =
          _host.footerHudKey.currentContext?.findRenderObject() as RenderBox?;
      if (footerBox != null && footerBox.hasSize) {
        final footerTop = footerBox.localToGlobal(Offset.zero).dy;
        bottomReserved = (h - footerTop) + 16;
      }
    }

    topReserved = topReserved.clamp(96.0, h * 0.55);
    bottomReserved = bottomReserved.clamp(64.0, h * 0.5);

    _host.engine.configurePlayfieldInsets(top: topReserved, bottom: bottomReserved);
  }
}
