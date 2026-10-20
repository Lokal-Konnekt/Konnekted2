import 'package:flutter/material.dart';
import 'package:flick/core/constants/app_constants.dart';
import 'package:flick/features/settings/widgets/apple_music_settings_tile.dart';
import 'package:flick/features/settings/widgets/lastfm_settings_tile.dart';
import 'package:flick/features/settings/widgets/listenbrainz_settings_tile.dart';
import 'package:flick/features/settings/widgets/youtube_music_settings_tile.dart';
import 'package:flick/features/spotiflac/spotiflac_addons_screen.dart';
import 'package:flick/features/settings/widgets/settings_widgets.dart';
import 'package:flick/l10n/l10n.dart';

class IntegrationsSettingsScreen extends StatelessWidget {
  const IntegrationsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: l10n.integrations,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsSectionHeader(l10n.integrations),
          const SettingsCard(
            children: [
              LastFmSettingsTile(),
              ListenBrainzSettingsTile(),
              YoutubeMusicSettingsTile(),
            ],
          ),
          const SizedBox(height: AppConstants.spacingLg),
          const SettingsSectionHeader('Add-ons'),
          SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Icons.extension_rounded),
                title: const Text('SpotiFLAC add-ons'),
                subtitle: const Text(
                  'Play and download songs Discovery finds that aren’t in your library',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SpotiflacAddonsScreen(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingLg),
          SettingsSectionHeader(l10n.metadata),
          const SettingsCard(children: [AppleMusicSettingsTile()]),
          const SizedBox(height: AppConstants.spacingLg),
          const SizedBox(height: AppConstants.navBarHeight + 40),
        ],
      ),
    );
  }
}
