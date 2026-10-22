import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flick/services/lyrics_service.dart';
import 'package:flick/features/player/widgets/lyric_motion_line.dart';
import 'package:flick/features/player/widgets/player_panel_stage.dart';

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
  testWidgets(
    'one cover moves between queue and lyrics without growing or losing scroll',
    (tester) async {
      final q = ValueNotifier<double>(1), l = ValueNotifier<double>(0);
      addTearDown(q.dispose);
      addTearDown(l.dispose);
      Widget list(String name) => ListView(
        key: ValueKey(name),
        children: [
          for (var i = 0; i < 50; i++)
            SizedBox(height: 40, child: Text('$name $i')),
        ],
      );
      final queue = list('queue'), lyrics = list('lyrics');
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 360,
              height: 560,
              child: ValueListenableBuilder<double>(
                valueListenable: l,
                builder: (context, value, _) => PlayerPanelStage(
                  queueProgress: AlwaysStoppedAnimation(q.value),
                  lyricsProgress: AlwaysStoppedAnimation(value),
                  queueOpen: value == 0 && q.value > 0,
                  lyricsOpen: value > 0,
                  artwork: (context, side, progress) => const ColoredBox(
                    key: ValueKey('shared-cover'),
                    color: Colors.blue,
                  ),
                  info: (context, progress) => const SizedBox(
                    height: 44,
                    child: Text('Song title', key: ValueKey('shared-title')),
                  ),
                  queue: queue,
                  lyrics: lyrics,
                ),
              ),
            ),
          ),
        ),
      );
      ScrollableState scroll(String name) => tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(ValueKey(name)),
          matching: find.byType(Scrollable),
        ),
      );
      scroll('queue').position.jumpTo(160);
      final start = tester.getRect(find.byKey(const ValueKey('shared-cover')));
      expect(start.width, 52);
      var previousY = start.top;
      for (final t in [.1, .3, .5, .7, 1.0]) {
        l.value = t;
        await tester.pump();
        final rect = tester.getRect(find.byKey(const ValueKey('shared-cover')));
        expect(rect.width, 52); // Never returns via the large cover.
        expect(rect.top, greaterThan(previousY));
        previousY = rect.top;
        expect(find.byKey(const ValueKey('shared-cover')), findsOneWidget);
      }
      scroll('lyrics').position.jumpTo(200);
      for (final t in [.8, .4, .6, .2, 0.0]) {
        l.value = t;
        await tester.pump();
      }
      expect(scroll('queue').position.pixels, 160);
      expect(scroll('lyrics').position.pixels, 200);
      expect(tester.getRect(find.byKey(const ValueKey('shared-cover'))), start);
      q.value = 0;
      l.value = .01;
      await tester.pump();
      l.value = 0;
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const ValueKey('shared-cover'))).width,
        greaterThan(300),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
