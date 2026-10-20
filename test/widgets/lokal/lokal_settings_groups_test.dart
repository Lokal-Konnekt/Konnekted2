import 'package:flick/core/theme/lokal_appearance.dart';
import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/features/settings/lokal/lokal_settings_group.dart';
import 'package:flick/features/settings/lokal/lokal_settings_page.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/providers/player_provider.dart';
import 'package:flick/services/player_service.dart';
import 'package:flick/widgets/lokal/settings/lokal_settings_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The player switches the Playback pages show, without the real engine.
class _FakePlayer extends Fake implements PlayerService {
  @override
  final gaplessPlaybackEnabledNotifier = ValueNotifier(true);
  @override
  final bitPerfectProcessingLockedNotifier = ValueNotifier(false);
  @override
  final wrapAroundQueueNotifier = ValueNotifier(true);
  @override
  final autoplayOnQueueEndNotifier = ValueNotifier(false);
  @override
  final duckOnInterruptionNotifier = ValueNotifier(true);
  @override
  final extendedVolumeEnabledNotifier = ValueNotifier(false);
  @override
  bool get isBitPerfectModeEnabled => false;

  @override
  Future<void> setWrapAroundQueue(bool value) async =>
      wrapAroundQueueNotifier.value = value;
}

Widget _app(Widget home, {PlayerService? player}) => ProviderScope(
  overrides: [playerServiceProvider.overrideWithValue(player ?? _FakePlayer())],
  child: Consumer(
    builder: (context, ref, _) => MaterialApp(
      theme: LokalTheme.build(ref.watch(lokalAppearanceProvider).tokens),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) {
        LocaleController.instance.bind(AppLocalizations.of(context));
        return child!;
      },
      home: home,
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final group in [
    LokalSettingsGroup.playback,
    LokalSettingsGroup.output,
    LokalSettingsGroup.library,
    LokalSettingsGroup.appearance,
    LokalSettingsGroup.about,
    LokalSettingsGroup.data,
    LokalSettingsGroup.integrations,
  ]) {
    testWidgets('${group.label} builds its sections with the kit', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(412, 915)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(LokalSettingsGroupPage(group: group)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.byType(LokalSettingsSection), findsWidgets);
    });
  }

  testWidgets('Online sources is one flow: add-ons, servers and accounts', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    expect(
      LokalSettingsGroup.listed,
      isNot(contains(LokalSettingsGroup.addons)),
    );
    // The old Add-ons group opens Online sources at its add-ons.
    await tester.pumpWidget(
      _app(lokalSettingsPage(group: LokalSettingsGroup.addons)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Online sources'), findsOneWidget);
    expect(find.text('ADD-ONS'), findsOneWidget);
    final page = tester.widget<LokalSettingsGroupPage>(
      find.byType(LokalSettingsGroupPage),
    );
    expect(page.group, LokalSettingsGroup.integrations);
    expect(page.section, LokalOnlineSections.addons);

    // Every section deep links reach is there.
    await tester.pumpWidget(
      _app(
        const LokalSettingsGroupPage(
          group: LokalSettingsGroup.integrations,
          section: 'Scrobbling',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    for (final title in [
      LokalOnlineSections.streaming,
      LokalOnlineSections.addons,
      LokalOnlineSections.repositories,
      LokalOnlineSections.accounts,
    ]) {
      await tester.scrollUntilVisible(
        find.text(title.toUpperCase()),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(title.toUpperCase()), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Playback rows drive the player and rebuild with it', (
    tester,
  ) async {
    final player = _FakePlayer();
    await tester.pumpWidget(
      _app(
        const LokalSettingsGroupPage(
          group: LokalSettingsGroup.playback,
          section: 'Queue',
        ),
        player: player,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wrap around'));
    await tester.pumpAndSettle();
    expect(player.wrapAroundQueueNotifier.value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search reaches rows in every real group', (tester) async {
    tester.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const LokalSettingsPage()));
    await tester.enterText(find.byType(TextField), 'lyrics automatically');
    await tester.pumpAndSettle();
    expect(find.text('Fetch lyrics automatically'), findsOneWidget);
    expect(find.text('PLAYBACK · LYRICS'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'scrobbl');
    await tester.pumpAndSettle();
    expect(find.text('ONLINE SOURCES · ACCOUNTS & SCROBBLING'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'licences');
    await tester.pumpAndSettle();
    expect(find.text('Licences'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
