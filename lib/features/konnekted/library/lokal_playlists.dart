import 'package:flick/l10n/l10n.dart';

import 'dart:async';

import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/konnekted/konnekted_data.dart';
import 'package:flick/features/konnekted/konnekted_home.dart';
import 'package:flick/models/playlist.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/playlist_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'lokal_library_kit.dart';
import 'lokal_song_browser.dart';

/// A playlist's songs in its own order, from the library.
List<Song> lokalPlaylistSongs(Playlist playlist, List<Song> library) {
  final byId = {for (final song in library) song.id: song};
  return [
    for (final id in playlist.songIds)
      if (byId[id] != null) byId[id]!,
  ];
}

Future<String?> _askName(
  BuildContext context, {
  required String title,
  required String action,
  String initial = '',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: context.lokal.surface2,
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: lokalText('Playlist name')),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(lokalText('Cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(action),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

void _say(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Asks for a name and creates a playlist.
Future<void> lokalCreatePlaylist(BuildContext context, WidgetRef ref) async {
  final name = await _askName(
    context,
    title: lokalText('New playlist'),
    action: 'Create',
  );
  if (name == null || name.trim().isEmpty || !context.mounted) return;
  final playlist = await ref
      .read(playlistsProvider.notifier)
      .createPlaylist(name);
  if (!context.mounted) return;
  _say(
    context,
    playlist == null
        ? 'A playlist with this name already exists.'
        : 'Created “${playlist.name}”.',
  );
}

/// Imports an M3U or M3U8 file as a playlist.
Future<void> lokalImportM3u(BuildContext context, WidgetRef ref) async {
  try {
    final result = await ref
        .read(playlistsProvider.notifier)
        .importM3uPlaylist();
    if (result == null || !context.mounted) return;
    _say(
      context,
      'Imported “${result.playlist.name}” with ${lokalSongCount(result.importedSongs)}'
      '${result.unmatchedEntries > 0 ? ', ${result.unmatchedEntries} not found' : ''}.',
    );
  } catch (e) {
    if (context.mounted) _say(context, 'Couldn’t import this file: $e');
  }
}

/// Library › Playlists.
class LokalPlaylistsPage extends ConsumerWidget {
  const LokalPlaylistsPage({super.key});

  Future<void> _syncServers(BuildContext context, WidgetRef ref) async {
    try {
      final synced = await ref
          .read(playlistsProvider.notifier)
          .syncServerPlaylists();
      if (context.mounted) {
        _say(
          context,
          synced == 0
              ? 'No server playlists found.'
              : 'Synced $synced playlists.',
        );
      }
    } catch (e) {
      if (context.mounted) _say(context, 'Couldn’t sync server playlists: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.lokal;
    final state = ref.watch(playlistsProvider);
    final library = ref.watch(konnektedLibraryProvider).value ?? const <Song>[];
    final hasServers =
        ref.watch(networkServersProvider).value?.isNotEmpty ?? false;
    final playlists = state.value?.playlists;
    return LokalLibraryPage(
      title: lokalText('Playlists'),
      subtitle: playlists == null
          ? null
          : lokalText("{arg0} playlists", args: {'arg0': playlists.length}),
      actions: [
        PopupMenuButton<String>(
          tooltip: lokalText('Add'),
          color: t.surface2,
          icon: Icon(Icons.add_rounded, color: t.text),
          onSelected: (value) => switch (value) {
            'new' => unawaited(lokalCreatePlaylist(context, ref)),
            'import' => unawaited(lokalImportM3u(context, ref)),
            'sync' => unawaited(_syncServers(context, ref)),
            _ => null,
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'new', child: Text(lokalText('New playlist'))),
            PopupMenuItem(
              value: 'import',
              child: Text(lokalText('Import M3U')),
            ),
            if (hasServers)
              PopupMenuItem(
                value: 'sync',
                child: Text(lokalText('Sync server playlists')),
              ),
          ],
        ),
      ],
      slivers: [
        if (playlists == null)
          SliverToBoxAdapter(
            child: state.hasError
                ? LokalEmptyState(
                    icon: Icons.error_outline_rounded,
                    title: lokalText('Couldn’t load your playlists'),
                    message: lokalText('Try again in a moment.'),
                    actionLabel: 'Try again',
                    onAction: () => ref.invalidate(playlistsProvider),
                  )
                : const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  ),
          )
        else ...[
          SliverToBoxAdapter(
            child: InkWell(
              onTap: () => lokalCreatePlaylist(context, ref),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: t.surface2,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.add_rounded, color: t.accent, size: 30),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      lokalText('New playlist…'),
                      style: TextStyle(fontSize: 16, color: t.accent),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverList.builder(
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              final songs = lokalPlaylistSongs(playlist, library);
              return InkWell(
                onTap: () => pushLokal(
                  context,
                  LokalPlaylistPage(playlistId: playlist.id),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: 64,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LokalCollage(songs: songs),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              playlist.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              playlist.isNetworkSource
                                  ? lokalText(
                                      "{arg0} · server",
                                      args: {
                                        'arg0': lokalSongCount(
                                          playlist.songIds.length,
                                        ),
                                      },
                                    )
                                  : lokalSongCount(playlist.songIds.length),
                              style: TextStyle(fontSize: 13, color: t.muted),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: t.muted2),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

/// One playlist: collage, name, Play and Shuffle, the songs.
class LokalPlaylistPage extends ConsumerWidget {
  const LokalPlaylistPage({super.key, required this.playlistId});

  final String playlistId;

  Future<void> _rename(BuildContext context, WidgetRef ref, Playlist p) async {
    final name = await _askName(
      context,
      title: lokalText('Rename playlist'),
      action: 'Rename',
      initial: p.name,
    );
    if (name == null || name.trim().isEmpty) return;
    final ok = await ref
        .read(playlistsProvider.notifier)
        .renamePlaylist(p.id, name.trim());
    if (!ok && context.mounted) _say(context, 'Couldn’t rename this playlist.');
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Playlist p) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.lokal.surface2,
        title: Text(lokalText("Delete “{arg0}”?", args: {'arg0': p.name})),
        content: Text(lokalText('The songs stay in your library.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(lokalText('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              lokalText('Delete'),
              style: TextStyle(color: context.lokal.red),
            ),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    await ref.read(playlistsProvider.notifier).deletePlaylist(p.id);
    if (context.mounted) Navigator.of(context).maybePop();
  }

  Future<void> _export(BuildContext context, WidgetRef ref, Playlist p) async {
    try {
      final result = await ref
          .read(playlistsProvider.notifier)
          .exportPlaylistAsM3u(p.id, utf8: true);
      if (result != null && context.mounted) {
        _say(
          context,
          'Exported ${lokalSongCount(result.exportedSongs)} to ${result.fileName}.',
        );
      }
    } catch (e) {
      if (context.mounted) _say(context, 'Couldn’t export: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.lokal;
    final playlist = ref.watch(playlistProvider(playlistId));
    final library = ref.watch(konnektedLibraryProvider).value ?? const <Song>[];
    if (playlist == null) {
      return LokalLibraryPage(
        title: lokalText('Playlist'),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        ],
      );
    }
    final songs = lokalPlaylistSongs(playlist, library);
    final width = MediaQuery.sizeOf(context).width;
    return LokalLibraryPage(
      title: playlist.name,
      actions: [
        PopupMenuButton<String>(
          tooltip: lokalText('More'),
          color: t.surface2,
          icon: Icon(Icons.more_horiz_rounded, color: t.text),
          onSelected: (value) => switch (value) {
            'queue' => unawaited(lokalQueueAll(context, ref, songs)),
            'reorder' => unawaited(
              pushLokal(context, _ReorderPage(playlistId: playlistId)),
            ),
            'rename' => unawaited(_rename(context, ref, playlist)),
            'export' => unawaited(_export(context, ref, playlist)),
            'delete' => unawaited(_delete(context, ref, playlist)),
            _ => null,
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'queue',
              child: Text(lokalText('Add to queue')),
            ),
            if (!playlist.isNetworkSource && playlist.songIds.length > 1)
              PopupMenuItem(
                value: 'reorder',
                child: Text(lokalText('Reorder songs')),
              ),
            if (!playlist.isNetworkSource)
              PopupMenuItem(value: 'rename', child: Text(lokalText('Rename'))),
            PopupMenuItem(
              value: 'export',
              child: Text(lokalText('Export as M3U8')),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Text(lokalText('Delete playlist')),
            ),
          ],
        ),
      ],
      header: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
        child: Column(
          children: [
            SizedBox.square(
              dimension: (width * .62).clamp(150.0, 300.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LokalCollage(songs: songs),
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: Text(
                playlist.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              lokalText(
                "{arg0}, {arg1}",
                args: {
                  'arg0': lokalSongCount(songs.length),
                  'arg1': lokalRunningTime(songs),
                },
              ),
              style: TextStyle(color: t.muted),
            ),
          ],
        ),
      ),
      slivers: [
        if (songs.isEmpty)
          SliverToBoxAdapter(
            child: LokalEmptyState(
              icon: Icons.queue_music_rounded,
              title: lokalText('No songs yet'),
              message: lokalText(
                'Add songs from any song’s menu: More › Add to a playlist.',
              ),
            ),
          )
        else
          LokalSongBrowser(
            songs: songs,
            initialSort: LokalSongSort.original,
            originalLabel: 'Playlist order',
            searchHint: 'Search in playlist',
            onRemove: playlist.isNetworkSource
                ? null
                : (song) => ref
                      .read(playlistsProvider.notifier)
                      .removeSongFromPlaylist(playlist.id, song.id),
          ),
      ],
    );
  }
}

class _ReorderPage extends ConsumerWidget {
  const _ReorderPage({required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.lokal;
    final playlist = ref.watch(playlistProvider(playlistId));
    final byId = {
      for (final song
          in ref.watch(konnektedLibraryProvider).value ?? const <Song>[])
        song.id: song,
    };
    final ids = playlist?.songIds ?? const <String>[];
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            LokalPageBar(
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(lokalText('Done')),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: LokalLargeTitle(
                title: lokalText('Reorder'),
                subtitle: lokalText('Drag to move'),
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                padding: EdgeInsets.only(
                  bottom: 150 + MediaQuery.paddingOf(context).bottom,
                ),
                itemCount: ids.length,
                // The service takes the drop index before removal, as onReorder had.
                onReorderItem: (from, to) => ref
                    .read(playlistsProvider.notifier)
                    .reorderSongs(playlistId, from, from < to ? to + 1 : to),
                itemBuilder: (context, index) {
                  final song = byId[ids[index]];
                  return ListTile(
                    key: ValueKey('${ids[index]}#$index'),
                    leading: song == null
                        ? Icon(Icons.music_off_rounded, color: t.muted)
                        : KonnektedArtwork(song: song, size: 44, radius: 6),
                    title: Text(
                      song?.title ?? lokalText('Missing song'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      song?.artist ?? '',
                      maxLines: 1,
                      style: TextStyle(color: t.muted),
                    ),
                    trailing: Icon(Icons.drag_handle_rounded, color: t.muted),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
