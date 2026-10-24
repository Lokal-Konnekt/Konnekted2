import 'package:flick/features/player/widgets/artwork_mesh_blur_backdrop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ambient artwork mesh is continuous across repeated cycles', () {
    for (final u in [0.0, .2, .5, .8, 1.0]) {
      for (final v in [0.0, .25, .5, .75, 1.0]) {
        final start = artworkMeshWaveOffset(0, u, v);
        final end = artworkMeshWaveOffset(1, u, v);
        expect((start - end).distance, lessThan(1e-10));
        // Match both tangent components at the wrap point. A mismatch would
        // make the background visibly snap, even when endpoints coincide.
        const step = 0.00001;
        final before = artworkMeshWaveOffset(1 - step, u, v);
        final after = artworkMeshWaveOffset(step, u, v);
        final velocityBefore = (end - before) / step;
        final velocityAfter = (after - start) / step;
        expect((velocityBefore - velocityAfter).distance, lessThan(.001));
      }
    }
  });

  test('mesh actually moves through several phases', () {
    final origin = artworkMeshWaveOffset(0, .37, .61);
    expect((origin - artworkMeshWaveOffset(.25, .37, .61)).distance,
        greaterThan(.01));
    expect((origin - artworkMeshWaveOffset(.5, .37, .61)).distance,
        greaterThan(.01));
  });

  test('Performance Mode limits ambient mesh repaint signals to 30 Hz', () {
    bool paint(Duration at, Duration? last, {bool performance = true}) =>
        artworkMeshNeedsFrame(at, last, performanceMode: performance);

    expect(paint(Duration.zero, null), isTrue);
    expect(paint(const Duration(milliseconds: 16), Duration.zero), isFalse);
    expect(paint(const Duration(milliseconds: 33), Duration.zero), isFalse);
    expect(paint(const Duration(milliseconds: 34), Duration.zero), isTrue);
    expect(paint(const Duration(milliseconds: 50),
        const Duration(milliseconds: 34)), isFalse);
    expect(paint(const Duration(milliseconds: 68),
        const Duration(milliseconds: 34)), isTrue);
    expect(paint(const Duration(milliseconds: 16),
        Duration.zero, performance: false), isTrue,
        reason: 'Full mode retains display-rate animation');
    expect(paint(Duration.zero, const Duration(seconds: 26)), isTrue,
        reason: 'Resuming a restarted ticker must not freeze rendering');
  });

}
