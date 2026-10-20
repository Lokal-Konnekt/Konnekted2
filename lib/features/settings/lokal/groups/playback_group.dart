import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flick/features/settings/lokal/lokal_settings_group.dart';
import 'package:flick/features/settings/lokal/lokal_settings_page.dart';
import 'package:flick/features/settings/screens/bluetooth_settings_screen.dart';
import 'package:flick/features/settings/screens/casting_settings_screen.dart';
import 'package:flick/features/settings/screens/equalizer_screen.dart';
import 'package:flick/features/settings/screens/uac2_preferences_screen.dart';
import 'package:flick/features/settings/screens/uac2_settings_screen.dart';
import 'package:flick/providers/app_preferences_provider.dart';
import 'package:flick/providers/player_provider.dart';
import 'package:flick/services/replaygain_service.dart';
import 'package:flick/services/uac2_preferences_service.dart';
import 'package:flick/widgets/lokal/settings/lokal_settings_kit.dart';

void _push(BuildContext context, Widget page) => unawaited(
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)),
);

/// The player's own switches, so pages showing them rebuild when they change
/// (from here or from Now Playing).
Listenable lokalSettingsListenable(WidgetRef ref) {
  final player = ref.watch(playerServiceProvider);
  return Listenable.merge([
    player.gaplessPlaybackEnabledNotifier,
    player.bitPerfectProcessingLockedNotifier,
    player.wrapAroundQueueNotifier,
    player.autoplayOnQueueEndNotifier,
    player.duckOnInterruptionNotifier,
    player.extendedVolumeEnabledNotifier,
  ]);
}

String _db(double db) =>
    db == 0 ? '0 dB' : '${db > 0 ? '+' : ''}${db.toStringAsFixed(1)} dB';

const _curves = [
  LokalSegment(0, 'Equal power'),
  LokalSegment(1, 'Linear'),
  LokalSegment(2, 'Square root'),
  LokalSegment(3, 'S-curve'),
];

List<LokalSettingsSection> playbackSettings(
  BuildContext context,
  WidgetRef ref,
) {
  final prefs = ref.watch(appPreferencesProvider);
  final notifier = ref.read(appPreferencesProvider.notifier);
  final player = ref.watch(playerServiceProvider);
  final locked = player.bitPerfectProcessingLockedNotifier.value;
  final lockedHint = Uac2PreferencesService.is432HzTuningEnabledSync
      ? 'Turn off 432 Hz tuning to use this.'
      : 'Not available in bit-perfect mode.';

  Future<void> crossfade({bool? enabled, double? secs, int? curve}) async {
    if (enabled != null) await notifier.setCrossfadeEnabled(enabled);
    if (secs != null) await notifier.setCrossfadeDurationSecs(secs);
    if (curve != null) await notifier.setCrossfadeCurveIndex(curve);
    final now = ref.read(appPreferencesProvider);
    await player.applyCrossfadeSettings(
      enabled: now.crossfadeEnabled,
      durationSecs: now.crossfadeDurationSecs,
    );
  }

  return [
    LokalSettingsSection(
      title: 'Playback',
      children: [
        LokalSettingRow(
          label: 'ReplayGain',
          description: 'Use ReplayGain tags to bring songs closer in loudness. Songs without tags are unchanged.',
          trailing: LokalSegmented<String>(
            segments: const [
              LokalSegment('off', 'Off'),
              LokalSegment('track', 'Track'),
              LokalSegment('album', 'Album'),
            ],
            value: prefs.replayGainMode,
            onChanged: (mode) async {
              await notifier.setReplayGainMode(mode);
              await player.applyReplayGainFromSettings();
            },
          ),
          stacked: true,
        ),
        LokalSettingSlider(
          label: 'ReplayGain pre-amp',
          description: 'Raise or lower every song by this much.',
          value: prefs.replayGainPreampDb,
          min: replayGainPreampMinDb,
          max: replayGainPreampMaxDb,
          divisions: 36,
          valueLabel: _db,
          onChanged: prefs.replayGainMode == 'off'
              ? null
              : (db) async {
                  await notifier.setReplayGainPreampDb(db);
                  await player.applyReplayGainFromSettings();
                },
        ),
        LokalSettingRow.toggle(
          label: 'Prevent clipping',
          description: 'Peak tags limit boosts so loud songs don’t distort.',
          value: prefs.replayGainPreventClipping,
          enabled: prefs.replayGainMode != 'off',
          onChanged: (value) async {
            await notifier.setReplayGainPreventClipping(value);
            await player.applyReplayGainFromSettings();
          },
        ),
        LokalSettingRow.toggle(
          label: 'Gapless playback',
          description: player.isBitPerfectModeEnabled
              ? 'Off in bit-perfect mode.'
              : 'Play one song straight into the next, with no silence between.',
          value: player.gaplessPlaybackEnabledNotifier.value,
          onChanged: player.setGaplessPlaybackEnabled,
        ),
      ],
    ),
    LokalSettingsSection(
      title: 'Song transitions',
      children: [
        LokalSettingRow.toggle(
          label: 'Crossfade',
          description: locked
              ? lockedHint
              : 'Start the next song before the current one ends.',
          value: !locked && prefs.crossfadeEnabled,
          enabled: !locked,
          onChanged: (value) => crossfade(enabled: value),
        ),
        LokalSettingSlider(
          label: 'Crossfade length',
          description: 'How long the two songs overlap.',
          value: prefs.crossfadeDurationSecs,
          min: .5,
          max: 12,
          divisions: 23,
          valueLabel: (s) => '${s.toStringAsFixed(1)} s',
          onChanged: locked || !prefs.crossfadeEnabled
              ? null
              : (secs) => crossfade(secs: secs),
        ),
        LokalSettingChoice<int>(
          label: 'Fade curve',
          description: 'Equal power fades evenly to the ear.',
          options: _curves,
          value: prefs.crossfadeCurveIndex.clamp(0, 3),
          enabled: !locked && prefs.crossfadeEnabled,
          onChanged: (curve) => crossfade(curve: curve),
        ),
      ],
    ),
    LokalSettingsSection(
      title: 'Queue',
      children: [
        LokalSettingRow.toggle(
          label: 'Wrap around',
          description: 'At the end of the queue, go back to the songs before the one you tapped.',
          value: player.wrapAroundQueueNotifier.value,
          onChanged: player.setWrapAroundQueue,
        ),
        LokalSettingRow.toggle(
          label: 'Autoplay',
          description:
              'When the queue ends, keep playing songs from your library.',
          value: player.autoplayOnQueueEndNotifier.value,
          onChanged: player.setAutoplayOnQueueEnd,
        ),
        LokalSettingRow.toggle(
          label: 'Keep playing on quit',
          description: 'Music goes on when you swipe Lokal away.',
          value: prefs.keepPlayingOnQuit,
          onChanged: notifier.setKeepPlayingOnQuit,
        ),
        if (Platform.isAndroid)
          LokalSettingRow.toggle(
            label: 'Duck on notifications',
            description: 'Lower the volume while a notification sounds. Off: pause instead.',
            value: player.duckOnInterruptionNotifier.value,
            onChanged: player.setDuckOnInterruption,
          ),
      ],
    ),
    LokalSettingsSection(
      title: 'Play from',
      children: [
        LokalSettingRow(
          label: 'After a search result',
          description: 'What plays next when you play a song from Search: the other results, your library, or your queue.',
          stacked: true,
          trailing: LokalSegmented<String>(
            expand: true,
            segments: const [
              LokalSegment('results', 'Results'),
              LokalSegment('library', 'Library'),
              LokalSegment('queue', 'Queue'),
            ],
            value: prefs.searchPlaybackMode,
            onChanged: notifier.setSearchPlaybackMode,
          ),
        ),
      ],
    ),
    LokalSettingsSection(
      title: 'Equalizer',
      children: [
        LokalSettingLink(
          label: 'Equalizer',
          description:
              'Bands, presets, AutoEQ headphone correction and effects.',
          onTap: () => _push(context, const EqualizerScreen()),
        ),
      ],
    ),
    LokalSettingsSection(
      title: 'Lyrics',
      children: [
        LokalSettingRow.toggle(
          label: 'Fetch lyrics automatically',
          description: 'Off: songs only show the lyrics they carry themselves. Searching from the lyrics view still looks online.',
          value: prefs.lyricsAutoFetch,
          onChanged: notifier.setLyricsAutoFetch,
        ),
        LokalSettingRow.toggle(
          label: 'Name lyrics after the song file',
          description: 'Lyrics Lokal saves take the song’s file name instead of its title.',
          value: prefs.lyricsMatchAudioFilename,
          onChanged: notifier.setLyricsMatchAudioFilename,
        ),
        LokalSettingRow.toggle(
          label: 'Word-by-word sync',
          description: 'In the classic player, light up each word as it’s sung when the lyrics have word timing.',
          value: prefs.karaokeEnabled,
          onChanged: notifier.setKaraokeEnabled,
        ),
        LokalSettingRow(
          label: 'Alignment',
          description: 'Where lyric lines sit in the classic player.',
          trailing: LokalSegmented<String>(
            segments: const [
              LokalSegment('left', 'Left'),
              LokalSegment('center', 'Centre'),
              LokalSegment('right', 'Right'),
            ],
            value: prefs.lyricsTextAlign,
            onChanged: notifier.setLyricsTextAlign,
          ),
          stacked: true,
        ),
      ],
    ),
    LokalSettingsSection(
      title: 'Casting',
      children: [
        LokalSettingLink(
          label: 'Casting',
          description:
              'Find DLNA, UPnP and Chromecast receivers on your network.',
          onTap: () => _push(context, const CastingSettingsScreen()),
        ),
      ],
    ),
    LokalSettingsSection(
      title: 'Output',
      children: [
        LokalSettingLink(
          label: LokalSettingsGroup.output.label,
          description: LokalSettingsGroup.output.description,
          onTap: () => unawaited(
            openLokalSettings(context, group: LokalSettingsGroup.output),
          ),
        ),
      ],
    ),
  ];
}

const _crossfeed = [
  LokalSegment(0, 'Off'),
  LokalSegment(1, 'Default'),
  LokalSegment(2, 'Crossfeed'),
  LokalSegment(3, 'Easy'),
];

/// Advanced output: USB DAC and engine, Bluetooth, volume and crossfeed.
List<LokalSettingsSection> outputSettings(BuildContext context, WidgetRef ref) {
  final prefs = ref.watch(appPreferencesProvider);
  final notifier = ref.read(appPreferencesProvider.notifier);
  final player = ref.watch(playerServiceProvider);
  final locked = player.bitPerfectProcessingLockedNotifier.value;
  return [
    LokalSettingsSection(
      title: 'USB DAC',
      children: [
        LokalSettingLink(
          label: 'USB DAC',
          description: 'Play straight to a USB DAC: bit-perfect, DSD and device diagnostics.',
          onTap: () => _push(context, const Uac2SettingsScreen()),
        ),
        LokalSettingLink(
          label: 'Engine and tuning',
          description: 'Playback engine, 432 Hz tuning and USB preferences.',
          onTap: () => _push(context, const Uac2PreferencesScreen()),
        ),
      ],
    ),
    LokalSettingsSection(
      title: 'Bluetooth',
      children: [
        LokalSettingLink(
          label: 'Bluetooth',
          description:
              'Codec, and what happens when headphones connect or drop.',
          onTap: () => _push(context, const BluetoothSettingsScreen()),
        ),
      ],
    ),
    LokalSettingsSection(
      title: 'Volume',
      children: [
        LokalSettingRow.toggle(
          label: 'Extended volume',
          description: 'Let the volume go past 100 %, up to 200 %.',
          value: prefs.extendedVolumeEnabled,
          onChanged: (value) async {
            await notifier.setExtendedVolumeEnabled(value);
            await player.setExtendedVolumeEnabled(value);
          },
        ),
        LokalSettingChoice<int>(
          label: 'Crossfeed',
          description: locked ? 'Not available in bit-perfect mode.' : 'Blend a little of each channel into the other, for easier listening on headphones.',
          options: _crossfeed,
          value: prefs.crossfeedLevel.clamp(0, 3),
          enabled: !locked,
          onChanged: (level) async {
            await notifier.setCrossfeedLevel(level);
            await player.applyCrossfeedSettings();
          },
        ),
      ],
    ),
    LokalSettingsSection(
      title: 'Background',
      children: [
        LokalSettingRow.toggle(
          label: 'Background playback anchor',
          description: 'Keep bit-perfect audio alive in the background. Off: some phones may stop it.',
          value: prefs.priorityAnchorEnabled,
          onChanged: (value) {
            player.setPriorityAnchorEnabled(value);
            notifier.setPriorityAnchorEnabled(value);
          },
        ),
        LokalSettingRow.toggle(
          label: 'Moving covers in bit-perfect',
          description: 'Play moving covers during bit-perfect output. Off: a still cover instead.',
          value: prefs.motionArtDuringBitPerfect,
          onChanged: (value) {
            player.setMotionArtDuringBitPerfect(value);
            notifier.setMotionArtDuringBitPerfect(value);
          },
        ),
      ],
    ),
  ];
}
