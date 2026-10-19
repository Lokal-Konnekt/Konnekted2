import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/features/konnekted/lokal_home_greeting.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/favorites_provider.dart';
import 'package:flick/providers/songs_provider.dart';
import 'package:flick/widgets/common/cached_image_widget.dart';
import 'package:flick/widgets/lokal/lokal_cover_flow.dart';
import 'package:flick/widgets/lokal/lokal_glass.dart';
import 'package:flick/widgets/lokal/lokal_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'konnekted_data.dart';
import 'konnekted_destination.dart';
import 'konnekted_style.dart';

class KonnektedHome extends ConsumerWidget {
  const KonnektedHome({
    super.key,
    required this.onNavigate,
    required this.onPlay,
  });

  final ValueChanged<KonnektedDestination> onNavigate;
  final void Function(Song song, List<Song> shelf) onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(konnektedLibraryProvider);
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        key: const PageStorageKey('konnekted-listen'),
        slivers: [
          SliverToBoxAdapter(
            child: KonnektedHomeTopBar(
              greeting: ref.watch(konnektedGreetingProvider).value,
              onSearch: () => onNavigate(KonnektedDestination.search),
              onSettings: () => onNavigate(KonnektedDestination.appearance),
            ),
          ),
          SliverToBoxAdapter(
            child: KonnektedCoverFlowSection(
              onPlay: onPlay,
              onOpenFlow: () => onNavigate(KonnektedDestination.flow),
            ),
          ),
          SliverToBoxAdapter(
            child: library.when(
              loading: () => const KonnektedLoading(),
              error: (_, _) => KonnektedMessage(
                title: 'Your library needs another look',
                message: 'We couldn’t load your music. Try again, or check your music folders in Library.',
                icon: Icons.cloud_off_rounded,
                actionLabel: 'Try again',
                onAction: () => ref.invalidate(songsProvider),
              ),
              data: (songs) => songs.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: KonnektedMessage(
                        title: 'Make room for your favorites',
                        message: 'Add a music folder to start your collection. Your albums, favorites, and listening history will live here.',
                        icon: Icons.library_music_rounded,
                        actionLabel: 'Add your music',
                        onAction: () =>
                            onNavigate(KonnektedDestination.librarySettings),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          SliverToBoxAdapter(
            child: KonnektedSongShelf(
              title: 'On repeat, lately',
              songs: ref.watch(konnektedRecentSongsProvider),
              emptyTitle: 'Your next listen starts a story',
              emptyMessage: 'The music you play will appear here. Pick something from your library to begin.',
              onSeeAll: () => onNavigate(KonnektedDestination.recentlyPlayed),
              onRetry: () => ref.invalidate(konnektedRecentSongsProvider),
              onPlay: onPlay,
            ),
          ),
          SliverToBoxAdapter(
            child: KonnektedSongShelf(
              title: 'Close to your heart',
              songs: ref.watch(konnektedFavoritesProvider),
              emptyTitle: 'Keep the songs you love close',
              emptyMessage:
                  'Tap the heart in the player to build your favorites.',
              onSeeAll: () => onNavigate(KonnektedDestination.favorites),
              onRetry: () => ref.invalidate(favoritesProvider),
              onPlay: onPlay,
            ),
          ),
          SliverToBoxAdapter(
            child: KonnektedSongShelf(
              title: 'Fresh in your library',
              songs: ref.watch(konnektedRecentlyAddedProvider),
              emptyTitle: 'A collection that’s yours',
              emptyMessage:
                  'Newly added music appears here after you scan a folder.',
              onSeeAll: () => onNavigate(KonnektedDestination.recentlyAdded),
              onRetry: () => ref.invalidate(songsProvider),
              onPlay: onPlay,
            ),
          ),
          // The floating dock reserves its height as bottom padding.
          SliverToBoxAdapter(
            child: SizedBox(height: 28 + MediaQuery.paddingOf(context).bottom),
          ),
        ],
      ),
    );
  }
}

/// Home's top bar: the Lokal logo and glass buttons floating over content.
class KonnektedHomeTopBar extends StatelessWidget {
  const KonnektedHomeTopBar({
    super.key,
    required this.onSearch,
    required this.onSettings,
    this.greeting,
    this.now,
  });

  final VoidCallback onSearch;
  final VoidCallback onSettings;

  /// The personal line under the salutation; a time-of-day line until
  /// history has loaded.
  final String? greeting;

  /// The clock, for tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final at = now ?? DateTime.now();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const LokalLogo(size: 32),
              const Spacer(),
              LokalGlassButton(
                semanticLabel: 'Search your music',
                onPressed: onSearch,
                child: Icon(Icons.search_rounded, color: context.lokal.text),
              ),
              const SizedBox(width: 8),
              LokalGlassButton(
                semanticLabel: 'Appearance',
                onPressed: onSettings,
                child: Icon(Icons.tune_rounded, color: context.lokal.text),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Desktop's greeting: a salutation, then a line from your listening.
          Semantics(
            header: true,
            child: Text(
              lokalHomeSalutation(at.hour),
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w600,
                letterSpacing: -.7,
                color: context.lokal.text,
              ),
            ),
          ),
          const SizedBox(height: 2),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Text(
              greeting ?? lokalHomeGreeting(const [], now: at),
              key: ValueKey(greeting),
              style: TextStyle(fontSize: 15, color: context.lokal.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cover Flow of your albums, with a glass shelf switch and the Flow button.
class KonnektedCoverFlowSection extends ConsumerStatefulWidget {
  const KonnektedCoverFlowSection({
    super.key,
    required this.onPlay,
    required this.onOpenFlow,
  });

  final void Function(Song song, List<Song> shelf) onPlay;
  final VoidCallback onOpenFlow;

  @override
  ConsumerState<KonnektedCoverFlowSection> createState() =>
      _KonnektedCoverFlowSectionState();
}

class _KonnektedCoverFlowSectionState
    extends ConsumerState<KonnektedCoverFlowSection> {
  KonnektedCoverShelf _shelf = KonnektedCoverShelf.recent;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    var albums = ref.watch(konnektedCoverAlbumsProvider(_shelf));
    // Nothing played yet: show what's new rather than an empty stage.
    if (_shelf == KonnektedCoverShelf.recent &&
        (albums.value?.isEmpty ?? false)) {
      albums = ref.watch(
        konnektedCoverAlbumsProvider(KonnektedCoverShelf.added),
      );
    }
    final list = albums.value ?? const <AlbumGroup>[];
    // Flow needs no library, so an empty one still gets the way in.
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Center(child: _FlowButton(onTap: widget.onOpenFlow)),
      );
    }
    return Column(
      children: [
        const SizedBox(height: 12),
        LokalGlass.capsule(
          thickness: LokalGlassThickness.thin,
          shadow: false,
          padding: const EdgeInsets.all(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final shelf in KonnektedCoverShelf.values)
                _ShelfChip(
                  label: shelf.label,
                  selected: shelf == _shelf,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _shelf = shelf);
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        LokalCoverFlow(
          key: ValueKey(_shelf),
          albums: list,
          onPlay: widget.onPlay,
          cover: (album) => CachedImageWidget(
            imagePath: _artworkSong(album).albumArt,
            audioSourcePath: _artworkSong(album).filePath,
            fit: BoxFit.cover,
            placeholder: Container(
              color: t.surface3,
              alignment: Alignment.center,
              child: Icon(Icons.album_rounded, color: t.muted, size: 56),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _FlowButton(onTap: widget.onOpenFlow),
      ],
    );
  }

  static Song _artworkSong(AlbumGroup album) => album.songs.firstWhere(
    (song) => song.albumArt?.isNotEmpty == true,
    orElse: () => album.songs.first,
  );
}

class _FlowButton extends StatelessWidget {
  const _FlowButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    return Semantics(
      button: true,
      label: 'Open Flow',
      excludeSemantics: true,
      child: LokalGlass.capsule(
        thickness: LokalGlassThickness.thin,
        shadow: false,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        const Color(0xFF7C6AFF),
                        const Color(0xFFFF6AA8),
                        t.accent,
                        const Color(0xFF7C6AFF),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('FLOW', style: LokalTheme.label(t, color: t.text)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShelfChip extends StatelessWidget {
  const _ShelfChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? (t.isLight
                      ? Colors.black.withValues(alpha: .06)
                      : Colors.white.withValues(alpha: .12))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label.toUpperCase(),
            style: LokalTheme.label(
              t,
              size: 10,
              color: selected ? t.text : t.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class KonnektedSongShelf extends StatelessWidget {
  const KonnektedSongShelf({
    super.key,
    required this.title,
    required this.songs,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.onSeeAll,
    required this.onRetry,
    required this.onPlay,
  });

  final String title;
  final AsyncValue<List<Song>> songs;
  final String emptyTitle;
  final String emptyMessage;
  final VoidCallback onSeeAll;
  final VoidCallback onRetry;
  final void Function(Song, List<Song>) onPlay;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      KonnektedSectionHeading(title: title, onSeeAll: onSeeAll),
      songs.when(
        loading: () => KonnektedLoading(label: 'Loading $title'),
        error: (_, _) => KonnektedMessage(
          title: 'Couldn’t load this shelf',
          message: 'Your music is still yours. Try loading this section again.',
          actionLabel: 'Try again',
          onAction: onRetry,
          icon: Icons.refresh_rounded,
        ),
        data: (items) {
          if (items.isEmpty) {
            return KonnektedMessage(title: emptyTitle, message: emptyMessage);
          }
          final scale = MediaQuery.textScalerOf(context);
          final width = MediaQuery.sizeOf(context).width < 360 ? 142.0 : 164.0;
          final height =
              width + scale.scale(14) * 2.6 + scale.scale(12) * 1.5 + 24;
          return SizedBox(
            height: height,
            child: ListView.separated(
              key: PageStorageKey('shelf-$title'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: items.length > 12 ? 12 : items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final song = items[index];
                return SizedBox(
                  width: width,
                  child: Semantics(
                    button: true,
                    label: 'Play ${song.title} by ${song.artist}',
                    onTap: () => onPlay(song, items),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => onPlay(song, items),
                      excludeFromSemantics: true,
                      child: ExcludeSemantics(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            KonnektedArtwork(
                              song: song,
                              size: width,
                              radius: 16,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              song.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.3,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                color: context.lokal.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    ],
  );
}

class KonnektedArtwork extends StatelessWidget {
  const KonnektedArtwork({
    super.key,
    required this.song,
    required this.size,
    this.radius = 10,
  });

  final Song song;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: context.lokal.surface3,
      alignment: Alignment.center,
      child: Icon(
        Icons.music_note_rounded,
        color: context.lokal.accent,
        size: size * .35,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedImageWidget(
        imagePath: song.albumArt,
        audioSourcePath: song.filePath,
        width: size,
        height: size,
        useThumbnail: true,
        placeholder: placeholder,
        errorWidget: placeholder,
      ),
    );
  }
}
