import 'package:flick/widgets/lokal/lokal_swipe_to_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('right swipe queues exactly one song', (tester) async {
    var queued = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LokalSwipeToQueue(
            onQueue: () { queued++; },
            child: const ListTile(title: Text('Track')),
          ),
        ),
      ),
    );

    await tester.drag(find.text('Track'), const Offset(110, 0));
    await tester.pumpAndSettle();

    expect(queued, 1);
    expect(find.text('Track'), findsOneWidget);
  });

  testWidgets('short, left and vertical drags do not queue', (tester) async {
    var queued = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LokalSwipeToQueue(
            onQueue: () { queued++; },
            child: const ListTile(title: Text('Track')),
          ),
        ),
      ),
    );

    await tester.drag(find.text('Track'), const Offset(24, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Track'), const Offset(-130, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Track'), const Offset(0, -100));
    await tester.pumpAndSettle();

    expect(queued, 0);
  });

  testWidgets('tap and long press still use the song row actions', (tester) async {
    var queued = 0;
    var taps = 0;
    var longPresses = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LokalSwipeToQueue(
            onQueue: () { queued++; },
            child: ListTile(
              title: const Text('Track'),
              onTap: () => taps++,
              onLongPress: () => longPresses++,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Track'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Track'));
    await tester.pumpAndSettle();

    expect(taps, 1);
    expect(longPresses, 1);
    expect(queued, 0);
  });

  testWidgets('disabled rows cannot be queued by swiping', (tester) async {
    var queued = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LokalSwipeToQueue(
            enabled: false,
            onQueue: () { queued++; },
            child: const ListTile(title: Text('Track')),
          ),
        ),
      ),
    );

    await tester.drag(find.text('Track'), const Offset(115, 0));
    await tester.pumpAndSettle();

    expect(queued, 0);
  });
}
