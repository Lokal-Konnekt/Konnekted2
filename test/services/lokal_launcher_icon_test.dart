import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:flick/core/theme/lokal_appearance.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/services/lokal_launcher_icon.dart';

void main() {
  test('explicit accent overrides a theme icon', () {
    expect(
      LokalLauncherIcon.iconNameFor(
        const LokalAppearance(
          theme: LokalThemeId.rosegold,
          accent: LokalAccent.pink,
        ),
      ),
      'pink',
    );
  });
  test('each theme has an exact color asset and declared launcher alias', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    for (final theme in LokalThemeId.values) {
      final look = LokalAppearance(theme: theme);
      final name = LokalLauncherIcon.iconNameFor(look);
      final cap = name[0].toUpperCase() + name.substring(1);
      expect(manifest, contains('.LauncherIcon$cap"'), reason: name);
      final image = img.decodePng(
        File('android/app/src/main/res/drawable-mdpi/ic_lokal_fg_$name.png')
            .readAsBytesSync(),
      )!;
      final color = look.tokens.accent;
      expect(
        image.any(
          (pixel) =>
              pixel.a == 255 &&
              pixel.r == ((color.toARGB32() >> 16) & 255) &&
              pixel.g == ((color.toARGB32() >> 8) & 255) &&
              pixel.b == (color.toARGB32() & 255),
        ),
        isTrue,
        reason: theme.name,
      );
    }
    expect(
      LokalLauncherIcon.iconNameFor(
        const LokalAppearance(theme: LokalThemeId.rosegold),
      ),
      isNot(
        LokalLauncherIcon.iconNameFor(
          const LokalAppearance(theme: LokalThemeId.warm),
        ),
      ),
    );
  });
}
