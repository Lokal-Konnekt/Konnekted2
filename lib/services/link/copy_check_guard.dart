import 'dart:async';

/// Stops a preview promptly; late I/O must check before publishing or starting
/// another operation. The preview never deletes or transfers audio files.
class CopyCheckGuard {
  CopyCheckGuard({this.limit = const Duration(seconds: 90)});
  final Duration limit;
  final _stopped = Completer<void>();
  StateError? _reason;
  bool get stopped => _reason != null;

  void cancel() => _stop('File check cancelled.');
  void _stop(String message) {
    if (stopped) return;
    _reason = StateError(message);
    _stopped.complete();
  }

  void check() {
    if (_reason case final reason?) throw reason;
  }

  Future<T> run<T>(Future<T> Function() work) async {
    check();
    final timer = Timer(
      limit,
      () => _stop(
        'Checking files took too long. Nothing was copied. Reconnect and try again.',
      ),
    );
    try {
      return await Future.any([
        work(),
        _stopped.future.then<T>((_) => throw _reason!),
      ]);
    } finally {
      timer.cancel();
    }
  }
}
