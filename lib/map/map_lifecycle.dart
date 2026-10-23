import 'package:flutter/widgets.dart';

enum MapLifecycleChange { none, suspend, resume }

/// Loss of focus is not loss of visibility. Hidden/paused are one transition.
class MapLifecycle {
  bool foreground = true;
  MapLifecycleChange accept(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (foreground) return MapLifecycleChange.none;
      foreground = true;
      return MapLifecycleChange.resume;
    }
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (!foreground) return MapLifecycleChange.none;
      foreground = false;
      return MapLifecycleChange.suspend;
    }
    return MapLifecycleChange.none;
  }
}

/// Stop must finish before another start can acquire native subscriptions.
class SerialMapOperations {
  Future<void> _tail = Future.value();
  Future<void> run(Future<void> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
