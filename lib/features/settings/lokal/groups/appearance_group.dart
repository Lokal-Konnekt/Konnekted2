import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flick/core/theme/lokal_appearance.dart';
import 'package:flick/core/utils/app_haptics.dart';
import 'package:flick/features/appearance/lokal_appearance_screen.dart';
import 'package:flick/features/settings/screens/visualizer_settings_screen.dart';
import 'package:flick/features/settings/screens/widget_settings_screen.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/providers/providers.dart';
import 'package:flick/widgets/lokal/settings/lokal_settings_kit.dart';

void _push(BuildContext context, Widget page) => unawaited(
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)),
);

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
        LokalSettingRow.toggle(
          label: 'Moving covers',
          description: 'Play an album’s animated cover in the classic player, when there is one.',
          value: prefs.animatedAlbumArt,
          onChanged: notifier.setAnimatedAlbumArt,
        ),
        LokalSettingLink(
          label: 'MilkDrop presets',
          description: 'Choose which MilkDrop presets rotate in the visualizer.',
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
