import 'package:flick/l10n/l10n.dart';

import '../../../link/lokal_desktop_link_screen.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flick/features/internet_radio/radio_providers.dart';
import 'package:flick/features/settings/screens/network_sources_screen.dart';
import 'package:flick/features/settings/widgets/http_addons_settings_panel.dart';
import 'package:flick/features/settings/widgets/lastfm_settings_tile.dart';
import 'package:flick/features/settings/widgets/listenbrainz_settings_tile.dart';
import 'package:flick/features/settings/widgets/youtube_music_settings_tile.dart';
import 'package:flick/features/settings/widgets/playback_source_priority_panel.dart';
import 'package:flick/features/morneye/morneye_addons_screen.dart';
import 'package:flick/features/spotify/spotify_library_screen.dart';
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
      LokalSettingCustom(
        label: lokalText('Playback search priority'),
        description: lokalText(
          'Try sources from top to bottom when finding a song to play. Installed add-ons appear here too.',
        ),
        child: const PlaybackSourcePriorityPanel(),
      ),
      LokalSettingCustom(
        label: lokalText('YouTube Music'),
        description: lokalText('Sign in to load your mixes, likes and history'),
        child: YoutubeMusicSettingsTile(),
      ),
      LokalSettingLink(
        label: lokalText('Network servers'),
        description: lokalText(
          'Subsonic, Jellyfin, WebDAV and other servers you run.',
        ),
        onTap: () => _push(context, const NetworkSourcesScreen()),
      ),
      LokalSettingLink(
        label: lokalText('Desktop link'),
        description: lokalText(
          'Pair, control playback and merge libraries over Wi-Fi.',
        ),
        onTap: () => _push(context, const LokalDesktopLinkScreen()),
      ),
    ],
  ),
  LokalSettingsSection(
    title: LokalOnlineSections.addons,
    children: [
      const MorneyeAddonsPanel(),
      LokalSettingCustom(
        label: lokalText('HTTP music add-ons'),
        description: lokalText(
          'Add HTTPS music catalogues using their manifest.json link.',
        ),
        child: HttpAddonsSettingsPanel(),
      ),
    ],
  ),
  const LokalSettingsSection(
    title: LokalOnlineSections.repositories,
    children: [MorneyeRepositoriesPanel()],
  ),
  LokalSettingsSection(
    title: LokalOnlineSections.radioVideos,
    children: [
      LokalSettingLink(
        label: lokalText('Station list'),
        description: ref.watch(radioCatalogUrlProvider),
        onTap: () => unawaited(_editCatalogUrl(context, ref)),
      ),
    ],
  ),
  LokalSettingsSection(
    title: LokalOnlineSections.accounts,
    children: [
      LokalSettingLink(
        label: lokalText('Spotify'),
        description: lokalText(
          'Sign in, import playlists and sync Liked Songs.',
        ),
        onTap: () => _push(context, const SpotifyLibraryScreen()),
      ),
      LokalSettingCustom(
        label: lokalText('Last.fm'),
        description: lokalText('Scrobble what you play and power Discovery'),
        child: LastFmSettingsTile(),
      ),
      LokalSettingCustom(
        label: lokalText('ListenBrainz'),
        description: lokalText('Send your listens to ListenBrainz'),
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
      title: Text(lokalText('Station list')),
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
          child: Text(lokalText('Cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(lokalText('Save')),
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
      SnackBar(content: Text(lokalText('Use an https link to a JSON file.'))),
    );
    return;
  }
  await ref.read(radioCatalogUrlProvider.notifier).set(url);
}
