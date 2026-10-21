import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/features/konnekted/konnekted_data.dart';
import 'package:flick/features/konnekted/konnekted_home.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/models/song.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'lokal_library_kit.dart';
import 'lokal_library_groups.dart';
import 'lokal_music_detail_page.dart';

export 'lokal_library_groups.dart';

final lokalAlbumsProvider = Provider<AsyncValue<List<AlbumGroup>>>(
  (ref) => ref.watch(konnektedLibraryProvider).whenData(lokalAlbums),
);

final lokalArtistsProvider = Provider<AsyncValue<List<LokalArtist>>>(
  (ref) => ref.watch(konnektedLibraryProvider).whenData(lokalArtists),
);

/// An album's cover.
class _AlbumArt extends StatelessWidget {
  const _AlbumArt(this.songs);

  final List<Song> songs;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => songs.isEmpty
        ? LokalCollage(songs: songs)
        : KonnektedArtwork(
            song: songs.firstWhere(
              (s) => s.albumArt != null,
              orElse: () => songs.first,
            ),
            size: c.maxWidth,
            radius: 0,
          ),
  );
}

/// A filterable list page: a search field under the title, then [build].
class _SearchablePage<T> extends StatefulWidget {
  const _SearchablePage({
    required this.title,
    required this.items,
    required this.nameOf,
    required this.builder,
    required this.hint,
    required this.emptyIcon,
    required this.emptyMessage,
  });

  final String title;
  final AsyncValue<List<T>> items;
  final String Function(T) nameOf;
  final Widget Function(List<T> items) builder;
  final String hint;
  final IconData emptyIcon;
  final String emptyMessage;

  @override
  State<_SearchablePage<T>> createState() => _SearchablePageState<T>();
}

class _SearchablePageState<T> extends State<_SearchablePage<T>> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.items.value;
    final query = _query.trim().toLowerCase();
    final items = all == null
        ? null
        : query.isEmpty
        ? all
        : [
            for (final item in all)
              if (widget.nameOf(item).toLowerCase().contains(query)) item,
          ];
    return LokalLibraryPage(
      title: widget.title,
      subtitle: all == null
          ? null
          : lokalText(
              "{arg0} {arg1}",
              args: {'arg0': all.length, 'arg1': widget.title.toLowerCase()},
            ),
      slivers: [
        if (all != null && all.isNotEmpty)
          SliverPersistentHeader(
            pinned: true,
            delegate: LokalPinnedHeader(
              height:
                  60 *
                  MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: LokalSearchField(
                  controller: _search,
                  hint: widget.hint,
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            ),
          ),
        if (items == null)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (items.isEmpty)
          SliverToBoxAdapter(
            child: LokalEmptyState(
              icon: widget.emptyIcon,
              title: query.isEmpty
                  ? lokalText('Nothing here yet')
                  : lokalText('No results'),
              message: query.isEmpty
                  ? widget.emptyMessage
                  : lokalText(
                      "Nothing matches “{arg0}”.",
                      args: {'arg0': _query},
                    ),
            ),
          )
        else
          const SliverPadding(padding: EdgeInsets.only(top: 8)),
        if (items != null && items.isNotEmpty) widget.builder(items),
      ],
    );
  }
}

/// Library › Albums: a grid of covers.
class LokalAlbumsPage extends ConsumerWidget {
  const LokalAlbumsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _SearchablePage<AlbumGroup>(
        title: lokalText('Albums'),
        items: ref.watch(lokalAlbumsProvider),
        nameOf: (a) => '${a.albumName}\n${a.albumArtist}',
        hint: 'Search albums',
        emptyIcon: Icons.album_rounded,
        emptyMessage: 'Albums come from your files’ album tags.',
        builder: (albums) => LokalCardGrid(
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final album = albums[index];
            return LokalCoverCard(
              art: _AlbumArt(album.songs),
              title: album.albumName,
              subtitle: album.albumArtist,
              onTap: () => pushLokal(context, LokalAlbumPage(album: album)),
            );
          },
        ),
      );
}

/// Library › Artists: round portraits A to Z.
class LokalArtistsPage extends ConsumerWidget {
  const LokalArtistsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _SearchablePage<LokalArtist>(
        title: lokalText('Artists'),
        items: ref.watch(lokalArtistsProvider),
        nameOf: (a) => a.name,
        hint: 'Search artists',
        emptyIcon: Icons.person_rounded,
        emptyMessage: 'Artists come from your files’ artist tags.',
        builder: (artists) => SliverList.builder(
          itemCount: artists.length,
          itemBuilder: (context, index) {
            final artist = artists[index];
            return _ArtistRow(artist: artist);
          },
        ),
      );
}

class _ArtistRow extends StatelessWidget {
  const _ArtistRow({required this.artist});

  final LokalArtist artist;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => pushLokal(
      context,
      LokalArtistPage(name: artist.name, songs: artist.songs),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        children: [
          KonnektedArtwork(song: artist.songs.first, size: 52, radius: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              artist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            lokalSongCount(artist.songs.length),
            style: TextStyle(fontSize: 13, color: context.lokal.muted),
          ),
          Icon(Icons.chevron_right_rounded, color: context.lokal.muted2),
        ],
      ),
    ),
  );
}

/// An album: cover, name, artist, Play and Shuffle, the tracks, and more by
/// the artist.
class LokalAlbumPage extends StatelessWidget {
  const LokalAlbumPage({
    super.key,
    required this.album,
    this.initialOnline = false,
  });
  final AlbumGroup album;
  final bool initialOnline;
  @override
  Widget build(BuildContext context) => LokalMusicDetailPage.album(
    title: album.albumName,
    artist: album.albumArtist,
    localSongs: album.songs,
    initialOnline: initialOnline,
  );
}

/// An artist: portrait, Play, Shuffle and Radio, top songs, albums.
class LokalArtistPage extends StatelessWidget {
  const LokalArtistPage({
    super.key,
    required this.name,
    required this.songs,
    this.initialOnline = false,
  });
  final String name;
  final List<Song> songs;
  final bool initialOnline;
  @override
  Widget build(BuildContext context) => LokalMusicDetailPage.artist(
    name: name,
    localSongs: songs,
    initialOnline: initialOnline,
  );
}
