import 'package:flick/features/discovery/discovery_http.dart';
import 'package:flick/features/discovery/discovery_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test(
    'opt-in live guest YouTube Music catalog smoke',
    () async {
      final client = http.Client();
      addTearDown(client.close);
      final results = await YoutubeMusicCatalog(
        DiscoveryHttp(client),
      ).search('Beethoven Moonlight Sonata');
      expect(results, isNotEmpty);
      expect(
        results.every((t) => t.sourceUrl?.host == 'music.youtube.com'),
        isTrue,
      );
    },
    skip: !const bool.fromEnvironment('DISCOVERY_LIVE_TEST'),
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
