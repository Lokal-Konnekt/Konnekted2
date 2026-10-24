import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flick/providers/app_build_info_provider.dart';

const lokalUpdateReleasesUrl =
    'https://github.com/Lokal-Konnekt/lokal-mobile/releases';

class LokalUpdateRelease {
  const LokalUpdateRelease({
    required this.version,
    required this.build,
    required this.apkUrl,
    required this.sha256,
    required this.pageUrl,
    required this.notes,
  });
  final String version, apkUrl, sha256, pageUrl, notes;
  final int build;
  String get identity => '$version+$build:$sha256';
}

class GithubUpdateService {
  GithubUpdateService(this.client);
  final http.Client client;
  static const _repo = 'Lokal-Konnekt/lokal-mobile';
  static const _headers = {
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'Lokal-Mobile',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  Future<dynamic> _json(String url) async {
    final response = await client
        .get(Uri.parse(url), headers: _headers)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200)
      throw StateError('Update server returned ${response.statusCode}');
    return jsonDecode(response.body);
  }

  Future<LokalUpdateRelease?> check(
    AppBuildInfo installed,
    String flavor,
  ) async {
    if (flavor != 'full' && flavor != 'play')
      throw StateError('Unknown APK variant');
    final current = int.tryParse(installed.build);
    if (current == null) throw StateError('Installed build number unavailable');
    final nightly = installed.version.contains('-nightly.');
    final response = await _json(
      nightly
          ? 'https://api.github.com/repos/$_repo/releases?per_page=20'
          : 'https://api.github.com/repos/$_repo/releases/latest',
    );
    final data = response is List ? List<dynamic>.of(response) : [response];
    // Replacing a stable release preserves its old creation date, so it may
    // be below many nightlies in the list. Always include GitHub's stable tip.
    if (nightly) {
      final stable = await _json(
        'https://api.github.com/repos/$_repo/releases/latest',
      );
      if (stable is Map<String, dynamic>) data.insert(0, stable);
    }
    final candidates = data
        .whereType<Map<String, dynamic>>()
        .where(
          (r) =>
              r['draft'] != true &&
              (r['prerelease'] != true ||
                  nightly && '${r['tag_name']}'.contains('-nightly.')),
        )
        .take(4);
    LokalUpdateRelease? newest;
    for (final release in candidates) {
      final assets = (release['assets'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      String? asset(String name) {
        for (final a in assets) {
          if (a['name'] == name && a['browser_download_url'] is String) {
            final url = a['browser_download_url'] as String;
            if (url.startsWith('https://github.com/$_repo/releases/download/'))
              return url;
          }
        }
        return null;
      }

      final metadataUrl = asset('$flavor-metadata.json');
      if (metadataUrl == null) continue;
      final metadata = await _json(metadataUrl);
      if (metadata is! Map || metadata['flavor'] != flavor) continue;
      final code = int.tryParse('${metadata['versionCode']}');
      final version = metadata['version'] as String?;
      final hash = metadata['sha256'] as String? ?? '';
      if (code == null ||
          code <= current ||
          version == null ||
          !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hash))
        continue;
      final prefix = 'Lokal-$version${flavor == 'play' ? '-Play' : ''}';
      // New releases contain ARM64 only. Keep finding older universal
      // releases so an installed signed beta can still update in place.
      final apk = asset('$prefix-arm64.apk') ??
          asset('$prefix-universal.apk');
      if (apk == null) continue;
      if (newest == null || code > newest.build) {
        newest = LokalUpdateRelease(
          version: version,
          build: code,
          apkUrl: apk,
          sha256: hash.toLowerCase(),
          pageUrl:
              '$lokalUpdateReleasesUrl/tag/${Uri.encodeComponent(release['tag_name'] as String)}',
          notes: release['body'] as String? ?? '',
        );
      }
    }
    return newest;
  }
}
