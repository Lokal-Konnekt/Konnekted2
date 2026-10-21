import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:flick/core/theme/lokal_appearance.dart';
import 'package:flick/core/theme/lokal_tokens.dart';

/// Keeps the launcher icon's sticker in the accent colour, like desktop's
/// Dock and taskbar icon.
///
/// Android only offers the twelve accent presets as icons, so a theme's own
/// accent maps to the nearest preset. The swap itself happens natively once
/// the app is in the background (LauncherIcon.kt).
abstract final class LokalLauncherIcon {
  static const _channel = MethodChannel('lokal/launcher_icon');
  static String? _last;

  /// The preset whose icon matches [appearance]'s accent.
  static LokalAccent accentFor(LokalAppearance appearance) =>
      appearance.accent ?? LokalAccent.nearest(appearance.tokens.accent);

  static Future<void> sync(LokalAppearance appearance) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final name = accentFor(appearance).name.toLowerCase();
    if (name == _last) return;
    try {
      await _channel.invokeMethod<void>('setAccent', {'accent': name});
      _last = name;
    } on PlatformException catch (e) {
      debugPrint('[LauncherIcon] not updated: ${e.message}');
    } on MissingPluginException {
      // Tests and other hosts without the native side.
    }
  }
}
