import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/discovery/discovery_models.dart';
import 'package:flick/features/discovery/lastfm_discovery.dart';
import 'package:flick/models/song.dart';
import 'package:flick/widgets/common/cached_image_widget.dart';
import 'package:flick/widgets/lokal/lokal_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'konnekted_data.dart';
import 'konnekted_destination.dart';
import 'konnekted_discovery.dart';
import 'konnekted_style.dart';

/// Home's Discovery tab, desktop's `RecommendationSections`: Fresh Finds,
/// Quick Picks, Scrobble History, Albums and Artists For You, from Last.fm.
class KonnektedDiscoveryView extends ConsumerStatefulWidget {
  const KonnektedDiscoveryView({
    super.key,
    required this.onNavigate,
    required this.onPlay,
    this.findOnAddons = findDiscoverySongOnAddons,
  });

  final ValueChanged<KonnektedDestination> onNavigate;
  final void Function(Song song, List<Song> shelf) onPlay;

  /// Looks for a song you don't have on your add-ons; replaced in tests.
  final Future<Song?> Function(
    LokalDiscoveryTrack track, {
    void Function(String status)? onStatus,
  })
  findOnAddons;

  @override
  ConsumerState<KonnektedDiscoveryView> createState() =>
      _KonnektedDiscoveryViewState();
}

enum _Shelf { fresh, quick, history }

class _KonnektedDiscoveryViewState
    extends ConsumerState<KonnektedDiscoveryView> {
  _Shelf? _open;
  String? _busy;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(konnektedDiscoveryProvider.notifier).load();
    });
  }

  void _toggle(_Shelf shelf) =>
      setState(() => _open = _open == shelf ? null : shelf);

  void _say(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  KonnektedLibraryIndex _library() => KonnektedLibraryIndex.of(
    ref.read(konnektedLibraryProvider).value ?? const [],
  );

  /// Plays your copy when you have it, with the shelf's other songs you
  /// have after it; otherwise looks on your add-ons.
  Future<void> _play(
    LokalDiscoveryTrack track,
    List<LokalDiscoveryTrack> shelf,
  ) async {
    final library = _library();
    final own = library.match(track);
    if (own != null) {
      final queue = library.matchAll(shelf);
      widget.onPlay(own, queue.contains(own) ? queue : [own, ...queue]);
      return;
    }
    if (_busy != null) return;
    setState(() => _busy = track.key);
    _say('Looking for ${track.title} on your add-ons…');
    try {
      final song = await widget.findOnAddons(
        track,
        onStatus: (status) {
          if (mounted) _say(status);
        },
      );
      if (!mounted) return;
      if (song == null) {
        _say(
          '${track.title} isn’t in your library, and none of your add-ons has it.',
        );
      } else {
        ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
        widget.onPlay(song, [song]);
      }
    } catch (error) {
      if (mounted) _say(discoveryError(error));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _playSongs(List<Song> songs, String missing) {
    if (songs.isEmpty) {
      _say(missing);
    } else {
      widget.onPlay(songs.first, songs);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    final discovery = ref.watch(konnektedDiscoveryProvider);
    final data = discovery.data;
    // Rebuild when the library changes, so "in your library" stays right.
    final library = KonnektedLibraryIndex.of(
      ref.watch(konnektedLibraryProvider).value ?? const [],
    );
    final fresh = data?.freshFinds ?? const <LokalDiscoveryTrack>[];
    final quick = data?.quickPicks ?? const <LokalDiscoveryTrack>[];
    final history = data?.history ?? const <LokalDiscoveryTrack>[];
    final albums = data?.albums ?? const <LokalDiscoveryAlbum>[];
    final artists = data?.artists ?? const <LokalDiscoveryArtist>[];

    Widget tracks(_Shelf shelf, List<LokalDiscoveryTrack> items) => Column(
      children: [
        for (final track in _open == shelf ? items : items.take(6))
          KonnektedDiscoveryRow(
            track: track,
            inLibrary: library.match(track) != null,
            busy: _busy == track.key,
            trailing: shelf == _Shelf.quick && (track.scrobbleCount ?? 0) > 1
                ? '×${track.scrobbleCount}'
                : null,
            onTap: () => _play(track, items),
          ),
      ],
    );

    KonnektedSectionHeading heading(
      _Shelf shelf,
      String title,
      IconData icon,
      int count, {
      String? subtitle,
      int shown = 6,
    }) => KonnektedSectionHeading(
      title: title,
      icon: icon,
      subtitle: subtitle,
      onSeeAll: count > shown ? () => _toggle(shelf) : null,
      seeAllLabel: _open == shelf ? 'Show less' : 'See all',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          loading: discovery.loading,
          onRefresh: () {
            HapticFeedback.selectionClick();
            ref.read(konnektedDiscoveryProvider.notifier).load(refresh: true);
          },
        ),
        if (discovery.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Semantics(
              liveRegion: true,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF87171).withValues(alpha: .1),
                  border: Border.all(
                    color: const Color(0xFFF87171).withValues(alpha: .25),
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  discovery.error!,
                  style: TextStyle(
                    fontSize: 13,
                    color: t.isLight
                        ? const Color(0xFFB91C1C)
                        : const Color(0xFFFECACA),
                  ),
                ),
              ),
            ),
          ),
        if (!discovery.connected)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: KonnektedMessage(
              title: 'Connect Last.fm for Discovery',
              message: 'Discovery recommends music from your Last.fm scrobbles. Sign in to Last.fm in Integrations to see your shelves.',
              icon: Icons.auto_awesome_rounded,
              actionLabel: 'Open Integrations',
              onAction: () =>
                  widget.onNavigate(KonnektedDestination.integrations),
            ),
          )
        else if (data == null && discovery.loading)
          const KonnektedLoading(
            label: 'Building your Last.fm recommendations…',
          )
        else if (data != null && data.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 20),
            child: KonnektedMessage(
              title: 'Nothing to recommend yet',
              message: 'No Last.fm recommendations are available yet. Scrobble a few songs, then refresh.',
              icon: Icons.auto_awesome_rounded,
            ),
          ),
        if (fresh.isNotEmpty) ...[
          heading(
            _Shelf.fresh,
            'Fresh Finds',
            Icons.music_note_rounded,
            fresh.length,
            subtitle: 'More music from Last.fm.',
          ),
          tracks(_Shelf.fresh, fresh),
        ],
        if (quick.isNotEmpty) ...[
          heading(
            _Shelf.quick,
            'Quick Picks',
            Icons.auto_awesome_rounded,
            quick.length,
            subtitle: 'Tracks you scrobbled most often over the past week.',
          ),
          tracks(_Shelf.quick, quick),
        ],
        if (history.isNotEmpty) ...[
          heading(
            _Shelf.history,
            'Scrobble History',
            Icons.history_rounded,
            history.length,
            subtitle: 'Your last 100 scrobbles, by day.',
          ),
          _History(
            entries: _open == _Shelf.history
                ? history
                : history.take(6).toList(),
            row: (track) => KonnektedDiscoveryRow(
              track: track,
              inLibrary: library.match(track) != null,
              busy: _busy == track.key,
              trailing: track.scrobbledAt == null
                  ? null
                  : DateFormat.Hm().format(
                      DateTime.fromMillisecondsSinceEpoch(
                        track.scrobbledAt! * 1000,
                      ),
                    ),
              onTap: () => _play(track, history),
            ),
          ),
        ],
        if (albums.isNotEmpty) ...[
          const KonnektedSectionHeading(
            title: 'Albums For You',
            icon: Icons.album_rounded,
          ),
          _AlbumShelf(
            albums: albums,
            onTap: (album) => _playSongs(
              _library().album(album.title, album.artist),
              '${album.title} isn’t in your library yet.',
            ),
          ),
        ],
        if (artists.isNotEmpty) ...[
          const KonnektedSectionHeading(
            title: 'Artists For You',
            icon: Icons.person_rounded,
          ),
          _ArtistShelf(
            artists: artists,
            onTap: (artist) => _playSongs(
              _library().artist(artist.name),
              'No songs by ${artist.name} in your library yet.',
            ),
          ),
        ],
      ],
    );
  }
}

/// Discovery's title row: where the picks come from, the provider switch and
/// Refresh. YouTube Music and Spotify join Last.fm next.
class _Header extends StatelessWidget {
  const _Header({required this.loading, required this.onRefresh});

  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 17,
                  color: t.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Discovery',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: t.text,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'LAST.FM',
                          style: LokalTheme.label(t, size: 10, color: t.muted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Personalized recommendations from your selected provider.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: t.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Wraps on narrow screens and large text instead of overflowing.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              // Shrinks rather than overflowing with very large text.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: LokalGlass.capsule(
                  thickness: LokalGlassThickness.thin,
                  shadow: false,
                  padding: const EdgeInsets.all(3),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ProviderChip(label: 'Last.fm', selected: true),
                      _ProviderChip(label: 'YouTube Music'),
                      _ProviderChip(label: 'Spotify'),
                    ],
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: loading ? null : onRefresh,
                icon: loading
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: t.accent,
                        ),
                      )
                    : const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProviderChip extends StatelessWidget {
  const _ProviderChip({required this.label, this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    return Semantics(
      button: true,
      selected: selected,
      enabled: selected,
      label: selected ? label : '$label, coming soon',
      excludeSemantics: true,
      child: Tooltip(
        message: selected ? label : '$label is coming soon',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? t.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: selected ? t.onAccent : t.muted.withValues(alpha: .55),
            ),
          ),
        ),
      ),
    );
  }
}

/// A recommended song: its cover, title, artist and why it's here. A check
/// marks songs you have, which play straight away.
class KonnektedDiscoveryRow extends StatelessWidget {
  const KonnektedDiscoveryRow({
    super.key,
    required this.track,
    required this.onTap,
    this.inLibrary = false,
    this.busy = false,
    this.trailing,
  });

  final LokalDiscoveryTrack track;
  final VoidCallback onTap;
  final bool inLibrary;
  final bool busy;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    final placeholder = Container(
      color: t.surface3,
      alignment: Alignment.center,
      child: Icon(Icons.music_note_rounded, color: t.accent, size: 20),
    );
    return Semantics(
      button: true,
      label:
          'Play ${track.title} by ${track.artist}${inLibrary ? ', in your library' : ''}',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox.square(
                  dimension: 52,
                  child: track.artworkUrl.isEmpty
                      ? placeholder
                      : CachedImageWidget(
                          imagePath: track.artworkUrl,
                          width: 52,
                          height: 52,
                          placeholder: placeholder,
                          errorWidget: placeholder,
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: t.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: t.muted),
                    ),
                    if (track.reason != null)
                      Text(
                        track.reason!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: t.muted.withValues(alpha: .75),
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 10),
                Text(
                  trailing!,
                  style: LokalTheme.label(t, size: 11, color: t.muted),
                ),
              ],
              const SizedBox(width: 10),
              SizedBox(
                width: 18,
                child: busy
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: t.accent,
                        ),
                      )
                    : inLibrary
                    ? Icon(
                        Icons.check_circle_rounded,
                        size: 16,
                        color: t.accent,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scrobbles under a heading per day, as desktop's Scrobble History.
class _History extends StatelessWidget {
  const _History({required this.entries, required this.row});

  final List<LokalDiscoveryTrack> entries;
  final Widget Function(LokalDiscoveryTrack track) row;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    final days = <String, List<LokalDiscoveryTrack>>{};
    for (final track in entries) {
      final day = track.scrobbledAt == null
          ? 'Earlier'
          : DateFormat.MMMMEEEEd().format(
              DateTime.fromMillisecondsSinceEpoch(track.scrobbledAt! * 1000),
            );
      days.putIfAbsent(day, () => []).add(track);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final MapEntry(key: day, value: tracks) in days.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(
              children: [
                Icon(Icons.calendar_today_rounded, size: 12, color: t.muted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    day.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LokalTheme.label(t, size: 10, color: t.muted),
                  ),
                ),
              ],
            ),
          ),
          for (final track in tracks) row(track),
        ],
      ],
    );
  }
}

class _AlbumShelf extends StatelessWidget {
  const _AlbumShelf({required this.albums, required this.onTap});

  final List<LokalDiscoveryAlbum> albums;
  final ValueChanged<LokalDiscoveryAlbum> onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    const size = 148.0;
    final scale = MediaQuery.textScalerOf(context);
    return SizedBox(
      height: size + scale.scale(14) * 1.4 + scale.scale(12) * 1.5 + 18,
      child: ListView.separated(
        key: const PageStorageKey('discovery-albums'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: albums.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final album = albums[index];
          final placeholder = Container(
            color: t.surface3,
            alignment: Alignment.center,
            child: Icon(Icons.album_rounded, color: t.muted, size: 48),
          );
          return Semantics(
            button: true,
            label: 'Play ${album.title} by ${album.artist}',
            excludeSemantics: true,
            onTap: () => onTap(album),
            child: GestureDetector(
              onTap: () => onTap(album),
              child: SizedBox(
                width: size,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox.square(
                        dimension: size,
                        child: album.artworkUrl.isEmpty
                            ? placeholder
                            : CachedImageWidget(
                                imagePath: album.artworkUrl,
                                width: size,
                                height: size,
                                placeholder: placeholder,
                                errorWidget: placeholder,
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      album.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      album.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: t.muted),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ArtistShelf extends StatelessWidget {
  const _ArtistShelf({required this.artists, required this.onTap});

  final List<LokalDiscoveryArtist> artists;
  final ValueChanged<LokalDiscoveryArtist> onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    const size = 96.0;
    final scale = MediaQuery.textScalerOf(context);
    return SizedBox(
      height: size + scale.scale(13) * 1.4 + 14,
      child: ListView.separated(
        key: const PageStorageKey('discovery-artists'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: artists.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final artist = artists[index];
          final initial = artist.name.characters.first.toUpperCase();
          final placeholder = Container(
            color: t.accent.withValues(alpha: .14),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w600,
                color: t.accent,
              ),
            ),
          );
          return Semantics(
            button: true,
            label: 'Play songs by ${artist.name}',
            excludeSemantics: true,
            onTap: () => onTap(artist),
            child: GestureDetector(
              onTap: () => onTap(artist),
              child: SizedBox(
                width: size,
                child: Column(
                  children: [
                    ClipOval(
                      child: SizedBox.square(
                        dimension: size,
                        child: artist.image.isEmpty
                            ? placeholder
                            : CachedImageWidget(
                                imagePath: artist.image,
                                width: size,
                                height: size,
                                placeholder: placeholder,
                                errorWidget: placeholder,
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      artist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
