import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flick/core/theme/lokal_appearance.dart';
import 'package:flick/core/utils/app_haptics.dart';
import 'package:flick/features/appearance/lokal_appearance_screen.dart';
import 'package:flick/features/settings/screens/widget_settings_screen.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/providers/providers.dart';
import 'package:flick/widgets/lokal/settings/lokal_settings_kit.dart';

void _push(BuildContext context, Widget page) => unawaited(
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)),
);

/// The language codes the segmented control offers; `null` follows the
/// phone.

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
      title: lokalText('Theme'),
      children: [
        LokalSettingRow(
          label: lokalText('Theme'),
          description: lokalText('Desktop Lokal’s ten themes.'),
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
          label: lokalText('Accent'),
          description: lokalText(
            'The app icon follows your accent after you leave Lokal with playback idle. Some launchers restart the app when updating its icon.',
          ),
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
          label: lokalText('Text size'),
          description: lokalText('Bigger or smaller text across Lokal.'),
          value: appearance.textScale,
          min: LokalAppearance.minTextScale,
          max: LokalAppearance.maxTextScale,
          divisions: 16,
          valueLabel: (v) => '${(v * 100).round()}%',
          semanticFormatter: (v) => '${(v * 100).round()} percent',
          onChanged: look.setTextScale,
        ),
        LokalSettingRow.toggle(
          label: lokalText('Performance mode'),
          description: lokalText(
            'Solid surfaces instead of glass, for older phones.',
          ),
          value: appearance.performanceMode,
          onChanged: look.setPerformanceMode,
        ),
      ],
    ),
    LokalSettingsSection(
      title: lokalText('Now Playing'),
      children: [
        LokalSettingRow.toggle(
          label: lokalText('Moving covers'),
          description: lokalText(
            'Play an album’s animated cover in the classic player, when there is one.',
          ),
          value: prefs.animatedAlbumArt,
          onChanged: notifier.setAnimatedAlbumArt,
        ),
      ],
    ),
    LokalSettingsSection(
      title: lokalText('Interface'),
      children: [
        LokalSettingRow(
          label: lokalText('Language'),
          description: lokalText(
            'The phone’s language, or one Lokal is translated into.',
          ),
          stacked: true,
          trailing: ValueListenableBuilder<Locale?>(
            valueListenable: LocaleController.instance,
            builder: (context, locale, _) => DropdownButtonFormField<String>(
              initialValue: locale == null ? 'system' : locale.languageCode,
              isExpanded: true,
              items: [
                DropdownMenuItem(
                  value: 'system',
                  child: Text(
                    lokalText('Phone'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownMenuItem(
                  value: 'en',
                  child: Text(lokalText('English')),
                ),
                DropdownMenuItem(
                  value: 'fr',
                  child: Text(lokalText('Français')),
                ),
                DropdownMenuItem(
                  value: 'de',
                  child: Text(lokalText('Deutsch')),
                ),
                DropdownMenuItem(
                  value: 'es',
                  child: Text(lokalText('Español')),
                ),
                DropdownMenuItem(
                  value: 'it',
                  child: Text(lokalText('Italiano')),
                ),
                DropdownMenuItem(
                  value: 'pt',
                  child: Text(lokalText('Português (Brasil)')),
                ),
                DropdownMenuItem(
                  value: 'nl',
                  child: Text(lokalText('Nederlands')),
                ),
                DropdownMenuItem(value: 'pl', child: Text(lokalText('Polski'))),
                DropdownMenuItem(
                  value: 'sv',
                  child: Text(lokalText('Svenska')),
                ),
                DropdownMenuItem(value: 'zh', child: Text('简体中文')),
              ],
              onChanged: (code) =>
                  LocaleController.instance.select(switch (code) {
                    'system' || null => null,
                    'zh' => const Locale('zh', 'CN'),
                    'pt' => const Locale('pt', 'BR'),
                    _ => Locale(code!),
                  }),
            ),
          ),
        ),
        LokalSettingRow.toggle(
          label: lokalText('Haptics'),
          description: lokalText(
            'A light tap under your finger as you use Lokal.',
          ),
          value: prefs.hapticsEnabled,
          onChanged: (value) {
            notifier.setHapticsEnabled(value);
            AppHaptics.setEnabled(value);
          },
        ),
        LokalSettingRow(
          label: lokalText('Refresh rate'),
          description: lokalText(
            'Adaptive lets the phone decide. 120 Hz is smoothest and uses more battery.',
          ),
          stacked: true,
          trailing: LokalSegmented<String>(
            expand: true,
            segments: [
              LokalSegment('adaptive', lokalText('Adaptive')),
              LokalSegment('standard', lokalText('60 Hz')),
              LokalSegment('high', lokalText('120 Hz')),
            ],
            value: prefs.refreshRateMode,
            onChanged: notifier.setRefreshRateMode,
          ),
        ),
      ],
    ),
    LokalSettingsSection(
      title: lokalText('Home-screen widget'),
      children: [
        LokalSettingLink(
          label: lokalText('Home-screen widget'),
          description: lokalText('What the widget on your home screen shows.'),
          onTap: () => _push(context, const WidgetSettingsScreen()),
        ),
      ],
    ),
  ];
}
