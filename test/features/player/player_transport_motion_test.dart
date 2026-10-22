import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flick/features/player/widgets/player_transport_controls.dart';

void main() {
  testWidgets(
    'play morph reverses and transport resizes with the lyrics pose',
    (tester) async {
      var playing = false, l = 0.0;
      late StateSetter change;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    change = setState;
                    return PlayerTransportControls(
                      playing: playing,
                      compact: false,
                      lyricsProgress: l,
                      accent: Colors.lime,
                      onAccent: Colors.black,
                      onPrevious: () {},
                      onNext: () {},
                      onPlayPause: () => setState(() => playing = !playing),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      final controls = find.byType(PlayerTransportControls);
      expect(tester.getSize(controls).height, 82);
      final icon = () =>
          tester.widget<AnimatedIcon>(find.byType(AnimatedIcon)).progress.value;
      await tester.tap(find.byKey(const ValueKey('player-play-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(icon(), greaterThan(0));
      expect(icon(), lessThan(1));
      change(() {
        playing = false;
        l = .5;
      });
      await tester.pump();
      expect(tester.getSize(controls).height, 67);
      change(() => l = 1);
      await tester.pumpAndSettle();
      expect(tester.getSize(controls).height, 52);
      expect(icon(), 0);
      expect(tester.takeException(), isNull);
    },
  );
}
