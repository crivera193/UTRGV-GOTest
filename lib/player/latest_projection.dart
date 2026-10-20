/// One native read in flight, one pending refresh. Camera/new-GPS invalidation
/// rejects late results. Frame-time interpolation is sampled when a read starts,
/// so high-frequency display ticks never enqueue historical positions.
class LatestProjection<T> {
  LatestProjection({required this.read, required this.apply});
  final Future<T?> Function() read;
  final void Function(T?) apply;
  Future<void>? _running;
  bool _queued = false, _disposed = false;
  int _revision = 0;

  Future<void> request({bool invalidate = false}) {
    if (_disposed) return Future.value();
    if (invalidate) _revision++;
    _queued = true;
    return _running ??= _drain().whenComplete(() => _running = null);
  }

  Future<void> _drain() async {
    while (_queued && !_disposed) {
      _queued = false;
      final revision = _revision;
      T? result;
      try {
        result = await read();
      } catch (_) {
        result = null;
      }
      if (!_disposed && revision == _revision) apply(result);
    }
  }

  void cancel() {
    _revision++;
    _queued = false;
  }

  void dispose() {
    cancel();
    _disposed = true;
  }
}
