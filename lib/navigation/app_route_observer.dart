import 'package:flutter/widgets.dart';

/// App-wide observer so screens can refresh when they become visible again.
///
/// Needed because campaign auto-advance swaps levels with `pushReplacement`,
/// which completes the original `push` future after the *first* level — so a
/// `.then` refresh on the launching screen fires once, too early, and never
/// again for the rest of the run.
final RouteObserver<ModalRoute<void>> appRouteObserver =
    RouteObserver<ModalRoute<void>>();

/// Rebuilds the screen whenever a route pushed on top of it is popped.
mixin RefreshOnReturn<T extends StatefulWidget> on State<T>
    implements RouteAware {
  ModalRoute<void>? _observedRoute;

  /// Called when the screen is uncovered. Defaults to a plain rebuild.
  void onReturnedTo() => setState(() {});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _observedRoute) {
      if (_observedRoute != null) appRouteObserver.unsubscribe(this);
      _observedRoute = route;
      if (route != null) appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    if (mounted) onReturnedTo();
  }

  @override
  void didPush() {}

  @override
  void didPop() {}

  @override
  void didPushNext() {}
}
