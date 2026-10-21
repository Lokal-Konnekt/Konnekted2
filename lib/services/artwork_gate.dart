import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';

// ponytail: refcounted pause so independent drivers (fling gate, audio
// preload service) can hold the pause without one's release clobbering
// the other. Flush deferred resolvers only when the count actually hits 0.
int _artworkExtractionPauses = 0;
final List<VoidCallback> _pendingArtworkResolvers = <VoidCallback>[];

bool get artworkExtractionPaused => _artworkExtractionPauses > 0;

void pauseArtworkExtraction(bool paused) {
  if (paused) {
    _artworkExtractionPauses++;
    return;
  }
  if (_artworkExtractionPauses > 0) _artworkExtractionPauses--;
  if (_artworkExtractionPauses == 0) _drainArtworkResolvers();
}

bool _drainScheduled = false;
void _drainArtworkResolvers() {
  if (_drainScheduled ||
      artworkExtractionPaused ||
      _pendingArtworkResolvers.isEmpty) {
    return;
  }
  _drainScheduled = true;
  // Avoid an extraction storm when a fling ends: admit a few visible requests
  // after each frame instead of launching the whole backlog synchronously.
  SchedulerBinding.instance.addPostFrameCallback((_) {
    _drainScheduled = false;
    if (artworkExtractionPaused) return;
    final count = _pendingArtworkResolvers.length.clamp(0, 4);
    final batch = _pendingArtworkResolvers.sublist(0, count);
    _pendingArtworkResolvers.removeRange(0, count);
    for (final resolve in batch) {
      resolve();
    }
    _drainArtworkResolvers();
  });
  SchedulerBinding.instance.ensureVisualUpdate();
}

void enqueueArtworkResolver(VoidCallback cb) {
  _pendingArtworkResolvers.add(cb);
  if (!artworkExtractionPaused) _drainArtworkResolvers();
}

/// Mix this onto a screen's [State] and route its [ScrollNotification]s to
/// [onScrollNotification] to keep embedded-artwork extraction paused during
/// flings. Call [disposeArtworkGate] from [State.dispose].
// ponytail: shared helper beats triplicating the timer logic across
// album/artist/playlist screens.
mixin ArtworkExtractionScrollGate {
  static const Duration _settleDelay = Duration(milliseconds: 150);

  Timer? _artworkGate;
  // ponytail: hold at most ONE pause per owner. Incrementing on every scroll
  // update while canceling the pending release timer leaked refcounts and
  // froze extraction forever.
  bool _artworkGateHeld = false;

  bool onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollEndNotification) {
      _releaseArtworkGate();
    } else if (notification is ScrollUpdateNotification ||
        notification is UserScrollNotification ||
        notification is OverscrollNotification) {
      if (!_artworkGateHeld) {
        _artworkGateHeld = true;
        pauseArtworkExtraction(true);
      }
      _artworkGate?.cancel();
      _artworkGate = Timer(_settleDelay, _releaseArtworkGate);
    }
    return true;
  }

  void _releaseArtworkGate() {
    _artworkGate?.cancel();
    _artworkGate = null;
    if (_artworkGateHeld) {
      _artworkGateHeld = false;
      pauseArtworkExtraction(false);
    }
  }

  void disposeArtworkGate() {
    // Release the global pause so extraction isn't left frozen when the
    // route is popped mid-scroll.
    _releaseArtworkGate();
  }
}
