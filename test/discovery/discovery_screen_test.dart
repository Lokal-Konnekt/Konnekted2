import 'dart:convert';

import 'package:flick/features/discovery/discovery_screen.dart';
import 'package:flick/features/discovery/discovery_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('secure settings round-trip and absence default off', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = DiscoverySettingsStore();
    expect((await store.load()).hasSource, isFalse);
    await store.save(
      const DiscoverySettings(
        youtubeEnabled: true,
        addons: [
          DiscoveryAddonConfig(
            id: 'saved',
            enabled: true,
            endpoint: 'https://addon.example/private-path',
            token: 'fixture-token',
          ),
        ],
      ),
    );
    final restored = await DiscoverySettingsStore().load();
    expect(restored.youtubeEnabled, isTrue);
    expect(restored.activeAddons, hasLength(1));
    expect(
      restored.addons.single.endpoint,
      'https://addon.example/private-path',
    );
    expect(restored.addons.single.token, 'fixture-token');
    await store.save(const DiscoverySettings());
    expect((await store.load()).hasSource, isFalse);
    expect((await store.load()).addons, isEmpty);
  });

  testWidgets('const shell entry shows opt-in and does not contact a source', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final client = MockClient(
      (_) async => fail('Disabled discovery contacted a source'),
    );
    addTearDown(client.close);
    const exportedEntry = DiscoveryScreen();
    expect(exportedEntry, isA<Widget>());
    await tester.pumpWidget(MaterialApp(home: DiscoveryScreen(client: client)));
    await tester.pumpAndSettle();
    expect(find.text('Online discovery is off'), findsOneWidget);
    expect(find.text('Choose sources'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await tester.tap(find.text('Choose sources'));
    await tester.pumpAndSettle();
    expect(find.text('Online sources'), findsOneWidget);
    expect(
      tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .every((s) => !s.value),
      isTrue,
    );
  });

  testWidgets(
    'source names, playback selection, and saved opt-out use the correct addon',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = DiscoverySettingsStore();
      await store.save(
        const DiscoverySettings(
          addons: [
            DiscoveryAddonConfig(
              id: 'alpha',
              endpoint: 'https://alpha.example/private-path',
              label: 'Home music',
              token: 'alpha-fixture',
              enabled: true,
            ),
            DiscoveryAddonConfig(
              id: 'beta',
              endpoint: 'https://beta.example',
              label: 'Second library',
              token: 'beta-fixture',
              enabled: true,
            ),
          ],
        ),
      );
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('manifest.json')) {
          expect(request.url.host, 'beta.example');
          expect(request.headers['Authorization'], 'Bearer beta-fixture');
          // Stop before native probing: this tests source selection, not hardware.
          return http.Response('private remote body', 403);
        }
        return http.Response(
          jsonEncode({
            'tracks': [
              {
                'id': 'shared-id',
                'title': 'Fixture recording',
                'artist': 'Artist',
              },
            ],
          }),
          200,
        );
      });
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryScreen(client: client, settingsStore: store),
        ),
      );
      await tester.pumpAndSettle();
      expect(requests, isEmpty);
      await tester.enterText(find.byType(TextField), 'recording');
      await tester.pump(const Duration(milliseconds: 450));
      // Mock HTTP stream cleanup needs a turn on the real event loop.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.text('Play from Home music'), findsOneWidget);
      expect(find.text('Play from Second library'), findsOneWidget);
      expect(requests, hasLength(2));

      await tester.ensureVisible(find.text('Play from Second library'));
      await tester.tap(find.text('Play from Second library'));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(requests, hasLength(3));
      expect(find.textContaining('private remote body'), findsNothing);

      await tester.tap(find.byTooltip('Online sources'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('enabled-addon-alpha')),
      );
      await tester.tap(find.byKey(const ValueKey('enabled-addon-alpha')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-sources')));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect((await store.load()).activeAddons.single.id, 'beta');
      expect(requests.skip(3).map((r) => r.url.host), ['beta.example']);
      expect(find.text('Play from Home music'), findsNothing);
      expect(find.text('Play from Second library'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
