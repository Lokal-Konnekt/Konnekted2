import 'package:flick/features/player/widgets/artist_credit_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'each credited artist is its own navigation target, with kept names intact',
    (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ArtistCreditLinks(
              credit: 'Tyler, The Creator, Kali Uchis',
              style: const TextStyle(fontSize: 14),
              onArtistTap: opened.add,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Tyler, The Creator'));
      await tester.tap(find.text('Kali Uchis'));
      expect(opened, ['Tyler, The Creator', 'Kali Uchis']);
    },
  );
}
