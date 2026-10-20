import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flick/features/internet_radio/radio_providers.dart';
import 'package:flick/features/settings/screens/network_sources_screen.dart';
import 'package:flick/features/settings/widgets/lastfm_settings_tile.dart';
import 'package:flick/features/settings/widgets/listenbrainz_settings_tile.dart';
import 'package:flick/features/settings/widgets/youtube_music_settings_tile.dart';
import 'package:flick/features/spotiflac/spotiflac_addons_screen.dart';
import 'package:flick/features/spotify/spotify_library_screen.dart';
import 'package:flick/providers/opt_in_source_provider.dart';
import 'package:flick/widgets/lokal/settings/lokal_settings_kit.dart';

import '../lokal_settings_group.dart';

void _push(BuildContext context, Widget page) => unawaited(
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)),
);

/// Online sources: desktop's Integrations and Add-ons as one flow. Where
/// Search and Discovery find songs (YouTube Music, add-ons, your servers),
/// then the accounts that sync and scrobble. Every one is off until you sign
/// in or install it.
List<LokalSettingsSection> onlineSourcesSettings(
  BuildContext context,
  WidgetRef ref,
) => [
  LokalSettingsSection(
    title: LokalOnlineSections.streaming,
    children: [
      const LokalSettingCustom(
        label: 'YouTube Music',
        description: 'Sign in to load your mixes, likes and history',
        child: YoutubeMusicSettingsTile(),
      ),
      LokalSettingLink(
        label: 'Network servers',
        description: 'Subsonic, Jellyfin, WebDAV and other servers you run.',
        onTap: () => _push(context, const NetworkSourcesScreen()),
      ),
    ],
  ),
  const LokalSettingsSection(
    title: LokalOnlineSections.addons,
    children: [SpotiflacAddonsPanel()],
  ),
  const LokalSettingsSection(
    title: LokalOnlineSections.repositories,
    children: [SpotiflacRepositoriesPanel()],
  ),
  LokalSettingsSection(
    title: LokalOnlineSections.radioVideos,
    children: [
      LokalSettingRow.toggle(
        label: 'Internet radio',
        description:
            'Live stations from a station list online (Library › Radio).',
        value: ref.watch(internetRadioEnabledProvider),
        onChanged: (on) {
          unawaited(ref.read(internetRadioEnabledProvider.notifier).set(on));
          if (!on) unawaited(ref.read(radioPlayerProvider.notifier).stop());
        },
      ),
      if (ref.watch(internetRadioEnabledProvider))
        LokalSettingLink(
          label: 'Station list',
          description: ref.watch(radioCatalogUrlProvider),
          onTap: () => unawaited(_editCatalogUrl(context, ref)),
        ),
      LokalSettingRow.toggle(
        label: 'Music videos',
        description:
            'Find official videos for your songs on YouTube Music and watch '
            'them in YouTube’s embedded player (Library › Videos).',
        value: ref.watch(musicVideosEnabledProvider),
        onChanged: (on) =>
            unawaited(ref.read(musicVideosEnabledProvider.notifier).set(on)),
      ),
    ],
  ),
  LokalSettingsSection(
    title: LokalOnlineSections.accounts,
    children: [
      LokalSettingLink(
        label: 'Spotify',
        description: 'Sign in, import playlists and sync Liked Songs.',
        onTap: () => _push(context, const SpotifyLibraryScreen()),
      ),
      const LokalSettingCustom(
        label: 'Last.fm',
        description: 'Scrobble what you play and power Discovery',
        child: LastFmSettingsTile(),
      ),
      const LokalSettingCustom(
        label: 'ListenBrainz',
        description: 'Send your listens to ListenBrainz',
        child: ListenBrainzSettingsTile(),
      ),
    ],
  ),
];

/// Desktop's "station list link": any https JSON in its radios.json format.
/// Empty goes back to Lokal's own list.
Future<void> _editCatalogUrl(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController(
    text: ref.read(radioCatalogUrlProvider),
  );
  final url = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Station list'),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: const InputDecoration(
          hintText: 'https://…/radios.json',
          helperText: 'Leave empty for Lokal’s own list.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (url == null) return;
  final uri = Uri.tryParse(url.trim());
  if (url.trim().isNotEmpty && (uri == null || uri.scheme != 'https')) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Use an https link to a JSON file.')),
    );
    return;
  }
  await ref.read(radioCatalogUrlProvider.notifier).set(url);
}
