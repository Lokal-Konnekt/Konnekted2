import 'package:flick/features/discovery/discovery_models.dart';
import 'package:flick/features/konnekted/konnekted_discovery.dart';
import 'package:flick/features/search/widgets/online_search_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

OnlineSource _source(String id, String name, List<String> titles) =>
    OnlineSource(
      id: id,
      name: name,
      addon: id != 'yt',
      results: (query) async => [
        for (final title in titles)
          OnlineResult(
            DiscoveryTrack(
              id: '$id-$title',
              title: title,
              artist: 'Artist',
              source: DiscoverySource.spotiflac,
            ),
          ),
      ],
      play: (_) async => throw const DiscoveryException('No stream'),
    );

void main() {
  testWidgets('add-ons appear as sources and their results play on tap', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                OnlineSearchSection(
                  query: 'song',
                  sources: (_, _) async => [
                    _source('yt', 'YouTube Music', ['From YouTube']),
                    _source('a-tidal', 'Tidal', ['From Tidal']),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('From YouTube'), findsOneWidget);

    await tester.tap(find.text('Tidal'));
    await tester.pumpAndSettle();
    expect(find.text('From Tidal'), findsOneWidget);
    expect(find.text('From an add-on you installed'), findsOneWidget);

    await tester.tap(find.text('From Tidal'));
    await tester.pumpAndSettle();
    expect(find.text('No stream'), findsOneWidget);
  });
}
