import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preference-backed switches for optional online sources. Radio and videos
/// pass [alwaysEnabled] because their user-facing opt-in controls were removed.
class OptInSourceNotifier extends Notifier<bool> {
  OptInSourceNotifier(this.key, {this.alwaysEnabled = false});

  final String key;
  final bool alwaysEnabled;

  @override
  bool build() {
    unawaited(_load());
    return alwaysEnabled;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = alwaysEnabled ? true : (prefs.getBool(key) ?? false);
    if (alwaysEnabled) await prefs.setBool(key, true);
    if (ref.mounted && value != state) state = value;
  }

  Future<void> set(bool value) async {
    final next = alwaysEnabled ? true : value;
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, next);
  }
}

/// Internet radio stations; the station list is fetched when used.
final internetRadioEnabledProvider =
    NotifierProvider<OptInSourceNotifier, bool>(
      () => OptInSourceNotifier(
         'lokal_internet_radio_enabled',
         alwaysEnabled: true,
       ),
    );

/// Music videos: YouTube Music search for a song's official video, watched
/// in YouTube's own embedded player.
final musicVideosEnabledProvider = NotifierProvider<OptInSourceNotifier, bool>(
  () => OptInSourceNotifier(
     'lokal_music_videos_enabled',
     alwaysEnabled: true,
   ),
);
