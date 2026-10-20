import 'dart:async';
import 'dart:io';

import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/konnekted/konnekted_home.dart';
import 'package:flick/features/konnekted/library/lokal_navigation.dart';
import 'package:flick/features/konnekted/library/lokal_radio.dart';
import 'package:flick/features/music_videos/music_videos_page.dart';
import 'package:flick/features/player/widgets/add_to_playlist_sheet.dart';
import 'package:flick/features/player/widgets/share/share_bottom_sheet.dart';
import 'package:flick/features/player/widgets/song_metadata_sheet.dart';
import 'package:flick/features/songs/widgets/album_art_picker_bottom_sheet.dart';
import 'package:flick/features/songs/widgets/metadata_editor_bottom_sheet.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/opt_in_source_provider.dart';
import 'package:flick/providers/providers.dart';
import 'package:flick/services/music_folder_service.dart';
import 'package:flick/services/player_service.dart';
import 'package:flick/widgets/lokal/settings/lokal_settings_surfaces.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// One extra row in a song's menu, for actions only one place has (the
/// queue's "Remove from queue", Now Playing's "Lyrics").
@immutable
class LokalSongMenuAction {
  const LokalSongMenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;

  /// Runs after the menu closes.
  final VoidCallback onTap;
  final bool destructive;
}

/// Lokal's one song menu, used by every song list, shelf, the queue and Now
/// Playing. Every action works on [song], the song the menu was opened for,
/// never on whatever happens to be playing.
class SongActionsBottomSheet extends ConsumerWidget {
  const SongActionsBottomSheet({
    super.key,
    required this.song,
    required this.rootContext,
    this.onSelect,
    this.onRemoveFromPlaylist,
    this.extras = const [],
    this.queueActions = true,
  });

  final Song song;

  /// Where the menu was opened from; follow-up sheets and pages use it.
  final BuildContext rootContext;
  final VoidCallback? onSelect;
  final VoidCallback? onRemoveFromPlaylist;
  final List<LokalSongMenuAction> extras;

  /// Shows Play next and Add to queue (off inside the queue itself).
  final bool queueActions;

  /// Opens the menu for [song].
  static Future<void> show(
    BuildContext context,
    Song song, {
    VoidCallback? onSelect,
    VoidCallback? onRemoveFromPlaylist,
    List<LokalSongMenuAction> extras = const [],
    bool queueActions = true,
  }) {
    final t = context.lokal;
    return showModalBottomSheet<void>(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: t.surface,
      barrierColor: Colors.black.withValues(alpha: t.isLight ? .25 : .5),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: t.border),
      ),
      builder: (_) => SongActionsBottomSheet(
        song: song,
        rootContext: context,
        onSelect: onSelect,
        onRemoveFromPlaylist: onRemoveFromPlaylist,
        extras: extras,
        queueActions: queueActions,
      ),
    );
  }

  bool get _isLocalFile =>
      song.filePath != null &&
      song.filePath!.isNotEmpty &&
      !song.isExternal &&
      !song.isNetworkSource;

  bool get _canEdit => _isLocalFile && song.startOffsetMs == null;

  bool get _canDelete => !song.isNetworkSource && int.tryParse(song.id) != null;

  void _say(String message) {
    if (!rootContext.mounted) return;
    ScaffoldMessenger.maybeOf(rootContext)?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.lokal;
    final liked = ref.watch(isSongFavoriteProvider(song.id));
    final videos = ref.watch(musicVideosEnabledProvider);
    final hasAlbum = song.album?.trim().isNotEmpty == true;
    // Actions run after the menu closes, so they read through the container,
    // not this widget's ref.
    final container = ProviderScope.containerOf(context, listen: false);

    /// Closes the menu, then runs [action].
    VoidCallback close(FutureOr<void> Function() action) => () {
      Navigator.of(context).pop();
      unawaited(Future<void>.sync(action));
    };

    final rows = <Widget>[
      if (onRemoveFromPlaylist != null)
        _MenuRow(
          icon: Icons.playlist_remove_rounded,
          label: 'Remove from playlist',
          onTap: close(onRemoveFromPlaylist!),
        ),
      if (onSelect != null)
        _MenuRow(
          icon: Icons.checklist_rounded,
          label: 'Select',
          onTap: close(onSelect!),
        ),
      if (queueActions && !song.isFromLocker) ...[
        _MenuRow(
          icon: Icons.playlist_play_rounded,
          label: 'Play next',
          onTap: close(() async {
            final player = container.read(playerProvider.notifier);
            final index = await player.addToQueue(song);
            if (index > 0) await player.moveQueueItemToNext(index);
            _say('“${song.title}” plays next');
          }),
        ),
        _MenuRow(
          icon: Icons.queue_music_rounded,
          label: 'Add to queue',
          onTap: close(() async {
            await container.read(playerProvider.notifier).addToQueue(song);
            _say('Added “${song.title}” to the queue');
          }),
        ),
      ],
      _MenuRow(
        icon: Icons.radio_rounded,
        label: 'Start radio',
        onTap: close(() => startLokalRadio(rootContext, seed: song)),
      ),
      _MenuRow(
        icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        label: liked ? 'Unlike' : 'Like',
        highlighted: liked,
        onTap: close(() async {
          await container
              .read(favoritesProvider.notifier)
              .toggleFavorite(song.id);
          PlayerService().refreshNotificationState();
        }),
      ),
      _MenuRow(
        icon: Icons.playlist_add_rounded,
        label: 'Add to a playlist',
        onTap: close(() => AddToPlaylistSheet.show(rootContext, song)),
      ),
      if (hasAlbum)
        _MenuRow(
          icon: Icons.album_rounded,
          label: 'Go to album',
          onTap: close(() => openLokalAlbumForSong(rootContext, song)),
        ),
      if (song.artist.trim().isNotEmpty)
        _MenuRow(
          icon: Icons.person_rounded,
          label: 'Go to artist',
          onTap: close(() => openLokalArtist(rootContext, song: song)),
        ),
      if (videos)
        _MenuRow(
          icon: Icons.smart_display_rounded,
          label: 'Watch video',
          onTap: close(() => watchMusicVideo(rootContext, song)),
        ),
      if (_canEdit)
        _MenuRow(
          icon: Icons.edit_rounded,
          label: 'Edit info',
          onTap: close(() async {
            final saved = await MetadataEditorBottomSheet.show(
              rootContext,
              song,
            );
            if (saved) container.invalidate(songsProvider);
          }),
        ),
      _MenuRow(
        icon: Icons.image_rounded,
        label: 'Change artwork',
        onTap: close(() async {
          final changed = await AlbumArtPickerBottomSheet.show(
            rootContext,
            song,
          );
          if (changed) container.invalidate(songsProvider);
        }),
      ),
      _MenuRow(
        icon: Icons.info_outline_rounded,
        label: 'Song info',
        onTap: close(() => SongMetadataSheet.show(rootContext, song)),
      ),
      if (_isLocalFile)
        _MenuRow(
          icon: Icons.ios_share_rounded,
          label: 'Share',
          onTap: close(
            () => SharePlus.instance.share(
              ShareParams(files: [XFile(song.filePath!)]),
            ),
          ),
        ),
      _MenuRow(
        icon: Icons.style_rounded,
        label: 'Share as card',
        onTap: close(
          () => showModalBottomSheet<void>(
            useRootNavigator: true,
            context: rootContext,
            backgroundColor: Colors.transparent,
            isScrollControlled: true,
            builder: (_) => ShareBottomSheet(song: song),
          ),
        ),
      ),
      for (final extra in extras)
        _MenuRow(
          icon: extra.icon,
          label: extra.label,
          destructive: extra.destructive,
          onTap: close(extra.onTap),
        ),
      if (_canDelete) ...[
        Divider(height: 17, color: t.border, indent: 24, endIndent: 24),
        _MenuRow(
          icon: Icons.delete_outline_rounded,
          label: _isLocalFile ? 'Delete from device' : 'Remove from library',
          destructive: true,
          onTap: close(_confirmDelete),
        ),
      ],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Row(
            children: [
              KonnektedArtwork(song: song, size: 52, radius: 8),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: LokalTheme.sans,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                    Text(
                      [
                        song.artist,
                        if (hasAlbum) song.album!.trim(),
                      ].where((s) => s.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: t.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: t.border),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              top: 6,
              bottom: 12 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete() async {
    if (!rootContext.mounted) return;
    final container = ProviderScope.containerOf(rootContext, listen: false);
    final choice = await showLokalSettingsSheet<String>(
      context: rootContext,
      title: 'Delete “${song.title}”?',
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LokalSheetOption(
            icon: Icons.library_music_outlined,
            label: 'Remove from library',
            description: _isLocalFile
                ? 'The file stays on your device.'
                : 'You can add it again by rescanning.',
            onTap: () => Navigator.of(context).pop('remove'),
          ),
          if (_isLocalFile)
            LokalSheetOption(
              icon: Icons.delete_forever_rounded,
              label: 'Delete from device',
              description: 'Deletes the file too. This can’t be undone.',
              onTap: () => Navigator.of(context).pop('file'),
            ),
          LokalSheetOption(
            label: 'Cancel',
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
    if (choice == null) return;
    await _delete(container, deleteFile: choice == 'file');
  }

  Future<void> _delete(
    ProviderContainer container, {
    required bool deleteFile,
  }) async {
    final songId = int.tryParse(song.id);
    if (songId == null) return;
    await container.read(songRepositoryProvider).deleteSong(songId);
    var deleted = !deleteFile;
    if (deleteFile && song.filePath != null) {
      try {
        deleted = await MusicFolderService.deleteDocument(
          folderTreeUri: song.folderUri ?? song.filePath!,
          filePath: song.filePath!,
        );
      } catch (_) {}
      if (!deleted) {
        try {
          final file = File(song.filePath!);
          if (await file.exists()) await file.delete();
          deleted = true;
        } catch (_) {}
      }
      if (deleted)
        await MusicFolderService.removeFromMediaStore(song.filePath!);
    }
    container.invalidate(songsProvider);
    _say(
      !deleteFile
          ? 'Removed “${song.title}” from your library'
          : deleted
          ? 'Deleted “${song.title}”'
          : 'Removed from your library, but couldn’t delete the file',
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    final color = destructive ? t.red : t.text;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 50),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: destructive
                      ? t.red
                      : (highlighted ? t.accent : t.muted),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: LokalTheme.sans,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
