import 'dart:io';

import '../../data/entities/song_entity.dart';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../music_folder_service.dart';
import 'link_protocol.dart';

class DesktopMusicFolder {
  const DesktopMusicFolder(this.uri, {this.path});
  final String uri;
  final String? path;
}

class DesktopMusicFile {
  const DesktopMusicFile({
    required this.path,
    required this.folderUri,
    this.documentUri,
  });
  final String path, folderUri;
  final String? documentUri;
}

/// Permanent copies use a selected library folder. Private files are staging or
/// recovery inputs; an unavailable folder must never silently change the target.
class DesktopMusicStorage {
  DesktopMusicStorage({
    Future<List<DesktopMusicFolder>> Function()? folders,
    MethodChannel channel = const MethodChannel('com.mossapps.flick/storage'),
    Future<void> Function(List<String>)? indexMedia,
  }) : _folders = folders ?? _savedFolders,
       _channel = channel,
       _indexMedia = indexMedia ?? MusicFolderService().indexMediaFiles;
  static const directoryName = 'Lokal Desktop';
  final Future<List<DesktopMusicFolder>> Function() _folders;
  final MethodChannel _channel;
  final Future<void> Function(List<String>) _indexMedia;
  static Future<List<DesktopMusicFolder>> _savedFolders() async {
    final service = MusicFolderService();
    return [
      for (final folder in await service.getSavedFolders())
        DesktopMusicFolder(
          folder.uri,
          path: (await service.resolveStorageInfo(folder.uri)).fsPath,
        ),
    ];
  }

  Future<void> requireFolder() async {
    if ((await _folders()).isEmpty)
      throw StateError(
        'Choose a music folder in Library settings before copying desktop songs.',
      );
  }

  static String _name(String artist, String title, String extension) {
    var base = '$artist - $title'
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
    if (base.isEmpty) base = 'Song';
    base = String.fromCharCodes(base.runes.take(90));
    return '$base - ${linkUuid()}.$extension';
  }

  Future<DesktopMusicFile> save(
    File source, {
    required String title,
    required String artist,
    required String extension,
  }) async {
    if (!RegExp(r'^[a-zA-Z0-9]{1,8}$').hasMatch(extension))
      throw const FormatException('Invalid audio format.');
    final folders = await _folders();
    if (folders.isEmpty)
      throw StateError(
        'Choose a music folder in Library settings before copying desktop songs.',
      );
    final length = await source.length();
    if (length == 0) throw StateError('The desktop song file is empty.');
    final name = _name(artist, title, extension.toLowerCase());
    for (final folder in folders) {
      final root = folder.path;
      if (root != null && p.isAbsolute(root)) {
        final target = File(p.join(root, directoryName, name));
        final part = File('${target.path}.part');
        try {
          await target.parent.create(recursive: true);
          await source.copy(part.path);
          if (await part.length() != length)
            throw const FileSystemException('Incomplete copy');
          await part.rename(target.path);
          return DesktopMusicFile(path: target.path, folderUri: folder.uri);
        } on FileSystemException {
          try {
            if (await part.exists()) await part.delete();
          } on FileSystemException {
            /* Keep the failure actionable below. */
          }
        }
      }
      if (Uri.tryParse(folder.uri)?.scheme == 'content') {
        try {
          final result = await _channel.invokeMapMethod<String, dynamic>(
            'copyMusicToFolder',
            {
              'folderTreeUri': folder.uri,
              'sourcePath': source.path,
              'directoryName': directoryName,
              'fileName': name,
            },
          );
          final uri = result?['uri'] as String?;
          if (uri == null || !uri.startsWith('content://')) continue;
          final resolved = result?['path'] as String?;
          return DesktopMusicFile(
            path: resolved ?? uri,
            folderUri: folder.uri,
            documentUri: uri,
          );
        } on PlatformException {
          /* Try another selected folder, never private storage. */
        }
      }
    }
    throw StateError(
      'Cannot write to your selected music folder. Re-select it in Library settings to restore access, then retry.',
    );
  }

  /// Keep the row's identity, likes, history, artwork and synced lyric key.
  /// The private input is retained as recovery data for already queued playback.
  Future<void> saveEntity(
    SongEntity entity, {
    required Future<void> Function(SongEntity) persist,
  }) async {
    final oldPath = entity.filePath, oldFolder = entity.folderUri;
    final oldDocument = entity.mediaStoreUri,
        oldRelative = entity.relativeFolderPath;
    final output = await save(
      File(oldPath),
      title: entity.title,
      artist: entity.artist,
      extension: entity.fileType ?? p.extension(oldPath).replaceFirst('.', ''),
    );
    try {
      entity.filePath = output.path;
      entity.folderUri = output.folderUri;
      entity.mediaStoreUri = output.documentUri;
      entity.relativeFolderPath = directoryName;
      await persist(entity);
    } catch (_) {
      entity.filePath = oldPath;
      entity.folderUri = oldFolder;
      entity.mediaStoreUri = oldDocument;
      entity.relativeFolderPath = oldRelative;
      try {
        await remove(output);
      } catch (_) {
        /* Never remove the recovery input. */
      }
      rethrow;
    }
    try {
      await index(output);
    } catch (_) {
      /* A later library scan can index it. */
    }
  }

  Future<void> index(DesktopMusicFile file) => _indexMedia([file.path]);
  Future<void> remove(DesktopMusicFile file) async {
    if (file.documentUri != null) {
      await _channel.invokeMethod<bool>('removeCopiedMusicDocument', {
        'uri': file.documentUri,
      });
    } else if (await File(file.path).exists()) {
      await File(file.path).delete();
    }
  }
}
