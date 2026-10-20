import 'dart:convert';

import 'package:flick/features/discovery/discovery_settings.dart';
import 'package:flick/features/settings/widgets/http_addons_settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _MemoryStore extends DiscoverySettingsStore {
  _MemoryStore(this.settings);

  DiscoverySettings settings;
  int saves = 0;

  @override
  Future<DiscoverySettings> load() async => settings;

  @override
  Future<void> save(DiscoverySettings value) async {
    saves++;
    settings = value.validated();
  }
}

Widget _host(HttpAddonsSettingsPanel panel) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: panel)),
);

void main() {
  testWidgets('adds a manifest URL inline after validating the manifest', (
    tester,
  ) async {
    final store = _MemoryStore(const DiscoverySettings(youtubeEnabled: true));
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.method, 'GET');
      expect(
        request.url.toString(),
        'https://music.example/library/manifest.json',
      );
      return http.Response(
        jsonEncode({
          'id': 'private-id',
          'name': 'https://private.example/do-not-display-secret',
          'resources': ['search', 'stream'],
          'allowDownloads': true,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);

    await tester.pumpWidget(
      _host(HttpAddonsSettingsPanel(store: store, client: client)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('http-addon-manifest-url')), findsOneWidget);
    expect(find.text('HTTP music add-ons'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('http-addon-manifest-url')),
      'https://music.example/library/manifest.json',
    );
    await tester.tap(find.byKey(const ValueKey('http-addon-add')));
    await tester.pumpAndSettle();

    expect(requests, 1);
    expect(store.saves, 1);
    expect(store.settings.youtubeEnabled, isTrue);
    expect(store.settings.addons, hasLength(1));
    expect(
      store.settings.addons.single.endpoint,
      'https://music.example/library',
    );
    expect(store.settings.addons.single.enabled, isTrue);
    expect(store.settings.addons.single.token, isEmpty);
    expect(find.text('Music add-on 1'), findsOneWidget);
    expect(find.textContaining('private.example'), findsNothing);
    expect(find.textContaining('do-not-display-secret'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rejects an invalid URL without contacting the server', (
    tester,
  ) async {
    final store = _MemoryStore(const DiscoverySettings());
    final client = MockClient((_) async => fail('Invalid URL must not be sent'));
    addTearDown(client.close);

    await tester.pumpWidget(
      _host(HttpAddonsSettingsPanel(store: store, client: client)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('http-addon-manifest-url')),
      'http://music.example/manifest.json',
    );
    await tester.tap(find.byKey(const ValueKey('http-addon-add')));
    await tester.pumpAndSettle();

    expect(store.saves, 0);
    expect(store.settings.addons, isEmpty);
    expect(
      find.text('Use an absolute HTTPS URL without user info or a fragment.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('existing sources can be toggled and removed inline', (
    tester,
  ) async {
    const existing = DiscoveryAddonConfig(
      id: 'home',
      endpoint: 'https://music.example/library',
      label: 'Home music',
      enabled: true,
    );
    final store = _MemoryStore(const DiscoverySettings(addons: [existing]));
    final client = MockClient((_) async => fail('No network request expected'));
    addTearDown(client.close);

    await tester.pumpWidget(
      _host(HttpAddonsSettingsPanel(
        initial: store.settings,
        store: store,
        client: client,
      )),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home music'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(store.settings.addons.single.enabled, isFalse);

    await tester.tap(find.byTooltip('Remove Home music'));
    await tester.pumpAndSettle();
    expect(store.settings.addons, isEmpty);
    expect(find.text('Home music'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
