import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/discovery/discovery_artwork.dart';
import 'package:flick/features/discovery/discovery_models.dart';
import 'package:flick/features/discovery/lastfm_discovery.dart';
import 'package:flick/features/discovery/youtube_music_account.dart';
import 'package:flick/features/discovery/youtube_music_sign_in.dart';
import 'package:flick/models/song.dart';
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
    this.findSong = findDiscoverySong,
  });

  final ValueChanged<KonnektedDestination> onNavigate;
  final void Function(Song song, List<Song> shelf) onPlay;

  /// Looks for a song you don't have on YouTube Music and your add-ons;
  /// replaced in tests.
  final Future<Song?> Function(
    LokalDiscoveryTrack track, {
    void Function(String status)? onStatus,
    Set<String> Function()? additionalProtectedPaths,
  })
  findSong;

  @override
  ConsumerState<KonnektedDiscoveryView> createState() =>
      _KonnektedDiscoveryViewState();
}

enum _Shelf { fresh, liked, quick, history }

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

  Future<void> _connectYoutubeMusic() async {
    try {
      final session = await YoutubeMusicSignInSheet.show(context);
      if (!mounted || session == null) return;
      await ref
          .read(konnektedYoutubeMusicSessionProvider.notifier)
          .save(session);
      final discovery = ref.read(konnektedDiscoveryProvider.notifier);
      if (ref.read(konnektedDiscoveryProvider).source ==
          KonnektedDiscoverySource.youtube) {
        await discovery.load(refresh: true);
      } else {
        await discovery.setSource(KonnektedDiscoverySource.youtube);
      }
    } catch (_) {
      if (mounted) _say('Could not sign in to YouTube Music. Try again.');
    }
  }

  Future<void> _playMix(LokalDiscoveryMix mix) async {
    final account = ref.read(konnektedYoutubeMusicAccountProvider);
    if (account == null) {
      await _connectYoutubeMusic();
      return;
    }
    if (_busy != null) return;
    setState(() => _busy = 'mix:' + mix.id);
    _say('Loading ' + mix.title + '…');
    try {
      final tracks = await youtubeMusicMix(account, mix.id);
      if (!mounted) return;
      if (tracks.isEmpty) {
        _say('This mix did not return any playable tracks.');
        return;
      }
      // A local copy costs nothing to stage. Provider tracks are prepared by
      // their video IDs directly, with a conservative queue bound for cache use.
      final songs = <Song>[];
      final seen = <String>{};
      final stagedPaths = <String>{};
      for (final track in tracks.take(8)) {
        final own = _library().match(track);
        if (own != null) {
          if (seen.add(own.id)) songs.add(own);
          continue;
        }
        try {
          final song = await widget.findSong(
            track,
            onStatus: (status) {
              if (mounted) _say(status);
            },
            additionalProtectedPaths: () => stagedPaths,
          );
          if (song != null) {
            if (song.filePath case final String path) stagedPaths.add(path);
            if (seen.add(song.id)) songs.add(song);
          }
        } catch (_) {
          // Keep valid tracks in the mix when one recording is unavailable.
        }
        if (!mounted) return;
      }
      if (songs.isEmpty) {
        _say('No tracks from this mix could be prepared.');
      } else {
        ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
        widget.onPlay(songs.first, songs);
      }
    } on YoutubeMusicSignedOut catch (error) {
      await ref.read(konnektedYoutubeMusicSessionProvider.notifier).signOut();
      if (mounted) _say(error.message);
    } catch (_) {
      if (mounted) {
        _say('Could not load this YouTube Music mix. Refresh and try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  KonnektedLibraryIndex _library() => KonnektedLibraryIndex.of(
    ref.read(konnektedLibraryProvider).value ?? const [],
  );

  /// Plays your copy when you have it, with the shelf's other songs you
  /// have after it; otherwise finds it on YouTube Music or your add-ons.
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
    _say('Looking for ${track.title}…');
    try {
      final song = await widget.findSong(
        track,
        onStatus: (status) {
          if (mounted) _say(status);
        },
      );
      if (!mounted) return;
      if (song == null) {
        _say('Couldn’t find ${track.title} on YouTube Music or your add-ons.');
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
    final liked = data?.liked ?? const <LokalDiscoveryTrack>[];
    final quick = data?.quickPicks ?? const <LokalDiscoveryTrack>[];
    final history = data?.history ?? const <LokalDiscoveryTrack>[];
    final mixes = data?.mixes ?? const <LokalDiscoveryMix>[];
    final source = discovery.source;
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
          source: source,
          onSourceChanged: (next) {
            HapticFeedback.selectionClick();
            ref.read(konnektedDiscoveryProvider.notifier).setSource(next);
          },
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
        if (!discovery.connected && source == KonnektedDiscoverySource.youtube)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: KonnektedMessage(
              title: 'Sign in to YouTube Music',
              message: 'Connect your account to see your mixes, Likes, history and personalized picks.',
              icon: Icons.music_note_rounded,
              actionLabel: 'Sign in',
              onAction: _connectYoutubeMusic,
            ),
          )
        else if (!discovery.connected &&
            source == KonnektedDiscoverySource.lastfm)
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
        else if (source == KonnektedDiscoverySource.spotify)
          const Padding(
            padding: EdgeInsets.only(top: 20),
            child: KonnektedMessage(
              title: 'Spotify Discovery is coming soon',
              message: 'Select Last.fm or YouTube Music for account-based recommendations.',
              icon: Icons.music_note_rounded,
            ),
          )
        else if (data == null && discovery.loading)
          KonnektedLoading(
            label: source == KonnektedDiscoverySource.youtube
                ? 'Loading your YouTube Music shelves…'
                : 'Building your Last.fm recommendations…',
          )
        else if (data != null && data.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: KonnektedMessage(
              title: 'Nothing to recommend yet',
              message: source == KonnektedDiscoverySource.youtube
                  ? 'No YouTube Music recommendations were returned. Refresh to retry.'
                  : 'No Last.fm recommendations are available yet. Scrobble a few songs, then refresh.',
              icon: Icons.auto_awesome_rounded,
            ),
          ),
        if (source == KonnektedDiscoverySource.youtube && mixes.isNotEmpty) ...[
          const KonnektedSectionHeading(
            title: 'Mixed for you',
            icon: Icons.queue_music_rounded,
            subtitle: 'Your YouTube Music radio mixes.',
          ),
          _MixShelf(
            mixes: mixes,
            busyId: _busy?.startsWith('mix:') == true
                ? _busy!.substring(4)
                : null,
            onTap: _playMix,
          ),
        ],
        if (source == KonnektedDiscoverySource.youtube &&
            data?.mixError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              data!.mixError!,
              style: TextStyle(fontSize: 12, color: t.muted),
            ),
          ),
        if (source == KonnektedDiscoverySource.youtube && liked.isNotEmpty) ...[
          heading(
            _Shelf.liked,
            'Your Likes',
            Icons.thumb_up_alt_rounded,
            liked.length,
            subtitle: 'Songs you liked on YouTube Music.',
          ),
          tracks(_Shelf.liked, liked),
        ],
        if (fresh.isNotEmpty) ...[
          heading(
            _Shelf.fresh,
            'Fresh Finds',
            Icons.music_note_rounded,
            fresh.length,
            subtitle: source == KonnektedDiscoverySource.youtube
                ? 'More from your YouTube Music home page.'
                : 'More music from Last.fm.',
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
            source == KonnektedDiscoverySource.youtube
                ? 'History'
                : 'Scrobble History',
            Icons.history_rounded,
            history.length,
            subtitle: source == KonnektedDiscoverySource.youtube
                ? 'Your YouTube Music listening history.'
                : 'Your last 100 scrobbles, by day.',
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
        if (source == KonnektedDiscoverySource.lastfm && albums.isNotEmpty) ...[
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

/// Discovery's title row and provider switch.
class _Header extends StatelessWidget {
  const _Header({
    required this.loading,
    required this.source,
    required this.onSourceChanged,
    required this.onRefresh,
  });

  final bool loading;
  final KonnektedDiscoverySource source;
  final ValueChanged<KonnektedDiscoverySource> onSourceChanged;
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
                          switch (source) {
                            KonnektedDiscoverySource.lastfm => 'LAST.FM',
                            KonnektedDiscoverySource.youtube => 'YOUTUBE MUSIC',
                            KonnektedDiscoverySource.spotify => 'SPOTIFY',
                          },
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ProviderChip(
                        label: 'Last.fm',
                        selected: source == KonnektedDiscoverySource.lastfm,
                        onTap: () =>
                            onSourceChanged(KonnektedDiscoverySource.lastfm),
                      ),
                      _ProviderChip(
                        label: 'YouTube Music',
                        selected: source == KonnektedDiscoverySource.youtube,
                        onTap: () =>
                            onSourceChanged(KonnektedDiscoverySource.youtube),
                      ),
                      _ProviderChip(label: 'Spotify', comingSoon: true),
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
  const _ProviderChip({
    required this.label,
    this.selected = false,
    this.onTap,
    this.comingSoon = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool comingSoon;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      label: comingSoon ? '$label, coming soon' : label,
      excludeSemantics: true,
      child: Tooltip(
        message: comingSoon ? '$label is coming soon' : label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
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
                  color: selected
                      ? t.onAccent
                      : t.muted.withValues(alpha: comingSoon ? .45 : .8),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Horizontal cards for provider-native radio mixes.
class _MixShelf extends StatelessWidget {
  const _MixShelf({required this.mixes, required this.onTap, this.busyId});

  final List<LokalDiscoveryMix> mixes;
  final ValueChanged<LokalDiscoveryMix> onTap;
  final String? busyId;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    return SizedBox(
      height: 205,
      child: ListView.separated(
        key: const PageStorageKey('youtube-music-mixes'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: mixes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final mix = mixes[index];
          final busy = busyId == mix.id;
          final placeholder = Container(
            color: t.surface3,
            alignment: Alignment.center,
            child: Icon(Icons.queue_music_rounded, color: t.accent, size: 32),
          );
          return SizedBox(
            width: 136,
            child: Semantics(
              button: true,
              label: 'Play mix ' + mix.title,
              excludeSemantics: true,
              child: InkWell(
                onTap: busy ? null : () => onTap(mix),
                borderRadius: BorderRadius.circular(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox.square(
                        dimension: 136,
                        child: busy
                            ? Container(
                                color: t.surface3,
                                alignment: Alignment.center,
                                child: CircularProgressIndicator(
                                  color: t.accent,
                                ),
                              )
                            : DiscoveryArtwork(
                                kind: DiscoveryArtworkKind.album,
                                title: mix.title,
                                artist: mix.author,
                                url: mix.artworkUrl,
                                width: 136,
                                height: 136,
                                placeholder: placeholder,
                              ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      mix.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: t.text,
                      ),
                    ),
                    if (mix.author.isNotEmpty)
                      Text(
                        mix.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: t.muted),
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
                  child: DiscoveryArtwork(
                    kind: DiscoveryArtworkKind.track,
                    title: track.title,
                    artist: track.artist,
                    url: track.artworkUrl,
                    width: 52,
                    height: 52,
                    placeholder: placeholder,
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
                        child: DiscoveryArtwork(
                          kind: DiscoveryArtworkKind.album,
                          title: album.title,
                          artist: album.artist,
                          url: album.artworkUrl,
                          width: size,
                          height: size,
                          placeholder: placeholder,
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
                        child: DiscoveryArtwork(
                          kind: DiscoveryArtworkKind.artist,
                          artist: artist.name,
                          url: artist.image,
                          width: size,
                          height: size,
                          placeholder: placeholder,
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
