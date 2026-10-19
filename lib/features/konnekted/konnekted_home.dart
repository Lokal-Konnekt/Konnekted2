import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/favorites_provider.dart';
import 'package:flick/providers/songs_provider.dart';
import 'package:flick/widgets/common/cached_image_widget.dart';
import 'package:flutter/material.dart';
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
            child: KonnektedHeading(
              title: 'Listen now',
              eyebrow: 'Konnekted · Your music, closer',
              action: IconButton.filledTonal(
                tooltip: 'Search your music',
                onPressed: () => onNavigate(KonnektedDestination.search),
                icon: const Icon(Icons.search_rounded),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: KonnektedFlowHero(
              onOpen: () => onNavigate(KonnektedDestination.flow),
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
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }
}

class KonnektedFlowHero extends StatelessWidget {
  const KonnektedFlowHero({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Semantics(
      button: true,
      label: 'Open Flow, your personal music mix',
      onTap: onOpen,
      child: Material(
        color: const Color(0xFF472235),
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF713B5C), Color(0xFF762D47), Color(0xFF362236)],
            ),
          ),
          child: InkWell(
            onTap: onOpen,
            excludeFromSemantics: true,
            child: Stack(
              children: [
                Positioned(
                  right: -40,
                  top: -48,
                  child: ExcludeSemantics(
                    child: Transform.rotate(
                      angle: -.35,
                      child: Icon(
                        Icons.all_inclusive_rounded,
                        size: 260,
                        color: Colors.white.withValues(alpha: .08),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'MADE FROM YOUR MUSIC',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFFFD6CE),
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Find your\nFlow ∞',
                        style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.6,
                          height: 1.02,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'A familiar favorite. A new direction.\nLet your library set the mood.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: Color(0xFFFFE5E7),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE9DF),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                'Open Flow',
                                style: TextStyle(
                                  color: Color(0xFF432532),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            SizedBox(width: 10),
                            Icon(
                              Icons.arrow_forward_rounded,
                              color: Color(0xFF432532),
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
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
