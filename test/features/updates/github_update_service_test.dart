import 'dart:convert';

import 'package:flick/features/updates/github_update_service.dart';
import 'package:flick/providers/app_build_info_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const root = 'https://github.com/Lokal-Konnekt/lokal-mobile/releases/download';
final hash = List.filled(64, 'a').join();
Map<String, Object?> release(
  String version, {
  bool prerelease = false,
  bool draft = false,
  String flavor = 'full',
}) => {
  'tag_name': 'v$version',
  'prerelease': prerelease,
  'draft': draft,
  'body': 'Release notes',
  'assets': [
    {
      'name': '$flavor-metadata.json',
      'browser_download_url': '$root/v$version/$flavor-metadata.json',
    },
    {
      'name': 'Lokal-$version${flavor == 'play' ? '-Play' : ''}-universal.apk',
      'browser_download_url':
          '$root/v$version/Lokal-$version${flavor == 'play' ? '-Play' : ''}-universal.apk',
    },
  ],
};

void main() {
  test(
    'same marketing version with higher build offers replacement; no downgrade',
    () async {
      final client = MockClient(
        (r) async => http.Response(
          jsonEncode(
            r.url.host == 'api.github.com'
                ? [release('1.0.0')]
                : {
                    'version': '1.0.0',
                    'versionCode': 200,
                    'flavor': 'full',
                    'sha256': hash,
                  },
          ),
          200,
        ),
      );
      final service = GithubUpdateService(client);
      expect(
        (await service.check(
          const AppBuildInfo(version: '1.0.0', build: '199'),
          'full',
        ))?.build,
        200,
      );
      expect(
        await service.check(
          const AppBuildInfo(version: '1.0.0', build: '200'),
          'full',
        ),
        isNull,
      );
      expect(
        await service.check(
          const AppBuildInfo(version: '1.0.0', build: '201'),
          'full',
        ),
        isNull,
      );
      client.close();
    },
  );

  test(
    'stable skips nightlies and drafts; nightly finds newer compatible build',
    () async {
      final client = MockClient(
        (r) async => http.Response(
          jsonEncode(
            r.url.host == 'api.github.com'
                ? [
                    release('2.0.0', draft: true),
                    release('1.0.1-nightly.2', prerelease: true),
                    release('1.0.0'),
                  ]
                : {
                    'version': r.url.path.contains('nightly')
                        ? '1.0.1-nightly.2'
                        : '1.0.0',
                    'versionCode': r.url.path.contains('nightly') ? 300 : 200,
                    'flavor': 'full',
                    'sha256': hash,
                  },
          ),
          200,
        ),
      );
      final service = GithubUpdateService(client);
      expect(
        (await service.check(
          const AppBuildInfo(version: '1.0.0', build: '199'),
          'full',
        ))?.build,
        200,
      );
      expect(
        (await service.check(
          const AppBuildInfo(version: '1.0.1-nightly.1', build: '199'),
          'full',
        ))?.build,
        300,
      );
      client.close();
    },
  );

  test(
    'chooses matching Play asset and rejects invalid checksum metadata',
    () async {
      var valid = true;
      final client = MockClient(
        (r) async => http.Response(
          jsonEncode(
            r.url.host == 'api.github.com'
                ? [release('1.0.1', flavor: 'play')]
                : {
                    'version': '1.0.1',
                    'versionCode': 201,
                    'flavor': 'play',
                    'sha256': valid ? hash : 'bad',
                  },
          ),
          200,
        ),
      );
      final service = GithubUpdateService(client);
      final installed = const AppBuildInfo(version: '1.0.0', build: '200');
      expect(
        (await service.check(installed, 'play'))?.apkUrl,
        endsWith('-Play-universal.apk'),
      );
      valid = false;
      expect(await service.check(installed, 'play'), isNull);
      client.close();
    },
  );

  test('API failure is not reported as up to date', () async {
    final client = MockClient((_) async => http.Response('limited', 403));
    expect(
      GithubUpdateService(client)
          .check(const AppBuildInfo(version: '1.0.0', build: '1'), 'full'),
      throwsStateError,
    );
    client.close();
  });
}
