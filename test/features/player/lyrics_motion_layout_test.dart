import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flick/services/lyrics_service.dart';
import 'package:flick/features/player/widgets/lyric_motion_line.dart';
import 'package:flick/features/player/widgets/player_lyrics_transition.dart';

void main() {
  testWidgets(
    'wrapped timed Japanese uses its measured paragraph height at large text scales',
    (tester) async {
      const text = '見覚えのある レインコート 黄昏の駅で 胸が震えた';
      const line = LyricsLine(
        timestamp: Duration.zero,
        text: text,
        words: [
          LyricsWord(
            start: Duration.zero,
            end: Duration(seconds: 3),
            text: text,
          ),
        ],
      );
      const style = TextStyle(
        fontSize: 34,
        height: 1.25,
        fontWeight: FontWeight.w700,
      );
      for (final scale in [1.0, 1.5]) {
        double? expected;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Center(
                child: SizedBox(
                  width: 280,
                  child: Builder(
                    builder: (context) {
                      expected = LyricMotionLine.height(
                        context,
                        text,
                        style,
                        280,
                      );
                      return const LyricMotionLine(
                        key: ValueKey('line'),
                        line: line,
                        position: Duration(seconds: 1),
                        style: style,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('line'))).height,
          expected,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets('rapid lyric transitions retain scroll state and controls', (
    tester,
  ) async {
    var show = false;
    late StateSetter change;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            change = setState;
            return Column(
              children: [
                Expanded(
                  child: PlayerLyricsTransition(
                    showLyrics: show,
                    cover: const Text('Artwork'),
                    lyrics: ListView(
                      key: const ValueKey('scroll'),
                      children: [
                        for (var i = 0; i < 50; i++)
                          SizedBox(height: 40, child: Text('Line $i')),
                      ],
                    ),
                  ),
                ),
                const Text('Transport'),
              ],
            );
          },
        ),
      ),
    );
    change(() => show = true);
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const ValueKey('scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    scroll.position.jumpTo(160);
    change(() => show = false);
    await tester.pump(const Duration(milliseconds: 100));
    change(() => show = true);
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, 160);
    expect(find.text('Transport'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
