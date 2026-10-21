import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Subset of the Butterchurn minimal preset pack used by Lokal desktop.
const milkDropPresetNames = <String>[
  "_Aderrasi - Wanderer in Curved Space - mash0000 - faclempt kibitzing meshuggana schmaltz (Geiss color mix)",
  "_Mig_085",
  "$$$ Royal - Mashup (197)",
  "$$$ Royal - Mashup (431)",
  "An AdamFX n Martin Infusion 2 flexi - Why The Sky Looks Diffrent Today - AdamFx n Martin Infusion - Tack Tile Disfunction B",
  "Flexi - alien fish pond",
  "flexi - bouncing balls [double mindblob neon mix]",
  "Flexi - mindblob [shiny mix]",
  "Flexi, fishbrain, Geiss + Martin - tokamak witchery",
  "Flexi, martin + geiss - dedicated to the sherwin maxawow",
  "Geiss - Cauldron - painterly 2 (saturation remix)",
  "Geiss - Reaction Diffusion 2",
  "Geiss - Thumb Drum",
  "Halfbreak - Funny Madness",
  "Martin - acid wiring",
  "martin - chain breaker",
  "martin - extreme heat",
  "martin - mandelbox explorer - high speed demo version",
  "martin - reflections on black tiles",
  "martin - witchcraft reloaded",
  "martin [shadow harlequins shape code] - fata morgana",
  "Milk Artist At our Best - FED - SlowFast Ft AdamFX n Martin - HD CosmoFX",
  "MilkDrop2077.R002",
  "ShadowHarlequin - LovelyShinySquares [ liquid starburst rmx ] - unchained + rovaster - luckless - martin - starfield sector",
  "shifter - liquid circuitry - conjugoth",
  "suksma - uninitialized variabowl (hydroponic chronic)",
  "Unchained - Rewop",
  "yin - 191 - Temporal singularities",
  "Zylot - Paint Spill (Music Reactive Paint Mix)",
];

const _milkDropPresetKey = 'milkdrop.enabled_presets.v1';

final milkDropPresetSelectionProvider =
    NotifierProvider<MilkDropPresetSelectionNotifier, Set<String>>(
  MilkDropPresetSelectionNotifier.new,
);

class MilkDropPresetSelectionNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    unawaited(_restore());
    return Set.unmodifiable(milkDropPresetNames);
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_milkDropPresetKey);
      if (!ref.mounted || saved == null) return;
      final valid = saved.where(milkDropPresetNames.contains).toSet();
      state = Set.unmodifiable(valid.isEmpty ? milkDropPresetNames.toSet() : valid);
    } catch (_) {
      // A failed preference read leaves the full preset pack available.
    }
  }

  Future<void> setEnabled(String preset, bool enabled) async {
    if (!milkDropPresetNames.contains(preset)) return;
    final next = Set<String>.from(state);
    if (enabled) {
      next.add(preset);
    } else {
      if (next.length == 1 && next.contains(preset)) return;
      next.remove(preset);
    }
    state = Set.unmodifiable(next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_milkDropPresetKey, next.toList()..sort());
    } catch (_) {
      // Keep the current in-memory selection if persistence fails.
    }
  }

  Future<void> reset() async {
    state = Set.unmodifiable(milkDropPresetNames);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_milkDropPresetKey, milkDropPresetNames);
  }
}
