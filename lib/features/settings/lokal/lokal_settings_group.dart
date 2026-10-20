import 'package:flutter/material.dart';

/// Desktop Lokal's seven settings groups, in desktop's order, plus pages that
/// open from inside one of them.
enum LokalSettingsGroup {
  integrations(
    'Integrations',
    'YouTube Music, Spotify, scrobbling and network sources',
    Icons.hub_rounded,
  ),
  playback(
    'Playback',
    'ReplayGain, crossfade, queue, equalizer, lyrics and output',
    Icons.play_circle_outline_rounded,
  ),
  library(
    'Library',
    'Folders, scanning and library maintenance',
    Icons.library_music_rounded,
  ),
  addons(
    'Add-ons',
    'SpotiFLAC add-ons for songs that aren’t in your library',
    Icons.extension_rounded,
  ),
  appearance(
    'Appearance',
    'Theme, accent, text size, Now Playing and interface',
    Icons.palette_rounded,
  ),
  data('Data', 'Caches and clearing your library', Icons.storage_rounded),
  about(
    'About',
    'Version, what’s new, help, licences and logs',
    Icons.info_outline_rounded,
  ),

  /// Advanced output, a page inside Playback.
  output(
    'Advanced output',
    'USB DAC, bit-perfect, engine, Bluetooth and volume',
    Icons.usb_rounded,
    parent: LokalSettingsGroup.playback,
  );

  const LokalSettingsGroup(
    this.label,
    this.description,
    this.icon, {
    this.parent,
  });

  final String label;
  final String description;
  final IconData icon;

  /// The group this page opens from; `null` for the seven groups.
  final LokalSettingsGroup? parent;

  /// The seven groups the Settings page lists, in desktop's order.
  static List<LokalSettingsGroup> get listed => [
    for (final group in values)
      if (group.parent == null) group,
  ];
}
