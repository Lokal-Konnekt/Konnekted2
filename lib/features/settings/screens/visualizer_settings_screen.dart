import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flick/features/player/widgets/milkdrop_presets.dart';
import 'package:flick/widgets/lokal/settings/lokal_settings_kit.dart';

class VisualizerSettingsScreen extends ConsumerWidget {
  const VisualizerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(milkDropPresetSelectionProvider);
    final selection = ref.read(milkDropPresetSelectionProvider.notifier);
    return LokalSettingsScaffold(
      title: 'MilkDrop presets',
      children: [
        LokalSettingsSection(
          title: 'Preset rotation',
          children: [
            LokalSettingLink(
              label: 'Enable all presets',
              description: 'Restore the full MilkDrop preset rotation.',
              onTap: () => unawaited(selection.reset()),
            ),
            for (final preset in milkDropPresetNames)
              LokalSettingRow.toggle(
                label: preset,
                description: 'Include this preset in the visualizer rotation.',
                value: enabled.contains(preset),
                onChanged: (value) =>
                    unawaited(selection.setEnabled(preset, value)),
              ),
          ],
        ),
      ],
    );
  }
}
