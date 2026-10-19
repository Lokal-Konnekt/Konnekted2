import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flick/core/theme/lokal_appearance.dart';
import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/appearance/lokal_appearance_screen.dart';
import 'package:flick/widgets/lokal/lokal_glass.dart';
import 'package:flick/widgets/lokal/lokal_logo.dart';

Widget _app(Widget child) => ProviderScope(
  child: Consumer(
    builder: (context, ref, _) => MaterialApp(
      theme: LokalTheme.build(ref.watch(lokalAppearanceProvider).tokens),
      home: child,
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('glass blurs, and turns solid in performance mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Scaffold(
          body: Center(
            child: LokalGlass(child: SizedBox(width: 80, height: 40)),
          ),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsOneWidget);

    final element = tester.element(find.byType(LokalGlass));
    await ProviderScope.containerOf(element)
        .read(lokalAppearanceProvider.notifier)
        .setPerformanceMode(true);
    await tester.pump();
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('logo shows its tile only when tinted', (tester) async {
    await tester.pumpWidget(_app(const Scaffold(body: LokalLogo(size: 40))));
    expect(find.byType(AnimatedContainer), findsOneWidget);

    final element = tester.element(find.byType(LokalLogo));
    await ProviderScope.containerOf(element)
        .read(lokalAppearanceProvider.notifier)
        .setTintLogo(false);
    await tester.pump();
    expect(find.byType(AnimatedContainer), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('Appearance screen switches theme and accent', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(const LokalAppearanceScreen()));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LokalAppearanceScreen)),
    );

    await tester.tap(find.bySemanticsLabel('Ocean theme'));
    await tester.pumpAndSettle();
    expect(container.read(lokalAppearanceProvider).theme, LokalThemeId.ocean);
    expect(
      Theme.of(tester.element(find.byType(LokalAppearanceScreen)))
          .extension<LokalTokens>()!
          .bg,
      LokalTokens.resolve(LokalThemeId.ocean).bg,
    );

    await tester.ensureVisible(find.bySemanticsLabel('Pink accent'));
    await tester.tap(find.bySemanticsLabel('Pink accent'));
    await tester.pumpAndSettle();
    expect(container.read(lokalAppearanceProvider).accent, LokalAccent.pink);
  });
}
