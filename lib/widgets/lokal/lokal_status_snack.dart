import 'package:flutter/material.dart';

/// One status line at the foot of the screen that updates in place ("Getting
/// Song from Qobuz… 42%") instead of a new snackbar sliding in for each
/// update, and goes away once the work is done or has failed.
class LokalStatusSnack {
  LokalStatusSnack(this._messenger);

  /// The messenger to show in; null once the screen is gone.
  final ScaffoldMessengerState? Function() _messenger;
  final _text = ValueNotifier<String>('');
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _shown;

  /// Whether the status line is on screen.
  bool get showing => _shown != null;

  /// Shows [text], in place of what the line said before.
  void update(String text) {
    _text.value = text;
    if (_shown != null) return;
    final messenger = _messenger();
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    final shown = messenger.showSnackBar(
      SnackBar(
        // Stays while the work goes on; [clear] or [fail] takes it away.
        duration: const Duration(minutes: 10),
        content: Row(
          children: [
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: _text,
                builder: (context, value, _) =>
                    Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ),
      ),
    );
    _shown = shown;
    shown.closed.then((_) {
      if (identical(_shown, shown)) _shown = null;
    });
  }

  /// Takes the status line away.
  void clear() {
    final shown = _shown;
    _shown = null;
    shown?.close();
  }

  /// Replaces the status line with [message], which goes after a while.
  void fail(String message) {
    clear();
    final messenger = _messenger();
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// The screen is going: the line goes with it. (The text stays
  /// undisposed: the snackbar may still be sliding away with it.)
  void dispose() => clear();
}
