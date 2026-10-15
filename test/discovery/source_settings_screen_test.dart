import 'dart:async';
import 'dart:convert';

import 'package:flick/features/discovery/discovery_models.dart';
import 'package:flick/features/discovery/discovery_settings.dart';
import 'package:flick/features/discovery/source_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _alpha = DiscoveryAddonConfig(
  id: 'alpha',
  label: 'Alpha',
  endpoint: 'https://alpha.example/private-alpha',
  token: 'alpha-secret',
  enabled: true,
);
const _beta = DiscoveryAddonConfig(
  id: 'beta',
  label: 'Beta',
  endpoint: 'https://beta.example/private-beta',
  token: 'beta-secret',
  enabled: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('empty settings are off and saving makes no network request', (
    tester,
  ) async {
    final store = DiscoverySettingsStore();
    final client = _TestClient();
    addTearDown(client.close);
    final route = await _open(tester, store: store, client: client);

    expect(find.textContaining('No music addons added.'), findsOneWidget);
    expect(_switch(tester, 'youtube-enabled').value, isFalse);
    expect(client.requests, isEmpty);
    await _tap(tester, _key('save-sources'));

    expect(route.completed, isTrue);
    expect(route.result!.hasSource, isFalse);
    expect(route.result!.addons, isEmpty);
    expect((await store.load()).hasSource, isFalse);
    expect(client.requests, isEmpty);
    expect(client.closed, isFalse);
  });

  testWidgets('add edit reorder remove and disable persist only on Save', (
    tester,
  ) async {
    final store = DiscoverySettingsStore();
    await store.save(const DiscoverySettings(addons: [_alpha, _beta]));
    final client = _TestClient();
    addTearDown(client.close);
    final route = await _open(tester, store: store, client: client);

    await _tap(tester, _key('add-addon'));
    await _fillAddon(
      tester,
      label: 'Gamma',
      endpoint: 'https://gamma.example/music/manifest.json',
      token: 'gamma-secret',
    );
    await _tap(tester, _key('apply-addon'));
    final gammaId = _idForName(tester, 'Gamma');
    expect(gammaId, isNot(anyOf('alpha', 'beta')));
    expect(_switch(tester, 'enabled-addon-$gammaId').value, isFalse);

    // Disabled configurations remain editable and retain their credentials.
    await _tap(tester, _key('enabled-addon-alpha'));
    await _tap(tester, _key('edit-addon-alpha'));
    await tester.enterText(_key('addon-label'), 'Alpha renamed');
    expect(_field(tester, 'addon-token').controller!.text, 'alpha-secret');
    await _tap(tester, _key('apply-addon'));
    await _tap(tester, _key('enabled-addon-$gammaId'));
    await _tap(tester, _key('move-up-addon-$gammaId'));
    await _tap(tester, _key('move-up-addon-$gammaId'));
    expect(
      tester.widget<IconButton>(_key('move-up-addon-$gammaId')).onPressed,
      isNull,
    );
    await _tap(tester, _key('move-down-addon-$gammaId'));
    await _tap(tester, _key('remove-addon-beta'));
    await _tap(tester, _key('youtube-enabled'));

    final beforeSave = await store.load();
    expect(beforeSave.addons.map((addon) => addon.id), ['alpha', 'beta']);
    expect(beforeSave.addons.first.enabled, isTrue);
    expect(beforeSave.addons.first.label, 'Alpha');
    expect(beforeSave.youtubeEnabled, isFalse);
    _expectNoSecrets();
    expect(find.textContaining('gamma-secret'), findsNothing);
    expect(find.textContaining('https://gamma.example'), findsNothing);

    await _tap(tester, _key('save-sources'));
    expect(route.completed, isTrue);
    final restored = await DiscoverySettingsStore().load();
    expect(restored.youtubeEnabled, isTrue);
    expect(restored.addons.map((addon) => addon.id), ['alpha', gammaId]);
    expect(restored.addons.first.label, 'Alpha renamed');
    expect(restored.addons.first.enabled, isFalse);
    expect(restored.addons.first.token, 'alpha-secret');
    expect(restored.addons.last.endpoint, 'https://gamma.example/music');
    expect(restored.addons.last.token, 'gamma-secret');
    expect(restored.activeAddons.single.id, gammaId);
    expect(route.result!.addons.map((addon) => addon.id), ['alpha', gammaId]);
    expect(client.requests, isEmpty);

    await _tap(tester, find.text('Open sources'));
    expect(find.text('Alpha renamed'), findsOneWidget);
    expect(find.text('Gamma'), findsOneWidget);
    expect(_switch(tester, 'enabled-addon-alpha').value, isFalse);
    expect(_switch(tester, 'enabled-addon-$gammaId').value, isTrue);
  });

  testWidgets('editor and screen cancellation leave the store intact', (
    tester,
  ) async {
    final original = DiscoverySettings(addons: [_alpha, _beta]);
    final store = _MemoryStore(original);
    final route = await _open(tester, store: store);

    await _tap(tester, _key('edit-addon-alpha'));
    await tester.enterText(_key('addon-label'), 'Discarded name');
    await tester.enterText(_key('addon-endpoint'), 'https://discard.example');
    await _tap(tester, find.text('Cancel'));
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Discarded name'), findsNothing);

    await _tap(tester, _key('edit-addon-alpha'));
    expect(_field(tester, 'addon-token').controller!.text, 'alpha-secret');
    await tester.enterText(_key('addon-label'), 'Draft name');
    await _tap(tester, _key('apply-addon'));
    await _tap(tester, _key('move-up-addon-beta'));
    await _tap(tester, _key('enabled-addon-alpha'));
    await _tap(tester, _key('remove-addon-beta'));
    await _tap(tester, _key('add-addon'));
    await _fillAddon(tester, endpoint: 'https://draft.example');
    await _tap(tester, _key('apply-addon'));
    await _tap(tester, _key('youtube-enabled'));
    await _tap(tester, find.text('Cancel'));

    expect(route.completed, isTrue);
    expect(route.result, isNull);
    expect(store.saves, 0);
    expect(await store.load(), same(original));
    expect(original.addons, [_alpha, _beta]);
    expect(original.addons.first.enabled, isTrue);
    expect(original.addons.first.token, 'alpha-secret');
    expect(original.youtubeEnabled, isFalse);
  });

  testWidgets('editing an endpoint clears the obscured token before saving', (
    tester,
  ) async {
    final store = _MemoryStore(const DiscoverySettings(addons: [_alpha]));
    await _open(tester, store: store);
    await _tap(tester, _key('edit-addon-alpha'));
    expect(_field(tester, 'addon-token').obscureText, isTrue);
    expect(_field(tester, 'addon-token').controller!.text, 'alpha-secret');
    await tester.enterText(_key('addon-endpoint'), 'https://changed.example');
    expect(_field(tester, 'addon-token').controller!.text, isEmpty);
    await _tap(tester, _key('apply-addon'));
    await _tap(tester, _key('save-sources'));

    final restored = await store.load();
    expect(restored.addons.single.id, 'alpha');
    expect(restored.addons.single.endpoint, 'https://changed.example');
    expect(restored.addons.single.token, isEmpty);
    expect(restored.addons.single.enabled, isTrue);
  });

  testWidgets('editor rejects invalid URLs tokens labels and duplicates', (
    tester,
  ) async {
    final store = _MemoryStore(const DiscoverySettings(addons: [_alpha]));
    final client = _TestClient();
    addTearDown(client.close);
    await _open(tester, store: store, client: client);
    await _tap(tester, _key('add-addon'));

    await _tap(tester, _key('apply-addon'));
    expect(find.textContaining('Use an absolute HTTPS URL'), findsOneWidget);
    await tester.enterText(
      _key('addon-endpoint'),
      'http://private.example/secret',
    );
    await _tap(tester, _key('apply-addon'));
    expect(find.textContaining('Use an absolute HTTPS URL'), findsOneWidget);

    await _fillAddon(
      tester,
      endpoint: 'https://valid.example',
      token: 'invalid token',
    );
    await _tap(tester, _key('apply-addon'));
    expect(
      find.textContaining('bearer token contains invalid'),
      findsOneWidget,
    );
    await _fillAddon(tester, endpoint: '${_alpha.endpoint}/manifest.json');
    await _tap(tester, _key('apply-addon'));
    expect(find.text('Each music addon must be unique.'), findsOneWidget);

    await _fillAddon(
      tester,
      label: List.filled(81, 'x').join(),
      endpoint: 'https://valid.example',
    );
    await _tap(tester, _key('apply-addon'));
    expect(find.text('The addon label is invalid.'), findsOneWidget);
    expect(store.saves, 0);
    expect(store.settings.addons, [_alpha]);
    expect(client.requests, isEmpty);

    await tester.enterText(_key('addon-label'), '');
    await _tap(tester, _key('apply-addon'));
    expect(find.text('Music addon'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await _tap(tester, _key('save-sources'));
    expect(store.settings.addons.last.displayName, 'Music addon');
    expect(store.settings.addons.last.enabled, isFalse);
  });

  testWidgets('Save rejects invalid drafts without persisting or popping', (
    tester,
  ) async {
    final store = _MemoryStore(const DiscoverySettings());
    final route = await _open(
      tester,
      store: store,
      initial: DiscoverySettings(
        addons: [
          _alpha,
          DiscoveryAddonConfig(id: 'duplicate', endpoint: _alpha.endpoint),
        ],
      ),
    );
    await _tap(tester, _key('save-sources'));
    expect(find.text('Each music addon must be unique.'), findsOneWidget);
    expect(find.text('Online sources'), findsOneWidget);
    expect(route.completed, isFalse);
    expect(store.saves, 0);
    _expectNoSecrets();
  });

  testWidgets('eight addons is the limit and removal makes room in the draft', (
    tester,
  ) async {
    final original = DiscoverySettings(
      addons: List.generate(
        DiscoverySettings.maxAddons,
        (index) => DiscoveryAddonConfig(
          id: 'addon-$index',
          label: 'Source $index',
          endpoint: 'https://source-$index.example',
        ),
      ),
    );
    final store = _MemoryStore(original);
    await _open(tester, store: store);
    await tester.scrollUntilVisible(
      _key('add-addon'),
      400,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(_key('add-addon')).onPressed, isNull);
    expect(find.textContaining('Maximum of 8 addons.'), findsOneWidget);
    await _tap(tester, _key('remove-addon-addon-7'));
    expect(
      tester.widget<OutlinedButton>(_key('add-addon')).onPressed,
      isNotNull,
    );
    await _tap(tester, _key('add-addon'));
    await _fillAddon(tester, endpoint: 'https://replacement.example');
    await _tap(tester, _key('apply-addon'));
    await _tap(tester, _key('save-sources'));
    expect(store.settings.addons.length, 8);
    expect(store.settings.addons.last.endpoint, 'https://replacement.example');
    expect(original.addons.length, 8);
  });

  testWidgets('failed persistence keeps the draft and a safe retry error', (
    tester,
  ) async {
    const original = DiscoverySettings(addons: [_alpha]);
    final store = _MemoryStore(original)
      ..failure = const DiscoveryException(
        'https://alpha.example/private-alpha alpha-secret',
      );
    final route = await _open(tester, store: store);
    await _tap(tester, _key('enabled-addon-alpha'));
    await _tap(tester, _key('save-sources'));

    expect(route.completed, isFalse);
    expect(store.settings, same(original));
    expect(_switch(tester, 'enabled-addon-alpha').value, isFalse);
    expect(_switch(tester, 'enabled-addon-alpha').onChanged, isNotNull);
    expect(
      find.text('Source settings could not be saved securely. Try again.'),
      findsOneWidget,
    );
    _expectNoSecrets();
    store.failure = null;
    await _tap(tester, _key('save-sources'));
    expect(route.completed, isTrue);
    expect(route.result!.addons.single.enabled, isFalse);
    expect(store.settings.addons.single.enabled, isFalse);
    expect(store.saves, 2);
  });

  testWidgets('pending persistence locks edits and back until success', (
    tester,
  ) async {
    const original = DiscoverySettings(addons: [_alpha]);
    final pending = Completer<void>();
    final store = _MemoryStore(original)..pendingSave = pending;
    final route = await _open(tester, store: store);
    await _tap(tester, _key('youtube-enabled'));
    await _tap(tester, _key('save-sources'));

    expect(find.text('Saving securely…'), findsOneWidget);
    expect(_switch(tester, 'youtube-enabled').onChanged, isNull);
    expect(_switch(tester, 'enabled-addon-alpha').onChanged, isNull);
    for (final action in ['edit', 'remove', 'move-up', 'move-down']) {
      expect(
        tester.widget<IconButton>(_key('$action-addon-alpha')).onPressed,
        isNull,
      );
    }
    expect(tester.widget<OutlinedButton>(_key('add-addon')).onPressed, isNull);
    expect(tester.widget<FilledButton>(_key('save-sources')).onPressed, isNull);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
          .onPressed,
      isNull,
    );
    await route.navigator.currentState!.maybePop();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(route.completed, isFalse);
    expect(store.settings, same(original));
    expect(store.saves, 1);

    pending.complete();
    await tester.pumpAndSettle();
    expect(route.completed, isTrue);
    expect(route.result!.youtubeEnabled, isTrue);
    expect(store.settings.youtubeEnabled, isTrue);
    expect(store.settings.addons.single.token, 'alpha-secret');
  });

  testWidgets('only Test endpoint connects and health messages stay safe', (
    tester,
  ) async {
    final store = _MemoryStore(const DiscoverySettings(addons: [_alpha]));
    var response = _manifest();
    final client = _TestClient((_) async => response);
    addTearDown(client.close);
    await _open(tester, store: store, client: client);
    await _tap(tester, _key('edit-addon-alpha'));
    expect(client.requests, isEmpty);
    await _testEndpoint(tester);

    expect(client.requests.length, 1);
    expect(client.requests.single.method, 'GET');
    expect(
      client.requests.single.url.toString(),
      '${_alpha.endpoint}/manifest.json',
    );
    expect(
      client.requests.single.headers['Authorization'],
      'Bearer alpha-secret',
    );
    expect(find.textContaining('Manifest reachable;'), findsOneWidget);
    expect(
      find.textContaining('https://alpha.example/private-alpha alpha-secret'),
      findsNothing,
    );

    response = _manifest(allowDownloads: false);
    await _testEndpoint(tester);
    expect(find.textContaining('disallows downloads.'), findsOneWidget);
    response = http.Response('private-alpha alpha-secret', 401);
    await _testEndpoint(tester);
    expect(
      find.text('The source refused access. Check its configuration or token.'),
      findsOneWidget,
    );
    expect(find.textContaining('private-alpha alpha-secret'), findsNothing);
    await _tap(tester, find.text('Cancel'));
    await _tap(tester, find.text('Cancel'));
    expect(client.requests.length, 3);
    expect(client.closed, isFalse);
    expect(store.saves, 0);
  });

  testWidgets('stale health cannot overwrite or unlock a newer test', (
    tester,
  ) async {
    final store = _MemoryStore(const DiscoverySettings(addons: [_alpha]));
    final first = Completer<http.Response>();
    final second = Completer<http.Response>();
    var requestCount = 0;
    final client = _TestClient(
      (_) => ++requestCount == 1 ? first.future : second.future,
    );
    addTearDown(client.close);
    await _open(tester, store: store, client: client);
    await _tap(tester, _key('edit-addon-alpha'));
    await tester.tap(_key('test-endpoint'));
    await tester.pump();
    expect(client.requests.length, 1);
    expect(tester.widget<FilledButton>(_key('apply-addon')).onPressed, isNull);

    await tester.enterText(_key('addon-endpoint'), 'https://new.example/music');
    await tester.pumpAndSettle();
    expect(_field(tester, 'addon-token').controller!.text, isEmpty);
    expect(find.textContaining('Manifest reachable;'), findsNothing);
    await tester.tap(_key('test-endpoint'));
    await tester.pump();
    expect(client.requests.length, 2);
    expect(client.requests.last.headers.containsKey('Authorization'), isFalse);

    first.complete(_manifest(allowDownloads: false));
    await tester.pump();
    expect(find.textContaining('disallows downloads.'), findsNothing);
    expect(find.text('Checking manifest…'), findsOneWidget);
    expect(tester.widget<FilledButton>(_key('apply-addon')).onPressed, isNull);
    expect(store.saves, 0);

    // Drain the mock response stream on the real async event loop.
    await tester.runAsync(() async {
      second.complete(_manifest());
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Manifest reachable;'), findsOneWidget);
    await tester.enterText(_key('addon-label'), 'Updated source');
    await tester.pump();
    expect(find.textContaining('Manifest reachable;'), findsNothing);
    await _tap(tester, _key('apply-addon'));
    await _tap(tester, _key('save-sources'));
    expect(store.settings.addons.single.endpoint, 'https://new.example/music');
    expect(store.settings.addons.single.token, isEmpty);
    expect(store.settings.addons.single.label, 'Updated source');
    expect(client.requests.length, 2);
  });

  testWidgets('cancelling the editor ignores late health responses', (
    tester,
  ) async {
    final store = _MemoryStore(const DiscoverySettings(addons: [_alpha]));
    final response = Completer<http.Response>();
    final client = _TestClient((_) => response.future);
    addTearDown(client.close);
    final route = await _open(tester, store: store, client: client);
    await _tap(tester, _key('edit-addon-alpha'));
    await tester.tap(_key('test-endpoint'));
    await tester.pump();
    expect(client.requests.length, 1);
    await _tap(tester, find.text('Cancel'));
    await _tap(tester, find.text('Cancel'));
    response.complete(_manifest());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(route.completed, isTrue);
    expect(route.result, isNull);
    expect(find.textContaining('Manifest reachable;'), findsNothing);
    expect(store.saves, 0);
    expect(client.closed, isFalse);
  });
}

Finder _key(String value) => find.byKey(ValueKey(value));

TextField _field(WidgetTester tester, String key) =>
    tester.widget<TextField>(_key(key));

SwitchListTile _switch(WidgetTester tester, String key) =>
    tester.widget<SwitchListTile>(_key(key));

String _idForName(WidgetTester tester, String name) {
  final tile = tester
      .widgetList<SwitchListTile>(find.byType(SwitchListTile))
      .singleWhere(
        (tile) => tile.title is Text && (tile.title! as Text).data == name,
      );
  return (tile.key! as ValueKey<String>).value.substring(
    'enabled-addon-'.length,
  );
}

void _expectNoSecrets() {
  for (final secret in [
    'alpha-secret',
    'beta-secret',
    'private-alpha',
    'private-beta',
    'https://alpha.example',
    'https://beta.example',
  ]) {
    expect(find.textContaining(secret), findsNothing);
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _testEndpoint(WidgetTester tester) async {
  await tester.ensureVisible(_key('test-endpoint'));
  // MockClient's response stream cleanup needs the real async event loop.
  await tester.runAsync(() async {
    await tester.tap(_key('test-endpoint'));
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
}

Future<void> _fillAddon(
  WidgetTester tester, {
  String label = '',
  required String endpoint,
  String token = '',
}) async {
  await tester.enterText(_key('addon-label'), label);
  await tester.enterText(_key('addon-endpoint'), endpoint);
  await tester.enterText(_key('addon-token'), token);
}

Future<_RouteResult> _open(
  WidgetTester tester, {
  required DiscoverySettingsStore store,
  DiscoverySettings? initial,
  http.Client? client,
}) async {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final route = _RouteResult();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: route.navigator,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              route.completed = false;
              route.result = await Navigator.of(context)
                  .push<DiscoverySettings>(
                    MaterialPageRoute(
                      builder: (_) => SourceSettingsScreen(
                        initial: initial,
                        store: store,
                        client: client,
                      ),
                    ),
                  );
              route.completed = true;
            },
            child: const Text('Open sources'),
          ),
        ),
      ),
    ),
  );
  await _tap(tester, find.text('Open sources'));
  return route;
}

class _RouteResult {
  final navigator = GlobalKey<NavigatorState>();
  bool completed = false;
  DiscoverySettings? result;
}

class _MemoryStore extends DiscoverySettingsStore {
  _MemoryStore(this.settings);
  DiscoverySettings settings;
  int saves = 0;
  Object? failure;
  Completer<void>? pendingSave;

  @override
  Future<DiscoverySettings> load() async => settings;

  @override
  Future<void> save(DiscoverySettings value) async {
    saves++;
    await pendingSave?.future;
    if (failure != null) throw failure!;
    settings = value.validated();
  }
}

class _TestClient extends MockClient {
  _TestClient([Future<http.Response> Function(http.Request)? handler])
    : super(handler ?? ((_) async => http.Response('', 500)));

  final requests = <http.BaseRequest>[];
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return super.send(request);
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

http.Response _manifest({bool allowDownloads = true}) => http.Response(
  jsonEncode({
    'id': 'test-addon',
    'name': 'https://alpha.example/private-alpha alpha-secret',
    'resources': ['search', 'stream'],
    'allowDownloads': allowDownloads,
  }),
  200,
);
