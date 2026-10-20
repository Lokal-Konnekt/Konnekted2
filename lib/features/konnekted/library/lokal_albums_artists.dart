import 'dart:async';

import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/features/konnekted/konnekted_data.dart';
import 'package:flick/features/konnekted/konnekted_home.dart';
import 'package:flick/features/player/widgets/add_to_playlist_sheet.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/favorites_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'lokal_library_kit.dart';
import 'lokal_radio.dart';

String _key(String value) => value.trim().toLowerCase();

int _byTrack(Song a, Song b) {
  final disc = (a.discNumber ?? 1).compareTo(b.discNumber ?? 1);
  if (disc != 0) return disc;
  final track = (a.trackNumber ?? 9999).compareTo(b.trackNumber ?? 9999);
  return track != 0
      ? track
      : a.title.toLowerCase().compareTo(b.title.toLowerCase());
}

/// The library's albums, A to Z, each in track order.
List<AlbumGroup> lokalAlbums(Iterable<Song> library) {
  final groups = <String, List<Song>>{};
  for (final song in library) {
    final album = song.album?.trim();
    if (album == null || album.isEmpty) continue;
    final artist = song.albumArtist?.trim().isNotEmpty == true
        ? song.albumArtist!
        : song.artist;
    (groups['${_key(album)}|${_key(artist)}'] ??= []).add(song);
  }
  final albums = [
    for (final entry in groups.entries)
      AlbumGroup(
        key: entry.key,
        albumName: entry.value.first.album!.trim(),
        albumArtist: entry.value.first.albumArtist?.trim().isNotEmpty == true
            ? entry.value.first.albumArtist!
            : entry.value.first.artist,
        songs: entry.value..sort(_byTrack),
      ),
  ];
  albums.sort(
    (a, b) => a.albumName.toLowerCase().compareTo(b.albumName.toLowerCase()),
  );
  return albums;
}

/// One artist and their songs.
@immutable
class LokalArtist {
  const LokalArtist(this.name, this.songs);

  final String name;
  final List<Song> songs;
}

/// The library's artists, A to Z (by album artist, or artist).
List<LokalArtist> lokalArtists(Iterable<Song> library) {
  final names = <String, String>{};
  final songs = <String, List<Song>>{};
  for (final song in library) {
    final name = song.albumArtist?.trim().isNotEmpty == true
        ? song.albumArtist!.trim()
        : song.artist.trim();
    if (name.isEmpty) continue;
    names.putIfAbsent(_key(name), () => name);
    (songs[_key(name)] ??= []).add(song);
  }
  return [
    for (final entry in songs.entries)
      LokalArtist(names[entry.key]!, entry.value),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

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
          : '${all.length} ${widget.title.toLowerCase()}',
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
              title: query.isEmpty ? 'Nothing here yet' : 'No results',
              message: query.isEmpty
                  ? widget.emptyMessage
                  : 'Nothing matches “$_query”.',
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
        title: 'Albums',
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
        title: 'Artists',
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
class LokalAlbumPage extends ConsumerWidget {
  const LokalAlbumPage({super.key, required this.album});

  final AlbumGroup album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.lokal;
    final songs = album.songs;
    final years = {
      for (final s in songs)
        if ((s.year ?? 0) > 0) s.year,
    };
    final genre = songs
        .map((s) => s.genre?.trim() ?? '')
        .firstWhere((g) => g.isNotEmpty, orElse: () => '');
    final meta = [
      if (genre.isNotEmpty) genre,
      if (years.length == 1) '${years.first}',
    ].join(' · ');
    final more = (ref.watch(lokalAlbumsProvider).value ?? const <AlbumGroup>[])
        .where(
          (a) =>
              a.key != album.key &&
              _key(a.albumArtist) == _key(album.albumArtist),
        )
        .toList();
    final favorites = ref.watch(favoritesProvider).value;
    final allLiked =
        favorites != null &&
        songs.isNotEmpty &&
        songs.every((s) => favorites.isFavorite(s.id));
    final multiArtist = songs.any(
      (s) => _key(s.artist) != _key(album.albumArtist),
    );
    final width = MediaQuery.sizeOf(context).width;
    return LokalLibraryPage(
      title: album.albumName,
      actions: [
        PopupMenuButton<String>(
          tooltip: 'More',
          color: t.surface2,
          icon: Icon(Icons.more_horiz_rounded, color: t.text),
          onSelected: (value) => switch (value) {
            'queue' => unawaited(lokalQueueAll(context, ref, songs)),
            'playlist' => unawaited(
              AddToPlaylistSheet.showSongs(context, songs),
            ),
            'like' => unawaited(_likeAll(ref, songs, !allLiked)),
            'radio' => unawaited(
              startLokalRadio(context, artist: album.albumArtist),
            ),
            _ => null,
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'queue', child: Text('Add to queue')),
            const PopupMenuItem(
              value: 'playlist',
              child: Text('Add to a playlist'),
            ),
            PopupMenuItem(
              value: 'like',
              child: Text(allLiked ? 'Unlike all' : 'Like all'),
            ),
            const PopupMenuItem(
              value: 'radio',
              child: Text('Start artist radio'),
            ),
          ],
        ),
      ],
      header: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: Column(
          children: [
            SizedBox.square(
              dimension: (width * .68).clamp(160.0, 320.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _AlbumArt(songs),
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: Text(
                album.albumName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.4,
                ),
              ),
            ),
            const SizedBox(height: 2),
            GestureDetector(
              onTap: () => _openArtist(context, ref, album.albumArtist),
              child: Text(
                album.albumArtist,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: t.accent),
              ),
            ),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(meta.toUpperCase(), style: LokalTheme.label(t)),
            ],
          ],
        ),
      ),
      slivers: [
        SliverToBoxAdapter(child: LokalPlayShufflePills(songs: songs)),
        SliverList.builder(
          itemCount: songs.length,
          itemBuilder: (context, index) {
            final song = songs[index];
            return LokalTrackRow(
              song: song,
              number: song.trackNumber ?? index + 1,
              subtitle: multiArtist ? song.artist : '',
              onTap: () => lokalPlay(context, ref, songs, start: song),
            );
          },
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Text(
              '${lokalSongCount(songs.length)}, ${lokalRunningTime(songs)}',
              style: TextStyle(color: t.muted, fontSize: 13),
            ),
          ),
        ),
        if (more.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: LokalSectionTitle(title: 'More by ${album.albumArtist}'),
          ),
          SliverToBoxAdapter(child: _AlbumShelf(albums: more)),
        ],
      ],
    );
  }
}

Future<void> _likeAll(WidgetRef ref, List<Song> songs, bool like) async {
  final notifier = ref.read(favoritesProvider.notifier);
  for (final song in songs) {
    if (like) {
      await notifier.addFavorite(song.id);
    } else {
      await notifier.removeFavorite(song.id);
    }
  }
}

void _openArtist(BuildContext context, WidgetRef ref, String name) {
  final artists = ref.read(lokalArtistsProvider).value ?? const <LokalArtist>[];
  final match = artists.where((a) => _key(a.name) == _key(name));
  if (match.isEmpty) return;
  unawaited(
    pushLokal(
      context,
      LokalArtistPage(name: match.first.name, songs: match.first.songs),
    ),
  );
}

class _AlbumShelf extends StatelessWidget {
  const _AlbumShelf({required this.albums});

  final List<AlbumGroup> albums;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return SizedBox(
      height: 150 + 46 * scale,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: albums.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final album = albums[index];
          return SizedBox(
            width: 150,
            child: LokalCoverCard(
              art: _AlbumArt(album.songs),
              title: album.albumName,
              subtitle: '${album.songs.first.year ?? album.albumArtist}',
              onTap: () => pushLokal(context, LokalAlbumPage(album: album)),
            ),
          );
        },
      ),
    );
  }
}

/// An artist: portrait, Play, Shuffle and Radio, top songs, albums.
class LokalArtistPage extends ConsumerWidget {
  const LokalArtistPage({super.key, required this.name, required this.songs});

  final String name;
  final List<Song> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.lokal;
    final counts = ref.watch(lokalPlayCountsProvider).value ?? const {};
    final top = List<Song>.of(songs)
      ..sort((a, b) {
        final c = (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0);
        return c != 0
            ? c
            : a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    final albums = lokalAlbums(songs)
      ..sort(
        (a, b) => (b.songs.first.year ?? 0).compareTo(a.songs.first.year ?? 0),
      );
    final width = MediaQuery.sizeOf(context).width;
    return LokalLibraryPage(
      title: name,
      header: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: Column(
          children: [
            KonnektedArtwork(
              song: songs.firstWhere(
                (s) => s.albumArt != null,
                orElse: () => songs.first,
              ),
              size: (width * .5).clamp(140.0, 240.0),
              radius: 999,
            ),
            const SizedBox(height: 14),
            Semantics(
              header: true,
              child: Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.8,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${lokalSongCount(songs.length)} · ${albums.length} '
                      '${albums.length == 1 ? 'album' : 'albums'}'
                  .toUpperCase(),
              style: LokalTheme.label(t),
            ),
          ],
        ),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: LokalPlayShufflePills(
            songs: top,
            extra: LokalPill(
              icon: Icons.radio_rounded,
              label: 'Start radio',
              compact: true,
              onTap: () => startLokalRadio(context, artist: name),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: LokalSectionTitle(
            title: 'Top songs',
            onSeeAll: songs.length > 5
                ? () => pushLokal(
                    context,
                    _ArtistSongsPage(name: name, songs: top),
                  )
                : null,
          ),
        ),
        SliverList.builder(
          itemCount: top.length > 5 ? 5 : top.length,
          itemBuilder: (context, index) => LokalTrackRow(
            song: top[index],
            subtitle: top[index].album ?? '',
            onTap: () => lokalPlay(context, ref, top, start: top[index]),
          ),
        ),
        if (albums.isNotEmpty) ...[
          const SliverToBoxAdapter(child: LokalSectionTitle(title: 'Albums')),
          SliverToBoxAdapter(child: _AlbumShelf(albums: albums)),
        ],
      ],
    );
  }
}

class _ArtistSongsPage extends ConsumerWidget {
  const _ArtistSongsPage({required this.name, required this.songs});

  final String name;
  final List<Song> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) => LokalLibraryPage(
    title: name,
    subtitle: lokalSongCount(songs.length),
    slivers: [
      SliverToBoxAdapter(child: LokalPlayShufflePills(songs: songs)),
      SliverList.builder(
        itemCount: songs.length,
        itemBuilder: (context, index) => LokalTrackRow(
          song: songs[index],
          subtitle: songs[index].album ?? '',
          onTap: () => lokalPlay(context, ref, songs, start: songs[index]),
        ),
      ),
    ],
  );
}
