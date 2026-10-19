import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flick/core/theme/lokal_appearance.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/services/lokal_launcher_icon.dart';

void main() {
  test('a chosen preset is its own icon', () {
    const look = LokalAppearance(accent: LokalAccent.pink);
    expect(LokalLauncherIcon.accentFor(look), LokalAccent.pink);
  });

  test("a theme's own accent maps to the nearest preset", () {
    for (final id in LokalThemeId.values) {
      final look = LokalAppearance(theme: id);
      expect(
        LokalAccent.presets,
        contains(LokalLauncherIcon.accentFor(look)),
        reason: id.name,
      );
    }
    expect(
      LokalLauncherIcon.accentFor(const LokalAppearance()),
      LokalAccent.lime,
    );
  });

  test('every preset has a launcher alias and icon', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    for (final accent in LokalAccent.presets) {
      final name = accent.name.toLowerCase();
      final cap = name[0].toUpperCase() + name.substring(1);
      expect(manifest, contains('.LauncherIcon$cap"'), reason: name);
      expect(
        File('android/app/src/main/res/mipmap-anydpi-v26/ic_lokal_$name.xml')
            .existsSync(),
        isTrue,
        reason: name,
      );
      final drawable = File(
        'android/app/src/main/res/drawable/ic_lokal_fg_$name.xml',
      ).readAsStringSync();
      final hex = accent.value.toARGB32().toRadixString(16).substring(2);
      expect(drawable.toLowerCase(), contains('#$hex'), reason: name);
    }
  });
}
