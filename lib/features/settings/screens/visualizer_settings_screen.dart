import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flick/l10n/l10n.dart';
import 'package:flick/providers/app_preferences_provider.dart';
import 'package:flick/widgets/lokal/settings/lokal_settings_kit.dart';

class VisualizerSettingsScreen extends ConsumerWidget {
  const VisualizerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(appPreferencesProvider);
    final notifier = ref.read(appPreferencesProvider.notifier);
    final l10n = context.l10n;

    LokalSettingsSection choices(
      String title,
      String current,
      ValueChanged<String> pick,
      List<(String, String, String)> options,
    ) => LokalSettingsSection(
      title: title,
      children: [
        for (final (value, label, description) in options)
          LokalSettingRow.option(
            label: label,
            description: description,
            selected: current == value,
            onTap: () => pick(value),
          ),
      ],
    );

    return LokalSettingsScaffold(
      title: l10n.visualizer,
      children: [
        LokalSettingsSection(
          title: l10n.visualizer,
          children: [
            LokalSettingRow.toggle(
              label: l10n.visualizer,
              description: l10n.showTheAudioVisualizerOffSaves,
              value: prefs.visualizerEnabled,
              onChanged: (value) => notifier.setVisualizerEnabled(value),
            ),
          ],
        ),
        choices(
          l10n.visualizerColors,
          prefs.visualizerColorMode,
          notifier.setVisualizerColorMode,
          [
            ('album_art', l10n.albumArt, l10n.visualizerAlbumColorsDescription),
            (
              'rainbow',
              l10n.visualizerRainbow,
              l10n.visualizerRainbowDescription,
            ),
            (
              'monochrome',
              l10n.visualizerMonochrome,
              l10n.visualizerMonochromeDescription,
            ),
          ],
        ),
        choices(
          l10n.animationStyle,
          prefs.visualizerAnimationStyle,
          notifier.setVisualizerAnimationStyle,
          [
            ('bars', l10n.bars, l10n.verticalBarsClassicSpectrumAnalyzer),
            ('blocks', l10n.visualizerBlocks, l10n.visualizerBlocksDescription),
            ('wave', l10n.wave, l10n.aSmoothContinuousWaveAcrossFrequencies),
            ('curved_wave', l10n.curvedWave, l10n.silkySmoothBZierCurvesFluid),
            (
              'mirrored',
              l10n.mirrored,
              l10n.symmetricalBarsMirroredFromTheCenter,
            ),
            ('dots', l10n.dots, l10n.circularDotsRadiusFollowsAmplitude),
          ],
        ),
        choices(
          l10n.frequencyFocus,
          prefs.visualizerFrequencyMode,
          notifier.setVisualizerFrequencyMode,
          [
            ('full', l10n.fullSpectrum, l10n.allFrequenciesEqually),
            ('bass', l10n.bass, l10n.lowFrequenciesOnly),
            ('mid', l10n.mid, l10n.midFrequenciesOnly),
            ('treble', l10n.treble, l10n.highFrequenciesOnly),
            (
              'bass_treble',
              l10n.bassTreble,
              l10n.lowAndHighFrequenciesScoopedMids,
            ),
          ],
        ),
        choices(
          l10n.movement,
          prefs.visualizerMovementMode,
          notifier.setVisualizerMovementMode,
          [
            ('bouncy', l10n.bouncy, l10n.springPhysicsEnergeticAndReactive),
            (
              'smooth',
              l10n.smooth,
              l10n.naturalEqualizerFeelResponsiveYetSmooth,
            ),
            ('snappy', l10n.snappy, l10n.fastDirectTrackingImmediateResponse),
          ],
        ),
      ],
    );
  }
}
