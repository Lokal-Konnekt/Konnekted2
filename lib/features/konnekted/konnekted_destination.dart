import 'package:flutter/foundation.dart';

import 'package:flick/features/settings/lokal/lokal_settings_group.dart';

/// UI destinations, deliberately independent from Flick's legacy tab indices.
///
/// Settings is one destination, [settings], optionally opened at a group and
/// a section with [KonnektedDestination.settingsAt].
@immutable
final class KonnektedDestination {
  const KonnektedDestination._(this.name)
    : settingsGroup = null,
      settingsSection = null;

  /// Settings, opened at [group] and scrolled to its [section] (a section
  /// title such as "Lyrics").
  const KonnektedDestination.settingsAt(
    LokalSettingsGroup group, {
    String? section,
  }) : name = 'settings',
       settingsGroup = group,
       settingsSection = section;

  /// The route name's last segment.
  final String name;
  final LokalSettingsGroup? settingsGroup;
  final String? settingsSection;

  static const flow = KonnektedDestination._('flow');
  static const search = KonnektedDestination._('search');
  static const songs = KonnektedDestination._('songs');
  static const albums = KonnektedDestination._('albums');
  static const artists = KonnektedDestination._('artists');
  static const folders = KonnektedDestination._('folders');
  static const playlists = KonnektedDestination._('playlists');
  static const favorites = KonnektedDestination._('favorites');
  static const recentlyPlayed = KonnektedDestination._('recentlyPlayed');
  static const recentlyAdded = KonnektedDestination._('recentlyAdded');
  static const queue = KonnektedDestination._('queue');
  static const linkedPlaylists = KonnektedDestination._('linkedPlaylists');
  static const genres = KonnektedDestination._('genres');
  static const downloads = KonnektedDestination._('downloads');
  static const recap = KonnektedDestination._('recap');

  /// The Settings page with its seven groups.
  static const settings = KonnektedDestination._('settings');

  static const values = <KonnektedDestination>[
    flow,
    search,
    songs,
    albums,
    artists,
    folders,
    playlists,
    favorites,
    recentlyPlayed,
    recentlyAdded,
    queue,
    linkedPlaylists,
    genres,
    downloads,
    recap,
    settings,
  ];

  bool get isSettings => name == settings.name;

  @override
  bool operator ==(Object other) =>
      other is KonnektedDestination &&
      other.name == name &&
      other.settingsGroup == settingsGroup &&
      other.settingsSection == settingsSection;

  @override
  int get hashCode => Object.hash(name, settingsGroup, settingsSection);

  @override
  String toString() => settingsGroup == null
      ? 'KonnektedDestination.$name'
      : 'KonnektedDestination.settingsAt(${settingsGroup!.name}'
            '${settingsSection == null ? '' : ', $settingsSection'})';
}
