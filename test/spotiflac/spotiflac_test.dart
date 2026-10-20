import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flick/features/spotiflac/spotiflac_host.dart';
import 'package:flick/features/spotiflac/spotiflac_network.dart';
import 'package:flick/features/spotiflac/spotiflac_packages.dart';
import 'package:flick/features/spotiflac/spotiflac_runtime.dart';
import 'package:flick/features/spotiflac/spotiflac_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'spotiflac_fakes.dart';

void main() {
  late Directory dir;
  late FakeNative native;
  late MemoryVault vault;
  late SpotiflacStorage storage;
  final namespace = spotiflacKeyOf('deezer');

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('spotiflac');
    native = FakeNative();
    vault = MemoryVault();
    storage = SpotiflacStorage(dir, sealer: native, vault: vault);
    await storage.open();
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  group('storage', () {
    test('keeps add-on storage plain and everything else sealed', () {
      storage.write(namespace, 'storage', {'a': 1});
      storage.write(namespace, 'credentials', {'token': 'secret'});

      final plain = File(p.join(dir.path, 'data', namespace, 'storage.json'));
      final sealed = File(
        p.join(dir.path, 'data', namespace, 'credentials.enc'),
      );
      expect(jsonDecode(plain.readAsStringSync()), {'a': 1});
      expect(
        utf8.decode(sealed.readAsBytesSync(), allowMalformed: true),
        isNot(contains('secret')),
      );
      expect(storage.read(namespace, 'credentials'), {'token': 'secret'});
    });

    test(
      'a lost key discards sealed records but keeps plain storage',
      () async {
        storage.write(namespace, 'storage', {'a': 1});
        storage.write(namespace, 'credentials', {'token': 'secret'});

        vault.key = null;
        final reopened = SpotiflacStorage(dir, sealer: native, vault: vault);
        await reopened.open();

        expect(reopened.read(namespace, 'credentials'), isEmpty);
        expect(reopened.read(namespace, 'storage'), {'a': 1});
        expect(vault.key, hasLength(32));
      },
    );

    test('rejects namespaces that could escape its folder', () {
      expect(() => storage.read('../x', 'storage'), throwsArgumentError);
      expect(() => storage.read(namespace, 'Settings'), throwsArgumentError);
    });

    test('update and forget', () {
      storage.update(namespace, 'storage', 'k', 'v');
      expect(storage.read(namespace, 'storage'), {'k': 'v'});
      storage.update(namespace, 'storage', 'k', null, remove: true);
      expect(storage.read(namespace, 'storage'), isEmpty);
      storage.update(namespace, 'storage', 'k', 'v');
      storage.forget(namespace);
      expect(
        Directory(p.join(dir.path, 'data', namespace)).existsSync(),
        isFalse,
      );
    });
  });

  group('network rules', () {
    test('private addresses', () {
      for (final address in [
        '127.0.0.1',
        '10.1.2.3',
        '192.168.0.4',
        '172.20.0.1',
        '169.254.1.1',
        '::1',
        'fe80::1',
        'fc00::2',
      ]) {
        expect(spotiflacPrivateAddress(address), isTrue, reason: address);
      }
      expect(spotiflacPrivateAddress('8.8.8.8'), isFalse);
      expect(spotiflacPrivateAddress('172.32.0.1'), isFalse);
    });

    test('domain permissions and wildcards', () {
      expect(
        spotiflacDomainAllowed('api.deezer.com', ['*.deezer.com']),
        isTrue,
      );
      expect(spotiflacDomainAllowed('deezer.com', ['deezer.com']), isTrue);
      expect(
        spotiflacDomainAllowed('evildeezer.com', ['*.deezer.com']),
        isFalse,
      );
      const permissions = SpotiflacPermissions(network: ['api.example.com']);
      expect(
        spotiflacValidateUrl('https://api.example.com/x', permissions).path,
        '/x',
      );
      expect(
        () => spotiflacValidateUrl('https://other.com/', permissions),
        throwsA(isA<SpotiflacNetworkException>()),
      );
      expect(
        () => spotiflacValidateUrl('http://api.example.com/', permissions),
        throwsA(isA<SpotiflacNetworkException>()),
      );
      expect(
        () => spotiflacValidateUrl('https://u:p@api.example.com/', permissions),
        throwsA(isA<SpotiflacNetworkException>()),
      );
    });

    test('cookie jar scopes cookies by domain, path and expiry', () {
      final jar = SpotiflacCookieJar();
      final url = Uri.parse('https://www.example.com/app/page');
      final now = DateTime.now();
      jar.store('sid=1; Domain=example.com; Path=/', url, now: now);
      jar.store('app=2; Path=/app', url, now: now);
      jar.store('old=3; Max-Age=10', url, now: now);

      expect(
        jar.header(Uri.parse('https://api.example.com/'), now: now),
        'sid=1',
      );
      expect(jar.header(url, now: now).split('; ')..sort(), [
        'app=2',
        'old=3',
        'sid=1',
      ]);
      expect(
        jar.header(url, now: now.add(const Duration(seconds: 11))),
        isNot(contains('old=3')),
      );
      expect(jar.header(Uri.parse('https://other.com/'), now: now), isEmpty);

      final copy = SpotiflacCookieJar.fromJson(jar.toJson());
      expect(copy.header(url, now: now), jar.header(url, now: now));
    });
  });

  group('network requests', () {
    late HttpServer server;
    late String base;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}';
      server.listen((request) async {
        final response = request.response;
        switch (request.uri.path) {
          case '/login':
            response.headers.add('set-cookie', 'sid=abc; Path=/');
            response.write('ok');
          case '/echo':
            response.headers.contentType = ContentType.json;
            response.write(
              jsonEncode({
                'cookie': request.headers.value('cookie'),
                'auth': request.headers.value('authorization'),
              }),
            );
          case '/away':
            response.statusCode = 302;
            response.headers.set('location', 'https://elsewhere.test/');
          case '/hop':
            response.statusCode = 302;
            response.headers.set('location', '/echo');
          default:
            response.statusCode = 404;
        }
        await response.close();
      });
    });

    tearDown(() => server.close(force: true));

    SpotiflacNetwork network([List<String> domains = const ['127.0.0.1']]) =>
        SpotiflacNetwork(
          SpotiflacPermissions(network: domains, allowHttp: true),
        );

    test(
      'keeps cookies between requests and follows local redirects',
      () async {
        final net = network();
        await net.jsonResponse('$base/login');
        final reply = await net.jsonResponse(
          '$base/hop',
          headers: {'Authorization': 'Bearer t'},
        );
        expect(reply['status'], 200);
        final body = jsonDecode('${reply['body']}') as Map;
        expect(body['cookie'], 'sid=abc');
        expect(body['auth'], 'Bearer t');
        net.close();
      },
    );

    test('refuses redirects to hosts outside its permissions', () async {
      final net = network();
      await expectLater(
        net.jsonResponse('$base/away'),
        throwsA(isA<SpotiflacNetworkException>()),
      );
      net.close();
    });

    test('refuses private addresses that were not asked for', () async {
      final net = SpotiflacNetwork(
        const SpotiflacPermissions(network: ['local.test'], allowHttp: true),
        lookup: (_) async => [InternetAddress.loopbackIPv4],
      );
      await expectLater(
        net.jsonResponse('http://local.test:${server.port}/echo'),
        throwsA(isA<SpotiflacNetworkException>()),
      );
      net.close();
    });
  });

  group('host', () {
    SpotiflacHost host({bool storagePermission = true}) => SpotiflacHost(
      addon: SpotiflacAddonInfo(
        key: namespace,
        name: 'deezer',
        manifest: {
          'permissions': {
            'network': ['api.example.com'],
            'storage': storagePermission,
            'file': true,
          },
        },
      ),
      storage: storage,
      network: SpotiflacNetwork(
        const SpotiflacPermissions(network: ['api.example.com']),
      ),
      native: native,
      root: p.join(dir.path, 'files'),
    );

    Future<void> noCallback(
      Object? descriptor,
      List<Object?> args, {
      bool strict = false,
    }) async {}

    test('storage and credentials need the storage permission', () async {
      final allowed = host();
      await allowed.call('storage.set', ['k', 1], noCallback);
      expect(await allowed.call('storage.get', ['k'], noCallback), {
        'found': true,
        'value': 1,
      });
      await allowed.call('credentials.set', ['t', 'x'], noCallback);
      expect(storage.read(namespace, 'credentials'), {'t': 'x'});

      expect(
        host(storagePermission: false).call('storage.get', ['k'], noCallback),
        throwsStateError,
      );
    });

    test('files stay inside the add-on folder', () async {
      final h = host();
      final written = await h.call('file.write', [
        'a/b.txt',
        'hello',
      ], noCallback);
      expect(written, isA<Map>());
      expect(await h.call('file.exists', ['a/b.txt'], noCallback), isTrue);
      expect(() => h.file('../outside.txt'), throwsArgumentError);
      expect(() => h.file(p.join(dir.path, 'x.txt')), throwsStateError);
    });

    test('helpers match desktop', () async {
      final h = host();
      expect(
        await h.call('utils.md5', ['abc'], noCallback),
        md5.convert(utf8.encode('abc')).toString(),
      );
      expect(
        await h.call('gobackend.buildFilename', [
          '{artist} - {title}',
          {'artist': 'AC/DC', 'title': 'T.N.T.'},
        ], noCallback),
        isNot(contains('/')),
      );
      expect(
        (await h.call('url.parse', ['https://a.com/p?q=1#f', null], noCallback)
            as Map)['hostname'],
        'a.com',
      );
      expect(
        await h.call('ffmpeg.execute', ['-i x'], noCallback),
        containsPair('success', false),
      );
      expect(h.call('nope.method', const [], noCallback), throwsStateError);
    });

    test('abort cancels sleeps', () async {
      final h = host();
      final sleeping = h.call('utils.sleep', [60000], noCallback);
      h.abort();
      await expectLater(sleeping, throwsA(isA<SpotiflacCancelled>()));
    });
  });

  group('runtime', () {
    late FakeEngine engine;
    late SpotiflacHost host;

    setUp(() {
      engine = FakeEngine();
      host = SpotiflacHost(
        addon: SpotiflacAddonInfo(
          key: namespace,
          name: 'deezer',
          manifest: const {
            'permissions': {'network': <String>[], 'storage': true},
          },
        ),
        storage: storage,
        network: SpotiflacNetwork(const SpotiflacPermissions()),
        native: native,
        root: p.join(dir.path, 'files'),
      );
    });

    test('calls run one at a time and reach the host', () async {
      final order = <String>[];
      engine.scripts['code'] = {
        'slow': (args, call) async {
          order.add('slow start');
          await Future<void>.delayed(const Duration(milliseconds: 30));
          order.add('slow end');
          return 1;
        },
        'fast': (args, call) async {
          order.add('fast');
          return call('utils.sha256', ['x']);
        },
        'broken': (args, call) => call('storage.nope', const []),
      };
      final runtime = await SpotiflacRuntime.start(
        'code',
        const {},
        host,
        starter: engine.start,
      );
      final results = await Future.wait([
        runtime.invoke('slow'),
        runtime.invoke('fast'),
      ]);
      expect(order, ['slow start', 'slow end', 'fast']);
      expect(results.last, sha256.convert(utf8.encode('x')).toString());
      expect(runtime.methods, containsAll(['slow', 'fast']));
      expect(runtime.closed, isFalse);
    });

    test('a call that times out stops the add-on', () async {
      engine.scripts['code'] = {
        'hang': (args, call) => Completer<Object?>().future,
      };
      final runtime = await SpotiflacRuntime.start(
        'code',
        const {},
        host,
        starter: engine.start,
      );
      await expectLater(
        runtime.invoke('hang', const [], const Duration(milliseconds: 20)),
        throwsA(
          isA<SpotiflacRuntimeError>().having(
            (e) => e.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
      expect(runtime.closed, isTrue);
      expect(host.aborted, isTrue);
      await expectLater(
        runtime.invoke('hang'),
        throwsA(isA<SpotiflacRuntimeError>()),
      );
    });
  });

  group('manifests', () {
    test('accepts a download provider', () {
      expect(spotiflacValidateManifest(manifestFor('qobuz'))['name'], 'qobuz');
    });

    test('rejects what desktop rejects', () {
      Matcher fails(String text) => throwsA(
        isA<SpotiflacPackageError>().having(
          (e) => e.message,
          'message',
          contains(text),
        ),
      );
      expect(
        () => spotiflacValidateManifest({...manifestFor('x'), 'name': 'Bad!'}),
        fails('manifest'),
      );
      expect(
        () => spotiflacValidateManifest({
          ...manifestFor('x'),
          'type': ['lyrics_provider'],
        }),
        fails('download-capable'),
      );
      expect(
        () => spotiflacValidateManifest({
          ...manifestFor('x'),
          'minAppVersion': '99.0.0',
        }),
        fails('compatibility'),
      );
      expect(
        () => spotiflacValidateManifest({
          ...manifestFor('x'),
          'requiredRuntimeFeatures': ['teleport@1'],
        }),
        fails('teleport'),
      );
      expect(
        () =>
            spotiflacValidateManifest(manifestFor('x', network: ['bad host/'])),
        fails('network'),
      );
    });

    test('version comparison', () {
      expect(spotiflacCompareVersions('1.10.0', '1.9.9'), greaterThan(0));
      expect(spotiflacCompareVersions('1.0.0', '1.0.0'), 0);
      expect(spotiflacCompareVersions(null, '0.0.1'), lessThan(0));
    });

    test('archives need manifest.json and index.js and safe paths', () {
      expect(
        () => spotiflacReadArchive(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<SpotiflacPackageError>()),
      );
      final ok = spotiflacReadArchive(
        packageBytes(manifestFor('qobuz'), 'code'),
      );
      expect(ok.code, 'code');
    });
  });

  group('package manager', () {
    late FakeEngine engine;
    late SpotiflacPackages packages;
    final served = <String, Uint8List>{};

    Map<String, GuestMethod> downloader({String? payload}) => {
      'initialize': (args, call) async => true,
      'searchTracks': (args, call) async => [
        {
          'id': 't1',
          'name': 'Song',
          'artists': 'Artist',
          'album_name': 'Album',
          'duration_ms': 180000,
        },
        {'id': 'a1', 'name': 'An album', 'item_type': 'album'},
      ],
      'download': (args, call) async {
        final path = '${args[2]}';
        await call('file.write', [path, payload ?? 'audio']);
        return {'success': true, 'file_path': path};
      },
    };

    setUp(() async {
      engine = FakeEngine();
      served.clear();
      packages = SpotiflacPackages(
        dir,
        storage: storage,
        native: native,
        starter: engine.start,
        fetch: (url, max) async {
          final body = served[url];
          if (body == null) throw const SpotiflacPackageError('HTTP 404');
          return body;
        },
      );
      await packages.load();
    });

    tearDown(() => packages.shutdown());

    test('starts with the official repository', () {
      expect(packages.repositories.single.url, spotiflacRegistry);
      expect(packages.repositories.single.official, isTrue);
    });

    test(
      'installs from a file, survives a reload, and removes cleanly',
      () async {
        engine.scripts['v1'] = downloader();
        final addon = await packages.install(
          bytes: packageBytes(manifestFor('qobuz'), 'v1'),
        );
        expect(addon.displayName, 'QOBUZ');
        expect(addon.methods, contains('download'));

        final again = SpotiflacPackages(
          dir,
          storage: storage,
          native: native,
          starter: engine.start,
        );
        await again.load();
        expect(again.find(addon.key)?.version, '1.0.0');

        await packages.remove(addon.key);
        expect(packages.find(addon.key), isNull);
        expect(
          Directory(p.join(dir.path, 'packages', addon.key)).existsSync(),
          isFalse,
        );
      },
    );

    test('refuses packages without the methods they promise', () async {
      engine.scripts['empty'] = {'initialize': (args, call) async => true};
      await expectLater(
        packages.install(bytes: packageBytes(manifestFor('qobuz'), 'empty')),
        throwsA(isA<SpotiflacPackageError>()),
      );
      expect(packages.addons, isEmpty);
    });

    test('updates but never downgrades', () async {
      engine.scripts['v1'] = downloader();
      engine.scripts['v2'] = downloader();
      await packages.install(
        bytes: packageBytes(manifestFor('qobuz', version: '1.2.0'), 'v1'),
      );
      await expectLater(
        packages.install(
          bytes: packageBytes(manifestFor('qobuz', version: '1.1.0'), 'v2'),
        ),
        throwsA(isA<SpotiflacPackageError>()),
      );
      final updated = await packages.install(
        bytes: packageBytes(manifestFor('qobuz', version: '2.0.0'), 'v2'),
      );
      expect(updated.version, '2.0.0');
    });

    test('installs from a repository and checks its SHA-256', () async {
      engine.scripts['v1'] = downloader();
      final bytes = packageBytes(manifestFor('tidal'), 'v1');
      const repo = 'https://repo.example.com/registry.json';
      const download = 'https://repo.example.com/tidal.sflx';
      Map<String, Object?> entry(String digest) => {
        'id': 'tidal',
        'name': 'Tidal',
        'version': '1.0.0',
        'category': 'download',
        'sha256': digest,
        'download_url': download,
      };
      served[download] = bytes;
      served[repo] = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'version': 1,
            'name': 'Friends',
            'extensions': [entry('0' * 64)],
          }),
        ),
      );
      final added = await packages.addRepo('https://repo.example.com/');
      expect(added.url, repo);
      expect(added.name, 'Friends');
      expect(packages.catalogue(added.id).single.name, 'Tidal');

      await expectLater(
        packages.install(repositoryId: added.id, id: 'tidal'),
        throwsA(
          isA<SpotiflacPackageError>().having(
            (e) => e.message,
            'message',
            contains('SHA-256'),
          ),
        ),
      );

      served[repo] = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'version': 1,
            'extensions': [entry(sha256.convert(bytes).toString())],
          }),
        ),
      );
      await packages.refreshRepo(added.id);
      final addon = await packages.install(repositoryId: added.id, id: 'tidal');
      expect(addon.repositoryId, added.id);
      expect(packages.catalogue(added.id).single.installed, isNotNull);
      expect(
        () => packages.addRepo('http://repo.example.com/'),
        throwsA(isA<SpotiflacPackageError>()),
      );
    });

    test('settings start from the schema defaults', () async {
      engine.scripts['v1'] = downloader();
      final addon = await packages.install(
        bytes: packageBytes(
          manifestFor(
            'qobuz',
            extra: {
              'settings': [
                {'key': 'region', 'type': 'string', 'default': 'us'},
              ],
            },
          ),
          'v1',
        ),
      );
      expect(packages.settings(addon)['region'], 'us');
    });

    test(
      'searches keep only songs; a turned-off add-on is unavailable',
      () async {
        engine.scripts['v1'] = downloader();
        final addon = await packages.install(
          bytes: packageBytes(manifestFor('qobuz'), 'v1'),
        );
        final songs = await packages.search(addon.key, 'song');
        expect(songs.map((s) => s.id), ['t1']);
        expect(songs.single.duration, const Duration(minutes: 3));

        packages.setEnabled(addon.key, false);
        await expectLater(
          packages.search(addon.key, 'song'),
          throwsA(isA<SpotiflacPackageError>()),
        );
      },
    );

    test('downloads into a staging folder with a playable name', () async {
      engine.scripts['v1'] = downloader();
      final addon = await packages.install(
        bytes: packageBytes(manifestFor('qobuz'), 'v1'),
      );
      await packages.search(addon.key, 'song');
      native.info = {'codec': 'aac', 'format': 'isomp4', 'duration_ms': 181000};

      final download = await packages.download(addon.key, 't1');
      expect(p.extension(download.file.path), '.m4a');
      expect(download.file.readAsStringSync(), 'audio');
      expect(download.metadata['name'], 'Song');
      await download.cleanup();
      expect(download.file.existsSync(), isFalse);
    });

    test('refuses audio the phone can’t play or that doesn’t match', () async {
      engine.scripts['v1'] = downloader();
      final addon = await packages.install(
        bytes: packageBytes(manifestFor('qobuz'), 'v1'),
      );
      await packages.search(addon.key, 'song');

      native.info = {'codec': 'eac3', 'format': 'isomp4', 'duration_ms': 0};
      await expectLater(
        packages.download(addon.key, 't1'),
        throwsA(isA<SpotiflacPackageError>()),
      );

      native.info = {'codec': 'flac', 'format': 'flac', 'duration_ms': 30000};
      await expectLater(
        packages.download(addon.key, 't1'),
        throwsA(
          isA<SpotiflacPackageError>().having(
            (e) => e.message,
            'message',
            contains('duration'),
          ),
        ),
      );
      expect(
        Directory(p.join(dir.path, 'work')).listSync(),
        isEmpty,
        reason: 'failed downloads clean up after themselves',
      );
    });
  });
}
