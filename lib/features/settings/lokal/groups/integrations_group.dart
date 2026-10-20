import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flick/features/settings/screens/network_sources_screen.dart';
import 'package:flick/features/settings/widgets/lastfm_settings_tile.dart';
import 'package:flick/features/settings/widgets/listenbrainz_settings_tile.dart';
import 'package:flick/features/settings/widgets/youtube_music_settings_tile.dart';
import 'package:flick/features/spotiflac/spotiflac_addons_screen.dart';
import 'package:flick/features/spotify/spotify_library_screen.dart';
import 'package:flick/widgets/lokal/settings/lokal_settings_kit.dart';

void _push(BuildContext context, Widget page) => unawaited(
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)),
);

/// Integrations: accounts, scrobbling and network sources. Every one of them
/// is off until you sign in.
List<LokalSettingsSection> integrationsSettings(
  BuildContext context,
  WidgetRef ref,
) => [
  LokalSettingsSection(
    title: 'Accounts',
    children: [
      const LokalSettingCustom(
        label: 'YouTube Music',
        description: 'Sign in to load your mixes, likes and history',
        child: YoutubeMusicSettingsTile(),
      ),
      LokalSettingLink(
        label: 'Spotify',
        description: 'Sign in, import playlists and sync Liked Songs.',
        onTap: () => _push(context, const SpotifyLibraryScreen()),
      ),
    ],
  ),
  const LokalSettingsSection(
    title: 'Scrobbling',
    children: [
      LokalSettingCustom(
        label: 'Last.fm',
        description: 'Scrobble what you play and power Discovery',
        child: LastFmSettingsTile(),
      ),
      LokalSettingCustom(
        label: 'ListenBrainz',
        description: 'Send your listens to ListenBrainz',
        child: ListenBrainzSettingsTile(),
      ),
    ],
  ),
  LokalSettingsSection(
    title: 'Network sources',
    children: [
      LokalSettingLink(
        label: 'Network sources',
        description: 'Subsonic servers: sync and streaming.',
        onTap: () => _push(context, const NetworkSourcesScreen()),
      ),
    ],
  ),
];

/// Add-ons: what search finds here; the group itself opens the add-on list.
List<LokalSettingsSection> addonsSettings(
  BuildContext context,
  WidgetRef ref,
) => [
  LokalSettingsSection(
    title: 'Add-ons',
    children: [
      LokalSettingLink(
        label: 'SpotiFLAC add-ons',
        description: 'Play and download songs Discovery finds that aren’t in your library.',
        onTap: () => _push(context, const SpotiflacAddonsScreen()),
      ),
    ],
  ),
];
