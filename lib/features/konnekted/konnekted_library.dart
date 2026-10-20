import 'dart:async';

import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/classipod/classipod_screen.dart';
import 'package:flick/features/settings/library_scan/library_scan_flow.dart';
import 'package:flick/features/settings/lokal/lokal_settings_group.dart';
import 'package:flick/providers/songs_provider.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'konnekted_data.dart';
import 'konnekted_destination.dart';
import 'konnekted_style.dart';

/// Settings › Library › Folders: "Add folder" is its first row, so the
/// header's + reaches the folder picker in two taps.
const _folders = KonnektedDestination.settingsAt(
  LokalSettingsGroup.library,
  section: 'Folders',
);

/// Settings › Integrations › Accounts, where Spotify is.
const _accounts = KonnektedDestination.settingsAt(
  LokalSettingsGroup.integrations,
  section: 'Accounts',
);

class KonnektedLibrary extends ConsumerWidget {
  const KonnektedLibrary({
    super.key,
    required this.onNavigate,
    this.onAddFolder,
  });

  final ValueChanged<KonnektedDestination> onNavigate;

  /// The empty state's action; defaults to the system folder picker followed
  /// by a scan ([LibraryScanFlow.addFolder]).
  final ValueChanged<BuildContext>? onAddFolder;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SafeArea(
    bottom: false,
    child: ListView(
      key: const PageStorageKey('konnekted-library'),
      padding: EdgeInsets.only(
        bottom: 28 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        KonnektedHeading(
          title: 'Your library',
          eyebrow: 'Collected by you',
          action: IconButton.filledTonal(
            tooltip: 'Add music and manage folders',
            onPressed: () => onNavigate(_folders),
            icon: const Icon(Icons.add_rounded),
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
                // Empty: straight to the system folder picker, then a scan.
                onAction: songs.isEmpty
                    ? () => onAddFolder != null
                          ? onAddFolder!(context)
                          : unawaited(LibraryScanFlow.addFolder(context))
                    : () => onNavigate(KonnektedDestination.songs),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Material(
            color: context.lokal.surface,
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: Icon(
                Icons.radio_button_checked,
                color: context.lokal.accent,
              ),
              title: const Text('Classipod'),
              subtitle: const Text('Your local music, with a click wheel'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () =>
                  Navigator.of(context).push(ClassipodScreen.route(context)),
            ),
          ),
        ),
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
        const KonnektedSectionHeading(title: 'Keep exploring'),
        KonnektedRouteGroup(
          onNavigate: onNavigate,
          entries: const [
            KonnektedRouteEntry(
              'Listening hub',
              'Smart mixes, listening recaps, and more',
              Icons.space_dashboard_rounded,
              KonnektedDestination.inheritedHome,
            ),
            KonnektedRouteEntry(
              'Manage library',
              'Folders, scanning, and metadata',
              Icons.create_new_folder_rounded,
              KonnektedDestination.settingsAt(LokalSettingsGroup.library),
            ),
          ],
        ),
      ],
    ),
  );
}

class KonnektedSettings extends StatelessWidget {
  const KonnektedSettings({super.key, required this.onNavigate});

  final ValueChanged<KonnektedDestination> onNavigate;

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: ListView(
      key: const PageStorageKey('konnekted-settings'),
      padding: EdgeInsets.only(
        bottom: 28 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        const KonnektedHeading(
          title: 'Fine tuning',
          eyebrow: 'Make it sound like you',
        ),
        const KonnektedMessage(
          title: 'A little closer to the music',
          message: 'Shape your sound, choose your output, and make the player your own.',
          icon: Icons.graphic_eq_rounded,
        ),
        const KonnektedSectionHeading(title: 'Sound & playback'),
        KonnektedRouteGroup(
          onNavigate: onNavigate,
          entries: const [
            KonnektedRouteEntry(
              'Playback',
              'ReplayGain, crossfade, queue and casting',
              Icons.tune_rounded,
              KonnektedDestination.settingsAt(LokalSettingsGroup.playback),
            ),
            KonnektedRouteEntry(
              'Equalizer',
              'EQ presets and headphone correction',
              Icons.equalizer_rounded,
              KonnektedDestination.settingsAt(
                LokalSettingsGroup.playback,
                section: 'Equalizer',
              ),
            ),
            KonnektedRouteEntry(
              'Advanced output',
              'USB DAC, bit-perfect, Bluetooth and volume',
              Icons.usb_rounded,
              KonnektedDestination.settingsAt(LokalSettingsGroup.output),
            ),
            KonnektedRouteEntry(
              'Queue',
              'See what’s playing next',
              Icons.queue_music_rounded,
              KonnektedDestination.queue,
            ),
            KonnektedRouteEntry(
              'Lyrics settings',
              'Sources and lyric preferences',
              Icons.lyrics_rounded,
              KonnektedDestination.settingsAt(
                LokalSettingsGroup.playback,
                section: 'Lyrics',
              ),
            ),
          ],
        ),
        const KonnektedSectionHeading(title: 'Your experience'),
        KonnektedRouteGroup(
          onNavigate: onNavigate,
          entries: const [
            KonnektedRouteEntry(
              'Appearance',
              'Themes, accent, glass, and text size',
              Icons.palette_rounded,
              KonnektedDestination.settingsAt(LokalSettingsGroup.appearance),
            ),
            KonnektedRouteEntry(
              'Music library',
              'Manage folders and scan your music',
              Icons.library_music_rounded,
              KonnektedDestination.settingsAt(LokalSettingsGroup.library),
            ),
            KonnektedRouteEntry(
              'All settings',
              'Integrations, playback, library, data and more',
              Icons.settings_rounded,
              KonnektedDestination.settings,
            ),
            KonnektedRouteEntry(
              'Spotify library',
              'Connect, import playlists, or sync Liked Songs',
              Icons.circle,
              _accounts,
            ),
            KonnektedRouteEntry(
              'Linked playlists',
              'Preview, refresh, or unlink external playlists',
              Icons.link_rounded,
              KonnektedDestination.linkedPlaylists,
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
