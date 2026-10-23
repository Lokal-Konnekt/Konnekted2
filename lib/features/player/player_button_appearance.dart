import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted transport appearance, shared by onboarding, settings and player.
class PlayerButtonAppearance extends ValueNotifier<bool> {
  PlayerButtonAppearance._() : super(false) {
    _load();
  }

  static final instance = PlayerButtonAppearance._();
  static const _key = 'player_buttons_unboxed';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_changed) value = prefs.getBool(_key) ?? false;
  }

  bool _changed = false;

  Future<void> setUnboxed(bool unboxed) async {
    _changed = true;
    value = unboxed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, unboxed);
  }
}
