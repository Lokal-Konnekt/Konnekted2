import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An online source that stays off until the user turns it on in
/// Settings › Online sources (AGENTS.md: new online services are opt-in).
/// Persisted in SharedPreferences under [key]; `false` until loaded.
class OptInSourceNotifier extends Notifier<bool> {
  OptInSourceNotifier(this.key);

  final String key;

  @override
  bool build() {
    unawaited(_load());
    return false;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getBool(key) ?? false;
    if (ref.mounted && value != state) state = value;
  }

  Future<void> set(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }
}

/// Internet radio stations (the station list is fetched only when on).
final internetRadioEnabledProvider =
    NotifierProvider<OptInSourceNotifier, bool>(
      () => OptInSourceNotifier('lokal_internet_radio_enabled'),
    );

/// Music videos: YouTube Music search for a song's official video, watched
/// in YouTube's own embedded player.
final musicVideosEnabledProvider = NotifierProvider<OptInSourceNotifier, bool>(
  () => OptInSourceNotifier('lokal_music_videos_enabled'),
);
