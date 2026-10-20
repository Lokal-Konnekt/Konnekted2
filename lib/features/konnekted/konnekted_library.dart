import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/classipod/classipod_screen.dart';
import 'package:flick/features/settings/lokal/lokal_settings_group.dart';
import 'package:flick/providers/songs_provider.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/widgets/lokal/lokal_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'konnekted_data.dart';
import 'konnekted_destination.dart';
import 'konnekted_style.dart';

/// Settings › Library › Folders, where music folders are added.
const _folders = KonnektedDestination.settingsAt(
  LokalSettingsGroup.library,
  section: 'Folders',
);

/// Settings › Library, which the header's gear opens.
const _librarySettings = KonnektedDestination.settingsAt(
  LokalSettingsGroup.library,
);

/// Settings › Integrations › Accounts, where Spotify is.
const _accounts = KonnektedDestination.settingsAt(
  LokalSettingsGroup.integrations,
  section: 'Accounts',
);

class KonnektedLibrary extends ConsumerWidget {
  const KonnektedLibrary({super.key, required this.onNavigate});

  final ValueChanged<KonnektedDestination> onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SafeArea(
    bottom: false,
    child: ListView(
      key: const PageStorageKey('konnekted-library'),
      padding: EdgeInsets.only(
        bottom: 28 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
          child: Row(
            children: [
              Tooltip(
                message: 'Library settings',
                excludeFromSemantics: true,
                child: LokalGlassButton(
                  semanticLabel: 'Library settings',
                  onPressed: () => onNavigate(_librarySettings),
                  child: Icon(
                    Icons.settings_rounded,
                    color: context.lokal.text,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Easter egg: a long press on the title opens Classipod.
        GestureDetector(
          onLongPress: () =>
              Navigator.of(context).push(ClassipodScreen.route(context)),
          child: KonnektedHeading(
            title: 'Your library',
            eyebrow: 'Collected by you',
            action: IconButton.filledTonal(
              tooltip: 'Add music and manage folders',
              onPressed: () => onNavigate(_folders),
              icon: const Icon(Icons.add_rounded),
            ),
          ),
        ),
        ref
            .watch(konnektedLibraryProvider)
            .when(
              loading: () =>
                  const KonnektedLoading(label: 'Opening your collection'),
              error: (_, _) => KonnektedMessage(
                title: 'Couldn’t open your collection',
                message: 'Try again or manage your music folders below.',
                actionLabel: 'Try again',
                onAction: () => ref.invalidate(songsProvider),
              ),
              data: (songs) => KonnektedMessage(
                title: songs.isEmpty
                    ? 'All your music. All yours.'
                    : '${context.l10n.songsCount(songs.length)}. One home.',
                message: songs.isEmpty
                    ? 'Choose a folder and let your collection take shape.'
                    : 'Albums to get lost in. Artists to come back to. Find your next listen below.',
                icon: Icons.library_music_rounded,
                actionLabel: songs.isEmpty
                    ? 'Add a music folder'
                    : 'Browse all songs',
                onAction: () => onNavigate(
                  songs.isEmpty ? _folders : KonnektedDestination.songs,
                ),
              ),
            ),
        const KonnektedSectionHeading(title: 'Made personal'),
        KonnektedRouteGroup(
          onNavigate: onNavigate,
          entries: const [
            KonnektedRouteEntry(
              'Favorites',
              'The songs that stay with you',
              Icons.favorite_rounded,
              KonnektedDestination.favorites,
            ),
            KonnektedRouteEntry(
              'Playlists',
              'Your own kind of order',
              Icons.queue_music_rounded,
              KonnektedDestination.playlists,
            ),
            KonnektedRouteEntry(
              'Linked playlists',
              'Keep public Spotify and YouTube lists in step',
              Icons.link_rounded,
              KonnektedDestination.linkedPlaylists,
            ),
            KonnektedRouteEntry(
              'Spotify library',
              'Import playlists and sync Liked Songs',
              Icons.circle,
              _accounts,
            ),
            KonnektedRouteEntry(
              'Recently played',
              'Pick up where you left off',
              Icons.history_rounded,
              KonnektedDestination.recentlyPlayed,
            ),
          ],
        ),
        const KonnektedSectionHeading(title: 'Browse your collection'),
        KonnektedRouteGroup(
          onNavigate: onNavigate,
          entries: const [
            KonnektedRouteEntry(
              'Songs',
              'Every track in your library',
              Icons.music_note_rounded,
              KonnektedDestination.songs,
            ),
            KonnektedRouteEntry(
              'Albums',
              'The complete picture',
              Icons.album_rounded,
              KonnektedDestination.albums,
            ),
            KonnektedRouteEntry(
              'Artists',
              'The people behind the music',
              Icons.person_rounded,
              KonnektedDestination.artists,
            ),
            KonnektedRouteEntry(
              'Folders',
              'Browse music by location',
              Icons.folder_rounded,
              KonnektedDestination.folders,
            ),
            KonnektedRouteEntry(
              'Recently added',
              'Fresh finds for your collection',
              Icons.auto_awesome_rounded,
              KonnektedDestination.recentlyAdded,
            ),
          ],
        ),
      ],
    ),
  );
}

class KonnektedRouteEntry {
  const KonnektedRouteEntry(
    this.title,
    this.subtitle,
    this.icon,
    this.destination,
  );

  final String title;
  final String subtitle;
  final IconData icon;
  final KonnektedDestination destination;
}

class KonnektedRouteGroup extends StatelessWidget {
  const KonnektedRouteGroup({
    super.key,
    required this.entries,
    required this.onNavigate,
  });

  final List<KonnektedRouteEntry> entries;
  final ValueChanged<KonnektedDestination> onNavigate;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Material(
      color: context.lokal.surface,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < entries.length; index++) ...[
            if (index > 0) const Divider(height: 1, indent: 64, endIndent: 16),
            _RouteTile(entry: entries[index], onNavigate: onNavigate),
          ],
        ],
      ),
    ),
  );
}

class _RouteTile extends StatelessWidget {
  const _RouteTile({required this.entry, required this.onNavigate});

  final KonnektedRouteEntry entry;
  final ValueChanged<KonnektedDestination> onNavigate;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      onTap: () => onNavigate(entry.destination),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(
          children: [
            Icon(entry.icon, color: context.lokal.accent, size: 26),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: context.lokal.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: context.lokal.muted,
            ),
          ],
        ),
      ),
    ),
  );
}
