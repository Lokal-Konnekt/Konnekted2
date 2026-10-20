import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/features/konnekted/lokal_home_greeting.dart';
import 'package:flick/features/konnekted/lokal_mixes.dart';
import 'package:flick/features/settings/lokal/lokal_settings_group.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/favorites_provider.dart';
import 'package:flick/providers/songs_provider.dart';
import 'package:flick/widgets/common/cached_image_widget.dart';
import 'package:flick/widgets/lokal/lokal_cover_flow.dart';
import 'package:flick/widgets/lokal/lokal_glass.dart';
import 'package:flick/widgets/lokal/lokal_logo.dart';
import 'package:flick/widgets/lokal/lokal_made_for_you.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'konnekted_data.dart';
import 'konnekted_destination.dart';
import 'konnekted_discovery_view.dart';
import 'konnekted_style.dart';

/// Home's tabs, as desktop's: your library, and Discovery.
enum KonnektedHomeTab {
  local('Local'),
  discovery('Discovery');

  const KonnektedHomeTab(this.label);
  final String label;
}

/// Where "Add your music" leads: Settings › Library › Folders.
const _addMusic = KonnektedDestination.settingsAt(
  LokalSettingsGroup.library,
  section: 'Folders',
);

class KonnektedHome extends ConsumerStatefulWidget {
  const KonnektedHome({
    super.key,
    required this.onNavigate,
    required this.onPlay,
  });

  final ValueChanged<KonnektedDestination> onNavigate;
  final void Function(Song song, List<Song> shelf) onPlay;

  @override
  ConsumerState<KonnektedHome> createState() => _KonnektedHomeState();
}

class _KonnektedHomeState extends ConsumerState<KonnektedHome> {
  late KonnektedHomeTab _tab =
      PageStorage.maybeOf(context)
              ?.readState(context, identifier: 'konnekted-home-tab')
          as KonnektedHomeTab? ??
      KonnektedHomeTab.local;

  void _select(KonnektedHomeTab tab) {
    if (tab == _tab) return;
    HapticFeedback.selectionClick();
    PageStorage.maybeOf(context)
        ?.writeState(context, tab, identifier: 'konnekted-home-tab');
    setState(() => _tab = tab);
  }

  ValueChanged<KonnektedDestination> get onNavigate => widget.onNavigate;
  void Function(Song song, List<Song> shelf) get onPlay => widget.onPlay;

  @override
  Widget build(BuildContext context) {
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
              onSettings: () => onNavigate(KonnektedDestination.settings),
              onAppearance: () => onNavigate(
                const KonnektedDestination.settingsAt(
                  LokalSettingsGroup.appearance,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Center(
                child: LokalGlass.capsule(
                  thickness: LokalGlassThickness.thin,
                  shadow: false,
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final tab in KonnektedHomeTab.values)
                        _ShelfChip(
                          label: tab.label,
                          selected: tab == _tab,
                          onTap: () => _select(tab),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_tab == KonnektedHomeTab.discovery)
            SliverToBoxAdapter(
              child: KonnektedDiscoveryView(
                onNavigate: onNavigate,
                onPlay: onPlay,
              ),
            )
          else ...[
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
                          onAction: () => onNavigate(_addMusic),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            SliverToBoxAdapter(
              child: KonnektedMadeForYou(
                picks: ref.watch(konnektedMadeForYouProvider).value ?? const [],
                onPlay: onPlay,
              ),
            ),
            SliverToBoxAdapter(
              child: KonnektedYourMixes(
                mixes: ref.watch(konnektedMixesProvider).value ?? const [],
                onPlay: onPlay,
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
          ],
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
    required this.onAppearance,
    this.greeting,
    this.now,
  });

  final VoidCallback onSearch;
  final VoidCallback onSettings;

  /// Opens Appearance, from the logo.
  final VoidCallback onAppearance;

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
              Semantics(
                button: true,
                label: 'Appearance',
                excludeSemantics: true,
                onTap: onAppearance,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onAppearance();
                  },
                  child: const LokalLogo(size: 32),
                ),
              ),
              const Spacer(),
              LokalGlassButton(
                semanticLabel: 'Search your music',
                onPressed: onSearch,
                child: Icon(Icons.search_rounded, color: context.lokal.text),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Settings',
                excludeFromSemantics: true,
                child: LokalGlassButton(
                  semanticLabel: 'Settings',
                  onPressed: onSettings,
                  child: Icon(
                    Icons.settings_rounded,
                    color: context.lokal.text,
                  ),
                ),
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

/// Cover Flow of songs (recent, made for you, new), with a glass shelf
/// switch and the Flow button. One tap on a cover plays that song, with the
/// whole shelf as the queue.
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
    // Nothing played (or mixed) yet: show what's new, not an empty stage.
    if (_shelf != KonnektedCoverShelf.added &&
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
          onSelect: (i) => widget.onPlay(list[i].songs.first, [
            for (final entry in list) ...entry.songs,
          ]),
          cover: (entry) {
            final placeholder = Container(
              color: t.surface3,
              alignment: Alignment.center,
              child: Icon(Icons.music_note_rounded, color: t.muted, size: 56),
            );
            return CachedImageWidget(
              imagePath: entry.songs.first.albumArt,
              audioSourcePath: entry.songs.first.filePath,
              fit: BoxFit.cover,
              placeholder: placeholder,
              errorWidget: placeholder,
            );
          },
        ),
        const SizedBox(height: 14),
        _FlowButton(onTap: widget.onOpenFlow),
      ],
    );
  }
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

/// Made for you: twelve songs, two from each of Your Mixes, on desktop's
/// rolling carousel. Hidden until there are mixes.
class KonnektedMadeForYou extends StatelessWidget {
  const KonnektedMadeForYou({
    super.key,
    required this.picks,
    required this.onPlay,
  });

  final List<LokalMadeForYouPick> picks;
  final void Function(Song song, List<Song> queue) onPlay;

  @override
  Widget build(BuildContext context) {
    if (picks.isEmpty) return const SizedBox.shrink();
    final songs = [for (final pick in picks) pick.song];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const KonnektedSectionHeading(
          title: 'Made for you',
          icon: Icons.auto_awesome_rounded,
        ),
        LokalMadeForYouCarousel(
          count: picks.length,
          semanticLabel: (index) =>
              'Play ${picks[index].song.title} by ${picks[index].song.artist}',
          onPlay: (index) {
            HapticFeedback.lightImpact();
            onPlay(songs[index], songs);
          },
          card: (context, index) => _MadeForYouCard(pick: picks[index]),
        ),
      ],
    );
  }
}

class _MadeForYouCard extends StatelessWidget {
  const _MadeForYouCard({required this.pick});

  final LokalMadeForYouPick pick;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    final song = pick.song;
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withValues(alpha: .10), Colors.black],
        ),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        // Desktop's lift; softer on light themes, where black reads heavy.
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: t.isLight ? .18 : .45),
            blurRadius: 40,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: t.surface2),
            CachedImageWidget(
              imagePath: song.albumArt,
              audioSourcePath: song.filePath,
              fit: BoxFit.cover,
              useThumbnail: true,
              placeholder: placeholder,
              errorWidget: placeholder,
            ),
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Color(0xD9000000),
                      Color(0x66000000),
                      Color(0x00000000),
                    ],
                    stops: [0, .33, .67],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .7),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      pick.mix.title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LokalTheme.label(
                        t,
                        size: 9,
                        color: Colors.white.withValues(alpha: .8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // A hairline rim, as desktop's border-white/10.
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Your Mixes: the first six as cards in two columns, each a collage of
/// its covers, as on desktop. A tap plays the mix from the top.
class KonnektedYourMixes extends StatelessWidget {
  const KonnektedYourMixes({
    super.key,
    required this.mixes,
    required this.onPlay,
  });

  final List<LokalMix> mixes;
  final void Function(Song song, List<Song> queue) onPlay;

  @override
  Widget build(BuildContext context) {
    if (mixes.isEmpty) return const SizedBox.shrink();
    final shown = mixes.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const KonnektedSectionHeading(
          title: 'Your Mixes',
          icon: Icons.radio_rounded,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 14) / 2;
              return Wrap(
                spacing: 14,
                runSpacing: 18,
                children: [
                  for (final mix in shown)
                    SizedBox(
                      width: width,
                      child: _MixCard(mix: mix, onPlay: onPlay),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MixCard extends StatelessWidget {
  const _MixCard({required this.mix, required this.onPlay});

  final LokalMix mix;
  final void Function(Song song, List<Song> queue) onPlay;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    void play() {
      HapticFeedback.lightImpact();
      onPlay(mix.tracks.first, mix.tracks);
    }

    return Semantics(
      button: true,
      label: 'Play ${mix.title}, ${mix.tracks.length} songs',
      excludeSemantics: true,
      onTap: play,
      child: InkWell(
        onTap: play,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: KonnektedMixArt(songs: mix.tracks),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              mix.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              '${mix.tracks.length} songs',
              style: TextStyle(fontSize: 12, color: t.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// A mix's cover: four of its album covers in a square, or the one cover it
/// has, or a radio glyph.
class KonnektedMixArt extends StatelessWidget {
  const KonnektedMixArt({super.key, required this.songs});

  final List<Song> songs;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    final covers = <String, Song>{};
    for (final song in songs) {
      final key =
          song.albumArt ??
          '${song.album ?? song.title}|${song.albumArtist ?? song.artist}';
      covers.putIfAbsent(key, () => song);
      if (covers.length == 4) break;
    }
    final placeholder = Container(
      color: t.surface3,
      alignment: Alignment.center,
      child: Icon(Icons.radio_rounded, color: t.muted, size: 36),
    );
    Widget art(Song song) => CachedImageWidget(
      imagePath: song.albumArt,
      audioSourcePath: song.filePath,
      fit: BoxFit.cover,
      useThumbnail: true,
      placeholder: placeholder,
      errorWidget: placeholder,
    );
    final list = covers.values.toList();
    if (list.isEmpty) return placeholder;
    if (list.length < 4) return SizedBox.expand(child: art(list.first));
    return Column(
      children: [
        for (final row in [list.sublist(0, 2), list.sublist(2, 4)])
          Expanded(
            child: Row(
              children: [
                for (final song in row)
                  Expanded(child: SizedBox.expand(child: art(song))),
              ],
            ),
          ),
      ],
    );
  }
}
