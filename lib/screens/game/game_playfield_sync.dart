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
    final stackBox =
        _host.bodyStackKey.currentContext?.findRenderObject() as RenderBox?;
    final hasStack = stackBox != null && stackBox.hasSize;
    // Measured in the body stack's own coordinates, never global ones. The
    // game screen opens inside the route's zoom transition, and a global
    // measurement taken mid-transition includes that scale: the toolbar read
    // lower than it is, the board was fitted too large (overlapping the
    // toolbar), then re-fitted once the transition ended — a visible
    // zoom-and-settle on every level launch. The stack is the GameWidget's
    // parent, so its coordinates are exactly the engine's.
    final h = hasStack ? stackBox.size.height : mq.size.height;
    Offset toStack(RenderBox box, Offset local) => hasStack
        ? box.localToGlobal(local, ancestor: stackBox)
        : box.localToGlobal(local);

    double topReserved = mq.padding.top + 128;
    final headerBox =
        _host.headerHudKey.currentContext?.findRenderObject() as RenderBox?;
    if (headerBox != null && headerBox.hasSize) {
      final headerBottom =
          toStack(headerBox, Offset(0, headerBox.size.height)).dy;
      topReserved = headerBottom + 20;

      if (hasStack) {
        final next = (headerBottom + 8).clamp(72.0, h * 0.4);
        if ((_host.hudBannerTop - next).abs() > 0.5) {
          _host.markDirty(() {
            _host.hudBannerTop = next;
          });
        }
      }
    }

    double bottomReserved = mq.padding.bottom + 88;
    if (!_host.hasWon) {
      final footerBox =
          _host.footerHudKey.currentContext?.findRenderObject() as RenderBox?;
      if (footerBox != null && footerBox.hasSize) {
        final footerTop = toStack(footerBox, Offset.zero).dy;
        bottomReserved = (h - footerTop) + 16;
      }
    }

    topReserved = topReserved.clamp(96.0, h * 0.55);
    bottomReserved = bottomReserved.clamp(64.0, h * 0.5);

    _host.engine
        .configurePlayfieldInsets(top: topReserved, bottom: bottomReserved);
  }
}
