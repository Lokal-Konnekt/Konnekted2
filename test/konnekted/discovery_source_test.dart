import 'dart:async';

import 'package:flick/features/konnekted/konnekted_discovery.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'manual Spotify selection and refresh never load or select Last.fm',
    () async {
      var lastfmReads = 0;
      final container = ProviderContainer(
        overrides: [
          konnektedLastfmAccountProvider.overrideWith((_) async {
            lastfmReads++;
            return null;
          }),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(konnektedDiscoveryProvider.notifier);
      await notifier.setSource(KonnektedDiscoverySource.spotify);
      await notifier.load(refresh: true);
      expect(
        container.read(konnektedDiscoveryProvider).source,
        KonnektedDiscoverySource.spotify,
      );
      expect(container.read(konnektedDiscoveryProvider).loading, isFalse);
      expect(lastfmReads, 0);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'lokal_discovery_source',
        ),
        'spotify',
      );
    },
  );
  test(
    'restoring Spotify does not fall through to the default provider',
    () async {
      SharedPreferences.setMockInitialValues({
        'lokal_discovery_source': 'spotify',
      });
      final container = ProviderContainer(
        overrides: [
          konnektedLastfmAccountProvider.overrideWith(
            (_) async => fail('Last.fm must not load'),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(konnektedDiscoveryProvider.notifier).load();
      expect(
        container.read(konnektedDiscoveryProvider).source,
        KonnektedDiscoverySource.spotify,
      );
    },
  );
  test(
    'an in-flight Last.fm load cannot overwrite a newer Spotify selection',
    () async {
      final account = Completer<String?>();
      final container = ProviderContainer(
        overrides: [
          konnektedLastfmAccountProvider.overrideWith((_) => account.future),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(konnektedDiscoveryProvider.notifier);
      final old = notifier.load();
      await Future<void>.delayed(Duration.zero);
      await notifier.setSource(KonnektedDiscoverySource.spotify);
      account.complete(null);
      await old;
      expect(
        container.read(konnektedDiscoveryProvider).source,
        KonnektedDiscoverySource.spotify,
      );
    },
  );
}
