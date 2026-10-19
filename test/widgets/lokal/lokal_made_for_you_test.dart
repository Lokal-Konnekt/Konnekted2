import 'package:flick/widgets/lokal/lokal_made_for_you.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop\'s geometry: middle biggest and highest, edges sink', () {
    const half = 2.5;
    expect(LokalMadeForYouCarousel.scaleAt(0, half), 1);
    expect(LokalMadeForYouCarousel.scaleAt(2.5, half), .72);
    expect(LokalMadeForYouCarousel.scaleAt(-4, half), .72);
    expect(LokalMadeForYouCarousel.sinkAt(0, half), 0);
    expect(LokalMadeForYouCarousel.sinkAt(2.5, half), closeTo(.27, 1e-9));
    expect(LokalMadeForYouCarousel.centreAt(-1, half), lessThan(0));
    expect(
      LokalMadeForYouCarousel.centreAt(2, half) -
          LokalMadeForYouCarousel.centreAt(1, half),
      lessThan(LokalMadeForYouCarousel.centreAt(1, half)),
    );
    expect(LokalMadeForYouCarousel.wrap(11, 12), -1);
    expect(LokalMadeForYouCarousel.wrap(-7, 12), 5);
  });

  test('wide rows get desktop\'s full-size cards; phones get three slots', () {
    final wide = LokalMadeForYouCarousel.layoutFor(1600);
    expect(wide.card, 187.5);
    expect(wide.half, greaterThanOrEqualTo(2.5));
    final phone = LokalMadeForYouCarousel.layoutFor(412);
    expect(phone.half, 1.5);
    expect(phone.card, inInclusiveRange(140, 187.5));
  });

  Future<List<int>> pump(WidgetTester tester) async {
    final played = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 412,
            child: LokalMadeForYouCarousel(
              count: 12,
              semanticLabel: (i) => 'Play song $i',
              onPlay: played.add,
              card: (context, i) => ColoredBox(
                color: Colors.blue,
                child: Center(child: Text('card $i')),
              ),
            ),
          ),
        ),
      ),
    );
    return played;
  }

  testWidgets('tapping the middle card plays it', (tester) async {
    final played = await pump(tester);
    // The middle card is painted last, on top.
    await tester.tap(find.text('card 0'));
    expect(played, [0]);
    // Only the cards near the middle are built; the row loops.
    expect(find.text('card 1'), findsOneWidget);
    expect(find.text('card 11'), findsOneWidget);
    expect(find.text('card 6'), findsNothing);
  });

  testWidgets('a drag rolls it and settles on a card', (tester) async {
    final played = await pump(tester);
    await tester.drag(find.text('card 0'), const Offset(-170, 0));
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getCenter(find.byType(LokalMadeForYouCarousel)) +
          const Offset(0, -40),
    );
    expect(played, [1]);
  });

  testWidgets('a screen reader can step through it', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);
    final node = tester.getSemantics(
      find.bySemanticsLabel('Made for you').first,
    );
    expect(node.value, 'Play song 0');
    tester.semantics.increase(find.semantics.byLabel('Made for you'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.bySemanticsLabel('Made for you').first).value,
      'Play song 1',
    );
    handle.dispose();
  });
}
