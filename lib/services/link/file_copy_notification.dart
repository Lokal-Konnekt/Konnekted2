import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/lokal_remote_state.dart';

/// Keeps an explicit copy alive while the UI is backgrounded. Does not own audio.
class FileCopyNotification {
  static const _channel = MethodChannel('lokal/file_copy');
  Future<void> _tail = Future.value();
  bool _active = false;
  DateTime? _sentAt;
  String _device = '';
  Future<void> begin(String device) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _device = device;
    _sentAt = null;
    // Must start while the user-triggered copy is still in the foreground.
    await _channel.invokeMethod<void>('start', {
      'title': 'Copying music',
      'message': 'Preparing files…',
      'device': device,
    });
    _active = true;
  }

  void update(LinkCopyProgress progress) {
    if (!_active || progress.phase != LinkCopyPhase.copying) return;
    final now = DateTime.now();
    if (_sentAt != null &&
        now.difference(_sentAt!) < const Duration(milliseconds: 500))
      return;
    _sentAt = now;
    _send('update', {
      'title': 'Copying music',
      'message':
          '${progress.processed} of ${progress.total} files · ${progress.currentTitle ?? (progress.toDesktop ? "Sending to desktop" : "Copying files")}',
      'device': _device,
      'processed': progress.processed,
      'total': progress.total,
    });
  }

  Future<void> finish(LinkCopyProgress progress) async {
    if (!_active) return;
    _active = false;
    await _send('stop', {
      'title': progress.phase == LinkCopyPhase.complete
          ? 'Music copy complete'
          : 'Music copy paused',
      'message':
          '${progress.sent} sent · ${progress.received} received · ${progress.failures.length} failed',
      'device': _device,
    });
  }

  void dispose() {
    unawaited(finish(const LinkCopyProgress(phase: LinkCopyPhase.paused)));
  }

  Future<void> _send(String method, Map<String, Object?> arguments) {
    _tail = _tail.catchError((Object _) {}).then((_) async {
      try {
        await _channel.invokeMethod<void>(method, arguments);
      } on PlatformException {
        /* A later update or final stop can still succeed. */
      } on MissingPluginException {
        /* Non-Android development hosts. */
      }
    });
    return _tail;
  }
}
