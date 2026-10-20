import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flick/core/constants/app_constants.dart';
import 'package:flick/core/theme/lokal_appearance.dart';
import 'package:flick/core/utils/app_haptics.dart';
import 'package:flick/features/appearance/lokal_appearance_screen.dart';
import 'package:flick/features/settings/screens/player_layout_settings_screen.dart';
import 'package:flick/features/settings/screens/visualizer_settings_screen.dart';
import 'package:flick/features/settings/screens/widget_settings_screen.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/models/album_color_mode.dart';
import 'package:flick/models/progress_bar_style.dart';
import 'package:flick/providers/providers.dart';
import 'package:flick/widgets/lokal/settings/lokal_settings_kit.dart';

void _push(BuildContext context, Widget page) => unawaited(
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)),
);

const _albumColours = [
  LokalSegment(AlbumColorMode.off, 'Off'),
  LokalSegment(AlbumColorMode.subtle, 'Subtle'),
  LokalSegment(AlbumColorMode.moderate, 'Moderate'),
  LokalSegment(AlbumColorMode.vibrant, 'Vibrant'),
];

/// The language codes the segmented control offers; `null` follows the
/// phone.
String? _languageOf(Locale? locale) => locale?.languageCode;

List<LokalSettingsSection> appearanceSettings(
  BuildContext context,
  WidgetRef ref,
) {
  final appearance = ref.watch(lokalAppearanceProvider);
  final look = ref.read(lokalAppearanceProvider.notifier);
  final prefs = ref.watch(appPreferencesProvider);
  final notifier = ref.read(appPreferencesProvider.notifier);
  return [
    LokalSettingsSection(
      title: 'Theme',
      children: [
        LokalSettingRow(
          label: 'Theme',
          description: 'Desktop Lokal’s ten themes.',
          stacked: true,
          trailing: LokalThemeGrid(
            padding: EdgeInsets.zero,
            selected: appearance.theme,
            onSelect: (id) {
              HapticFeedback.selectionClick();
              look.selectTheme(id);
            },
          ),
        ),
        LokalSettingRow(
          label: 'Accent',
          description: 'The theme’s own accent, or one of desktop’s. The app icon follows it.',
          stacked: true,
          trailing: LokalAccentRow(
            padding: EdgeInsets.zero,
            selected: appearance.accent,
            onSelect: (accent) {
              HapticFeedback.selectionClick();
              look.setAccent(accent);
            },
          ),
        ),
        LokalSettingSlider(
          label: 'Text size',
          description: 'Bigger or smaller text across Lokal.',
          value: appearance.textScale,
          min: LokalAppearance.minTextScale,
          max: LokalAppearance.maxTextScale,
          divisions: 16,
          valueLabel: (v) => '${(v * 100).round()}%',
          semanticFormatter: (v) => '${(v * 100).round()} percent',
          onChanged: look.setTextScale,
        ),
        LokalSettingRow.toggle(
          label: 'Performance mode',
          description: 'Solid surfaces instead of glass, for older phones.',
          value: appearance.performanceMode,
          onChanged: look.setPerformanceMode,
        ),
      ],
    ),
    LokalSettingsSection(
      title: 'Now Playing',
      children: [
        LokalSettingLink(
          label: 'Classic player layout',
          description: 'Artwork size, file info and quick actions in the classic player (⋮ › Player layout).',
          onTap: () => _push(context, const PlayerLayoutSettingsScreen()),
        ),
        LokalSettingChoice<AlbumColorMode>(
          label: 'Colour from the cover',
          description: 'How much the classic player’s controls take colour from the album cover.',
          options: _albumColours,
          value: ref.watch(albumColorModeProvider),
          onChanged: ref.read(albumColorModeProvider.notifier).setMode,
        ),
        LokalSettingRow.toggle(
          label: 'Moving covers',
          description: 'Play an album’s animated cover in the classic player, when there is one.',
          value: prefs.animatedAlbumArt,
          onChanged: notifier.setAnimatedAlbumArt,
        ),
        LokalSettingRow(
          label: 'Progress bar',
          description: 'A waveform or a plain line in the classic player.',
          trailing: LokalSegmented<ProgressBarStyle>(
            segments: const [
              LokalSegment(ProgressBarStyle.waveform, 'Waveform'),
              LokalSegment(ProgressBarStyle.line, 'Line'),
            ],
            value: ref.watch(progressBarStyleProvider),
            onChanged: ref.read(progressBarStyleProvider.notifier).setStyle,
          ),
        ),
        LokalSettingLink(
          label: 'Visualizer',
          description:
              'Style and frequency focus of the audio-reactive graphic.',
          onTap: () => _push(context, const VisualizerSettingsScreen()),
        ),
      ],
    ),
    LokalSettingsSection(
      title: 'Interface',
      children: [
        LokalSettingRow(
          label: 'Language',
          description: 'The phone’s language, or one Lokal is translated into.',
          stacked: true,
          trailing: ValueListenableBuilder<Locale?>(
            valueListenable: LocaleController.instance,
            builder: (context, locale, _) => LokalSegmented<String?>(
              expand: true,
              segments: const [
                LokalSegment(null, 'Phone'),
                LokalSegment('en', 'English'),
                LokalSegment('zh', '简体中文'),
              ],
              value: _languageOf(locale),
              onChanged: (code) =>
                  LocaleController.instance.select(switch (code) {
                    'en' => const Locale('en'),
                    'zh' => const Locale('zh', 'CN'),
                    _ => null,
                  }),
            ),
          ),
        ),
        LokalSettingRow.toggle(
          label: 'Haptics',
          description: 'A light tap under your finger as you use Lokal.',
          value: prefs.hapticsEnabled,
          onChanged: (value) {
            notifier.setHapticsEnabled(value);
            AppHaptics.setEnabled(value);
          },
        ),
        LokalSettingRow.toggle(
          label: 'Swipe actions',
          description: 'Swipe a song left to queue it or right to like it.',
          value: prefs.swipeActionsEnabled,
          onChanged: notifier.setSwipeActionsEnabled,
        ),
        LokalSettingRow(
          label: 'Remove a liked song',
          description: 'How you unlike a song in Liked.',
          trailing: LokalSegmented<String>(
            segments: const [
              LokalSegment('swipe', 'Swipe'),
              LokalSegment('longpress', 'Hold'),
            ],
            value: prefs.favoriteRemovalMode,
            onChanged: notifier.setFavoriteRemovalMode,
          ),
        ),
        LokalSettingRow.toggle(
          label: 'Reduce motion',
          description: 'Fewer animated transitions and effects.',
          value: !prefs.animationsEnabled,
          onChanged: (reduce) {
            notifier.setAnimationsEnabled(!reduce);
            AppConstants.setAnimationsEnabled(!reduce);
          },
        ),
        LokalSettingRow(
          label: 'Refresh rate',
          description: 'Adaptive lets the phone decide. 120 Hz is smoothest and uses more battery.',
          stacked: true,
          trailing: LokalSegmented<String>(
            expand: true,
            segments: const [
              LokalSegment('adaptive', 'Adaptive'),
              LokalSegment('standard', '60 Hz'),
              LokalSegment('high', '120 Hz'),
            ],
            value: prefs.refreshRateMode,
            onChanged: notifier.setRefreshRateMode,
          ),
        ),
        LokalSettingRow.toggle(
          label: 'Fast scroll index',
          description: 'An A–Z rail beside long song lists.',
          value: prefs.fastIndexEnabled,
          onChanged: notifier.setFastIndexEnabled,
        ),
        LokalSettingRow.toggle(
          label: 'Open the keyboard in Search',
          description: 'Start typing as soon as Search opens.',
          value: prefs.autoFocusSearch,
          onChanged: notifier.setAutoFocusSearch,
        ),
        LokalSettingRow.toggle(
          label: 'Connection notices',
          description: 'Say so when you go offline or come back.',
          value: prefs.connectionNoticesEnabled,
          onChanged: notifier.setConnectionNoticesEnabled,
        ),
      ],
    ),
    LokalSettingsSection(
      title: 'Home-screen widget',
      children: [
        LokalSettingLink(
          label: 'Home-screen widget',
          description: 'What the widget on your home screen shows.',
          onTap: () => _push(context, const WidgetSettingsScreen()),
        ),
      ],
    ),
  ];
}
