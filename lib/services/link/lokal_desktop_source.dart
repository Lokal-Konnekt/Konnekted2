import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:crypto/crypto.dart';

import 'package:http/http.dart' as http;
import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/database.dart';
import '../../data/repositories/song_repository.dart';
import '../../models/song.dart';
import '../library_scanner_service.dart' show ScanProgress;
import '../lokal_remote_credentials_store.dart';
import '../../models/lokal_remote_state.dart';
import '../network_cache_service.dart';
import '../sources/network_source_service.dart';
import 'link_journal.dart';

/// Desktop songs use the existing ranged network-player and bounded audio cache.
/// The server row contains no token; encrypted storage remains the only token owner.
class LokalDesktopSource extends NetworkSourceService {
  static final instance = LokalDesktopSource();
  final _cache = NetworkCacheService();
  final Map<String, Future<String>> _downloads = {};
  @override
  String get protocol => 'lokal';
  @override
  String get coverScheme => 'lokal-cover://';
  Future<LokalRemoteCredentials> _credentials(
    NetworkServerEntity server,
  ) async {
    final value = await SecureLokalRemoteCredentialsStore().read();
    if (value == null ||
        '${value.desktopId}:${value.desktopUserId ?? 'guest'}' !=
            server.username ||
        value.origin.toString() != server.baseUrl)
      throw StateError('Reconnect to this Lokal desktop to stream its songs.');
    return value;
  }

  Map<String, String> _headers(LokalRemoteCredentials credentials) => {
    'x-remote-token': credentials.remoteToken,
    if (credentials.apiKey.isNotEmpty) 'x-api-key': credentials.apiKey,
  };
  @override
  Future<String?> resolveToken(
    NetworkServerEntity server,
    String password,
  ) async => null;
  @override
  Future<bool> ping(NetworkServerEntity server) async {
    try {
      final credentials = await _credentials(server);
      final response = await http
          .get(
            credentials.origin.replace(path: '/api/remote/state'),
            headers: _headers(credentials),
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } on Object {
      return false;
    }
  }

  @override
  Future<List<int>> getCoverArt(
    NetworkServerEntity server,
    String marker,
  ) async {
    final credentials = await _credentials(server);
    final response = await http
        .get(
          credentials.origin.replace(pathSegments: ['api', 'artwork', marker]),
          headers: _headers(credentials),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200)
      throw const HttpException('Desktop artwork is unavailable.');
    return response.bodyBytes;
  }

  @override
  Future<({String url, Map<String, String> headers})?> streamDescriptor(
    NetworkServerEntity server,
    String remoteId, {
    String? extension,
  }) async {
    final cached = await _cache.getPath(server.id, remoteId);
    if (cached != null) return null; // ensureLocal returns the offline copy.
    final credentials = await _credentials(server);
    return (
      url: credentials.origin
          .replace(pathSegments: ['api', 'stream', remoteId])
          .toString(),
      headers: _headers(credentials),
    );
  }

  @override
  Future<String> stream(
    NetworkServerEntity server,
    String remoteId, {
    String? extension,
    void Function(double)? onProgress,
  }) async {
    final cached = await _cache.getPath(server.id, remoteId);
    if (cached != null) return cached;
    final key = '${server.id}:$remoteId';
    return _downloads.putIfAbsent(
      key,
      () => _download(
        server,
        remoteId,
        extension,
        onProgress,
      ).whenComplete(() => _downloads.remove(key)),
    );
  }

  Future<String> _download(
    NetworkServerEntity server,
    String remoteId,
    String? extension,
    void Function(double)? onProgress,
  ) async {
    final credentials = await _credentials(server), client = http.Client();
    final ext = RegExp(r'^[a-zA-Z0-9]{1,8}$').hasMatch(extension ?? '')
        ? extension
        : 'bin';
    final path = await _cache.pathFor(server.id, remoteId, extension: ext),
        part = File('$path.part');
    try {
      final request = http.Request(
        'GET',
        credentials.origin.replace(pathSegments: ['api', 'stream', remoteId]),
      )..headers.addAll(_headers(credentials));
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200)
        throw HttpException('Desktop returned HTTP ${response.statusCode}.');
      final output = part.openWrite();
      var received = 0;
      try {
        await for (final bytes in response.stream.timeout(
          const Duration(seconds: 30),
        )) {
          received += bytes.length;
          output.add(bytes);
          if (response.contentLength != null && response.contentLength! > 0)
            onProgress?.call((received / response.contentLength!).clamp(0, 1));
        }
        await output.flush();
      } finally {
        await output.close();
      }
      if (response.contentLength != null && received != response.contentLength)
        throw const HttpException(
          'Desktop stream ended before the file was complete.',
        );
      await part.rename(path);
      await _cache.commitDownload(path);
      onProgress?.call(1);
      return path;
    } finally {
      client.close();
      if (await part.exists()) await part.delete();
    }
  }

  Future<NetworkServerEntity> ensureServer(
    LokalRemoteCredentials credentials, {
    String name = 'Lokal desktop',
  }) async {
    if (credentials.desktopId == null)
      throw StateError('Pair this desktop first.');
    var server = await Database.networkServers
        .filter()
        .protocolEqualTo('lokal')
        .usernameEqualTo(
          '${credentials.desktopId}:${credentials.desktopUserId ?? 'guest'}',
        )
        .findFirst();
    server ??= NetworkServerEntity()
      ..protocol = 'lokal'
      ..label = name;
    server.baseUrl = credentials.origin.toString();
    server.username =
        '${credentials.desktopId}:${credentials.desktopUserId ?? 'guest'}';
    server.token = null;
    await Database.instance.writeTxn(
      () => Database.networkServers.put(server!),
    );
    return server;
  }

  Future<Song> importTrack(
    NetworkServerEntity server,
    Map<String, dynamic> track,
  ) async {
    final journal = LinkJournal.instance;
    final key =
        track['track_key'] ??
        '${track['artist']?.toString().trim().toLowerCase()}|${track['title']?.toString().trim().toLowerCase()}|${(track['duration'] as num? ?? 0).round()}';
    final local = await journal.match({...track, 'track_key': key});
    if (local != null && local.sourceType != 'lokal') return local;
    final remoteId = track['id']?.toString();
    if (remoteId == null || remoteId.isEmpty)
      throw const FormatException('Desktop song is missing its identifier.');
    var entity = await Database.songs
        .filter()
        .remoteServerIdEqualTo(server.id)
        .remoteIdEqualTo(remoteId)
        .findFirst();
    entity ??= SongEntity()
      ..filePath = 'lokal://${server.id}/$remoteId'
      ..dateAdded = DateTime.now();
    entity.title = track['title']?.toString() ?? 'Unknown track';
    entity.artist = track['artist']?.toString() ?? 'Unknown artist';
    entity.album = track['album']?.toString();
    entity.durationMs = ((track['duration'] as num? ?? 0) * 1000).round();
    entity.fileType = track['fileType']?.toString() ?? entity.fileType ?? 'bin';
    entity.sourceType = 'lokal';
    entity.remoteId = remoteId;
    entity.remoteServerId = server.id;
    entity.metadataComplete = true;
    if (track['hasArtwork'] == true)
      entity.albumArtPath = 'lokal-cover://$remoteId';
    final saved = entity;
    await Database.instance.writeTxn(() => Database.songs.put(saved));
    return SongRepository().songFromEntity(saved);
  }

  Future<void> uploadToDesktop(
    Song song,
    LokalRemoteCredentials credentials,
  ) async {
    if (song.filePath == null || song.isNetworkSource) return;
    var extension = song.fileType.toLowerCase();
    extension =
        const {'mpeg': 'mp3', 'mp4': 'm4a', 'wave': 'wav'}[extension] ??
        extension;
    if (!RegExp(r'^[a-z0-9]{1,8}$').hasMatch(extension))
      throw StateError('This file format cannot be sent.');
    var temporary = false;
    var path = song.filePath!;
    if (path.startsWith('content://')) {
      path =
          await const MethodChannel('lokal/desktop_link').invokeMethod<String>(
            'stageAudio',
            {'uri': path, 'extension': extension},
          ) ??
          '';
      temporary = true;
    }
    final file = File(path);
    try {
      if (!await file.exists())
        throw StateError('This song is not stored as a readable local file.');
      final digest = await sha256.bind(file.openRead()).first;
      final request = http.StreamedRequest(
        'POST',
        credentials.origin.replace(path: '/api/remote/files'),
      );
      request.headers.addAll({
        ..._headers(credentials),
        'content-type': 'application/octet-stream',
        'x-link-metadata': base64Url.encode(
          utf8.encode(
            jsonEncode({
              'title': song.title,
              'artist': song.artist,
              'album': song.album,
              'extension': extension,
              'sha256': digest.toString(),
            }),
          ),
        ),
      });
      request.contentLength = await file.length();
      final client = http.Client();
      try {
        final responseFuture = client.send(request);
        await request.sink.addStream(file.openRead());
        await request.sink.close();
        final response = await responseFuture.timeout(
          const Duration(minutes: 3),
        );
        await response.stream.drain<void>();
        if (response.statusCode != 200)
          throw const HttpException('The desktop could not save this song.');
      } finally {
        client.close();
      }
    } finally {
      if (temporary && await file.exists()) await file.delete();
    }
  }

  Future<void> downloadToPhone(Song song) async {
    final server = await Database.networkServers.get(song.remoteServerId!);
    if (server == null) throw StateError('Reconnect to this desktop first.');
    final cached = await stream(
      server,
      song.remoteId!,
      extension: song.fileType,
    );
    final directory = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/desktop_music',
    );
    await directory.create(recursive: true);
    final extension = RegExp(r'^[a-zA-Z0-9]{1,8}$').hasMatch(song.fileType)
        ? song.fileType
        : 'bin';
    final path = '${directory.path}/${song.id}.$extension';
    if (!await File(path).exists()) await File(cached).copy(path);
    final entity = await Database.songs.get(int.parse(song.id));
    if (entity == null) return;
    entity.filePath = path;
    entity.sourceType = null;
    entity.folderUri = directory.path;
    await Database.instance.writeTxn(() => Database.songs.put(entity));
  }

  @override
  Stream<ScanProgress> syncLibrary(NetworkServerEntity server) async* {
    final credentials = await _credentials(server);
    var offset = 0, imported = 0, total = 0;
    do {
      final response = await http
          .get(
            credentials.origin.replace(
              path: '/api/remote/library/tracks',
              queryParameters: {'offset': '$offset', 'limit': '50'},
            ),
            headers: _headers(credentials),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200)
        throw const HttpException('Desktop library is unavailable.');
      final body = jsonDecode(response.body) as Map,
          items = body['items'] as List;
      total = (body['total'] as num? ?? 0).toInt();
      for (final raw in items) {
        await importTrack(server, Map<String, dynamic>.from(raw as Map));
        imported++;
      }
      offset += items.length;
      yield ScanProgress(
        songsFound: imported,
        totalFiles: total,
        filesProcessed: imported,
        isComplete: body['hasMore'] != true,
      );
      if (body['hasMore'] != true || items.isEmpty) break;
    } while (offset < total);
    // Missing desktop rows never delete local songs or downloaded files.
    server.lastSyncedAt = DateTime.now();
    await Database.instance.writeTxn(() => Database.networkServers.put(server));
  }
}
