import 'package:flick/features/player/widgets/full_player_action_chip_row.dart';
import 'package:flick/services/player_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _PlayerServiceFake extends Fake implements PlayerService {}

void main() {
  testWidgets('full player action strip exposes labeled, scrollable actions', (
    tester,
  ) async {
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FullPlayerActionChipRow(
            playerService: _PlayerServiceFake(),
            lyricsActive: false,
            onOpenQueue: () => calls.add('queue'),
            onToggleLyrics: () => calls.add('lyrics'),
            onOpenEqualizer: () => calls.add('equalizer'),
          ),
        ),
      ),
    );

    expect(find.text('Queue'), findsOneWidget);
    expect(find.text('Lyrics'), findsOneWidget);
    expect(find.text('Sleep timer'), findsOneWidget);
    expect(find.text('Speed up'), findsOneWidget);
    expect(find.text('Equalizer'), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);

    await tester.tap(find.text('Queue'));
    await tester.tap(find.text('Lyrics'));
    await tester.drag(find.byType(ListView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Equalizer'));
    expect(calls, ['queue', 'lyrics', 'equalizer']);
    expect(tester.takeException(), isNull);
  });
}
